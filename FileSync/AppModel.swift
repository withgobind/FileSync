import SwiftUI
import AppKit

/// A chosen folder plus what the card shows about its drive.
struct Location: Equatable {
    let url: URL
    let volumeName: String
    let isExternal: Bool
    let freeBytes: Int64?
    let volumeURL: URL?

    var name: String { url.lastPathComponent.isEmpty ? volumeName : url.lastPathComponent }
    var symbol: String { isExternal ? "externaldrive.fill" : "internaldrive.fill" }

    init(url: URL) {
        self.url = url
        let keys: Set<URLResourceKey> = [
            .volumeNameKey, .volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsEjectableKey,
            .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey, .volumeURLKey,
        ]
        let v = try? url.resourceValues(forKeys: keys)
        volumeName = v?.volumeName ?? "Disk"
        volumeURL = v?.volume
        isExternal = (v?.volumeIsInternal == false) || (v?.volumeIsRemovable ?? false) || (v?.volumeIsEjectable ?? false)
        if let important = v?.volumeAvailableCapacityForImportantUsage, important > 0 {
            freeBytes = important
        } else {
            freeBytes = v?.volumeAvailableCapacity.map(Int64.init)
        }
    }
}

enum Filter: Hashable, CaseIterable {
    case all, onlyInSource, onlyInTarget, changed

    var kind: DiffKind? {
        switch self {
        case .all: nil
        case .onlyInSource: .onlyInSource
        case .onlyInTarget: .onlyInTarget
        case .changed: .changed
        }
    }

    var title: String {
        switch self {
        case .all: "All"
        case .onlyInSource: "Only in master"
        case .onlyInTarget: "Only in target"
        case .changed: "Changed"
        }
    }
}

enum SyncStage: Equatable {
    case preview
    case running
    case done
}

@MainActor
@Observable
final class AppModel {
    var source: Location? { didSet { if oldValue != source { locationsChanged(); save(source, key: "source") } } }
    var target: Location? { didSet { if oldValue != target { locationsChanged(); save(target, key: "target") } } }
    /// Last-used folders whose drive isn't plugged in right now (shown on the empty card).
    var missing: [Side: String] = [:]
    /// Open while the in-app folder picker is showing.
    var picker: PickerModel?
    /// The saved sync currently loaded in the window, if any.
    var selectedJobID: UUID?
    var showAutomateSheet = false
    /// Called when a sync of a saved job finishes from the review sheet.
    var onManualSyncFinished: (UUID) -> Void = { _ in }

    var options = CompareOptions()
    var removeExtras = false

    var result: CompareResult?
    var isComparing = false
    var compareProgress: CompareProgress?
    var errorMessage: String?
    var filter: Filter = .all
    var search = ""

    var showSyncSheet = false
    var syncStage: SyncStage = .preview
    var syncProgress: SyncProgress?
    var syncReport: SyncReport?

