import Foundation
import Testing
@testable import FileSync

/// A pair of fresh master/target folders under the temp directory.
final class Sandbox {
    let root: URL
    let source: URL
    let target: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileSyncTests-\(UUID().uuidString)")
        source = root.appendingPathComponent("master")
        target = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) } // test scratch only

    static let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    @discardableResult
    func write(_ rel: String, in base: URL, _ text: String, date: Date = Sandbox.baseDate) throws -> URL {
        let url = base.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        return url
    }

    func both(_ rel: String, _ text: String, date: Date = Sandbox.baseDate) throws {
        try write(rel, in: source, text, date: date)
        try write(rel, in: target, text, date: date)
    }

    func compare(_ options: CompareOptions = CompareOptions()) async throws -> CompareResult {
        try await Comparer.compare(source: source, target: target, options: options) { _ in }
    }
}

@Suite("Comparer")
struct ComparerTests {
    @Test func classifiesOnlyInSourceOnlyInTargetAndChanged() async throws {
        let box = try Sandbox()
        try box.both("same.txt", "hello")
        try box.write("new.txt", in: box.source, "new")
        try box.write("extra.txt", in: box.target, "extra")
        try box.write("edited.txt", in: box.source, "longer text")
        try box.write("edited.txt", in: box.target, "short")

        let r = try await box.compare()
        #expect(r.items(.onlyInSource).map(\.relativePath) == ["new.txt"])
        #expect(r.items(.onlyInTarget).map(\.relativePath) == ["extra.txt"])
        #expect(r.items(.changed).map(\.relativePath) == ["edited.txt"])
        #expect(r.identicalCount == 1)
        #expect(r.sourceFileCount == 3)
        #expect(r.targetFileCount == 3)
        #expect(r.items.map(\.relativePath) == ["edited.txt", "extra.txt", "new.txt"])
    }

    @Test func collapsesOneSidedFolders() async throws {
        let box = try Sandbox()
        try box.write("Photos/a.jpg", in: box.source, "12345")
        try box.write("Photos/2024/b.jpg", in: box.source, "123")
        try box.write("Photos/2024/deep/c.jpg", in: box.source, "12")
        try box.write("Old/x.txt", in: box.target, "abcd")

        let r = try await box.compare()
        #expect(r.items.count == 2)
        let photos = try #require(r.items.first { $0.relativePath == "Photos" })
        #expect(photos.kind == .onlyInSource)
        #expect(photos.isDirectory)
        #expect(photos.fileCount == 3)
        #expect(photos.source?.size == 10)
        #expect(photos.size == 10)
        let old = try #require(r.items.first { $0.relativePath == "Old" })
        #expect(old.kind == .onlyInTarget)
        #expect(old.fileCount == 1)
        #expect(old.size == 4)
    }

    @Test func nestedFilesUseSlashPaths() async throws {
        let box = try Sandbox()
        try box.both("a/b/same.txt", "x")
        try box.write("a/b/new.txt", in: box.source, "y")
        let r = try await box.compare()
        #expect(r.items.map(\.relativePath) == ["a/b/new.txt"])
        #expect(r.items.first?.parentPath == "a/b")
    }

    @Test func dateTolerance() async throws {
        let box = try Sandbox()
        try box.write("one.txt", in: box.source, "x", date: Sandbox.baseDate)
        try box.write("one.txt", in: box.target, "x", date: Sandbox.baseDate.addingTimeInterval(1))
        try box.write("five.txt", in: box.source, "x", date: Sandbox.baseDate.addingTimeInterval(5))
        try box.write("five.txt", in: box.target, "x", date: Sandbox.baseDate)

        let r = try await box.compare()
        #expect(r.items.map(\.relativePath) == ["five.txt"])
        #expect(r.items.first?.kind == .changed)
        #expect(r.items.first?.newerSide == .source)
        #expect(r.identicalCount == 1)
    }

    @Test func contentCompareCatchesSilentEdits() async throws {
        let box = try Sandbox()
        try box.write("doc.txt", in: box.source, "aaaa")
        try box.write("doc.txt", in: box.target, "aaab")
        try box.both("ok.txt", "same")

        #expect(try await box.compare().isInSync)
        var opts = CompareOptions()
        opts.compareContents = true
        let r = try await box.compare(opts)
        #expect(r.items.map(\.relativePath) == ["doc.txt"])
        #expect(r.items.first?.newerSide == nil)
        #expect(r.identicalCount == 1)
    }

