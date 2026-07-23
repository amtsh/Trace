import Foundation

struct ContextContinuity: Sendable {
    let stars: Int
    let explanation: String

    var starLabel: String {
        String(repeating: "★", count: stars) + String(repeating: "☆", count: 5 - stars)
    }

    var displayLabel: String {
        "\(starLabel) · \(explanation)"
    }

    var accessibilityLabel: String {
        "Context continuity: \(stars) out of five stars. \(explanation)."
    }
}

enum SessionDisplay {
    private static let shortSessionSeconds = 60
    private static let mediumSessionSeconds = 300
    private static let timeSkewThreshold = 0.30
    private static let continuityMinimumSeconds = 180

    static func elapsedSeconds(for session: Session) -> Int {
        max(session.durationSeconds, 0)
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
            if seconds < 60 {
                return end.formatted(Date.FormatStyle().hour().minute())
            }
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

        if ranked.contains(where: {
            SessionAppDisplay.inferredProject(for: $0)?.lowercased() == session.activity.lowercased()
        }) {
            return session.activity
        }

        if ranked.contains(where: { $0.appName.lowercased() == session.activity.lowercased() }),
           let dominant = ranked.first(where: { $0.appName.lowercased() == session.activity.lowercased() }),
           SessionAppDisplay.bestDisplayLine(for: dominant) == nil,
           let contextual = SessionAppDisplay.bestContextTitle(in: ranked) {
            return contextual
        }

        return session.activity
    }

    static func featuredApp(for session: Session) -> SessionApp? {
        let ranked = SessionAppDisplay.rankedApps(session.apps)
        guard !ranked.isEmpty else { return nil }

        let title = sessionTitle(for: session)
        if let owner = ranked.first(where: {
            SessionAppDisplay.bestDisplayLine(for: $0)?.text == title
        }) {
            return owner
        }

        if !ranked.contains(where: { $0.appName.lowercased() == session.activity.lowercased() }),
           let owner = ranked.first(where: {
               SessionAppDisplay.inferredProject(for: $0)?.lowercased() == session.activity.lowercased()
           }) {
            return owner
        }

        return SessionAppDisplay.appWithBestContext(in: ranked) ?? ranked.first
    }

    static func shouldShowAppInList(
        _ app: SessionApp,
        session: Session,
        candidates: [SessionApp]? = nil
    ) -> Bool {
        let pool = candidates ?? SessionAppDisplay.rankedApps(session.apps)
        let title = sessionTitle(for: session).lowercased()
        let appName = app.appName.lowercased()
        let displayName = SessionAppDisplay.displayName(for: app).lowercased()
        let hasContext = !SessionAppDisplay.contextLines(for: app).isEmpty

        if appName == title || displayName == title {
            return pool.count > 1 ? false : hasContext
        }

        if let line = SessionAppDisplay.bestDisplayLine(for: app),
           line.text == SessionDisplay.sessionTitle(for: session) {
            let others = pool.filter { $0.bundleId != app.bundleId }
            return others.isEmpty ? hasContext : false
        }

        return true
    }

    static func expandedApps(for session: Session) -> [SessionApp] {
        let featured = featuredApp(for: session)
        let detail = session.apps.filter { SessionAppDisplay.shouldShowInDetail($0, in: session) }
        let candidates = detail.isEmpty
            ? SessionAppDisplay.rankedApps(session.apps)
            : detail
        var filtered = candidates.filter {
            shouldShowAppInList($0, session: session, candidates: candidates)
                && !isNoiseApp($0, in: session)
        }
        if filtered.isEmpty {
            let withoutNoise = candidates.filter { !isNoiseApp($0, in: session) }
            filtered = withoutNoise.isEmpty ? candidates : withoutNoise
        }
        if let featured, !filtered.contains(where: { $0.bundleId == featured.bundleId }) {
            filtered.insert(featured, at: 0)
        }
        return filtered
    }

