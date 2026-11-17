import Foundation

/// Carries out a sync plan, master → target. Never permanently deletes anything in the target:
/// removed items go to the Trash, and replacements swap in a finished copy.
enum Syncer {
    enum SyncError: LocalizedError {
        case unsafePath(String)
        case missingSource(String)

        var errorDescription: String? {
            switch self {
            case .unsafePath(let p): "Refused to write outside the target folder: \(p)"
            case .missingSource(let p): "\(p) is no longer in the master folder."
            }
        }
    }

    static func run(
        _ plan: SyncPlan,
        source: URL,
        target: URL,
        progress: @escaping @Sendable (SyncProgress) -> Void
    ) async -> SyncReport {
        let sourceRoot = LocationValidator.canonical(source)
        let targetRoot = LocationValidator.canonical(target)
        let total = plan.actions.reduce(Int64(0)) { $0 + $1.bytes }
        var copied = 0, replaced = 0, trashed = 0
        var bytesWritten: Int64 = 0
        var bytesDone: Int64 = 0
        var failures: [SyncFailure] = []
        var done = 0

        progress(SyncProgress(actionsDone: 0, actionsTotal: plan.actions.count,
                              bytesDone: 0, bytesTotal: total, currentPath: ""))

        for action in plan.actions {
            if Task.isCancelled {
                return SyncReport(copied: copied, replaced: replaced, trashed: trashed,
                                  bytesWritten: bytesWritten, failures: failures, cancelled: true)
            }
            let rel = action.relativePath
            do {
                let dest = try resolve(rel, in: targetRoot)
                switch action {
                case .copy:
                    let src = try resolve(rel, in: sourceRoot)
                    try copy(from: src, to: dest)
                    copied += 1
                    bytesWritten += action.bytes
                case .replace:
                    let src = try resolve(rel, in: sourceRoot)
                    try replace(dest, with: src)
                    replaced += 1
                    bytesWritten += action.bytes
                case .trash:
                    try FileManager.default.trashItem(at: dest, resultingItemURL: nil)
                    trashed += 1
                }
            } catch {
                failures.append(SyncFailure(relativePath: rel, message: error.localizedDescription))
            }
            done += 1
            bytesDone += action.bytes
            progress(SyncProgress(actionsDone: done, actionsTotal: plan.actions.count,
                                  bytesDone: bytesDone, bytesTotal: total, currentPath: rel))
        }
        return SyncReport(copied: copied, replaced: replaced, trashed: trashed,
                          bytesWritten: bytesWritten, failures: failures, cancelled: false)
    }

    /// Joins a relative path onto a root, rejecting anything that could escape it.
    static func resolve(_ relativePath: String, in root: URL) throws -> URL {
        let parts = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/"),
              !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            throw SyncError.unsafePath(relativePath)
        }
        let url = parts.reduce(root) { $0.appendingPathComponent(String($1)) }.standardizedFileURL
        let rootComps = root.standardizedFileURL.pathComponents
        let comps = url.pathComponents
        guard comps.count > rootComps.count, comps.starts(with: rootComps) else {
            throw SyncError.unsafePath(relativePath)
        }
        return url
    }

    private static func copy(from src: URL, to dest: URL) throws {
        let fm = FileManager.default
        guard exists(src) else { throw SyncError.missingSource(src.lastPathComponent) }
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: src, to: dest)
    }

    private static func replace(_ dest: URL, with src: URL) throws {
        let fm = FileManager.default
        guard exists(src) else { throw SyncError.missingSource(src.lastPathComponent) }
        guard exists(dest) else {
            try copy(from: src, to: dest)
            return
        }
        if isFolder(src) != isFolder(dest) {
            // File ↔ folder: the old item goes to the Trash, then the master's is copied in.
            try fm.trashItem(at: dest, resultingItemURL: nil)
            try fm.copyItem(at: src, to: dest)
            return
        }
        let temp = dest.deletingLastPathComponent()
            .appendingPathComponent(".filesync-\(UUID().uuidString)-\(dest.lastPathComponent)")
        do {
            try fm.copyItem(at: src, to: temp)
            _ = try fm.replaceItemAt(dest, withItemAt: temp, backupItemName: nil, options: .usingNewMetadataOnly)
        } catch {
            // Only our own temp copy is ever removed; the user's file is untouched on failure.
            if exists(temp) { try? fm.removeItem(at: temp) }
            throw error
        }
    }

    private static func exists(_ url: URL) -> Bool {
        // lstat-style check so a dangling symlink still counts as present.
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    private static func isFolder(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        return !(values?.isSymbolicLink ?? false) && (values?.isDirectory ?? false)
    }
}
