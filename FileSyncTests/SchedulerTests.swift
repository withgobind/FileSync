import Foundation
import Testing
@testable import FileSync

/// Fixed calendar and dates so the tests don't depend on the Mac's clock, zone or locale.
enum Clock {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        c.locale = Locale(identifier: "en_US")
        return c
    }()

    static let locale = Locale(identifier: "en_US")

    /// 17 Nov 2026 is a Tuesday.
    static func date(_ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0, month: Int = 11) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day,
                                           hour: hour, minute: minute, second: second))!
    }

    static func job(_ schedule: Schedule, lastRun: Date?, enabled: Bool = true) -> SyncJob {
        SyncJob(name: "Test", sourcePath: "/a", targetPath: "/b",
                schedule: schedule, isEnabled: enabled, lastRun: lastRun)
    }
}

@Suite("ScheduleMath")
struct ScheduleMathTests {
    let cal = Clock.calendar

    func next(_ s: Schedule, last: Date?, now: Date) -> Date? {
        ScheduleMath.nextRun(for: s, lastRun: last, after: now, calendar: cal)
    }

    func due(_ s: Schedule, last: Date?, now: Date, enabled: Bool = true) -> Bool {
        ScheduleMath.isDue(Clock.job(s, lastRun: last, enabled: enabled), now: now, calendar: cal)
    }

    @Test func offNeverRuns() {
        let now = Clock.date(17, 10)
        #expect(next(.off, last: nil, now: now) == nil)
        #expect(next(.off, last: Clock.date(1, 0), now: now) == nil)
        #expect(!due(.off, last: nil, now: now))
    }

    @Test func everyHoursDueAndNotDue() {
        let now = Clock.date(17, 10)
        #expect(next(.everyHours(6), last: nil, now: now) == now)
        #expect(due(.everyHours(6), last: nil, now: now))
        #expect(next(.everyHours(6), last: Clock.date(17, 5), now: now) == Clock.date(17, 11))
        #expect(!due(.everyHours(6), last: Clock.date(17, 5), now: now))
        #expect(due(.everyHours(6), last: Clock.date(17, 3), now: now))
        #expect(due(.everyHours(6), last: Clock.date(17, 4), now: now)) // exactly on time
    }

    @Test func everyHoursClampsToOneThroughTwentyFour() {
        let last = Clock.date(17, 0)
        let now = Clock.date(17, 0, 30)
        #expect(next(.everyHours(0), last: last, now: now) == Clock.date(17, 1))
        #expect(next(.everyHours(-3), last: last, now: now) == Clock.date(17, 1))
        #expect(next(.everyHours(99), last: last, now: now) == Clock.date(18, 0))
    }

    @Test func disabledJobIsNeverDue() {
        #expect(!due(.everyHours(1), last: nil, now: Clock.date(17, 10), enabled: false))
    }

    @Test func dailyFirstRunIsNextOccurrenceAtOrAfterNow() {
        let nine = Schedule.daily(hour: 9, minute: 0)
        #expect(next(nine, last: nil, now: Clock.date(17, 8)) == Clock.date(17, 9))
        #expect(next(nine, last: nil, now: Clock.date(17, 9)) == Clock.date(17, 9))
        #expect(due(nine, last: nil, now: Clock.date(17, 9)))
        #expect(next(nine, last: nil, now: Clock.date(17, 10)) == Clock.date(18, 9))
        #expect(!due(nine, last: nil, now: Clock.date(17, 10)))
    }

    @Test func dailyBeforeAndAfterTime() {
        let nine = Schedule.daily(hour: 9, minute: 0)
        // Ran yesterday on time; before 9 today → not due yet, next is today 9:00.
        let ranYesterday = Clock.date(16, 9, 0, 4)
        #expect(next(nine, last: ranYesterday, now: Clock.date(17, 8, 59)) == Clock.date(17, 9))
        #expect(!due(nine, last: ranYesterday, now: Clock.date(17, 8, 59)))
        // After 9 today without a run since yesterday → due at today's 9:00.
        #expect(next(nine, last: ranYesterday, now: Clock.date(17, 9, 1)) == Clock.date(17, 9))
        #expect(due(nine, last: ranYesterday, now: Clock.date(17, 9, 1)))
        // Ran today at 9 → next is tomorrow.
        #expect(next(nine, last: Clock.date(17, 9, 0, 3), now: Clock.date(17, 10)) == Clock.date(18, 9))
        #expect(!due(nine, last: Clock.date(17, 9, 0, 3), now: Clock.date(17, 10)))
    }