    @Test func contentCompareAcrossChunks() async throws {
        let box = try Sandbox()
        var big = Data(repeating: 7, count: (1 << 20) + 10)
        let a = box.source.appendingPathComponent("big.bin")
        let b = box.target.appendingPathComponent("big.bin")
        try big.write(to: a)
        big[big.count - 1] = 8
        try big.write(to: b)
        for url in [a, b] {
            try FileManager.default.setAttributes([.modificationDate: Sandbox.baseDate], ofItemAtPath: url.path)
        }
        var opts = CompareOptions()
        opts.compareContents = true
        #expect(try await box.compare(opts).items.map(\.relativePath) == ["big.bin"])
    }

    @Test func ignoresSystemClutterAndAppleDouble() async throws {
        let box = try Sandbox()
        try box.write(".DS_Store", in: box.source, "junk")
        try box.write("sub/.DS_Store", in: box.target, "junk")
        try box.write("._photo.jpg", in: box.source, "rsrc")
        try box.both("sub/keep.txt", "k")

        var opts = CompareOptions()
        opts.skipHidden = false // prove ignoredNames/AppleDouble work on their own
        let r = try await box.compare(opts)
        #expect(r.isInSync)
        #expect(r.sourceFileCount == 1)
    }

    @Test func skipHiddenFiles() async throws {
        let box = try Sandbox()
        try box.write(".secret", in: box.source, "s")
        #expect(try await box.compare().isInSync)
        var opts = CompareOptions()
        opts.skipHidden = false
        #expect(try await box.compare(opts).items.map(\.relativePath) == [".secret"])
    }

    @Test func fileVersusFolderIsChanged() async throws {
        let box = try Sandbox()
        try box.write("thing", in: box.source, "file")
        try box.write("thing/inner.txt", in: box.target, "x")
        let r = try await box.compare()
        #expect(r.items.count == 1)
        #expect(r.items.first?.kind == .changed)
        #expect(r.items.first?.relativePath == "thing")
    }

    @Test func reportsProgressPhases() async throws {
        let box = try Sandbox()
        try box.both("a.txt", "a")
        let phases = Locked<[String]>([])
        var opts = CompareOptions()
        opts.compareContents = true
        _ = try await Comparer.compare(source: box.source, target: box.target, options: opts) { p in
            phases.mutate { $0.append(p.phase) }
        }
        let seen = Set(phases.value)
        #expect(seen == ["Scanning master", "Scanning target", "Comparing contents"])
    }
}

@Suite("LocationValidator")
struct LocationValidatorTests {
    @Test func rejectsSameAndNested() throws {
        let box = try Sandbox()
        #expect(throws: LocationError.same) {
            try LocationValidator.validate(source: box.source, target: box.source.appendingPathComponent("."))
        }
        let inner = box.source.appendingPathComponent("inner")
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        #expect(throws: LocationError.nested) {
            try LocationValidator.validate(source: box.source, target: inner)
        }
        #expect(throws: LocationError.nested) {
            try LocationValidator.validate(source: inner, target: box.source)
        }
        try LocationValidator.validate(source: box.source, target: box.target)
    }

    @Test func siblingWithSharedPrefixIsNotNested() throws {
        let box = try Sandbox()
        let sibling = box.root.appendingPathComponent("master copy")
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        try LocationValidator.validate(source: box.source, target: sibling)
    }

    @Test func rejectsFilesAndMissingPaths() throws {
        let box = try Sandbox()
        let file = try box.write("f.txt", in: box.root, "x")
        #expect(throws: LocationError.notAFolder(file.path)) {
            try LocationValidator.validate(source: file, target: box.target)
        }
        let missing = box.root.appendingPathComponent("nope")
        #expect(throws: LocationError.unreadable(missing.path)) {
            try LocationValidator.validate(source: box.source, target: missing)
        }
    }
}

@Suite("Planner")
struct PlannerTests {
    @Test func plansByKindAndRemoveExtras() async throws {
        let box = try Sandbox()
        try box.write("new.txt", in: box.source, "123")
        try box.write("extra.txt", in: box.target, "12345")
        try box.write("edited.txt", in: box.source, "1234567")
        try box.write("edited.txt", in: box.target, "1")
        let r = try await box.compare()

        let keep = Planner.plan(r, removeExtras: false)
        #expect(keep.actions == [
            .copy(relativePath: "new.txt", bytes: 3),
            .replace(relativePath: "edited.txt", bytes: 7),
        ])
        #expect(keep.bytesToWrite == 10)

        let remove = Planner.plan(r, removeExtras: true)
        #expect(remove.actions.last == .trash(relativePath: "extra.txt", bytes: 5))
        #expect(remove.trashes.count == 1)
        #expect(Planner.plan(CompareResult(items: [], identicalCount: 0, sourceFileCount: 0, targetFileCount: 0),
                             removeExtras: true).isEmpty)
    }
}

