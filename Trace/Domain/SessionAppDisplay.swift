import Foundation

enum SessionAppDisplay {
    struct Line: Identifiable, Sendable {
        let id: String
        let text: String
        let isPath: Bool
    }

    private static let xcodeBundle = "com.apple.dt.Xcode"

    private static let editorBundles: Set<String> = [
        xcodeBundle,
        "com.todesktop.230313mzl4w4u92",
        "com.microsoft.VSCode",
        "com.apple.TextEdit",
    ]

    private static let utilityBundles: Set<String> = [
        "com.apple.systempreferences",
        "com.apple.systempreferences.GeneralSettings",
        "com.apple.finder",
    ]

    private static let sourceExtensions: Set<String> = [
        "swift", "m", "mm", "h", "cpp", "c", "rs", "go", "py", "js", "ts",
        "tsx", "jsx", "java", "kt", "rb", "php", "cs", "vue", "svelte",
        "xcodeproj", "xcworkspace",
    ]

    private static let chatAppSuffixes: [String: [String]] = [
        "com.anthropic.claude": ["Claude"],
        "com.openai.chat": ["ChatGPT"],
        "com.notion.id": ["Notion"],
    ]

    static func rankedApps(_ apps: [SessionApp]) -> [SessionApp] {
        apps.sorted { rank($0) > rank($1) }
    }

    static func shouldShowInDetail(_ app: SessionApp, in session: Session? = nil) -> Bool {
        if !displayLines(for: app).isEmpty { return true }
        if fallbackLine(for: app) != nil { return true }
        if utilityBundles.contains(app.bundleId) { return false }
        if let session, session.apps.count > 1 { return true }
        return app.snapshotCount >= 6
    }

    static func hasRestorableContent(_ app: SessionApp) -> Bool {
        !app.urls.isEmpty
    }

    static func isEditor(_ bundleId: String) -> Bool {
        editorBundles.contains(bundleId)
    }

    static func bestDisplayLine(for app: SessionApp) -> Line? {
        let lines = displayLines(for: app)
        if let line = lines.first(where: { !isProjectBundleName($0.text) }) {
            return line
        }
        if let line = lines.first {
            return line
        }
        return fallbackLine(for: app)
    }

    static func contextLines(for app: SessionApp) -> [Line] {
        let lines = displayLines(for: app)
        if !lines.isEmpty { return lines }
        if let fallback = fallbackLine(for: app) {
            return [fallback]
        }
        return []
    }

    static func fallbackLine(for app: SessionApp) -> Line? {
        for title in app.windowTitles {
            let normalized = normalizeTitle(title, appName: app.appName, bundleId: app.bundleId)
            guard !normalized.isEmpty,
                  !isNoiseTitle(normalized, appName: app.appName),
                  normalized.lowercased() != app.appName.lowercased() else { continue }
            return Line(id: "fallback-\(normalized)", text: normalized, isPath: false)
        }

        if let project = inferredProject(for: app) {
            return Line(id: "fallback-project-\(project)", text: project, isPath: false)
        }

        for url in app.urls where !isNoiseURL(url) {
            let formatted = DisplayURL.format(url)
            guard !formatted.isEmpty else { continue }
            return Line(id: "fallback-url-\(formatted)", text: formatted, isPath: url.hasPrefix("file://"))
        }

        return nil
    }

    static func inferredProject(for app: SessionApp) -> String? {
        for title in app.windowTitles {
            if let project = projectFromTitle(title, bundleId: app.bundleId) {
                return project
            }
        }
        for url in app.urls where url.hasPrefix("file://") {
            if let project = projectFromFileURL(url) {
                return project
            }
        }
        return nil
    }