    @Test func dailyCatchUpReturnsOnlyMostRecentMissedOccurrence() {
        let nine = Schedule.daily(hour: 9, minute: 30)
        let ranDaysAgo = Clock.date(12, 9, 30)
        // Mac was off for days; after today's time → today's occurrence only.
        #expect(next(nine, last: ranDaysAgo, now: Clock.date(17, 11)) == Clock.date(17, 9, 30))
        // Woken before today's time → yesterday's occurrence, not the 13th.
        #expect(next(nine, last: ranDaysAgo, now: Clock.date(17, 7)) == Clock.date(16, 9, 30))
        #expect(due(nine, last: ranDaysAgo, now: Clock.date(17, 7)))
        // After the catch-up run, the next one is the following occurrence, not another missed day.
        let caughtUp = Clock.date(17, 7, 0, 5)
        #expect(next(nine, last: caughtUp, now: Clock.date(17, 7, 1)) == Clock.date(17, 9, 30))
        #expect(!due(nine, last: caughtUp, now: Clock.date(17, 7, 1)))
    }

    @Test func weekly() {
        let monday = Schedule.weekly(weekday: 2, hour: 9, minute: 0)
        let now = Clock.date(17, 10) // Tuesday
        #expect(next(monday, last: nil, now: now) == Clock.date(23, 9))
        #expect(next(monday, last: Clock.date(16, 9, 0, 2), now: now) == Clock.date(23, 9))
        #expect(!due(monday, last: Clock.date(16, 9, 0, 2), now: now))
        // Missed yesterday's run (and the one before) → a single catch-up for Monday 16th.
        #expect(next(monday, last: Clock.date(2, 9, 0, 2), now: now) == Clock.date(16, 9))
        #expect(due(monday, last: Clock.date(2, 9, 0, 2), now: now))
    }

    @Test func describeStrings() {
        func d(_ s: Schedule) -> String { ScheduleMath.describe(s, calendar: cal, locale: Clock.locale) }
        #expect(d(.off) == "Off")
        #expect(d(.everyHours(1)) == "Every hour")
        #expect(d(.everyHours(6)) == "Every 6 hours")
        #expect(d(.daily(hour: 9, minute: 0)) == "Daily at 9:00 AM")
        #expect(d(.daily(hour: 18, minute: 45)) == "Daily at 6:45 PM")
        #expect(d(.weekly(weekday: 2, hour: 9, minute: 0)) == "Every Monday at 9:00 AM")
        #expect(d(.weekly(weekday: 1, hour: 0, minute: 5)) == "Every Sunday at 12:05 AM")
    }

    @Test func describeNextStrings() {
        func d(_ s: Schedule, last: Date?, now: Date) -> String? {
            ScheduleMath.describeNext(Clock.job(s, lastRun: last), now: now, calendar: cal, locale: Clock.locale)
        }
        let nine = Schedule.daily(hour: 9, minute: 0)
        #expect(d(.off, last: nil, now: Clock.date(17, 8)) == nil)
        #expect(d(nine, last: Clock.date(16, 9), now: Clock.date(17, 8)) == "Next: today at 9:00 AM")
        #expect(d(nine, last: Clock.date(17, 9), now: Clock.date(17, 10)) == "Next: tomorrow at 9:00 AM")
        #expect(d(nine, last: Clock.date(10, 9), now: Clock.date(17, 10)) == "Due now")
        #expect(d(.weekly(weekday: 2, hour: 9, minute: 0), last: Clock.date(16, 9), now: Clock.date(17, 10))
                == "Next: Mon 23 Nov at 9:00 AM")
    }

    @Test(arguments: [
        Schedule.off,
        .everyHours(6),
        .daily(hour: 9, minute: 15),
        .weekly(weekday: 7, hour: 22, minute: 0),
    ])
    func syncJobCodableRoundTrip(_ schedule: Schedule) throws {
        var job = SyncJob(name: "Photos", sourcePath: "/Volumes/A/Photos", targetPath: "/Volumes/B/Photos")
        job.sourceBookmark = Data([1, 2, 3])
        job.removeExtras = true
        job.schedule = schedule
        job.action = .syncAutomatically
        job.lastRun = Date(timeIntervalSince1970: 1_700_000_000)
        job.lastSummary = "Copied 3 files"
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let back = try decoder.decode(SyncJob.self, from: encoder.encode(job))
        #expect(back == job)
    }
}