@Suite("Syncer")
struct SyncerTests {
    @Test func copyReplaceTrashEndToEnd() async throws {
        let box = try Sandbox()
        try box.both("same.txt", "same")
        try box.write("new.txt", in: box.source, "new")
        try box.write("Album/one.jpg", in: box.source, "1")
        try box.write("Album/sub/two.jpg", in: box.source, "22")
        try box.write("edited.txt", in: box.source, "master version", date: Sandbox.baseDate.addingTimeInterval(60))
        try box.write("edited.txt", in: box.target, "old")
        try box.write("thing", in: box.source, "now a file")
        try box.write("thing/inner.txt", in: box.target, "was a folder")
        try box.write("extra.txt", in: box.target, "extra")

        let before = try await box.compare()
        let plan = Planner.plan(before, removeExtras: true)
        let updates = Locked<[SyncProgress]>([])
        let report = await Syncer.run(plan, source: box.source, target: box.target) { p in
            updates.mutate { $0.append(p) }
        }

        #expect(report.copied == 2)
        #expect(report.replaced == 2)
        #expect(!report.cancelled)
        #expect(updates.value.last?.actionsDone == plan.actions.count)
        #expect(updates.value.last?.fraction == 1)

        let edited = try String(contentsOf: box.target.appendingPathComponent("edited.txt"), encoding: .utf8)
        #expect(edited == "master version")
        let mtime = try box.target.appendingPathComponent("edited.txt")
            .resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        #expect(mtime == Sandbox.baseDate.addingTimeInterval(60))
        #expect(FileManager.default.fileExists(atPath: box.target.appendingPathComponent("Album/sub/two.jpg").path))

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: box.target.path)
            .filter { $0.hasPrefix(".filesync-") }
        #expect(leftovers.isEmpty)

        if report.trashed == 1 { // "extra.txt"; the folder "thing" is trashed inside its replace
            #expect(report.failures.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: box.target.appendingPathComponent("extra.txt").path))
            #expect(try await box.compare().isInSync)
        } else {
            // No Trash available here (e.g. a volume without one). The engine must report it,
            // never fall back to a permanent delete.
            #expect(!report.failures.isEmpty)
            #expect(FileManager.default.fileExists(atPath: box.target.appendingPathComponent("extra.txt").path))
            print("Note: trashItem unavailable in this environment; verified it was reported, not deleted.")
        }
    }

    @Test func keepsExtrasWhenNotRemoving() async throws {
        let box = try Sandbox()
        try box.write("new.txt", in: box.source, "n")
        try box.write("extra.txt", in: box.target, "e")
        let plan = Planner.plan(try await box.compare(), removeExtras: false)
        let report = await Syncer.run(plan, source: box.source, target: box.target) { _ in }
        #expect(report.copied == 1 && report.trashed == 0 && report.failures.isEmpty)
        let after = try await box.compare()
        #expect(after.items.map(\.kind) == [.onlyInTarget])
    }

    @Test func rejectsPathsThatEscapeTarget() async throws {
        let box = try Sandbox()
        try box.write("victim.txt", in: box.root, "do not touch")
        let plan = SyncPlan(actions: [
            .trash(relativePath: "../victim.txt", bytes: 1),
            .copy(relativePath: "a/../../victim.txt", bytes: 1),
            .replace(relativePath: "/etc/hosts", bytes: 1),
        ])
        let report = await Syncer.run(plan, source: box.source, target: box.target) { _ in }
        #expect(report.failures.count == 3)
        #expect(report.copied + report.replaced + report.trashed == 0)
        #expect(FileManager.default.fileExists(atPath: box.root.appendingPathComponent("victim.txt").path))
        #expect(throws: Syncer.SyncError.self) { try Syncer.resolve("..", in: box.target) }
    }

    @Test func stopsWhenCancelled() async throws {
        let box = try Sandbox()
        try box.write("a.txt", in: box.source, "a")
        let plan = Planner.plan(try await box.compare(), removeExtras: false)
        let source = box.source, target = box.target
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await Syncer.run(plan, source: source, target: target) { _ in }
        }
        let report = await task.value
        #expect(report.cancelled)
        #expect(report.copied == 0)
    }
}

/// Minimal thread-safe box for collecting values from @Sendable callbacks.
final class Locked<Value>: @unchecked Sendable {
    private var _value: Value
    private let lock = NSLock()
    init(_ value: Value) { _value = value }
    var value: Value { lock.withLock { _value } }
    func mutate(_ body: (inout Value) -> Void) { lock.withLock { body(&_value) } }
}