    private static func isNoiseApp(_ app: SessionApp, in session: Session) -> Bool {
        guard session.apps.count > 1 else { return false }
        let totalActive = session.apps.reduce(0) { $0 + $1.activeSeconds }
        guard totalActive > 0 else { return false }
        let share = Double(app.activeSeconds) / Double(totalActive)
        return app.activeSeconds <= 10 && share < 0.1
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
        if textLower == "work session" { return nil }
        if textLower.hasPrefix("reviewed code in ") { return nil }
        if textLower.hasPrefix("worked in ") { return nil }

        let appNames = apps.flatMap {
            [$0.appName.lowercased(), SessionAppDisplay.displayName(for: $0).lowercased()]
        }
        let summaryParts = textLower
            .components(separatedBy: " + ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if summaryParts.count >= 1 && summaryParts.allSatisfy({ appNames.contains($0) }) {
            return nil
        }

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
        let title = sessionTitle(for: session)
        for app in SessionAppDisplay.rankedApps(session.apps) {
            if let line = SessionAppDisplay.bestDisplayLine(for: app),
               line.text != title {
                return line.text
            }
        }
        return nil
    }

    static func appTimeShare(for app: SessionApp, in session: Session) -> String? {
        guard shouldShowAppTimeShares(for: session) else { return nil }
        let seconds = max(app.activeSeconds, 1)
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        return minutes == 1 ? "1m" : "\(minutes)m"
    }

    static func hasRichDetail(_ apps: [SessionApp]) -> Bool {
        apps.contains { !SessionAppDisplay.contextLines(for: $0).isEmpty }
    }

    static func isSingleAppSession(_ session: Session, detailApps: [SessionApp]) -> Bool {
        detailApps.count <= 1 && session.apps.count <= 1
    }

    static func contextContinuity(for session: Session) -> ContextContinuity? {
        let apps = session.apps.filter { !isNoiseApp($0, in: session) }
        let totalActive = apps.reduce(0) { $0 + $1.activeSeconds }
        guard totalActive >= continuityMinimumSeconds else { return nil }

        let onTaskSeconds = apps
            .filter { isOnTask($0, activity: session.activity) }
            .reduce(0) { $0 + $1.activeSeconds }
        let focusRatio = Double(onTaskSeconds) / Double(totalActive)

        if focusRatio > 0.90 {
            return ContextContinuity(stars: 5, explanation: "Stayed on task throughout")
        }
        if focusRatio >= 0.75 {
            return ContextContinuity(stars: 4, explanation: "Mostly on task")
        }
        if focusRatio >= 0.50 {
            return ContextContinuity(stars: 3, explanation: "Some unrelated activity")
        }
        if focusRatio >= 0.30 {
            return ContextContinuity(stars: 2, explanation: "Split between tasks")
        }
        return ContextContinuity(stars: 1, explanation: "Mostly unrelated activity")
    }

    private static func isOnTask(_ app: SessionApp, activity: String) -> Bool {
        let bundle = app.bundleId
        if SessionAppDisplay.isEditor(bundle) { return true }
        if assistantBundles.contains(bundle) { return true }

        let activityLower = activity.lowercased()
        for title in app.windowTitles {
            if title.lowercased().contains(activityLower) { return true }
        }
        for url in app.urls {
            if url.lowercased().contains(activityLower) { return true }
        }

        if let project = SessionAppDisplay.inferredProject(for: app),
           project.lowercased() == activityLower {
            return true
        }

        let devHints = ["stackoverflow", "github", "developer.apple", "localhost", "127.0.0.1"]
        let allContent = (app.windowTitles + app.urls).joined(separator: " ").lowercased()
        if devHints.contains(where: { allContent.contains($0) }) { return true }

        return false
    }

    private static let assistantBundles: Set<String> = [
        "com.anthropic.claude",
        "com.anthropic.claudefordesktop",
        "com.openai.chat",
        "ai.perplexity.mac",
        "ai.perplexity.macv3",
    ]

    private static func appTimeSkew(for session: Session) -> Double {
        let totalActive = session.apps.reduce(0) { $0 + $1.activeSeconds }
        guard totalActive > 0 else { return 0 }

        let shares = session.apps.map { Double($0.activeSeconds) / Double(totalActive) }
        guard let maxShare = shares.max(), let minShare = shares.min() else { return 0 }
        return maxShare - minShare
    }
}