@Suite("JobStore")
@MainActor
struct JobStoreTests {
    let folder: URL
    var file: URL { folder.appendingPathComponent("jobs.json") }

    init() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileSyncJobStore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func contents() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    @Test func upsertUpdateDeletePersistAndReload() throws {
        defer { try? FileManager.default.removeItem(at: folder) } // test scratch only
        let store = JobStore(fileURL: file)
        #expect(store.jobs.isEmpty)

        let b = SyncJob(name: "Backup 10", sourcePath: "/s", targetPath: "/t", schedule: .daily(hour: 9, minute: 0))
        let a = SyncJob(name: "backup 2", sourcePath: "/s2", targetPath: "/t2", schedule: .everyHours(3))
        let c = SyncJob(name: "Archive", sourcePath: "/s3", targetPath: "/t3")
        store.upsert(b)
        store.upsert(a)
        store.upsert(c)
        #expect(store.jobs.map(\.name) == ["Archive", "backup 2", "Backup 10"])

        let ran = Date(timeIntervalSince1970: 1_763_000_000)
        store.update(id: a.id) { $0.lastRun = ran; $0.lastSummary = "Done" }
        var renamed = c
        renamed.name = "Zed"
        store.upsert(renamed)
        store.delete(id: b.id)
        #expect(store.jobs.map(\.name) == ["backup 2", "Zed"])
        #expect(store.job(id: b.id) == nil)

        let reloaded = JobStore(fileURL: file)
        #expect(reloaded.jobs == store.jobs)
        #expect(reloaded.job(id: a.id)?.lastRun == ran)
        #expect(reloaded.job(id: a.id)?.schedule == .everyHours(3))

        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("\"lastRun\" : \"2025-"))
    }

    @Test func corruptFileLoadsEmptyAndIsKeptAside() throws {
        defer { try? FileManager.default.removeItem(at: folder) } // test scratch only
        try Data("not json {".utf8).write(to: file)
        let store = JobStore(fileURL: file)
        #expect(store.jobs.isEmpty)
        #expect(store.lastError != nil)
        let names = try contents()
        #expect(!names.contains("jobs.json"))
        let aside = try #require(names.first { $0.hasPrefix("jobs.corrupt-") && $0.hasSuffix(".json") })
        #expect(try String(contentsOf: folder.appendingPathComponent(aside), encoding: .utf8) == "not json {")

        store.upsert(SyncJob(name: "New", sourcePath: "/s", targetPath: "/t"))
        #expect(try contents().count == 2)
        #expect(JobStore(fileURL: file).jobs.map(\.name) == ["New"])
    }

    @Test func resolvePrefersExistingLocations() throws {
        defer { try? FileManager.default.removeItem(at: folder) } // test scratch only
        let real = folder.appendingPathComponent("Real", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let mark = JobStore.bookmark(for: real)
        #expect(mark != nil)
        #expect(JobStore.resolve(path: "/nope/missing", bookmark: mark)?.standardizedFileURL.lastPathComponent == "Real")
        #expect(JobStore.resolve(path: real.path, bookmark: nil) != nil)
        #expect(JobStore.resolve(path: folder.appendingPathComponent("Gone").path, bookmark: nil) == nil)
    }
}
