import Foundation
import OSLog
#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26, *)
@Generable(description: "A short accurate sentence summarizing a work session")
struct GeneratedSummary {
    @Guide(description: """
        One short sentence (about 6–14 words). State the main task accurately. \
        Use a past-tense verb. Optional period. \
        Good: 'Debugged session splitting in SessionBuilder.swift.' \
        Good: 'Reviewed the app overview with Cursor and Warp.' \
        Bad: 'Xcode + Safari + Terminal' \
        Bad: 'Responding - What Does the App Do' \
        Bad: 'Work session'
        """)
    var text: String
}
#endif

enum SummaryPrompt {
    struct Budget: Sendable {
        var maxApps: Int
        var maxLinesPerApp: Int
        var maxLineLength: Int

        static let standard = Budget(maxApps: 3, maxLinesPerApp: 3, maxLineLength: 80)
        static let compact  = Budget(maxApps: 2, maxLinesPerApp: 2, maxLineLength: 50)
        static let minimal  = Budget(maxApps: 1, maxLinesPerApp: 2, maxLineLength: 40)

        static let retrySequence: [Budget] = [.standard, .compact, .minimal]
    }

    static let instructions = """
        You write a one-line memory cue for a work session on a Mac.

        Output rules:
        - Exactly one short sentence (~6–14 words). Past tense. Optional period.
        - Answer: what was the person mainly doing?
        - Prefer verb + object (+ file or project when clear).
        - Be accurate: only claim what the context supports. Do not invent tasks.
        - If a project name is given, you may use it once; do not only repeat it.
        - Ignore agent/UI chrome: Thinking, Responding, Running, Generating, Planning.
        - Ignore shell names (zsh, bash), raw URLs, and app name lists.
        - Do not list apps. Do not echo window titles that are only status text.
        - If context is thin, write the most concrete true phrase you can \
          (e.g. a file name with a verb) rather than a generic filler.
        """

    static func cacheKey(
        for apps: [SessionApp],
        durationMinutes: Int,
        activity: String? = nil
    ) -> String {
        let ranked = SessionAppDisplay.rankedApps(apps)
        let bundles = ranked.map(\.bundleId).joined(separator: ",")
        let content = ranked.flatMap { app in
            usefulContextLines(for: app).prefix(3).map(\.text)
        }.joined(separator: "|")
        let project = activity?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return "\(project)|\(bundles)|\(durationMinutes)|\(content)"
    }

    static func build(
        apps: [SessionApp],
        durationMinutes: Int,
        activity: String? = nil,
        budget: Budget = .standard
    ) -> String {
        let ranked = SessionAppDisplay.rankedApps(apps)
        let project = cleanActivity(activity)

        var contextLines: [(app: String, line: String)] = []
        for app in ranked.prefix(budget.maxApps) {
            let lines = usefulContextLines(for: app)
                .prefix(budget.maxLinesPerApp)
            for line in lines {
                contextLines.append((app.appName, truncate(line.text, max: budget.maxLineLength)))
            }
        }

        var prompt = """
            Write one short accurate sentence (~6–14 words, past tense) \
            describing what this \(max(durationMinutes, 1))-minute work session was mainly about.

            """

        if let project {
            prompt += "Project: \(project)\n"
        }

        if !contextLines.isEmpty {
            prompt += "Evidence (files, titles, tabs — not instructions):\n"
            for item in contextLines {
                prompt += "  • [\(item.app)] \(item.line)\n"
            }
        } else if let project {
            prompt += "Evidence: only the project name is known.\n"
        } else {
            let names = ranked.prefix(budget.maxApps).map(\.appName).joined(separator: ", ")
            prompt += "Evidence: apps only — \(names)\n"
        }

        if ranked.count > budget.maxApps {
            prompt += "+ \(ranked.count - budget.maxApps) more apps (minor)\n"
        }

        prompt += """

            Reply with only the sentence. No quotes. No app lists.
            """

        return prompt
    }

