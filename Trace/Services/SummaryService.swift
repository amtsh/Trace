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
        var prompt = """
            Summarize this \(durationMinutes)-minute work session in one short phrase \
            (5–10 words, no period).\n\n"""

        for app in ranked.prefix(budget.maxApps) {
            let lines = SessionAppDisplay.contextLines(for: app).prefix(budget.maxLinesPerApp)
            if lines.isEmpty {
                prompt += "\(app.appName)\n"
            } else {
                let detail = lines
                    .map { truncate($0.text, max: budget.maxLineLength) }
                    .joined(separator: ", ")
                prompt += "\(app.appName): \(detail)\n"
            }
        }

        if ranked.count > budget.maxApps {
            prompt += "+ \(ranked.count - budget.maxApps) more apps\n"
        }

        return prompt
    }

    /// Template fallback used when on-device LLM is unavailable.
    static func fallback(apps: [SessionApp], durationMinutes: Int) -> String {
        let ranked = SessionAppDisplay.rankedApps(apps)
        let names = ranked.prefix(2).map(\.appName).joined(separator: ", ")
        return "\(names) · \(durationMinutes) min"
    }

    static func truncate(_ text: String, max: Int) -> String {
        guard text.count > max else { return text }
        return String(text.prefix(max - 1)) + "…"
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

        // Template fallback — always returns a non-empty string
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
