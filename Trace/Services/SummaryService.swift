import Foundation
#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26, *)
@Generable(description: "A short phrase summarizing a work session")
struct GeneratedSummary {
    @Guide(description: "A natural phrase of 5–10 words, no period. Describe the activity or task — e.g. 'Debugging auth flow in SessionDisplay.swift' or 'Researching electromagnetic fields'. Avoid listing app names.")
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
        You summarize what someone did in a work session. \
        Reply with a short natural phrase of 5–10 words. No period. \
        Focus on what they were doing or working on — name specific files, topics, or tasks. \
        Do not just list app names.
        """

    static func cacheKey(for apps: [SessionApp], durationMinutes: Int) -> String {
        let ranked = SessionAppDisplay.rankedApps(apps)
        let bundles = ranked.map(\.bundleId).joined(separator: ",")
        let content = ranked.flatMap { app in
            SessionAppDisplay.contextLines(for: app).prefix(3).map(\.text)
        }.joined(separator: "|")
        return "\(bundles)|\(durationMinutes)|\(content)"
    }

    static func build(apps: [SessionApp], durationMinutes: Int, budget: Budget = .standard) -> String {
        let ranked = SessionAppDisplay.rankedApps(apps)

        // Surface the richest signals first: files, titles, URLs — not app names.
        var contextLines: [(app: String, line: String)] = []
        for app in ranked.prefix(budget.maxApps) {
            let lines = SessionAppDisplay.contextLines(for: app).prefix(budget.maxLinesPerApp)
            for line in lines {
                contextLines.append((app.appName, truncate(line.text, max: budget.maxLineLength)))
            }
        }

        var prompt = "Summarize this \(durationMinutes)-minute work session in one short phrase (5\u201310 words, no period).\n\n"

        if !contextLines.isEmpty {
            prompt += "Context (files, titles, tabs):\n"
            for item in contextLines {
                prompt += "  \u2022 [\(item.app)] \(item.line)\n"
            }
        } else {
            // No rich context — fall back to app list so model has something
            let names = ranked.prefix(budget.maxApps).map(\.appName).joined(separator: ", ")
            prompt += "Apps used: \(names)\n"
        }

        if ranked.count > budget.maxApps {
            prompt += "+ \(ranked.count - budget.maxApps) more apps\n"
        }

        return prompt
    }

    /// Heuristic fallback — uses the richest available signal rather than just listing app names.
    /// This is what shows when the on-device LLM is unavailable, so it must be useful on its own.
    static func fallback(apps: [SessionApp], durationMinutes: Int) -> String {
        let ranked = SessionAppDisplay.rankedApps(apps)

        // 1. Best display line from the primary app (file name, page title, project)
        if let primary = ranked.first,
           let best = SessionAppDisplay.bestDisplayLine(for: primary) {
            let detail = best.text
            // Only use it if it's meaningfully different from the app name
            if detail.lowercased() != primary.appName.lowercased() {
                // If there's a secondary app with its own context, append it
                if let secondary = ranked.dropFirst().first(where: {
                    SessionAppDisplay.bestDisplayLine(for: $0) != nil
                }),
                let secondaryLine = SessionAppDisplay.bestDisplayLine(for: secondary),
                secondaryLine.text.lowercased() != secondary.appName.lowercased() {
                    return "\(detail) — \(secondaryLine.text)"
                }
                return detail
            }
        }

        // 2. Inferred project name from the primary app
        if let primary = ranked.first,
           let project = SessionAppDisplay.inferredProject(for: primary) {
            return project
        }

        // 3. Top two app names as last resort
        let names = ranked.prefix(2).map(\.appName).joined(separator: " + ")
        return names.isEmpty ? "Work session" : names
    }

    static func truncate(_ text: String, max: Int) -> String {
        guard text.count > max else { return text }
        return String(text.prefix(max - 1)) + "\u2026"
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

    func summarize(apps: [SessionApp], durationMinutes: Int) async -> String {
        let ranked = SessionAppDisplay.rankedApps(apps)
        let key = SummaryPrompt.cacheKey(for: ranked, durationMinutes: durationMinutes)

        if let cached = cache[key] { return cached }

        #if canImport(FoundationModels)
        if #available(macOS 26, *),
           let llm = await llmSummarize(apps: ranked, durationMinutes: durationMinutes) {
            store(key: key, value: llm)
            return llm
        }
        #endif

        let fallback = SummaryPrompt.fallback(apps: ranked, durationMinutes: durationMinutes)
        store(key: key, value: fallback)
        return fallback
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
        guard let url = cacheFileURL(),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return decoded
    }

    private static func saveCache(_ cache: [String: String]) {
        guard let url = cacheFileURL(),
              let data = try? JSONEncoder().encode(cache)
        else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Apple Foundation Models

    #if canImport(FoundationModels)
    @available(macOS 26, *)
    private func llmSummarize(apps: [SessionApp], durationMinutes: Int) async -> String? {
        guard SystemLanguageModel.default.isAvailable else { return nil }

        for budget in SummaryPrompt.Budget.retrySequence {
            do {
                let session = LanguageModelSession(
                    model: .default,
                    instructions: SummaryPrompt.instructions
                )
                let prompt = SummaryPrompt.build(
                    apps: apps,
                    durationMinutes: durationMinutes,
                    budget: budget
                )
                let response = try await session.respond(
                    to: prompt,
                    generating: GeneratedSummary.self
                )
                let text = response.content.text
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            } catch let error as LanguageModelSession.GenerationError {
                if case .exceededContextWindowSize = error { continue }
                return nil
            } catch {
                return nil
            }
        }

        return nil
    }
    #endif
}
