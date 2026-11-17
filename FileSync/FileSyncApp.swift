import SwiftUI
import UserNotifications

/// Everything the window, the menu bar item and notification clicks share.
@MainActor
final class Services {
    static let shared = Services()
    let model = AppModel()
    let store = JobStore()
    let permissions = Permissions()
    lazy var scheduler: Scheduler = {
        let s = Scheduler(store: store)
        s.isAppBusy = { [unowned self] in self.model.isBusy || self.model.showSyncSheet }
        return s
    }()

    /// Loads a saved sync into the window; with a waiting result, opens its review sheet.
    func open(jobID: UUID, review: Bool) {
        guard let job = store.job(id: jobID) else { return }
        model.load(job)
        if review, let result = scheduler.pending[jobID] {
            model.result = result
            model.showSyncSheet = true
        }
        NSApp.activate()
        for window in NSApp.windows where window.identifier?.rawValue == "main" || window.title == "File Sync" {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        MainActor.assumeIsolated {
            let services = Services.shared
            services.model.onManualSyncFinished = { jobID in
                services.scheduler.clearPending(jobID)
                services.store.update(id: jobID) {
                    $0.lastRun = Date()
                    $0.lastSummary = "Synced after review"
                }
            }
            #if DEBUG
            if UserDefaults.standard.string(forKey: "walkthrough") != nil { return }
            #endif
            services.scheduler.start()
            Task { await services.permissions.refresh() }
        }
    }

    /// Closing the window keeps File Sync running in the menu bar so saved syncs still run.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let s = info["jobID"] as? String, let id = UUID(uuidString: s) else { return }
        let review = info["review"] as? Bool ?? false
        await MainActor.run { Services.shared.open(jobID: id, review: review) }
    }
}

@main
struct FileSyncApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let services = Services.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("File Sync", id: "main") {
            ContentView()
                .environment(services.model)
                .environment(services.store)
                .environment(services.scheduler)
                .environment(services.permissions)
                .frame(minWidth: 1060, minHeight: 600)
        }
        .defaultSize(width: 1140, height: 700)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Sync") {
                Button("Compare") { services.model.compare() }
                    .keyboardShortcut("r")
                    .disabled(!services.model.canCompare)
                Button("Swap Master and Target") { services.model.swap() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(services.model.isBusy)
                Divider()
                Button("Sync…") { services.model.showSyncSheet = true }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!services.model.canSync)
                Button("Automate…") { services.model.showAutomateSheet = true }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .disabled(services.model.source == nil || services.model.target == nil)
            }
        }

        MenuBarExtra("File Sync", systemImage: "arrow.triangle.2.circlepath") {
            MenuBarContent(openMain: { openWindow(id: "main") })
                .environment(services.store)
                .environment(services.scheduler)
        }
    }
}

/// Menu bar menu: what's saved, what's waiting, run one now.
private struct MenuBarContent: View {
    @Environment(JobStore.self) private var store
    @Environment(Scheduler.self) private var scheduler
    let openMain: () -> Void

    var body: some View {
        if store.jobs.isEmpty {
            Text("No saved syncs yet")
        }
        ForEach(store.jobs) { job in
            Menu(job.name) {
                if scheduler.pending[job.id] != nil {
                    Button("Review Changes…") { openMain(); Services.shared.open(jobID: job.id, review: true) }
                }
                Button("Sync Now") { scheduler.runNow(job.id) }
                    .disabled(scheduler.running != nil || !scheduler.available(job))
                Button("Open in File Sync") { openMain(); Services.shared.open(jobID: job.id, review: false) }
                Divider()
                Text(job.lastSummary ?? "Hasn't run yet")
                if let next = ScheduleMath.describeNext(job, now: Date()) { Text(next) }
            }
        }
        Divider()
        Button("Open File Sync") { openMain(); NSApp.activate() }
        Button("Quit File Sync") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
