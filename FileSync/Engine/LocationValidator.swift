import Foundation

/// Checks that a master and a target folder can be compared and synced.
enum LocationValidator {
    /// Throws `LocationError` when either location is missing, not a folder, unreadable,
    /// the same folder as the other, or inside the other.
    static func validate(source: URL, target: URL) throws {
        let src = canonical(source)
        let dst = canonical(target)
        try checkFolder(src, original: source)
        try checkFolder(dst, original: target)

        let a = src.pathComponents
        let b = dst.pathComponents
        if a == b { throw LocationError.same }
        if a.starts(with: b) || b.starts(with: a) { throw LocationError.nested }
    }

    /// Standardized, symlink-resolved file URL (e.g. /var → /private/var).
    static func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private static func checkFolder(_ url: URL, original: URL) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw LocationError.unreadable(original.path)
        }
        guard isDir.boolValue else { throw LocationError.notAFolder(original.path) }
        guard fm.isReadableFile(atPath: url.path) else {
            throw LocationError.unreadable(original.path)
        }
    }
}
