import Foundation

enum SessionBuilder {
    private static let hardBreakSeconds: TimeInterval = 30 * 60
    private static let unrelatedSnapshotThreshold = 2
    private static let substantialDetourSeconds: TimeInterval = 5 * 60

    private static let assistantBundles: Set<String> = [
        "com.anthropic.claude",
        "com.openai.chat",
    ]
    private static let xcodeBundle = "com.apple.dt.Xcode"

    private static let workBundles: Set<String> = [
        xcodeBundle,
        "com.todesktop.230313mzl4w4u92",
        "com.microsoft.VSCode",
        "com.apple.TextEdit",
    ]

    private static let browserBundles: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "company.thebrowser.Browser",
        "company.thebrowser.dia",
        "org.mozilla.firefox",
        "com.brave.Browser",
        "com.microsoft.edgemac",
    ]

    private static let sourceFileExtensions: Set<String> = [
        "swift", "m", "mm", "h", "cpp", "c", "rs", "go", "py", "js", "ts",
        "tsx", "jsx", "java", "kt", "rb", "php", "cs", "vue", "svelte",
    ]

    static func buildSessions(from snapshots: [Snapshot]) -> [Session] {
        let active = snapshots
            .filter { !$0.isIdle }
            .sorted { $0.timestamp < $1.timestamp }
        guard let first = active.first else { return [] }

        var groups: [(snapshots: [Snapshot], project: String?)] = []
        var related: [Snapshot] = []
        var relatedProject: String?
        var unrelatedPending: [Snapshot] = []

        func flushRelated() {
            guard !related.isEmpty else { return }
            groups.append((related, relatedProject))
            related = []
            relatedProject = nil
        }

        func isSubstantialDetour(endingAt end: Date) -> Bool {
            guard unrelatedPending.count >= unrelatedSnapshotThreshold,
                  let first = unrelatedPending.first else { return false }
            return end.timeIntervalSince(first.timestamp) >= substantialDetourSeconds
        }

        func flushAtBoundary() {
            let end = unrelatedPending.last?.timestamp ?? .distantPast
            if isSubstantialDetour(endingAt: end) {
                flushRelated()
                let project = unrelatedPending.compactMap { extractProject(from: $0) }.first
                groups.append((unrelatedPending, project))
            } else {
                related.append(contentsOf: unrelatedPending)
                flushRelated()
            }
            unrelatedPending = []
        }

        func absorbRelated(_ snap: Snapshot) {
            if isSubstantialDetour(endingAt: snap.timestamp) {
                let project = unrelatedPending.compactMap { extractProject(from: $0) }.first
                groups.append((unrelatedPending, project))
            } else {
                related.append(contentsOf: unrelatedPending)
            }
            unrelatedPending = []
            related.append(snap)
            if let project = extractProject(from: snap) {
                relatedProject = mergeProjects(relatedProject, project)
            }
        }

        absorbRelated(first)

        for snap in active.dropFirst() {
            let anchor = related.last ?? unrelatedPending.last ?? snap
            let gap = snap.timestamp.timeIntervalSince(anchor.timestamp)

            if gap > hardBreakSeconds {
                flushAtBoundary()
                absorbRelated(snap)
                continue
            }

            if let project = extractProject(from: snap),
               let current = relatedProject,
               projectsConflict(current: current, next: project) {
                flushAtBoundary()
                absorbRelated(snap)
                continue
            }

            if isRelated(snap, sessionProject: relatedProject, sessionSnapshots: related) {
                absorbRelated(snap)
            } else {
                unrelatedPending.append(snap)
            }
        }

        flushAtBoundary()

        return groups.map { makeSession(from: $0.snapshots, project: $0.project) }.reversed()
    }

    // MARK: - Relatedness

    private static func isRelated(
        _ snapshot: Snapshot,
        sessionProject: String?,
        sessionSnapshots: [Snapshot]
    ) -> Bool {
        if sessionSnapshots.isEmpty { return true }

        if let snapProject = extractProject(from: snapshot) {
            if let sessionProject {
                return !projectsConflict(current: sessionProject, next: snapProject)
            }
            return true
        }

        if assistantBundles.contains(snapshot.appBundle) { return true }

        if isWorkApp(snapshot.appBundle) {
            if let sessionProject, let url = snapshot.documentURL,
               let pathProject = projectFromFileURL(url) {
                return normalizeProjectName(pathProject) == normalizeProjectName(sessionProject)
            }
            return true
        }

        if let sessionProject {
            return contentRelatesToProject(snapshot, project: sessionProject)
        }

        return true
    }

    private static func isWorkApp(_ bundleId: String) -> Bool {
        workBundles.contains(bundleId) || terminalBundles.contains(bundleId)
    }

    private static func isCompanionApp(_ bundleId: String) -> Bool {
        browserBundles.contains(bundleId)
    }

    private static func contentRelatesToProject(_ snapshot: Snapshot, project: String) -> Bool {
        let needle = normalizeProjectName(project).lowercased()
        guard !needle.isEmpty else { return false }

        if let title = snapshot.windowTitle?.lowercased() {
            if title.contains(needle) { return true }
            let devHints = ["stackoverflow", "github", "developer.apple", "localhost", "127.0.0.1"]
            if devHints.contains(where: { title.contains($0) }) { return true }
        }

        if let url = snapshot.documentURL?.lowercased() {
            if url.contains(needle) { return true }
            let devHints = [
                "github.com", "stackoverflow.com", "developer.apple.com",
                "localhost", "127.0.0.1",
            ]
            if devHints.contains(where: { url.contains($0) }) { return true }
        }

        return false
    }

    private static func projectsConflict(current: String?, next: String?) -> Bool {
        guard let next else { return false }
        guard let current else { return false }
        return normalizeProjectName(current) != normalizeProjectName(next)
    }

    private static func mergeProjects(_ existing: String?, _ incoming: String) -> String {
        guard let existing else { return incoming }
        return projectNamePriority(incoming) > projectNamePriority(existing) ? incoming : existing
    }

    private static func projectNamePriority(_ name: String) -> Int {
        if name.hasSuffix(".xcodeproj") || name.hasSuffix(".xcworkspace") { return 3 }
        if !looksLikeSourceFile(name) { return 2 }
        return 1
    }

    private static func normalizeProjectName(_ name: String) -> String {
        if name.hasSuffix(".xcodeproj") {
            return String(name.dropLast(".xcodeproj".count))
        }
        if name.hasSuffix(".xcworkspace") {
            return String(name.dropLast(".xcworkspace".count))
        }
        return name
    }

    private static func looksLikeSourceFile(_ name: String) -> Bool {
        guard let ext = name.split(separator: ".").last?.lowercased(),
              name.contains(".") else { return false }
        return sourceFileExtensions.contains(ext)
    }

    // MARK: - Project extraction

    private static let editorSuffixes: Set<String> = [
        "Cursor", "Visual Studio Code", "Code",
        "IntelliJ IDEA", "WebStorm", "PyCharm", "CLion", "GoLand",
        "RubyMine", "PhpStorm", "DataGrip", "Rider", "RustRover",
        "Android Studio", "Fleet",
        "Sublime Text",
        "Nova", "BBEdit", "TextMate", "CotEditor",
        "VIM", "MacVim",
    ]

    private static let terminalBundles: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "io.alacritty",
        "net.kovidgoyal.kitty",
        "com.mitchellh.ghostty",
    ]

    private static let genericDirs: Set<String> = [
        "users", "home", "developer", "documents", "desktop",
        "downloads", "projects", "repos", "workspace", "workspaces",
        "src", "lib", "app", "sources", "tests", "test", "spec",
        "build", "dist", "out", "bin", "cmd", "internal", "pkg",
        "vendor", "node_modules", "packages", "target",
    ]

    static func extractProject(from snapshot: Snapshot) -> String? {
        let isTerminal = terminalBundles.contains(snapshot.appBundle)
        let isXcode = snapshot.appBundle == xcodeBundle

        if let title = snapshot.windowTitle, !title.isEmpty {
            if isTerminal {
                if let project = projectFromTerminalTitle(title) {
                    return project
                }
            } else if isXcode, let project = projectFromXcodeTitle(title, documentURL: snapshot.documentURL) {
                return project
            } else if workBundles.contains(snapshot.appBundle) || browserBundles.contains(snapshot.appBundle) {
                let emParts = title.components(separatedBy: " — ")
                if emParts.count >= 2, let last = emParts.last, !last.isEmpty {
                    let trimmed = last.trimmingCharacters(in: .whitespaces)
                    if !looksLikeSourceFile(trimmed),
                       trimmed.caseInsensitiveCompare(snapshot.appName) != .orderedSame {
                        return trimmed
                    }
                }

                let hyphenParts = title.components(separatedBy: " - ")
                if hyphenParts.count >= 3 {
                    let last = hyphenParts.last!.trimmingCharacters(in: .whitespaces)
                    if editorSuffixes.contains(last) {
                        let proj = hyphenParts[hyphenParts.count - 2]
                            .trimmingCharacters(in: .whitespaces)
                        if !proj.isEmpty { return proj }
                    }
                }
            }
        }

        if let url = snapshot.documentURL {
            if url.hasPrefix("file://") {
                if let project = projectFromFileURL(url) {
                    return project
                }
            }
            if url.contains("github.com/") {
                let parts = url.components(separatedBy: "github.com/")
                if let pathPart = parts.last {
                    let segments = pathPart.components(separatedBy: "/")
                        .filter { !$0.isEmpty }
                    if segments.count >= 2 {
                        return segments[1].components(separatedBy: "?").first
                    }
                }
            }
        }

        return nil
    }

    private static func projectFromXcodeTitle(_ title: String, documentURL: String?) -> String? {
        let parts = title.components(separatedBy: " — ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if parts.count >= 2 {
            for part in parts {
                if part.hasSuffix(".xcodeproj") || part.hasSuffix(".xcworkspace") {
                    return normalizeProjectName(part)
                }
            }
            for part in parts where !looksLikeSourceFile(part) {
                return part
            }
            if let project = documentURL.flatMap(projectFromFileURL) {
                return project
            }
            return parts.first
        }

        let single = parts.first ?? title.trimmingCharacters(in: .whitespaces)
        if single.hasSuffix(".xcodeproj") || single.hasSuffix(".xcworkspace") {
            return normalizeProjectName(single)
        }
        return documentURL.flatMap(projectFromFileURL)
    }

    private static func projectFromTerminalTitle(_ title: String) -> String? {
        for part in title.components(separatedBy: " — ") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if let project = projectFromPath(trimmed) {
                return project
            }
        }

        if let colonIdx = title.firstIndex(of: ":") {
            let after = String(title[title.index(after: colonIdx)...])
                .trimmingCharacters(in: .whitespaces)
            if let project = projectFromPath(after) {
                return project
            }
        }

        return projectFromPath(title)
    }

    private static func projectFromFileURL(_ urlString: String) -> String? {
        var path = String(urlString.dropFirst("file://".count))
        if let decoded = path.removingPercentEncoding { path = decoded }
        return projectFromPath(path)
    }

    private static func projectFromPath(_ path: String) -> String? {
        let components = path.components(separatedBy: "/")
            .filter { !$0.isEmpty && $0 != "~" }
        guard components.count >= 2 else { return nil }

        var dirs = components
        if let last = dirs.last, last.contains(".") && !last.hasPrefix(".") {
            dirs.removeLast()
        }

        for dir in dirs.reversed() {
            if !genericDirs.contains(dir.lowercased()) && !dir.hasPrefix(".") {
                return dir
            }
        }
        return nil
    }

    // MARK: - Build session

    private static func makeSession(from snapshots: [Snapshot], project: String?) -> Session {
        let start = snapshots.first!.timestamp
        let end = snapshots.last!.timestamp
        let minutes = max(Int(end.timeIntervalSince(start) / 60), 1)
        let activity = resolveActivity(from: snapshots, project: project)

        return Session(
            id: "session-\(Int(start.timeIntervalSince1970))",
            startTime: start,
            endTime: end,
            durationMinutes: minutes,
            apps: buildApps(from: snapshots),
            activity: activity
        )
    }

    private static func resolveActivity(from snapshots: [Snapshot], project: String?) -> String {
        var best: (priority: Int, name: String)?

        if let project {
            best = (projectNamePriority(project), normalizeProjectName(project))
        }

        for snap in snapshots {
            guard let raw = extractProject(from: snap) else { continue }
            let priority = projectNamePriority(raw)
            let name = normalizeProjectName(raw)
            if best == nil || priority > best!.priority {
                best = (priority, name)
            }
        }

        if let best { return best.name }
        return dominantApp(from: snapshots)
    }

    private static func dominantApp(from snapshots: [Snapshot]) -> String {
        var counts: [String: Int] = [:]
        for snap in snapshots {
            counts[snap.appName, default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key ?? "Activity"
    }

    private static func buildApps(from snapshots: [Snapshot]) -> [SessionApp] {
        var order: [String] = []
        var names: [String: String] = [:]
        var titles: [String: Set<String>] = [:]
        var urls: [String: Set<String>] = [:]
        var counts: [String: Int] = [:]

        for snap in snapshots {
            let b = snap.appBundle
            counts[b, default: 0] += 1
            if names[b] == nil {
                order.append(b)
                names[b] = snap.appName
                titles[b] = []
                urls[b] = []
            }
            if let t = snap.windowTitle { titles[b]!.insert(t) }
            if let u = snap.documentURL { urls[b]!.insert(u) }
        }

        let apps = order.map { b in
            SessionApp(
                appName: names[b]!,
                bundleId: b,
                windowTitles: Array(titles[b]!),
                urls: Array(urls[b]!),
                snapshotCount: counts[b] ?? 1
            )
        }
        return SessionAppDisplay.rankedApps(apps)
    }
}
