import Foundation

/// Pure date math for saved-sync schedules: when a job runs next, whether it is due, and how to say so.
enum ScheduleMath {
    /// The next time `schedule` should run.
    ///
    /// A date at or before `now` means the job is due. A clock time missed while the Mac was asleep or off
    /// comes back as the most recent missed occurrence, so it runs once on wake; older misses are not replayed.
    static func nextRun(for schedule: Schedule, lastRun: Date?, after now: Date, calendar: Calendar = .current) -> Date? {
        switch schedule {
        case .off:
            return nil
        case .everyHours(let hours):
            guard let lastRun else { return now }
            let h = min(max(hours, 1), 24)
            return lastRun.addingTimeInterval(TimeInterval(h) * 3600)
        case .daily(let hour, let minute):
            return nextOccurrence(of: components(weekday: nil, hour: hour, minute: minute),
                                  lastRun: lastRun, now: now, calendar: calendar)
        case .weekly(let weekday, let hour, let minute):
            return nextOccurrence(of: components(weekday: weekday, hour: hour, minute: minute),
                                  lastRun: lastRun, now: now, calendar: calendar)
        }
    }

    /// True when the job is turned on and its next run is now or earlier.
    static func isDue(_ job: SyncJob, now: Date, calendar: Calendar = .current) -> Bool {
        guard job.isEnabled,
              let next = nextRun(for: job.schedule, lastRun: job.lastRun, after: now, calendar: calendar)
        else { return false }
        return next <= now
    }

    /// Plain words for a schedule, such as "Every 6 hours" or "Every Monday at 9:00 AM".
    static func describe(_ schedule: Schedule, calendar: Calendar = .current, locale: Locale = .current) -> String {
        switch schedule {
        case .off:
            return "Off"
        case .everyHours(let hours):
            let h = min(max(hours, 1), 24)
            return h == 1 ? "Every hour" : "Every \(h) hours"
        case .daily(let hour, let minute):
            return "Daily at \(timeText(hour: hour, minute: minute, calendar: calendar, locale: locale))"
        case .weekly(let weekday, let hour, let minute):
            var cal = calendar
            cal.locale = locale
            let symbols = cal.weekdaySymbols
            let day = symbols[min(max(weekday, 1), 7) - 1]
            return "Every \(day) at \(timeText(hour: hour, minute: minute, calendar: calendar, locale: locale))"
        }
    }

    /// "Next: today at 9:00 AM", "Next: tomorrow at 9:00 AM", "Next: Mon 17 Nov at 9:00 AM" or "Due now";
    /// nil when the schedule is off.
    static func describeNext(_ job: SyncJob, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String? {
        guard let next = nextRun(for: job.schedule, lastRun: job.lastRun, after: now, calendar: calendar) else {
            return nil
        }
        if next <= now { return "Due now" }
        let time = formatted(next, calendar: calendar, locale: locale) { $0.timeStyle = .short; $0.dateStyle = .none }
        let startOfToday = calendar.startOfDay(for: now)
        let dayGap = calendar.dateComponents([.day], from: startOfToday, to: calendar.startOfDay(for: next)).day ?? 0
        switch dayGap {
        case 0: return "Next: today at \(time)"
        case 1: return "Next: tomorrow at \(time)"
        default:
            let day = formatted(next, calendar: calendar, locale: locale) { $0.dateFormat = "EEE d MMM" }
            return "Next: \(day) at \(time)"
        }
    }

    // MARK: - Helpers

    private static func components(weekday: Int?, hour: Int, minute: Int) -> DateComponents {
        var c = DateComponents()
        if let weekday { c.weekday = min(max(weekday, 1), 7) }
        c.hour = min(max(hour, 0), 23)
        c.minute = min(max(minute, 0), 59)
        c.second = 0
        return c
    }

    private static func nextOccurrence(of match: DateComponents, lastRun: Date?, now: Date, calendar: Calendar) -> Date? {
        guard let lastRun else {
            // First run: the next occurrence at or after now.
            return calendar.nextDate(after: now.addingTimeInterval(-1), matching: match, matchingPolicy: .nextTime)
        }
        // The most recent occurrence at or before now. If the last run predates it, that one was missed:
        // return it so the job is due now (a single catch-up, not one per missed day).
        if let previous = calendar.nextDate(after: now.addingTimeInterval(1), matching: match,
                                            matchingPolicy: .nextTime, direction: .backward),
           previous <= now, lastRun < previous {
            return previous
        }
        return calendar.nextDate(after: lastRun, matching: match, matchingPolicy: .nextTime)
    }

    private static func timeText(hour: Int, minute: Int, calendar: Calendar, locale: Locale) -> String {
        var c = DateComponents()
        c.year = 2001; c.month = 1; c.day = 1
        c.hour = min(max(hour, 0), 23)
        c.minute = min(max(minute, 0), 59)
        guard let date = calendar.date(from: c) else { return String(format: "%d:%02d", hour, minute) }
        return formatted(date, calendar: calendar, locale: locale) { $0.timeStyle = .short; $0.dateStyle = .none }
    }

    private static func formatted(_ date: Date, calendar: Calendar, locale: Locale,
                                  configure: (DateFormatter) -> Void) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = locale
        configure(f)
        // Newer ICU puts a narrow no-break space before AM/PM; plain spaces read the same and compare simply.
        return f.string(from: date).replacingOccurrences(of: "\u{202F}", with: " ")
    }
}
