import Foundation

/// Which side of the comparison a file lives on. The source is the master.
enum Side: String, Sendable, Hashable {
    case source, target
}

/// One file or folder found while scanning a root, keyed by its path relative to that root.
struct FileEntry: Sendable, Hashable {
    let relativePath: String
    let isDirectory: Bool
    /// Bytes for a file; for a folder, the total of everything inside it.
    let size: Int64
    let modified: Date
}

enum DiffKind: String, CaseIterable, Sendable, Hashable {
    /// Exists only in the master. Sync copies it to the target.
    case onlyInSource
    /// Exists only in the target. Sync moves it to the Trash, and only when "Remove extras" is on.
    case onlyInTarget
    /// Exists on both sides but differs. Sync replaces the target copy with the master's.
    case changed
}

/// One row of the difference list.
///
/// When a whole folder exists on one side only, the folder is a single item
/// (with `fileCount` and total `size`) and its children are not listed.
struct DiffItem: Identifiable, Sendable, Hashable {
    var id: String { relativePath }
    let relativePath: String
    let kind: DiffKind
    let isDirectory: Bool
    let source: FileEntry?
    let target: FileEntry?
    /// Number of files inside a one-sided folder (1 for a file).
    let fileCount: Int
    /// For `.changed`: the side with the later modification date, if the dates differ.
    let newerSide: Side?

    var name: String { (relativePath as NSString).lastPathComponent }
    var parentPath: String { (relativePath as NSString).deletingLastPathComponent }
    /// Bytes that sync would copy (source) or remove (target) for this row.
    var size: Int64 { (kind == .onlyInTarget ? target?.size : source?.size) ?? 0 }
}

struct CompareOptions: Sendable, Hashable {
    /// Read and compare file bytes when size and date match. Slow, but catches silent edits.
    var compareContents = false
    /// exFAT/FAT drives store times at 2-second resolution, so smaller gaps count as equal.
    var dateTolerance: TimeInterval = 2
    var skipHidden = true
    /// File and folder names ignored everywhere (system clutter).
    var ignoredNames: Set<String> = [
        ".DS_Store", ".Spotlight-V100", ".Trashes", ".fseventsd",
        ".TemporaryItems", ".DocumentRevisions-V100", "Thumbs.db", "desktop.ini",
    ]
}

struct CompareResult: Sendable {
    let items: [DiffItem]
    /// Files present and equal on both sides.
    let identicalCount: Int
    let sourceFileCount: Int
    let targetFileCount: Int

    func items(_ kind: DiffKind) -> [DiffItem] { items.filter { $0.kind == kind } }
    var isInSync: Bool { items.isEmpty }
}

/// Progress reported while scanning and comparing.
struct CompareProgress: Sendable {
    var phase: String          // "Scanning master", "Scanning target", "Comparing contents"
    var filesSeen: Int
}

enum SyncAction: Sendable, Hashable {
    /// Copy a file or whole folder that is missing from the target.
    case copy(relativePath: String, bytes: Int64)
    /// Overwrite the target's copy with the master's.
    case replace(relativePath: String, bytes: Int64)
    /// Move a target-only file or folder to the Trash (never a permanent delete).
    case trash(relativePath: String, bytes: Int64)

    var relativePath: String {
        switch self {
        case .copy(let p, _), .replace(let p, _), .trash(let p, _): p
        }
    }
    var bytes: Int64 {
        switch self {
        case .copy(_, let b), .replace(_, let b), .trash(_, let b): b
        }
    }
}

/// What a sync would do. Building a plan touches nothing on disk; it is the dry run.
struct SyncPlan: Sendable {
    let actions: [SyncAction]

    var copies: [SyncAction] { actions.filter { if case .copy = $0 { true } else { false } } }
    var replacements: [SyncAction] { actions.filter { if case .replace = $0 { true } else { false } } }
    var trashes: [SyncAction] { actions.filter { if case .trash = $0 { true } else { false } } }
    /// Bytes written to the target (copies + replacements).
    var bytesToWrite: Int64 { (copies + replacements).reduce(0) { $0 + $1.bytes } }
    var isEmpty: Bool { actions.isEmpty }
}

struct SyncProgress: Sendable {
    var actionsDone: Int
    var actionsTotal: Int
    var bytesDone: Int64
    var bytesTotal: Int64
    var currentPath: String

    var fraction: Double {
        if bytesTotal > 0 { return min(1, Double(bytesDone) / Double(bytesTotal)) }
        return actionsTotal == 0 ? 1 : Double(actionsDone) / Double(actionsTotal)
    }
}

struct SyncFailure: Sendable, Hashable {
    let relativePath: String
    let message: String
}

struct SyncReport: Sendable {
    let copied: Int
    let replaced: Int
    let trashed: Int
    let bytesWritten: Int64
    let failures: [SyncFailure]
    let cancelled: Bool
}

enum LocationError: LocalizedError, Equatable {
    case same
    case nested
    case notAFolder(String)
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .same: "Both locations are the same folder."
        case .nested: "One location is inside the other. Pick two separate folders."
        case .notAFolder(let p): "\(p) is not a folder."
        case .unreadable(let p): "Can't read \(p)."
        }
    }
}