    private var compareTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    init() {
        source = restore(key: "source")
        target = restore(key: "target")
        // Reconnect remembered folders when their drive is plugged in; drop them when it's ejected.
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconnect() }
        })
        observers.append(nc.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dropUnmounted() }
        })
        #if DEBUG
        if let dir = UserDefaults.standard.string(forKey: "walkthrough"),
           let s = UserDefaults.standard.string(forKey: "demoSource"),
           let t = UserDefaults.standard.string(forKey: "demoTarget") {
            Task { @MainActor in await self.walkthrough(dir: dir, source: URL(fileURLWithPath: s), target: URL(fileURLWithPath: t)) }
        }
        #endif
    }

    // MARK: State

    var isBusy: Bool { isComparing || syncStage == .running }
    var canCompare: Bool { source != nil && target != nil && !isBusy }
    var plan: SyncPlan? { result.map { Planner.plan($0, removeExtras: removeExtras) } }
    var canSync: Bool { !isBusy && (plan.map { !$0.isEmpty } ?? false) }

    func count(_ filter: Filter) -> Int {
        guard let result else { return 0 }
        guard let kind = filter.kind else { return result.items.count }
        return result.items.lazy.filter { $0.kind == kind }.count
    }

    var visibleItems: [DiffItem] {
        guard let result else { return [] }
        let q = search.trimmingCharacters(in: .whitespaces)
        return result.items.filter { item in
            (filter.kind == nil || item.kind == filter.kind)
                && (q.isEmpty || item.relativePath.localizedCaseInsensitiveContains(q))
        }
    }

    // MARK: Choosing folders

    func choose(_ side: Side) {
        guard !isBusy else { return }
        let start = (side == .source ? source : target)?.url
        picker = PickerModel(side: side, start: start)
    }

    func usePicked() {
        guard let picker else { return }
        let url = picker.chosen
        closePicker()
        set(url, for: picker.side)
    }

    func closePicker() {
        picker?.stop()
        picker = nil
    }

    /// Fallback: the standard macOS open panel.
    func chooseWithFinder(_ side: Side) {
        let start = picker?.current
        closePicker()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use This Folder"
        panel.message = side == .source ? "Choose the master folder or drive." : "Choose the target folder or drive."
        panel.directoryURL = start
        guard panel.runModal() == .OK, let url = panel.url else { return }
        set(url, for: side)
    }

    func set(_ url: URL, for side: Side) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            errorMessage = LocationError.notAFolder(url.lastPathComponent).errorDescription
            return
        }
        let location = Location(url: url)
        missing[side] = nil
        selectedJobID = nil
        if side == .source { source = location } else { target = location }
    }

    /// Puts a saved sync's folders and options into the window.
    func load(_ job: SyncJob) {
        guard !isBusy else { return }
        let src = JobStore.resolve(path: job.sourcePath, bookmark: job.sourceBookmark)
        let tgt = JobStore.resolve(path: job.targetPath, bookmark: job.targetBookmark)
        source = src.map { Location(url: $0) }
        target = tgt.map { Location(url: $0) }
        missing[.source] = src == nil ? job.sourcePath : nil
        missing[.target] = tgt == nil ? job.targetPath : nil
        removeExtras = job.removeExtras
        options.compareContents = job.compareContents
        selectedJobID = job.id
    }

    /// A new, unsaved comparison.
    func newComparison() {
        guard !isBusy else { return }
        selectedJobID = nil
        source = nil
        target = nil
        missing = [:]
        result = nil
        for key in ["source", "target", "sourcePath", "targetPath"] { UserDefaults.standard.removeObject(forKey: key) }
    }

    private func reconnect() {
        if source == nil, missing[.source] != nil { source = restore(key: "source") }
        if target == nil, missing[.target] != nil { target = restore(key: "target") }
    }

    private func dropUnmounted() {
        guard !isBusy else { return }
        if let s = source, !FileManager.default.fileExists(atPath: s.url.path) { missing[.source] = s.url.path; source = nil }
        if let t = target, !FileManager.default.fileExists(atPath: t.url.path) { missing[.target] = t.url.path; target = nil }
    }

    func swap() {
        guard !isBusy else { return }
        selectedJobID = nil
        let s = source
        source = target
        target = s
    }

    private func locationsChanged() {
        cancelCompare()
        result = nil
        errorMessage = nil
        filter = .all
    }

    // MARK: Compare

    func compare() {
        guard let source, let target, !isBusy else { return }
        errorMessage = nil
        do {
            try LocationValidator.validate(source: source.url, target: target.url)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        isComparing = true
        compareProgress = CompareProgress(phase: "Scanning master", filesSeen: 0)
        let options = options
        compareTask = Task {
            do {
                let result = try await Comparer.compare(source: source.url, target: target.url, options: options) { p in
                    Task { @MainActor in
                        guard self.isComparing else { return }
                        self.compareProgress = p
                    }
                }
                guard !Task.isCancelled else { return }
                self.result = result
                if !result.items.contains(where: { $0.kind == self.filter.kind }) { self.filter = .all }
            } catch is CancellationError {
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isComparing = false
            self.compareProgress = nil
        }
    }

    func cancelCompare() {
        compareTask?.cancel()
        isComparing = false
        compareProgress = nil
    }

    // MARK: Sync

    func startSync() {
        guard let plan, let source, let target, !plan.isEmpty else { return }
        syncStage = .running
        syncProgress = SyncProgress(actionsDone: 0, actionsTotal: plan.actions.count, bytesDone: 0, bytesTotal: plan.bytesToWrite, currentPath: "")
        syncTask = Task {
            let report = await Syncer.run(plan, source: source.url, target: target.url) { p in
                Task { @MainActor in self.syncProgress = p }
            }
            self.syncReport = report
            self.syncStage = .done
        }
    }

    func cancelSync() { syncTask?.cancel() }

    func closeSyncSheet() {
        let finished = syncStage == .done
        let completed = syncReport.map { !$0.cancelled } ?? false
        showSyncSheet = false
        syncStage = .preview
        syncProgress = nil
        syncReport = nil
        if finished, completed, let id = selectedJobID {
            onManualSyncFinished(id)
        }
        if finished {
            // Refresh drive info and the list so the window shows what is true now.
            source = source.map { Location(url: $0.url) }
            target = target.map { Location(url: $0.url) }
            compare()
        }
    }

    // MARK: Remembering folders between launches (security-scoped bookmarks)

    private func save(_ location: Location?, key: String) {
        // Only remember real choices; a drive being unplugged must not forget the folder.
        guard let location else { return }
        UserDefaults.standard.set(location.url.path, forKey: key + "Path")
        if let data = try? location.url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func restore(key: String) -> Location? {
        let side: Side = key == "source" ? .source : .target
        var url: URL?
        if let data = UserDefaults.standard.data(forKey: key) {
            var stale = false
            url = try? URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale)
        }
        if url == nil, let path = UserDefaults.standard.string(forKey: key + "Path") { url = URL(fileURLWithPath: path) }
        guard let url else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else {
            missing[side] = UserDefaults.standard.string(forKey: key + "Path") ?? url.path
            return nil
        }
        missing[side] = nil
        return Location(url: url)
    }
}

#if DEBUG
extension AppModel {
    /// Steps through the app the way a person would, saving a picture of each screen.
    /// Run the Debug build with `-walkthrough <dir> -demoSource <master> -demoTarget <target>`.
    func walkthrough(dir: String, source s: URL, target t: URL) async {
        func shot(_ name: String, wait: Double = 1.2) async {
            try? await Task.sleep(for: .seconds(wait))
            AppModel.snapshotWindows(to: dir, prefix: name)
        }
        source = nil; target = nil; missing = [:]
        await shot("01-start")
        choose(.source)
        await shot("02-picker-drives")
        picker?.open(s.deletingLastPathComponent())
        try? await Task.sleep(for: .seconds(0.5))
        picker?.selection = s
        await shot("03-picker-master")
        usePicked()
        await shot("04-master-chosen")
        choose(.target)
        picker?.open(t.deletingLastPathComponent())
        try? await Task.sleep(for: .seconds(0.5))
        picker?.selection = t
        await shot("05-picker-target")
        usePicked()
        await shot("06-ready")
        compare()
        while isComparing { try? await Task.sleep(for: .milliseconds(100)) }
        await shot("07-results")
        removeExtras = true
        showSyncSheet = true
        await shot("08-review")
        startSync()
        while syncStage != .done { try? await Task.sleep(for: .milliseconds(100)) }
        await shot("09-done")
        closeSyncSheet()
        while isComparing { try? await Task.sleep(for: .milliseconds(100)) }
        await shot("10-in-sync")
        // Save it as an automatic sync.
        showAutomateSheet = true
        await shot("11-automate", wait: 1.5)
        showAutomateSheet = false
        let services = Services.shared
        var job = SyncJob(name: "Photos → Backup", sourcePath: s.path, targetPath: t.path)
        job.schedule = .daily(hour: 21, minute: 0)
        job.lastRun = Date()
        job.lastSummary = "In sync"
        services.store.upsert(job)
        selectedJobID = job.id
        await shot("12-saved")
        // A new photo arrives in the master; the saved sync notices and waits for review.
        try? Data(repeating: 7, count: 300_000).write(to: s.appending(path: "Trips/goa-5.heic"))
        services.scheduler.runNow(job.id)
        while services.scheduler.running != nil || services.scheduler.pending[job.id] == nil {
            try? await Task.sleep(for: .milliseconds(100))
        }
        await shot("13-waiting-review")
        services.open(jobID: job.id, review: true)
        await shot("14-review-from-saved")
        showSyncSheet = false
        services.store.delete(id: job.id)
        for key in ["source", "target", "sourcePath", "targetPath"] { UserDefaults.standard.removeObject(forKey: key) }
        NSApp.terminate(nil)
    }

    /// Draws each visible window into a PNG (no screen-recording permission needed).
    static func snapshotWindows(to dir: String, prefix: String) {
        for (i, window) in NSApp.windows.enumerated() where window.isVisible {
            guard let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let url = URL(fileURLWithPath: dir).appending(path: "\(prefix)-\(i).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
    }
}
#endif
