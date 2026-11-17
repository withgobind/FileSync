import Foundation
import Observation

/// The saved syncs, kept in a JSON file and written after every change.
@MainActor @Observable
final class JobStore {
    /// Sorted by name, the way Finder sorts.
    private(set) var jobs: [SyncJob] = []
    /// The last read or write problem, for showing in the UI; nil when all is well.
    private(set) var lastError: String?

    @ObservationIgnored let fileURL: URL

    init(fileURL: URL = JobStore.defaultURL) {
        self.fileURL = fileURL
        load()
    }

    /// ~/Library/Application Support/FileSync/jobs.json (the folder is created if missing).
    nonisolated static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let folder = base.appendingPathComponent("FileSync", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("jobs.json")
    }

    // MARK: - Changes

    /// Adds the job, or replaces the saved job with the same id.
    func upsert(_ job: SyncJob) {
        if let i = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[i] = job
        } else {
            jobs.append(job)
        }
        sortAndSave()
    }

    func delete(id: UUID) {
        jobs.removeAll { $0.id == id }
        save()
    }

    func update(id: UUID, _ change: (inout SyncJob) -> Void) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[i])
        sortAndSave()
    }

    func job(id: UUID) -> SyncJob? {
        jobs.first { $0.id == id }
    }

    // MARK: - Bookmarks

    /// A bookmark that follows the folder if it is renamed or moved, or nil if one can't be made.
    nonisolated static func bookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// The location as it is now, preferring the bookmark and falling back to the saved path.
    /// Nil when neither points at something that exists (for example, the drive is unplugged).
    nonisolated static func resolve(path: String, bookmark: Data?) -> URL? {
        if let bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                                  relativeTo: nil, bookmarkDataIsStale: &stale),
               FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    // MARK: - Disk

    private func sortAndSave() {
        jobs.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        save()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            jobs = try Self.decoder.decode([SyncJob].self, from: data)
            jobs.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch {
            // Keep the unreadable file for inspection instead of overwriting it on the next save.
            jobs = []
            let stamp = Self.stampFormatter.string(from: Date())
            var aside = fileURL.deletingLastPathComponent().appendingPathComponent("jobs.corrupt-\(stamp).json")
            if FileManager.default.fileExists(atPath: aside.path) {
                aside = fileURL.deletingLastPathComponent()
                    .appendingPathComponent("jobs.corrupt-\(stamp)-\(UUID().uuidString.prefix(8)).json")
            }
            do {
                try FileManager.default.moveItem(at: fileURL, to: aside)
                lastError = "The saved syncs file couldn't be read. It was kept as \(aside.lastPathComponent)."
            } catch {
                lastError = "The saved syncs file couldn't be read: \(error.localizedDescription)"
            }
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try Self.encoder.encode(jobs)
            try data.write(to: fileURL, options: .atomic)
            lastError = nil
        } catch {
            lastError = "Couldn't save the saved syncs: \(error.localizedDescription)"
        }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()
}
