import Foundation

/// Scans two folders and lists how the target differs from the master.
enum Comparer {
    static func compare(
        source: URL,
        target: URL,
        options: CompareOptions,
        progress: @escaping @Sendable (CompareProgress) -> Void
    ) async throws -> CompareResult {
        try Task.checkCancellation()
        let src = try scan(root: source, options: options, phase: "Scanning master", progress: progress)
        try Task.checkCancellation()
        let dst = try scan(root: target, options: options, phase: "Scanning target", progress: progress)
        try Task.checkCancellation()
        return try diff(src, dst, sourceRoot: source, targetRoot: target, options: options, progress: progress)
    }

    // MARK: - Scanning

    struct ScannedEntry: Sendable {
        let relativePath: String
        let url: URL
        let isDirectory: Bool
        let isSymlink: Bool
        let size: Int64
        let modified: Date
    }

    struct Scan: Sendable {
        var entries: [String: ScannedEntry] = [:]
        /// Total bytes of files under each folder (keyed by the folder's relative path).
        var folderBytes: [String: Int64] = [:]
        /// Number of files under each folder.
        var folderFiles: [String: Int] = [:]
        var fileCount = 0
    }

    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey, .isHiddenKey,
    ]

    /// Synchronous so the NSEnumerator can be iterated (not allowed in async contexts).
    static func scan(
        root: URL,
        options: CompareOptions,
        phase: String,
        progress: @Sendable (CompareProgress) -> Void
    ) throws -> Scan {
        let rootURL = LocationValidator.canonical(root)
        let rootComponents = rootURL.pathComponents
        var result = Scan()
        var seen = 0
        progress(CompareProgress(phase: phase, filesSeen: 0))

        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: keys,
            options: options.skipHidden ? [.skipsHiddenFiles] : [],
            errorHandler: { _, _ in true } // skip unreadable subfolders
        ) else {
            throw LocationError.unreadable(root.path)
        }

        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isSymlink = values?.isSymbolicLink ?? false
            let isDirectory = !isSymlink && (values?.isDirectory ?? false)

            if options.ignoredNames.contains(name) || name.hasPrefix("._")
                || (options.skipHidden && (values?.isHidden ?? false)) {
                if isDirectory { enumerator.skipDescendants() }
                continue
            }

            guard let rel = relativePath(of: url, rootComponents: rootComponents) else { continue }
            let size = isDirectory || isSymlink ? 0 : Int64(values?.fileSize ?? 0)
            let entry = ScannedEntry(
                relativePath: rel, url: url, isDirectory: isDirectory, isSymlink: isSymlink,
                size: size, modified: values?.contentModificationDate ?? .distantPast
            )
            result.entries[rel] = entry

            if !isDirectory {
                result.fileCount += 1
                for ancestor in ancestors(of: rel) {
                    result.folderBytes[ancestor, default: 0] += size
                    result.folderFiles[ancestor, default: 0] += 1
                }
                seen += 1
                if seen % 500 == 0 {
                    try Task.checkCancellation()
                    progress(CompareProgress(phase: phase, filesSeen: seen))
                }
            }
        }
        try Task.checkCancellation()
        progress(CompareProgress(phase: phase, filesSeen: seen))
        return result
    }

    /// "/"-joined, NFC-normalized path relative to the root, with no leading slash.
    static func relativePath(of url: URL, rootComponents: [String]) -> String? {
        var comps = url.pathComponents
        if !comps.starts(with: rootComponents) {
            comps = url.resolvingSymlinksInPath().pathComponents
            guard comps.starts(with: rootComponents) else { return nil }
        }
        let rest = comps.dropFirst(rootComponents.count)
        guard !rest.isEmpty else { return nil }
        return rest.map { $0.precomposedStringWithCanonicalMapping }.joined(separator: "/")
    }

    /// Every ancestor folder path of a relative path, nearest last ("a/b/c" → ["a", "a/b"]).
    static func ancestors(of rel: String) -> [String] {
        let parts = rel.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count > 1 else { return [] }
        var out: [String] = []
        out.reserveCapacity(parts.count - 1)
        var current = ""
        for part in parts.dropLast() {
            current = current.isEmpty ? String(part) : current + "/" + part
            out.append(current)
        }
        return out
    }

    // MARK: - Diffing

    private static func diff(
        _ src: Scan,
        _ dst: Scan,
        sourceRoot: URL,
        targetRoot: URL,
        options: CompareOptions,
        progress: @Sendable (CompareProgress) -> Void
    ) throws -> CompareResult {
        var items: [DiffItem] = []
        var identical = 0
        /// Paths whose descendants are already represented by one item.
        var collapsed = Set<String>()
        /// File pairs with matching size and date, waiting for a byte comparison.
        var contentCandidates: [(ScannedEntry, ScannedEntry)] = []

        // Process parents before children so collapsing works.
        let allPaths = Set(src.entries.keys).union(dst.entries.keys).sorted {
            $0.split(separator: "/").count < $1.split(separator: "/").count
        }

        for path in allPaths {
            if ancestors(of: path).contains(where: collapsed.contains) { continue }
            let s = src.entries[path]
            let t = dst.entries[path]

            switch (s, t) {
            case let (s?, nil):
                if s.isDirectory { collapsed.insert(path) }
                items.append(DiffItem(
                    relativePath: path, kind: .onlyInSource, isDirectory: s.isDirectory,
                    source: fileEntry(s, in: src), target: nil,
                    fileCount: s.isDirectory ? src.folderFiles[path, default: 0] : 1, newerSide: nil
                ))
            case let (nil, t?):
                if t.isDirectory { collapsed.insert(path) }
                items.append(DiffItem(
                    relativePath: path, kind: .onlyInTarget, isDirectory: t.isDirectory,
                    source: nil, target: fileEntry(t, in: dst),
                    fileCount: t.isDirectory ? dst.folderFiles[path, default: 0] : 1, newerSide: nil
                ))
            case let (s?, t?):
                if s.isDirectory && t.isDirectory { continue }
                if s.isDirectory != t.isDirectory {
                    collapsed.insert(path)
                    items.append(changedItem(path, s, t, src, dst, options))
                    continue
                }
                if differsByMetadata(s, t, options) {
                    items.append(changedItem(path, s, t, src, dst, options))
                } else if options.compareContents {
                    contentCandidates.append((s, t))
                } else {
                    identical += 1
                }
            case (nil, nil):
                continue
            }
        }

        if !contentCandidates.isEmpty {
            let phase = "Comparing contents"
            progress(CompareProgress(phase: phase, filesSeen: 0))
            for (index, pair) in contentCandidates.enumerated() {
                try Task.checkCancellation()
                if try contentsDiffer(pair.0, pair.1) {
                    items.append(changedItem(pair.0.relativePath, pair.0, pair.1, src, dst, options))
                } else {
                    identical += 1
                }
                if (index + 1) % 500 == 0 {
                    progress(CompareProgress(phase: phase, filesSeen: index + 1))
                }
            }
            progress(CompareProgress(phase: phase, filesSeen: contentCandidates.count))
        }

        items.sort { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
        return CompareResult(
            items: items, identicalCount: identical,
            sourceFileCount: src.fileCount, targetFileCount: dst.fileCount
        )
    }

    private static func fileEntry(_ e: ScannedEntry, in scan: Scan) -> FileEntry {
        FileEntry(
            relativePath: e.relativePath, isDirectory: e.isDirectory,
            size: e.isDirectory ? scan.folderBytes[e.relativePath, default: 0] : e.size,
            modified: e.modified
        )
    }

    private static func changedItem(
        _ path: String, _ s: ScannedEntry, _ t: ScannedEntry,
        _ src: Scan, _ dst: Scan, _ options: CompareOptions
    ) -> DiffItem {
        let delta = s.modified.timeIntervalSince(t.modified)
        let newer: Side? = abs(delta) > options.dateTolerance ? (delta > 0 ? .source : .target) : nil
        return DiffItem(
            relativePath: path, kind: .changed, isDirectory: s.isDirectory,
            source: fileEntry(s, in: src), target: fileEntry(t, in: dst),
            fileCount: s.isDirectory ? src.folderFiles[path, default: 0] : 1, newerSide: newer
        )
    }

    private static func differsByMetadata(_ s: ScannedEntry, _ t: ScannedEntry, _ options: CompareOptions) -> Bool {
        if s.isSymlink != t.isSymlink { return true }
        if s.isSymlink {
            let fm = FileManager.default
            return (try? fm.destinationOfSymbolicLink(atPath: s.url.path))
                != (try? fm.destinationOfSymbolicLink(atPath: t.url.path))
        }
        if s.size != t.size { return true }
        return abs(s.modified.timeIntervalSince(t.modified)) > options.dateTolerance
    }

    /// Streams both files in 1 MB chunks and stops at the first difference.
    static func contentsDiffer(_ s: ScannedEntry, _ t: ScannedEntry) throws -> Bool {
        if s.isSymlink || t.isSymlink { return false } // already compared by destination
        guard s.size == t.size else { return true }
        guard let a = try? FileHandle(forReadingFrom: s.url),
              let b = try? FileHandle(forReadingFrom: t.url) else {
            return true // can't read one side: treat as changed so the user sees it
        }
        defer { try? a.close(); try? b.close() }
        let chunk = 1 << 20
        while true {
            try Task.checkCancellation()
            let da = try a.read(upToCount: chunk) ?? Data()
            let db = try b.read(upToCount: chunk) ?? Data()
            if da != db { return true }
            if da.isEmpty { return false }
        }
    }
}
