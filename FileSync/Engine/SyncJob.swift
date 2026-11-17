import Foundation

/// When a saved sync runs on its own (besides "when both drives are connected").
enum Schedule: Codable, Hashable, Sendable {
    case off
    /// Every `hours` hours (1...24), counted from the last run.
    case everyHours(Int)
    /// Every day at `hour`:`minute` local time.
    case daily(hour: Int, minute: Int)
    /// Every week on `weekday` (1 = Sunday ... 7 = Saturday, like Calendar) at `hour`:`minute`.
    case weekly(weekday: Int, hour: Int, minute: Int)
}

/// What happens when a saved sync is triggered.
enum AutoAction: String, Codable, Hashable, Sendable, CaseIterable {
    /// Compare, then post a notification; nothing changes until the user reviews it.
    case askFirst
    /// Compare and sync straight away, then post a summary notification.
    case syncAutomatically
}

/// A saved master → target pair that can run on its own.
struct SyncJob: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var sourcePath: String
    var targetPath: String
    var sourceBookmark: Data?
    var targetBookmark: Data?
    var removeExtras = false
    var compareContents = false
    /// Run when both locations become available (a drive is plugged in).
    var runOnConnect = true
    var schedule: Schedule = .off
    var action: AutoAction = .askFirst
    /// Turned off = saved but never runs on its own.
    var isEnabled = true
    var lastRun: Date?
    var lastSummary: String?
}
