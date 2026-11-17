import AppKit
import UserNotifications

/// Runs saved syncs on their own: when both drives are connected, and on their schedule.
/// "Ask me first" jobs only compare and notify; nothing on disk changes until the user reviews.
@MainActor
@Observable
final class Scheduler {
    let store: JobStore
    /// Compare results waiting for the user's review, by job.
    private(set) var pending: [UUID: CompareResult] = [:]
    private(set) var running: UUID?
    /// Whether both locations of each job were reachable at the last check.
    private(set) var connected: [UUID: Bool] = [:]

    /// Set by the app: true while the window is busy comparing or syncing, so jobs wait.
    var isAppBusy: () -> Bool = { false }

    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var queue: [UUID] = []

    init(store: JobStore) {
        self.store = store
    }

    func start() {
        guard timer == nil else { return }
        // Launch counts as "connected" for jobs that haven't run in the last hour,
        // so a drive already plugged in at login still syncs.
        for job in store.jobs {
            let now = available(job)
            connected[job.id] = now
            if now, job.isEnabled, job.runOnConnect,
               (job.lastRun.map { Date().timeIntervalSince($0) > 3600 } ?? true) {
                enqueue(job.id)
            }
        }
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didWakeNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.check() }
            })
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        check()
    }

    /// Looks at every job: newly connected ones and due schedules get queued.
    func check() {
        let now = Date()
        for job in store.jobs {
            let isUp = available(job)
            let wasUp = connected[job.id] ?? false
            connected[job.id] = isUp
            guard job.isEnabled, isUp else { continue }
            if job.runOnConnect && !wasUp {
                enqueue(job.id)
            } else if ScheduleMath.isDue(job, now: now) {
                enqueue(job.id)
            }
        }
        runNext()
    }

    func runNow(_ id: UUID) {
        enqueue(id)
        runNext()
    }

    func clearPending(_ id: UUID) { pending[id] = nil }

    func available(_ job: SyncJob) -> Bool {
        JobStore.resolve(path: job.sourcePath, bookmark: job.sourceBookmark) != nil
            && JobStore.resolve(path: job.targetPath, bookmark: job.targetBookmark) != nil
    }

    private func enqueue(_ id: UUID) {
        if running != id, !queue.contains(id) { queue.append(id) }
    }

    private func runNext() {
        guard running == nil, !isAppBusy(), !queue.isEmpty else { return }
        let id = queue.removeFirst()
        guard let job = store.job(id: id),
              let source = JobStore.resolve(path: job.sourcePath, bookmark: job.sourceBookmark),
              let target = JobStore.resolve(path: job.targetPath, bookmark: job.targetBookmark)
        else { runNext(); return }
        running = id
        Task { await run(job, source: source, target: target) }
    }

    private func run(_ job: SyncJob, source: URL, target: URL) async {
        defer {
            running = nil
            runNext()
        }
        var options = CompareOptions()
        options.compareContents = job.compareContents
        let summary: String
        do {
            try LocationValidator.validate(source: source, target: target)
            let result = try await Comparer.compare(source: source, target: target, options: options) { _ in }
            let plan = Planner.plan(result, removeExtras: job.removeExtras)
            if plan.isEmpty {
                summary = "In sync"
                pending[job.id] = nil
            } else if job.action == .askFirst {
                pending[job.id] = result
                summary = "\(Format.count(plan.actions.count, "change")) waiting for review"
                notify(job, title: "\(job.name): ready to sync",
                       body: describe(plan) + ". Open File Sync to review.", review: true)
            } else {
                let report = await Syncer.run(plan, source: source, target: target) { _ in }
                pending[job.id] = nil
                if report.failures.isEmpty {
                    summary = "Synced: copied \(report.copied), replaced \(report.replaced), trashed \(report.trashed)"
                } else {
                    summary = "Synced with \(Format.count(report.failures.count, "problem"))"
                }
                notify(job, title: "\(job.name): synced", body: summary, review: false)
            }
        } catch is CancellationError {
            return
        } catch {
            summary = "Couldn't run: \(error.localizedDescription)"
            notify(job, title: "\(job.name): couldn't sync", body: error.localizedDescription, review: false)
        }
        store.update(id: job.id) {
            $0.lastRun = Date()
            $0.lastSummary = summary
        }
    }

    private func describe(_ plan: SyncPlan) -> String {
        var parts: [String] = []
        if !plan.copies.isEmpty { parts.append("\(plan.copies.count) to copy") }
        if !plan.replacements.isEmpty { parts.append("\(plan.replacements.count) to replace") }
        if !plan.trashes.isEmpty { parts.append("\(plan.trashes.count) to Trash") }
        return parts.joined(separator: ", ")
    }

    private func notify(_ job: SyncJob, title: String, body: String, review: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["jobID": job.id.uuidString, "review": review]
        let request = UNNotificationRequest(identifier: "\(job.id)-\(Date().timeIntervalSince1970)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
