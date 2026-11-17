import AppKit
import ServiceManagement
import UserNotifications

/// The three things automatic syncs need, each with a one-click fix that opens the exact Settings page.
@MainActor
@Observable
final class Permissions {
    enum State: Equatable {
        case granted
        case needed
        case denied      // the user said no once; only System Settings can change it now
        case unknown

        var isGranted: Bool { self == .granted }
    }

    private(set) var notifications: State = .unknown
    private(set) var openAtLogin: State = .unknown
    /// Per job: can File Sync read both folders right now.
    private(set) var driveAccess: [UUID: State] = [:]

    func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: notifications = .granted
        case .denied: notifications = .denied
        case .notDetermined: notifications = .needed
        @unknown default: notifications = .unknown
        }
        switch SMAppService.mainApp.status {
        case .enabled: openAtLogin = .granted
        case .requiresApproval: openAtLogin = .denied
        case .notRegistered, .notFound: openAtLogin = .needed
        @unknown default: openAtLogin = .unknown
        }
    }

    var allGranted: Bool { notifications.isGranted && openAtLogin.isGranted }

    func requestNotifications() async {
        if notifications == .denied {
            openNotificationSettings()
            return
        }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        await refresh()
    }

    func enableOpenAtLogin() async {
        do {
            try SMAppService.mainApp.register()
        } catch {
            SMAppService.openSystemSettingsLoginItems()
        }
        await refresh()
        if openAtLogin == .denied { SMAppService.openSystemSettingsLoginItems() }
    }

    /// Reading a folder on an external drive is what makes macOS ask "allow access to files on a removable volume".
    func checkDriveAccess(for job: SyncJob) {
        let fm = FileManager.default
        var state = State.granted
        for path in [job.sourcePath, job.targetPath] {
            guard fm.fileExists(atPath: path) else { state = .unknown; continue }
            if (try? fm.contentsOfDirectory(atPath: path)) == nil { state = .denied }
        }
        driveAccess[job.id] = state
    }

    func openNotificationSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        open("x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)")
    }

    func openFilesAndFoldersSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")
    }

    private func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}
