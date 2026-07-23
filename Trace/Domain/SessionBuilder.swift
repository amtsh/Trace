import Foundation

enum SessionBuilder {
    private static let hardBreakSeconds: TimeInterval = 30 * 60
    private static let unrelatedSnapshotThreshold = 4
    private static let substantialDetourSeconds: TimeInterval = 8 * 60
    private static let microSessionSeconds = 120

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

    private static let supportingBundles: Set<String> = [
        "com.apple.finder",
        "com.apple.Preview",
        "com.apple.ActivityMonitor",
        "com.apple.systempreferences",
        "com.apple.SystemPreferences",
        "com.apple.Spotlight",
        "com.apple.archiveutility",
        "com.apple.installer",
        "com.apple.keychainaccess",
        "com.apple.Console",
        "com.apple.dt.Instruments",
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
                flushRelated()
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

        let merged = absorbMicroGroups(groups)
        return merged.map { makeSession(from: $0.snapshots, project: $0.project) }.reversed()
    }

    private static func absorbMicroGroups(
        _ groups: [(snapshots: [Snapshot], project: String?)]
    ) -> [(snapshots: [Snapshot], project: String?)] {
        guard groups.count > 1 else { return groups }

        var result = groups
        var absorbed = true
        while absorbed {
            absorbed = false
            var next: [(snapshots: [Snapshot], project: String?)] = []
            var i = 0
            while i < result.count {
                let group = result[i]
                let duration = groupDuration(group.snapshots)

                if duration < microSessionSeconds, result.count > 1 {
                    let canMergePrev = next.last.map { canAbsorbMicro(group, into: $0) } ?? false
                    let canMergeNext = (i + 1 < result.count) ? canAbsorbMicro(group, into: result[i + 1]) : false

                    if !canMergePrev && !canMergeNext {
                        next.append(group)
                        i += 1
                        continue
                    }

                    let target: Int
                    if canMergePrev && canMergeNext {
                        let gapToPrev = group.snapshots.first.map { s in
                            s.timestamp.timeIntervalSince(next.last!.snapshots.last?.timestamp ?? s.timestamp)
                        } ?? .infinity
                        let gapToNext = result[i + 1].snapshots.first.map { s in
                            s.timestamp.timeIntervalSince(group.snapshots.last?.timestamp ?? s.timestamp)
                        } ?? .infinity
                        target = gapToPrev <= gapToNext ? -1 : 1
                    } else {
                        target = canMergePrev ? -1 : 1
                    }

                    if target == -1 {
                        let last = next.removeLast()
                        let mergedProject = last.project ?? group.project
                        next.append((last.snapshots + group.snapshots, mergedProject))
                    } else {
                        let following = result[i + 1]
                        let mergedProject = following.project ?? group.project
                        result[i + 1] = (group.snapshots + following.snapshots, mergedProject)
                    }
                    absorbed = true
                } else {
                    next.append(group)
                }
                i += 1
            }
            result = next
        }
        return result
    }

    private static func canAbsorbMicro(
        _ micro: (snapshots: [Snapshot], project: String?),
        into target: (snapshots: [Snapshot], project: String?)
    ) -> Bool {
        if let microProject = micro.project, let targetProject = target.project {
            return normalizeProjectName(microProject) == normalizeProjectName(targetProject)
        }
        if micro.project == nil && target.project == nil { return true }
        if micro.project != nil { return false }
        guard let targetProject = target.project else { return true }
        return micro.snapshots.contains { contentRelatesToProject($0, project: targetProject) }
    }

