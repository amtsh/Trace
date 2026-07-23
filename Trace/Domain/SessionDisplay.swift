import Foundation

enum SessionDisplay {
    private static let shortSessionSeconds = 60
    private static let mediumSessionSeconds = 300
    private static let timeSkewThreshold = 0.30

    static func elapsedSeconds(for session: Session) -> Int {
        max(Int(session.endTime.timeIntervalSince(session.startTime)), 0)
    }

    static func durationLabel(for session: Session) -> String {
        let seconds = elapsedSeconds(for: session)
        if seconds < 60 {
            return seconds <= 5 ? "< 1 min" : "\(seconds)s"
        }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }

    static func relativeTimeLabel(for session: Session, now: Date = Date()) -> String {
        let end = session.endTime
        let calendar = Calendar.current

        if calendar.isDateInToday(end) {
            let seconds = max(Int(now.timeIntervalSince(end)), 0)
            if seconds < 60 { return "Now" }
            if seconds < 3600 { return "\(seconds / 60)m ago" }
            return "\(seconds / 3600)h ago"
        }

        if calendar.isDateInYesterday(end) {
            let time = end.formatted(Date.FormatStyle().hour().minute())
            return "Yesterday, \(time)"
        }

        let endDay = calendar.startOfDay(for: end)
        let nowDay = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: endDay, to: nowDay).day ?? 0
        if days < 7 {
            return days == 1 ? "1 day ago" : "\(days) days ago"
        }

        return end.formatted(Date.FormatStyle().month(.abbreviated).day().hour().minute())
    }

    static func shouldShowTimeRange(for session: Session) -> Bool {
        elapsedSeconds(for: session) >= shortSessionSeconds
    }

    static func timeRangeLabel(for session: Session) -> String? {
        guard shouldShowTimeRange(for: session) else { return nil }
        let fmt = Date.FormatStyle().hour().minute()
        return "\(session.startTime.formatted(fmt)) – \(session.endTime.formatted(fmt))"
    }

    static func timeRangeWithDurationLabel(for session: Session) -> String? {
        guard let range = timeRangeLabel(for: session) else { return nil }
        return "\(range) · \(durationLabel(for: session))"
    }

    static func shouldShowAppTimeShares(for session: Session) -> Bool {
        guard session.apps.count > 1 else { return false }
        let seconds = elapsedSeconds(for: session)
        guard seconds >= shortSessionSeconds else { return false }
        if seconds > mediumSessionSeconds { return true }
        return appTimeSkew(for: session) > timeSkewThreshold
    }

    static func sessionTitle(for session: Session) -> String {
        let ranked = SessionAppDisplay.rankedApps(session.apps)
        guard let primary = ranked.first else { return session.activity }

        if session.activity.lowercased() == primary.appName.lowercased(),
           let project = SessionAppDisplay.inferredProject(for: primary) {
            return project
        }

        return session.activity
    }

    static func contextSubtitle(for session: Session) -> String? {
        if let summary = usefulSummary(session.summary, activity: sessionTitle(for: session), apps: session.apps) {
            return summary
        }
        return builtInContext(for: session)
    }

    static func usefulSummary(_ summary: String?, activity: String, apps: [SessionApp]) -> String? {
        guard var text = summary?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }

        let activityLower = activity.lowercased()
        let textLower = text.lowercased()

        if textLower == activityLower { return nil }
        if textLower == "working in \(activityLower)" { return nil }
        if textLower == "no activity recorded" { return nil }

        if text.hasSuffix(":") {
            let withoutColon = text.dropLast().trimmingCharacters(in: .whitespaces)
            if withoutColon.lowercased() == activityLower { return nil }
        }

        if textLower.hasPrefix("\(activityLower):") {
            text = String(text.dropFirst(activity.count + 1)).trimmingCharacters(in: .whitespaces)
            if text.isEmpty { return nil }
        }

        if apps.count == 1,
           let app = apps.first,
           app.appName.lowercased() == activityLower,
           textLower == app.appName.lowercased() {
            return nil
        }

        return text
    }

    static func builtInContext(for session: Session) -> String? {
        let ranked = SessionAppDisplay.rankedApps(session.apps)
        guard let primary = ranked.first else { return nil }
        return SessionAppDisplay.bestDisplayLine(for: primary)?.text
    }

    static func appTimeShare(for app: SessionApp, in session: Session) -> String? {
        guard shouldShowAppTimeShares(for: session) else { return nil }
        let total = session.apps.reduce(0) { $0 + $1.snapshotCount }
        guard total > 0 else { return nil }

        let seconds = elapsedSeconds(for: session)
        let share = max(Int((Double(seconds) * Double(app.snapshotCount)) / Double(total)), 1)
        if share < 60 { return "\(share)s" }
        let minutes = share / 60
        return minutes == 1 ? "1m" : "\(minutes)m"
    }

    static func hasRichDetail(_ apps: [SessionApp]) -> Bool {
        apps.contains { !SessionAppDisplay.contextLines(for: $0).isEmpty }
    }

    static func isSingleAppSession(_ session: Session, detailApps: [SessionApp]) -> Bool {
        detailApps.count <= 1 && session.apps.count <= 1
    }

    private static func appTimeSkew(for session: Session) -> Double {
        let totalSnapshots = session.apps.reduce(0) { $0 + $1.snapshotCount }
        guard totalSnapshots > 0 else { return 0 }

        let seconds = Double(elapsedSeconds(for: session))
        guard seconds > 0 else { return 0 }

        let shares = session.apps.map {
            Double($0.snapshotCount) / Double(totalSnapshots) * seconds
        }
        guard let maxShare = shares.max(), let minShare = shares.min() else { return 0 }
        return (maxShare - minShare) / seconds
    }
}