    static func displayLines(for app: SessionApp) -> [Line] {
        var lines: [Line] = []
        var seen: Set<String> = []

        let filteredTitles = app.windowTitles
            .map { normalizeTitle($0, appName: app.appName, bundleId: app.bundleId) }
            .filter { !isNoiseTitle($0, appName: app.appName) }

        let filteredURLs = app.urls.filter { !isNoiseURL($0) }

        if app.bundleId == xcodeBundle {
            appendTitleLines(
                filteredTitles.filter { looksLikeFile($0) },
                to: &lines,
                seen: &seen
            )
        } else if isEditor(app.bundleId) {
            for url in filteredURLs.sorted(by: pathSortPriority) {
                guard let line = pathLine(from: url), !isProjectBundleName(line.text),
                      seen.insert(line.key).inserted else { continue }
                lines.append(Line(id: "url-\(line.key)", text: line.text, isPath: true))
            }
            appendTitleLines(filteredTitles, to: &lines, seen: &seen, skipMatching: lines.map(\.text))
        } else {
            appendTitleLines(filteredTitles, to: &lines, seen: &seen)
            for url in filteredURLs.sorted() {
                let formatted = DisplayURL.format(url)
                let key = formatted.lowercased()
                guard !seen.contains(where: { formatted.contains($0) || $0.contains(key) }) else { continue }
                guard seen.insert(key).inserted else { continue }
                lines.append(Line(id: "url-\(key)", text: formatted, isPath: url.hasPrefix("file://")))
            }
        }

        return lines
    }

    private static func appendTitleLines(
        _ titles: [String],
        to lines: inout [Line],
        seen: inout Set<String>,
        skipMatching: [String] = []
    ) {
        for title in titles {
            guard !isProjectBundleName(title) else { continue }
            let key = title.lowercased()
            guard seen.insert(key).inserted else { continue }
            if skipMatching.contains(where: { $0.lowercased() == key || $0.hasSuffix(title) }) { continue }
            lines.append(Line(id: "title-\(key)", text: title, isPath: false))
        }
    }

    // MARK: - Ranking

    private static func rank(_ app: SessionApp) -> Int {
        var score = app.snapshotCount * 10
        if utilityBundles.contains(app.bundleId) { score -= 80 }
        if app.bundleId.hasPrefix("com.apple.") && !editorBundles.contains(app.bundleId) { score -= 40 }
        return score
    }

    private static let editorSuffixes: Set<String> = [
        "Cursor", "Visual Studio Code", "Code",
    ]

    private static let genericDirs: Set<String> = [
        "users", "home", "developer", "documents", "desktop",
        "downloads", "projects", "repos", "workspace", "workspaces",
        "src", "lib", "app", "sources", "tests", "test", "spec",
        "build", "dist", "out", "bin", "cmd", "internal", "pkg",
        "vendor", "node_modules", "packages", "target",
    ]

    private static func projectFromTitle(_ title: String, bundleId: String) -> String? {
        let emParts = title.components(separatedBy: " — ")
        if emParts.count >= 2, let last = emParts.last?.trimmingCharacters(in: .whitespaces), !last.isEmpty {
            if !looksLikeSourceFile(last) { return last }
        }

        let hyphenParts = title.components(separatedBy: " - ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if hyphenParts.count >= 3, editorSuffixes.contains(hyphenParts.last!) {
            let project = hyphenParts[hyphenParts.count - 2]
            if !project.isEmpty, !looksLikeSourceFile(project) { return project }
        }

        if isEditor(bundleId) {
            for part in hyphenParts where !looksLikeSourceFile(part) && !editorSuffixes.contains(part) {
                if !part.contains(".") { return part }
            }
        }

        return nil
    }