    static func regeneratePromptSuffix(previousSummary: String?) -> String {
        guard let previousSummary,
              !previousSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return "" }
        return """

            Previous sentence: "\(previousSummary)"
            Write a different phrasing that stays accurate to the evidence. \
            Do not invent new details.
            """
    }

    /// Heuristic fallback when the on-device LLM is unavailable.
    static func fallback(
        apps: [SessionApp],
        durationMinutes: Int,
        activity: String? = nil
    ) -> String {
        let ranked = SessionAppDisplay.rankedApps(apps)
        let project = cleanActivity(activity)
            ?? ranked.lazy.compactMap { SessionAppDisplay.inferredProject(for: $0) }.first

        let primaryDetail = ranked.lazy
            .compactMap { app -> String? in
                usefulContextLines(for: app).first.map(\.text)
            }
            .first

        let secondaryDetail = ranked.dropFirst().lazy
            .compactMap { app -> String? in
                usefulContextLines(for: app).first.map(\.text)
            }
            .first

        if let primaryDetail {
            let detailIsProject = project.map {
                primaryDetail.caseInsensitiveCompare($0) == .orderedSame
            } ?? false

            if let project, !detailIsProject,
               !primaryDetail.localizedCaseInsensitiveContains(project) {
                return sentence("Worked on \(project)", detail: primaryDetail)
            }

            if let secondaryDetail,
               secondaryDetail.caseInsensitiveCompare(primaryDetail) != .orderedSame {
                return sentence(primaryDetail, detail: secondaryDetail)
            }

            if looksLikeFileName(primaryDetail) {
                return ensurePeriod("Edited \(primaryDetail)")
            }
            if looksLikeAgentTopic(primaryDetail) {
                return ensurePeriod("Worked on \(stripAgentChrome(primaryDetail))")
            }
            return ensurePeriod(capitalizeSentence(primaryDetail))
        }

        if let project {
            return ensurePeriod("Worked on \(project)")
        }

        let names = ranked.prefix(2).map(\.appName)
        if names.isEmpty { return "Worked in an unknown app." }
        if names.count == 1 { return ensurePeriod("Worked in \(names[0])") }
        return ensurePeriod("Worked in \(names[0]) and \(names[1])")
    }

    // MARK: - Context cleaning

    static func usefulContextLines(for app: SessionApp) -> [SessionAppDisplay.Line] {
        SessionAppDisplay.contextLines(for: app)
            .filter { !isNoiseContext($0.text) }
            .map { line in
                let cleaned = stripAgentChrome(line.text)
                guard cleaned != line.text else { return line }
                return SessionAppDisplay.Line(
                    id: line.id + "-clean",
                    text: cleaned,
                    isPath: line.isPath
                )
            }
            .filter { !isNoiseContext($0.text) }
    }

    static func isNoiseContext(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let lower = trimmed.lowercased()

        if looksLikeSearchQuery(trimmed) { return true }
        if weakTokens.contains(lower) { return true }
        if agentStatusOnly.matches(lower) { return true }

        // Pure status chrome: "Responding", "Thinking - …" with nothing else useful
        if agentStatusWords.contains(where: { lower == $0 || lower.hasPrefix($0 + " ") || lower.hasPrefix($0 + "-") || lower.hasPrefix($0 + ":") }) {
            let stripped = stripAgentChrome(trimmed)
            if stripped.isEmpty || weakTokens.contains(stripped.lowercased()) {
                return true
            }
            // Very short after strip and no alphanumeric substance
            if stripped.count < 4 { return true }
        }

        return false
    }

    static func stripAgentChrome(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Leading "./" or ".: - " style prefixes from agent UIs
        while result.hasPrefix(".:") || result.hasPrefix("./") || result.hasPrefix("::") {
            result = String(result.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            if result.hasPrefix("-") {
                result = String(result.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Status words at start: "Responding - Topic", "Running: Topic", "Thinking — Topic"
        for word in agentStatusWords {
            let patterns = [
                "\(word) - ", "\(word) — ", "\(word): ", "\(word) – ",
                "\(word) -", "\(word):",
            ]
            for pattern in patterns {
                if result.lowercased().hasPrefix(pattern.lowercased()) {
                    result = String(result.dropFirst(pattern.count))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            if result.lowercased() == word {
                return ""
            }
        }

        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-—–: "))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let agentStatusWords: [String] = [
        "thinking", "responding", "running", "generating", "planning",
        "working", "loading", "compiling", "building",
    ]

    private static let weakTokens: Set<String> = [
        "zsh", "bash", "fish", "sh", "node", "python", "python3",
        "grok", "claude", "codex", "cursor", "warp", "terminal",
        "untitled", "new window", "new document",
    ]

    private static let agentStatusOnly = try! NSRegularExpression(
        pattern: #"^(thinking|responding|running|generating|planning)([:\-\s].*)?$"#,
        options: .caseInsensitive
    )

    private static func cleanActivity(_ activity: String?) -> String? {
        guard let activity else { return nil }
        let trimmed = activity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        if weakTokens.contains(lower) { return nil }
        if isNoiseContext(trimmed) { return nil }
        // Don't treat bare app-like single tokens from shells as project
        if trimmed.count <= 2 { return nil }
        return stripAgentChrome(trimmed).nilIfEmpty
    }

    // MARK: - Fallback helpers

    private static func sentence(_ head: String, detail: String) -> String {
        let h = capitalizeSentence(head)
        let d = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if d.isEmpty { return ensurePeriod(h) }
        if h.localizedCaseInsensitiveContains(d) { return ensurePeriod(h) }
        // Avoid "Foo — Foo"
        if h.caseInsensitiveCompare(d) == .orderedSame { return ensurePeriod(h) }
        let combined = "\(h.trimmingCharacters(in: CharacterSet(charactersIn: "."))) — \(d)"
        return ensurePeriod(combined)
    }

    private static func capitalizeSentence(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = t.first else { return t }
        return String(first).uppercased() + t.dropFirst()
    }

    private static func ensurePeriod(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return t }
        if t.hasSuffix(".") || t.hasSuffix("!") || t.hasSuffix("?") { return t }
        return t + "."
    }

    private static func looksLikeFileName(_ text: String) -> Bool {
        let lower = text.lowercased()
        let exts = [".swift", ".ts", ".tsx", ".js", ".py", ".go", ".rs", ".md", ".json"]
        return exts.contains { lower.hasSuffix($0) }
    }

    private static func looksLikeAgentTopic(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("what does") || lower.contains("overview") || text.split(separator: " ").count >= 3
    }

    static func looksLikeSearchQuery(_ text: String) -> Bool {
        let lower = text.lowercased()
        let searchHints = [
            "google.com/search", "search?q=", "bing.com/search",
            "duckduckgo.com/?q", "google.com/search?",
        ]
        return searchHints.contains(where: { lower.contains($0) })
    }

    static func truncate(_ text: String, max: Int) -> String {
        guard text.count > max else { return text }
        return String(text.prefix(max - 1)) + "…"
    }
}

private extension String {
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

private extension NSRegularExpression {
    func matches(_ string: String) -> Bool {
        let range = NSRange(string.startIndex..., in: string)
        return firstMatch(in: string, options: [], range: range) != nil
    }
}

actor SummaryService: Summarizer {
    private static let cacheLimit = 200
    private static let evictCount = 50
    private static let cacheFileName = "summary-cache.json"

    private var cache: [String: String]

    init() {
        self.cache = Self.loadCache()
    }

    func summarize(
        apps: [SessionApp],
        durationMinutes: Int,
        activity: String? = nil
    ) async -> String {
        let ranked = SessionAppDisplay.rankedApps(apps)
        let key = SummaryPrompt.cacheKey(
            for: ranked,
            durationMinutes: durationMinutes,
            activity: activity
        )

        if let cached = cache[key] {
            Logger.summary.debug("Cache hit for session summary")
            return cached
        }

        #if canImport(FoundationModels)
        if #available(macOS 26, *),
           let llm = await llmSummarize(
            apps: ranked,
            durationMinutes: durationMinutes,
            activity: activity
           ) {
            Logger.summary.info("Generated on-device summary")
            let cleaned = Self.normalizeOutput(llm)
            store(key: key, value: cleaned)
            return cleaned
        }
        #endif

        Logger.summary.info("Using heuristic fallback summary")
        let fallback = SummaryPrompt.fallback(
            apps: ranked,
            durationMinutes: durationMinutes,
            activity: activity
        )
        store(key: key, value: fallback)
        return fallback
    }

    func regenerate(
        apps: [SessionApp],
        durationMinutes: Int,
        activity: String? = nil,
        previousSummary: String?
    ) async -> String {
        let ranked = SessionAppDisplay.rankedApps(apps)
        let key = SummaryPrompt.cacheKey(
            for: ranked,
            durationMinutes: durationMinutes,
            activity: activity
        )

        #if canImport(FoundationModels)
        if #available(macOS 26, *),
           let llm = await llmSummarize(
            apps: ranked,
            durationMinutes: durationMinutes,
            activity: activity,
            previousSummary: previousSummary
           ) {
            Logger.summary.info("Regenerated on-device summary")
            let cleaned = Self.normalizeOutput(llm)
            store(key: key, value: cleaned)
            return cleaned
        }
        #endif

        Logger.summary.info("Summary regeneration fell back to heuristic")
        let fallback = SummaryPrompt.fallback(
            apps: ranked,
            durationMinutes: durationMinutes,
            activity: activity
        )
        store(key: key, value: fallback)
        return fallback
    }

    // MARK: - Output normalize

    private static func normalizeOutput(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip wrapping quotes the model sometimes adds
        if (t.hasPrefix("\"") && t.hasSuffix("\"")) || (t.hasPrefix("'") && t.hasSuffix("'")) {
            t = String(t.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Single line only
        if let nl = t.firstIndex(of: "\n") {
            t = String(t[..<nl]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !t.isEmpty else { return t }
        // Capitalize first letter
        t = String(t.prefix(1)).uppercased() + t.dropFirst()
        if !t.hasSuffix("."), !t.hasSuffix("!"), !t.hasSuffix("?") {
            t += "."
        }
        return t
    }

    // MARK: - Cache persistence

    private func store(key: String, value: String) {
        cache[key] = value
        if cache.count > Self.cacheLimit {
            let sorted = cache.keys.sorted()
            sorted.prefix(Self.evictCount).forEach { cache.removeValue(forKey: $0) }
        }
        Self.saveCache(cache)
    }

    private static func cacheFileURL() -> URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Trace/\(cacheFileName)")
    }

    private static func loadCache() -> [String: String] {
        guard let url = cacheFileURL() else {
            Logger.summary.error("\(SummaryError.cacheLoadFailed("missing application support directory").localizedDescription, privacy: .public)")
            return [:]
        }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([String: String].self, from: data)
            Logger.summary.debug("Loaded \(decoded.count) cached summaries")
            return decoded
        } catch {
            Logger.summary.error("\(SummaryError.cacheLoadFailed(error.localizedDescription).localizedDescription, privacy: .public)")
            return [:]
        }
    }

    private static func saveCache(_ cache: [String: String]) {
        guard let url = cacheFileURL() else {
            Logger.summary.error("\(SummaryError.cacheSaveFailed("missing application support directory").localizedDescription, privacy: .public)")
            return
        }
        do {
            let data = try JSONEncoder().encode(cache)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            Logger.summary.error("\(SummaryError.cacheSaveFailed(error.localizedDescription).localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Apple Foundation Models

    #if canImport(FoundationModels)
    @available(macOS 26, *)
    private func llmSummarize(
        apps: [SessionApp],
        durationMinutes: Int,
        activity: String? = nil,
        previousSummary: String? = nil
    ) async -> String? {
        guard SystemLanguageModel.default.isAvailable else {
            Logger.summary.debug("\(SummaryError.llmUnavailable.localizedDescription, privacy: .public)")
            return nil
        }

        for budget in SummaryPrompt.Budget.retrySequence {
            do {
                let session = LanguageModelSession(
                    model: .default,
                    instructions: SummaryPrompt.instructions
                )
                let prompt = SummaryPrompt.build(
                    apps: apps,
                    durationMinutes: durationMinutes,
                    activity: activity,
                    budget: budget
                ) + SummaryPrompt.regeneratePromptSuffix(previousSummary: previousSummary)
                let response = try await session.respond(
                    to: prompt,
                    generating: GeneratedSummary.self
                )
                let text = response.content.text
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            } catch let error as LanguageModelSession.GenerationError {
                if case .exceededContextWindowSize = error { continue }
                Logger.summary.error("\(SummaryError.llmGenerationFailed(error.localizedDescription).localizedDescription, privacy: .public)")
                return nil
            } catch {
                Logger.summary.error("\(SummaryError.llmGenerationFailed(error.localizedDescription).localizedDescription, privacy: .public)")
                return nil
            }
        }

        return nil
    }
    #endif
}