    private static func groupDuration(_ snapshots: [Snapshot]) -> Int {
        guard let first = snapshots.first, let last = snapshots.last else { return 0 }
        return max(Int(last.timestamp.timeIntervalSince(first.timestamp)), 0)
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
        if supportingBundles.contains(snapshot.appBundle) { return true }

        if isWorkApp(snapshot.appBundle) {
            if let sessionProject, let url = snapshot.documentURL,
               let pathProject = projectFromURL(url) {
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
        workBundles.contains(bundleId) || BundleRegistry.shared.terminals.contains(bundleId)
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
        guard let next, let current else { return false }
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

    static func normalizeProjectName(_ name: String) -> String {
        if name.hasSuffix(".xcodeproj") { return String(name.dropLast(".xcodeproj".count)) }
        if name.hasSuffix(".xcworkspace") { return String(name.dropLast(".xcworkspace".count)) }
        return name
    }

    private static func looksLikeSourceFile(_ name: String) -> Bool {
        guard let ext = name.split(separator: ".").last?.lowercased(), name.contains(".") else { return false }
        return sourceFileExtensions.contains(ext)
    }

    // MARK: - Project extraction

    private static let terminalBundles: Set<String> = BundleRegistry.shared.terminals

    private static let genericDirs: Set<String> = [
        "users", "home", "developer", "documents", "desktop",
        "downloads", "projects", "repos", "workspace", "workspaces",
        "src", "lib", "app", "sources", "tests", "test", "spec",
        "build", "dist", "out", "bin", "cmd", "internal", "pkg",
        "vendor", "node_modules", "packages", "target",
        "public", "static", "assets", "www", "htdocs",
        "tmp", "temp", "cache", "logs", "log",
        "config", "configs", "scripts", "tools",
    ]

    private static let sourceSubdirs: Set<String> = [
        "views", "view", "models", "model", "services", "service",
        "controllers", "controller", "resources", "assets",
        "preview content", "extensions", "utils", "utilities",
        "helpers", "components", "screens", "features", "domain",
        "data", "networking", "ui", "supporting files",
    ]

    static func extractProject(from snapshot: Snapshot) -> String? {
        if snapshot.appBundle == xcodeBundle, let title = snapshot.windowTitle, !title.isEmpty {
            if let project = projectFromXcodeTitle(title, documentURL: snapshot.documentURL) { return project }
        }
        if let url = snapshot.documentURL, url.hasPrefix("file://") {
            if let project = projectFromFileURL(url) { return project }
        }
        if let url = snapshot.documentURL {
            if let project = projectFromGitHubURL(url) { return project }
        }
        if terminalBundles.contains(snapshot.appBundle), let title = snapshot.windowTitle, !title.isEmpty {
            if let project = projectFromTerminalTitle(title) { return project }
        }
        return nil
    }

    // MARK: - URL-based extraction

    static func projectFromURL(_ urlString: String) -> String? {
        if urlString.hasPrefix("file://") { return projectFromFileURL(urlString) }
        if urlString.contains("github.com/") { return projectFromGitHubURL(urlString) }
        return nil
    }

    private static func projectFromGitHubURL(_ url: String) -> String? {
        guard url.contains("github.com/") else { return nil }
        let parts = url.components(separatedBy: "github.com/")
        guard let pathPart = parts.last else { return nil }
        let segments = pathPart.components(separatedBy: "/").filter { !$0.isEmpty }
        guard segments.count >= 2 else { return nil }
        return segments[1].components(separatedBy: "?").first
    }

    static func projectFromFileURL(_ urlString: String) -> String? {
        var path = String(urlString.dropFirst("file://".count))
        if let decoded = path.removingPercentEncoding { path = decoded }
        return projectFromPath(path)
    }

    static func projectFromPath(_ path: String) -> String? {
        let components = path.components(separatedBy: "/")
            .filter { !$0.isEmpty && $0 != "~" }
        guard !components.isEmpty else { return nil }

        for component in components.reversed() {
            if component.hasSuffix(".xcodeproj") || component.hasSuffix(".xcworkspace") {
                return normalizeProjectName(component)
            }
        }

        var dirs = components
        if let last = dirs.last, last.contains(".") && !last.hasPrefix(".") {
            dirs.removeLast()
        }
        guard dirs.count >= 1 else { return nil }

        for dir in dirs.reversed() {
            let lower = dir.lowercased()
            if !genericDirs.contains(lower),
               !sourceSubdirs.contains(lower),
               !dir.hasPrefix("."),
               !isJunkProjectName(lower) {
                return dir
            }
        }
        return nil
    }

    private static func isJunkProjectName(_ name: String) -> Bool {
        if name.count <= 2 { return true }
        return junkNames.contains(name)
    }

    private static let junkNames: Set<String> = [
        "pwd", "usr", "var", "etc", "opt", "run", "srv",
        "private", "volumes", "applications", "library",
        "system", "cores", "dev", "sbin",
    ]

    private static func projectFromXcodeTitle(_ title: String, documentURL: String?) -> String? {
        let parts = title.components(separatedBy: " — ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if parts.count >= 2 {
            for part in parts where part.hasSuffix(".xcodeproj") || part.hasSuffix(".xcworkspace") {
                return normalizeProjectName(part)
            }
            for part in parts where !looksLikeSourceFile(part) {
                return part
            }
            if let project = documentURL.flatMap({ projectFromURL($0) }) { return project }
            return parts.first
        }

        let single = parts.first ?? title.trimmingCharacters(in: .whitespaces)
        if single.hasSuffix(".xcodeproj") || single.hasSuffix(".xcworkspace") {
            return normalizeProjectName(single)
        }
        return documentURL.flatMap { projectFromURL($0) }
    }

    private static func projectFromTerminalTitle(_ title: String) -> String? {
        for part in title.components(separatedBy: " — ") {
            if let p = projectFromPath(part.trimmingCharacters(in: .whitespaces)) { return p }
        }
        if let colonIdx = title.firstIndex(of: ":") {
            let after = String(title[title.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
            if let p = projectFromPath(after) { return p }
        }
        return projectFromPath(title)
    }

    // MARK: - Build session

    private static func makeSession(from snapshots: [Snapshot], project: String?) -> Session {
        let start = snapshots.first!.timestamp
        let end = snapshots.last!.timestamp
        let activeSeconds = computeActiveSeconds(from: snapshots)
        let seconds = max(activeSeconds.values.reduce(0, +), 1)
        let apps = buildApps(from: snapshots, activeSeconds: activeSeconds)
        let activity = resolveActivity(from: snapshots, project: project, apps: apps)

        return Session(
            id: "session-\(Int(start.timeIntervalSince1970))",
            startTime: start,
            endTime: end,
            durationSeconds: seconds,
            apps: apps,
            activity: activity
        )
    }

    private static func computeActiveSeconds(from snapshots: [Snapshot]) -> [String: Int] {
        guard !snapshots.isEmpty else { return [:] }
        var result: [String: Int] = [:]
        let maxGap = 90

        for index in snapshots.indices {
            let snap = snapshots[index]
            let delta: Int
            if index + 1 < snapshots.count {
                delta = min(max(Int(snapshots[index + 1].timestamp.timeIntervalSince(snap.timestamp)), 1), maxGap)
            } else {
                delta = 30
            }
            result[snap.appBundle, default: 0] += delta
        }
        return result
    }

    private static func resolveActivity(from snapshots: [Snapshot], project: String?, apps: [SessionApp]) -> String {
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
        if let contextual = SessionAppDisplay.bestContextTitle(in: apps) {
            return contextual
        }
        return dominantApp(from: snapshots)
    }

    private static func dominantApp(from snapshots: [Snapshot]) -> String {
        var counts: [String: Int] = [:]
        for snap in snapshots { counts[snap.appName, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key ?? "Activity"
    }

    private static func buildApps(from snapshots: [Snapshot], activeSeconds: [String: Int]) -> [SessionApp] {
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
            if let t = snap.windowTitle {
                let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { titles[b]!.insert(trimmed) }
            }
            if let u = snap.documentURL { urls[b]!.insert(u) }
        }

        let apps = order.map { b in
            SessionApp(
                appName: names[b]!,
                bundleId: b,
                windowTitles: Array(titles[b]!),
                urls: Array(urls[b]!),
                snapshotCount: counts[b] ?? 1,
                activeSeconds: activeSeconds[b] ?? 0
            )
        }
        return SessionAppDisplay.rankedApps(apps)
    }
}
