import Foundation

/// A single day's activity total, used for the weekly bar chart.
struct DayActivity: Sendable, Identifiable {
    var id: String { dayKey }
    let dayKey: String
    let date: Date
    let label: String
    let activeSeconds: Int
}

/// Time spent on one project/task, aggregated across sessions.
struct ProjectStat: Sendable, Identifiable {
    var id: String { name }
    let name: String
    let activeSeconds: Int
    let sessionCount: Int
}

/// A simple, at-a-glance rollup of the last 7 days of sessions.
/// Everything here is derived from sessions already in memory — no new capture.
struct TimelineStats: Sendable {
    let todayActiveSeconds: Int
    let weekActiveSeconds: Int
    let sessionCount: Int
    let dailyActivity: [DayActivity]      // oldest → newest, always 7 entries
    let topProjects: [ProjectStat]        // sorted desc by time
    let deepWorkCount: Int                // sessions ≥ deep-work threshold
    let longestSessionSeconds: Int
    let averageFocusStars: Double?        // nil when no session qualifies

    var isEmpty: Bool { sessionCount == 0 }
}

enum StatsBuilder {
    static let deepWorkThresholdSeconds = 25 * 60
    private static let daysInWindow = 7
    private static let maxTopProjects = 5

    static func build(from sessions: [Session], now: Date = Date()) -> TimelineStats {
        let calendar = Calendar.current

        let todaySeconds = sessions
            .filter { calendar.isDateInToday($0.startTime) }
            .reduce(0) { $0 + max($1.durationSeconds, 0) }

        let weekSeconds = sessions.reduce(0) { $0 + max($1.durationSeconds, 0) }

        return TimelineStats(
            todayActiveSeconds: todaySeconds,
            weekActiveSeconds: weekSeconds,
            sessionCount: sessions.count,
            dailyActivity: dailyActivity(from: sessions, now: now, calendar: calendar),
            topProjects: topProjects(from: sessions),
            deepWorkCount: sessions.filter { $0.durationSeconds >= deepWorkThresholdSeconds }.count,
            longestSessionSeconds: sessions.map(\.durationSeconds).max() ?? 0,
            averageFocusStars: averageFocusStars(from: sessions)
        )
    }

    // MARK: - Per-day totals

    private static func dailyActivity(
        from sessions: [Session],
        now: Date,
        calendar: Calendar
    ) -> [DayActivity] {
        // Pre-sum active seconds per calendar day.
        var totals: [String: Int] = [:]
        for session in sessions {
            let key = dayKey(session.startTime, calendar: calendar)
            totals[key, default: 0] += max(session.durationSeconds, 0)
        }

        // Emit exactly `daysInWindow` buckets, oldest first, including empty days
        // so the chart shows the shape of the week rather than only active days.
        let today = calendar.startOfDay(for: now)
        return (0..<daysInWindow).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let key = dayKey(date, calendar: calendar)
            return DayActivity(
                dayKey: key,
                date: date,
                label: dayLabel(date, calendar: calendar),
                activeSeconds: totals[key] ?? 0
            )
        }
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    private static func dayLabel(_ date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }

    // MARK: - Top projects

    private static func topProjects(from sessions: [Session]) -> [ProjectStat] {
        var seconds: [String: Int] = [:]
        var counts: [String: Int] = [:]

        for session in sessions {
            let name = SessionDisplay.sessionTitle(for: session).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            seconds[name, default: 0] += max(session.durationSeconds, 0)
            counts[name, default: 0] += 1
        }

        return seconds
            .map { ProjectStat(name: $0.key, activeSeconds: $0.value, sessionCount: counts[$0.key] ?? 1) }
            .sorted { ($0.activeSeconds, $1.name) > ($1.activeSeconds, $0.name) }
            .prefix(maxTopProjects)
            .map { $0 }
    }

    // MARK: - Focus

    private static func averageFocusStars(from sessions: [Session]) -> Double? {
        let stars = sessions.compactMap { SessionDisplay.contextContinuity(for: $0)?.stars }
        guard !stars.isEmpty else { return nil }
        return Double(stars.reduce(0, +)) / Double(stars.count)
    }

    // MARK: - Formatting

    /// Compact hour/minute label for a raw second count, e.g. "0m", "42m", "2h 5m".
    static func durationLabel(_ seconds: Int) -> String {
        let minutes = max(seconds, 0) / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }
}