    private static func projectFromFileURL(_ urlString: String) -> String? {
        var path = String(urlString.dropFirst("file://".count))
        if let decoded = path.removingPercentEncoding { path = decoded }
        let components = path.components(separatedBy: "/").filter { !$0.isEmpty && $0 != "~" }
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

    private static func looksLikeSourceFile(_ name: String) -> Bool {
        looksLikeFile(name)
    }

    // MARK: - Title normalization

    private static func normalizeTitle(_ title: String, appName: String, bundleId: String) -> String {
        var trimmed = title.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return trimmed }

        if trimmed.lowercased() == appName.lowercased() { return trimmed }

        if let suffixes = chatAppSuffixes[bundleId] {
            for sep in [" — ", " – ", " - ", " | "] {
                let parts = trimmed.components(separatedBy: sep)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                guard parts.count >= 2 else { continue }
                if suffixes.contains(where: { parts.last?.caseInsensitiveCompare($0) == .orderedSame }) {
                    return parts.dropLast().joined(separator: sep.trimmingCharacters(in: .whitespaces))
                }
                if suffixes.contains(where: { parts.first?.caseInsensitiveCompare($0) == .orderedSame }) {
                    return parts.dropFirst().joined(separator: sep.trimmingCharacters(in: .whitespaces))
                }
            }
        }

        for sep in [" — ", " – ", " - "] {
            let parts = trimmed.components(separatedBy: sep)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard parts.count >= 2 else { continue }

            if isEditor(bundleId) {
                if let filePart = parts.first(where: { looksLikeFile($0) }) {
                    return filePart
                }
                if let projectPart = parts.first(where: { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }) {
                    return normalizeProjectName(projectPart)
                }
                return parts.last ?? trimmed
            }

            if looksLikeFile(parts.last ?? "") {
                return parts.last ?? trimmed
            }
            return parts.first ?? trimmed
        }

        if trimmed.hasSuffix(".xcodeproj") || trimmed.hasSuffix(".xcworkspace") {
            return normalizeProjectName(trimmed)
        }

        return trimmed
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

    private static func looksLikeFile(_ name: String) -> Bool {
        guard let ext = name.split(separator: ".").last?.lowercased(), name.contains(".") else { return false }
        return sourceExtensions.contains(ext)
    }

    private static func pathLine(from url: String) -> (key: String, text: String)? {
        guard url.hasPrefix("file://") else { return nil }
        var path = String(url.dropFirst("file://".count))
        if let decoded = path.removingPercentEncoding { path = decoded }
        let filename = (path as NSString).lastPathComponent
        guard !filename.isEmpty, !isProjectBundleName(filename) else { return nil }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            path = "~" + path.dropFirst(home.count)
        }

        let components = path.split(separator: "/").map(String.init)
        let text: String
        if components.count > 3 {
            text = components.suffix(3).joined(separator: "/")
        } else {
            text = path
        }
        return (key: filename.lowercased(), text: text)
    }

    private static func isProjectBundleName(_ name: String) -> Bool {
        name.hasSuffix(".xcodeproj") || name.hasSuffix(".xcworkspace")
    }

    private static func pathSortPriority(_ lhs: String, _ rhs: String) -> Bool {
        let lf = (String(lhs.dropFirst("file://".count)) as NSString).lastPathComponent
        let rf = (String(rhs.dropFirst("file://".count)) as NSString).lastPathComponent
        let lp = isProjectBundleName(lf)
        let rp = isProjectBundleName(rf)
        if lp != rp { return !lp }
        return lf.localizedCaseInsensitiveCompare(rf) == .orderedAscending
    }

    // MARK: - Noise filters

    private static func isNoiseTitle(_ title: String, appName: String) -> Bool {
        let lower = title.lowercased()
        if lower == appName.lowercased() { return true }
        if title.trimmingCharacters(in: .whitespaces).isEmpty { return true }

        let noisePatterns = [
            "sign in", "log in", "login", "signin",
            "full disk access", "files & folders", "accessibility",
            "privacy & security", "security & privacy",
            "watched folders", "add files to project",
            "cursor agents",
        ]
        if noisePatterns.contains(where: { lower.contains($0) }) { return true }
        if lower == "settings" || lower == "preferences" { return true }
        return false
    }

    private static func isNoiseURL(_ url: String) -> Bool {
        let lower = url.lowercased()
        let noisePatterns = [
            "accounts.google.com", "signin", "sign-in", "login", "oauth", "auth",
        ]
        return noisePatterns.contains(where: { lower.contains($0) })
    }
}

enum DisplayURL {
    static func format(_ raw: String) -> String {
        if raw.hasPrefix("file://") {
            var path = raw.replacingOccurrences(of: "file://", with: "")
            if let decoded = path.removingPercentEncoding { path = decoded }
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            if path.hasPrefix(home) {
                path = "~" + path.dropFirst(home.count)
            }
            return path
        }

        var display = raw
        for prefix in ["https://www.", "http://www.", "https://", "http://"] {
            if display.hasPrefix(prefix) {
                display = String(display.dropFirst(prefix.count))
                break
            }
        }
        if display.hasSuffix("/") {
            display = String(display.dropLast())
        }
        return display
    }
}
