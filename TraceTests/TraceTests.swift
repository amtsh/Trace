//
//  TraceTests.swift
//  TraceTests
//
//  Created by Amit Shinde on 2026-07-22.
//

import Foundation
import Testing
@testable import Trace

struct SessionBuilderTests {
    private func snapshot(
        id: Int64,
        at timestamp: Date,
        title: String?,
        url: String? = nil,
        bundle: String = "com.apple.dt.Xcode",
        appName: String = "Xcode"
    ) -> Snapshot {
        Snapshot(
            id: id,
            timestamp: timestamp,
            appBundle: bundle,
            appName: appName,
            windowTitle: title,
            documentURL: url,
            isIdle: false
        )
    }

    @Test func mergesXcodeFileAndProjectIntoOneSession() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshots = [
            snapshot(
                id: 1,
                at: base,
                title: "Trace.xcodeproj",
                url: "file:///Users/dev/Trace/Trace.xcodeproj"
            ),
            snapshot(
                id: 2,
                at: base.addingTimeInterval(60),
                title: "TimelineView.swift — Trace",
                url: "file:///Users/dev/Trace/Trace/Views/TimelineView.swift"
            ),
            snapshot(
                id: 3,
                at: base.addingTimeInterval(120),
                title: "Trace — TimelineView.swift",
                url: "file:///Users/dev/Trace/Trace/Views/TimelineView.swift"
            ),
        ]

        let sessions = SessionBuilder.buildSessions(from: snapshots)

        #expect(sessions.count == 1)
        #expect(sessions[0].activity == "Trace")
        #expect(sessions[0].durationMinutes == 2)
    }

    @Test func prefersXcodeProjectNameOverFolderName() {
        let path = "/Users/dev/xcode/Trace/Trace/Views/TimelineView.swift"
        #expect(SessionBuilder.projectFromPath(path) == "Trace")

        let projectURL = "file:///Users/dev/xcode/Trace/Trace.xcodeproj"
        #expect(SessionBuilder.projectFromFileURL(projectURL) == "Trace")
    }

    @Test func extractsProjectFromXcodeTitleWhenFileIsInSourceSubdir() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshots = [
            snapshot(
                id: 1,
                at: base,
                title: "Trace — SessionCardView.swift",
                url: "file:///Users/dev/xcode/Trace/Trace/Views/SessionCardView.swift"
            ),
        ]

        let sessions = SessionBuilder.buildSessions(from: snapshots)

        #expect(sessions.count == 1)
        #expect(sessions[0].activity == "Trace")
    }

    @Test func splitsDifferentProjectsEvenInSameApp() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshots = [
            snapshot(
                id: 1,
                at: base,
                title: "Trace.xcodeproj",
                url: "file:///Users/dev/Trace/Trace.xcodeproj"
            ),
            snapshot(
                id: 2,
                at: base.addingTimeInterval(60),
                title: "Other.xcodeproj",
                url: "file:///Users/dev/Other/Other.xcodeproj"
            ),
        ]

        let sessions = SessionBuilder.buildSessions(from: snapshots)

        #expect(sessions.count == 2)
    }

    @Test func splitsSustainedUnrelatedActivityIntoNewSession() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshots = [
            snapshot(id: 1, at: base, title: "Trace — TraceApp.swift",
                     url: "file:///Users/dev/Trace/Trace/TraceApp.swift"),
            snapshot(id: 2, at: base.addingTimeInterval(60), title: "Trace — TimelineView.swift",
                     url: "file:///Users/dev/Trace/Trace/Views/TimelineView.swift"),
            snapshot(id: 3, at: base.addingTimeInterval(120), title: "ElevenLabs Pronunciation",
                     url: "https://www.perplexity.ai/search/elevenlabs", bundle: "com.google.Chrome",
                     appName: "Google Chrome"),
            snapshot(id: 4, at: base.addingTimeInterval(300), title: "How to make mac app",
                     url: "https://www.perplexity.ai/search/mac-app", bundle: "com.google.Chrome",
                     appName: "Google Chrome"),
            snapshot(id: 5, at: base.addingTimeInterval(420), title: "Trace — SessionCardView.swift",
                     url: "file:///Users/dev/Trace/Trace/Views/SessionCardView.swift"),
        ]

        let sessions = SessionBuilder.buildSessions(from: snapshots)

        #expect(sessions.count == 2)
        #expect(sessions[0].activity == "Trace")
        #expect(sessions[0].apps.contains { $0.appName == "Xcode" })
        #expect(sessions[1].apps.contains { $0.appName == "Google Chrome" })
    }

    @Test func keepsSustainedAssistantChatInWorkSession() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshots = [
            snapshot(id: 1, at: base, title: "Trace — TraceApp.swift",
                     url: "file:///Users/dev/Trace/Trace/TraceApp.swift"),
            snapshot(id: 2, at: base.addingTimeInterval(60), title: "Fix session splitting — Claude",
                     bundle: "com.anthropic.claude", appName: "Claude"),
            snapshot(id: 3, at: base.addingTimeInterval(360), title: "Claude",
                     bundle: "com.anthropic.claude", appName: "Claude"),
            snapshot(id: 4, at: base.addingTimeInterval(600), title: "Trace — TimelineView.swift",
                     url: "file:///Users/dev/Trace/Trace/Views/TimelineView.swift"),
        ]

        let sessions = SessionBuilder.buildSessions(from: snapshots)

        #expect(sessions.count == 1)
        #expect(sessions[0].activity == "Trace")
        #expect(sessions[0].apps.contains { $0.appName == "Claude" })
    }

    @Test func absorbsSingleChatGlanceDuringWork() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshots = [
            snapshot(id: 1, at: base, title: "Trace — TraceApp.swift",
                     url: "file:///Users/dev/Trace/Trace/TraceApp.swift"),
            snapshot(id: 2, at: base.addingTimeInterval(60), title: "ElevenLabs Pronunciation — Claude",
                     bundle: "com.anthropic.claude", appName: "Claude"),
            snapshot(id: 3, at: base.addingTimeInterval(120), title: "Trace — TimelineView.swift",
                     url: "file:///Users/dev/Trace/Trace/Views/TimelineView.swift"),
        ]

        let sessions = SessionBuilder.buildSessions(from: snapshots)

        #expect(sessions.count == 1)
        #expect(sessions[0].activity == "Trace")
    }

    @Test func splitsUnrelatedAppsFromWorkSession() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshots = [
            snapshot(id: 1, at: base, title: "Trace — TraceApp.swift",
                     url: "file:///Users/dev/Trace/Trace/TraceApp.swift"),
            snapshot(id: 2, at: base.addingTimeInterval(60), title: "Pune",
                     bundle: "com.apple.weather", appName: "Weather"),
            snapshot(id: 3, at: base.addingTimeInterval(240), title: "INTC",
                     bundle: "com.apple.stocks", appName: "Stocks"),
            snapshot(id: 4, at: base.addingTimeInterval(360), title: "Trace — TimelineView.swift",
                     url: "file:///Users/dev/Trace/Trace/Views/TimelineView.swift"),
        ]

        let sessions = SessionBuilder.buildSessions(from: snapshots)

        #expect(sessions.count == 2)
        #expect(sessions[0].activity == "Trace")
        #expect(sessions[1].apps.contains { $0.appName == "Weather" || $0.appName == "Stocks" })
    }

    @Test func keepsXcodeSettingsPanesInWorkSession() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshots = [
            snapshot(id: 1, at: base, title: "Trace — TraceApp.swift",
                     url: "file:///Users/dev/Trace/Trace/TraceApp.swift"),
            snapshot(id: 2, at: base.addingTimeInterval(60), title: "Source Control"),
            snapshot(id: 3, at: base.addingTimeInterval(90), title: "Intelligence"),
            snapshot(id: 4, at: base.addingTimeInterval(120), title: "General"),
            snapshot(id: 5, at: base.addingTimeInterval(180), title: "Trace — TimelineView.swift",
                     url: "file:///Users/dev/Trace/Trace/Views/TimelineView.swift"),
        ]

        let sessions = SessionBuilder.buildSessions(from: snapshots)

        #expect(sessions.count == 1)
        #expect(sessions[0].activity == "Trace")
    }

    @Test func foldsBriefDetourIntoWorkSession() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshots = [
            snapshot(id: 1, at: base, title: "Trace — TraceApp.swift",
                     url: "file:///Users/dev/Trace/Trace/TraceApp.swift"),
            snapshot(id: 2, at: base.addingTimeInterval(60), title: "Pune",
                     bundle: "com.apple.weather", appName: "Weather"),
            snapshot(id: 3, at: base.addingTimeInterval(90), title: "INTC",
                     bundle: "com.apple.stocks", appName: "Stocks"),
            snapshot(id: 4, at: base.addingTimeInterval(150), title: "Trace — TimelineView.swift",
                     url: "file:///Users/dev/Trace/Trace/Views/TimelineView.swift"),
        ]

        let sessions = SessionBuilder.buildSessions(from: snapshots)

        #expect(sessions.count == 1)
        #expect(sessions[0].activity == "Trace")
        #expect(sessions[0].apps.contains { $0.appName == "Weather" })
    }

    @Test func ignoresTransientUnrelatedGlance() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshots = [
            snapshot(id: 1, at: base, title: "Trace — TraceApp.swift",
                     url: "file:///Users/dev/Trace/Trace/TraceApp.swift"),
            snapshot(id: 2, at: base.addingTimeInterval(60), title: "Random search",
                     url: "https://www.perplexity.ai/search/random", bundle: "com.google.Chrome",
                     appName: "Google Chrome"),
            snapshot(id: 3, at: base.addingTimeInterval(120), title: "Trace — TimelineView.swift",
                     url: "file:///Users/dev/Trace/Trace/Views/TimelineView.swift"),
        ]

        let sessions = SessionBuilder.buildSessions(from: snapshots)

        #expect(sessions.count == 1)
        #expect(sessions[0].activity == "Trace")
    }
}

struct SessionDisplayTests {
    @Test func relativeTimeLabelFormats() {
        let now = Date()
        let calendar = Calendar.current

        func session(endingAt end: Date) -> Session {
            Session(
                id: "s",
                startTime: end.addingTimeInterval(-120),
                endTime: end,
                durationMinutes: 2,
                apps: [],
                activity: "Trace"
            )
        }

        let twentyThreeMinAgo = calendar.date(byAdding: .minute, value: -23, to: now)!
        #expect(SessionDisplay.relativeTimeLabel(for: session(endingAt: twentyThreeMinAgo), now: now) == "23m ago")

        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let yesterdayLabel = SessionDisplay.relativeTimeLabel(for: session(endingAt: yesterday), now: now)
        let expectedTime = yesterday.formatted(Date.FormatStyle().hour().minute())
        #expect(yesterdayLabel == "Yesterday, \(expectedTime)")

        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: now)!
        #expect(SessionDisplay.relativeTimeLabel(for: session(endingAt: twoDaysAgo), now: now) == "2 days ago")
    }

    @Test func timeRangeNeverIncludesSeconds() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let session = Session(
            id: "s2",
            startTime: start,
            endTime: start.addingTimeInterval(150),
            durationMinutes: 2,
            apps: [],
            activity: "Trace"
        )
        let range = SessionDisplay.timeRangeLabel(for: session)!
        #expect(range.filter { $0 == ":" }.count == 2)
        #expect(range.contains("–"))
    }

    @Test func timeRangeIncludesDuration() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let session = Session(
            id: "s2",
            startTime: start,
            endTime: start.addingTimeInterval(150),
            durationMinutes: 2,
            apps: [],
            activity: "Trace"
        )
        let label = SessionDisplay.timeRangeWithDurationLabel(for: session)!
        #expect(label.contains("–"))
        #expect(label.contains("·"))
        #expect(label.hasSuffix("2 min"))
    }

    @Test func durationShowsSecondsForShortSessions() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let session = Session(
            id: "s1",
            startTime: start,
            endTime: start.addingTimeInterval(45),
            durationMinutes: 1,
            apps: [],
            activity: "Trace"
        )
        #expect(SessionDisplay.durationLabel(for: session) == "45s")
        #expect(SessionDisplay.timeRangeLabel(for: session) == nil)
    }

    @Test func showsTimeRangeForMediumSessions() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let session = Session(
            id: "s2",
            startTime: start,
            endTime: start.addingTimeInterval(150),
            durationMinutes: 2,
            apps: [],
            activity: "Trace"
        )
        let range = SessionDisplay.timeRangeLabel(for: session)
        #expect(range != nil)
        #expect(range?.contains(":") == true)
    }

    @Test func hidesPerAppTimeForShortBalancedSessions() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let apps = [
            SessionApp(appName: "Cursor", bundleId: "a", windowTitles: [], urls: [], snapshotCount: 1),
            SessionApp(appName: "Claude", bundleId: "b", windowTitles: [], urls: [], snapshotCount: 1),
        ]
        let session = Session(
            id: "s3",
            startTime: start,
            endTime: start.addingTimeInterval(29),
            durationMinutes: 1,
            apps: apps,
            activity: "Cursor"
        )
        #expect(SessionDisplay.shouldShowAppTimeShares(for: session) == false)
        #expect(SessionDisplay.appTimeShare(for: apps[0], in: session) == nil)
    }

    @Test func showsPerAppTimeForLongSessions() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let apps = [
            SessionApp(appName: "Cursor", bundleId: "a", windowTitles: [], urls: [], snapshotCount: 8),
            SessionApp(appName: "Claude", bundleId: "b", windowTitles: [], urls: [], snapshotCount: 2),
        ]
        let session = Session(
            id: "s4",
            startTime: start,
            endTime: start.addingTimeInterval(360),
            durationMinutes: 6,
            apps: apps,
            activity: "Cursor"
        )
        #expect(SessionDisplay.shouldShowAppTimeShares(for: session) == true)
        #expect(SessionDisplay.appTimeShare(for: apps[0], in: session) == "4m")
    }

    @Test func hidesRedundantSummary() {
        #expect(SessionDisplay.usefulSummary("Claude:", activity: "Claude", apps: []) == nil)
        #expect(SessionDisplay.usefulSummary("Claude", activity: "Claude", apps: []) == nil)
        #expect(SessionDisplay.usefulSummary("TraceApp.swift", activity: "Trace", apps: []) == "TraceApp.swift")
    }

    @Test func extractsChatConversationTitle() {
        let claude = SessionApp(
            appName: "Claude",
            bundleId: "com.anthropic.claude",
            windowTitles: ["ElevenLabs pronunciation — Claude"],
            urls: [],
            snapshotCount: 3
        )
        let lines = SessionAppDisplay.displayLines(for: claude)
        #expect(lines.first?.text == "ElevenLabs pronunciation")
    }

    @Test func buildsMultiAppContext() {
        let cursor = SessionApp(
            appName: "Cursor",
            bundleId: "com.todesktop.230313mzl4w4u92",
            windowTitles: [
                "SessionCardView.swift — Trace",
                "TimelineView.swift — Trace",
            ],
            urls: ["file:///Users/dev/Trace/Trace/Views/SessionCardView.swift"],
            snapshotCount: 24
        )
        let claude = SessionApp(
            appName: "Claude",
            bundleId: "com.anthropic.claude",
            windowTitles: ["Review session card UX — Claude"],
            urls: [],
            snapshotCount: 5
        )
        let session = Session(
            id: "s1",
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: Date(timeIntervalSince1970: 1_700_000_300),
            durationMinutes: 5,
            apps: [cursor, claude],
            activity: "Cursor"
        )

        #expect(SessionDisplay.sessionTitle(for: session) == "Trace")
        let context = SessionDisplay.builtInContext(for: session)
        #expect(context?.contains("SessionCardView.swift") == true)
        #expect(context?.contains("Claude:") == true)
    }

    @Test func infersProjectFromCursorTitle() {
        let cursor = SessionApp(
            appName: "Cursor",
            bundleId: "com.todesktop.230313mzl4w4u92",
            windowTitles: ["SessionCardView.swift - Trace - Cursor"],
            urls: [],
            snapshotCount: 10
        )
        #expect(SessionAppDisplay.inferredProject(for: cursor) == "Trace")
    }
}

struct SummaryPromptTests {
    @Test func truncatesLongPromptLines() {
        let long = String(repeating: "a", count: 100)
        #expect(SummaryPrompt.truncate(long, max: 80).count == 80)
        #expect(SummaryPrompt.truncate("short", max: 80) == "short")
    }

    @Test func cacheKeyIncludesContext() {
        let app = SessionApp(
            appName: "Xcode",
            bundleId: "com.apple.dt.Xcode",
            windowTitles: ["Trace — TraceApp.swift"],
            urls: [],
            snapshotCount: 5
        )
        let keyA = SummaryPrompt.cacheKey(for: [app], durationMinutes: 5)
        let keyB = SummaryPrompt.cacheKey(for: [app], durationMinutes: 10)
        #expect(keyA != keyB)

        let other = SessionApp(
            appName: "Xcode",
            bundleId: "com.apple.dt.Xcode",
            windowTitles: ["Trace — TimelineView.swift"],
            urls: [],
            snapshotCount: 5
        )
        #expect(keyA != SummaryPrompt.cacheKey(for: [other], durationMinutes: 5))
    }

    @Test func buildsBoundedPrompt() {
        let apps = (0..<5).map { i in
            SessionApp(
                appName: "App\(i)",
                bundleId: "com.example.app\(i)",
                windowTitles: ["File\(i).swift — Project"],
                urls: [],
                snapshotCount: 10
            )
        }
        let prompt = SummaryPrompt.build(apps: apps, durationMinutes: 5, budget: .standard)
        #expect(prompt.contains("max 10 words"))
        #expect(prompt.contains("+ 2 more apps"))
        #expect(!prompt.contains("App4"))
    }
}

struct SessionAppDisplayTests {
    private func app(
        bundleId: String = "com.apple.dt.Xcode",
        appName: String = "Xcode",
        titles: [String] = [],
        urls: [String] = [],
        count: Int = 10
    ) -> SessionApp {
        SessionApp(
            appName: appName,
            bundleId: bundleId,
            windowTitles: titles,
            urls: urls,
            snapshotCount: count
        )
    }

    @Test func dedupesXcodeTitleAndPath() {
        let xcode = app(
            titles: ["Trace — TimelineView.swift", "Trace — TraceApp.swift"],
            urls: [
                "file:///Users/dev/Trace/Trace.xcodeproj",
                "file:///Users/dev/Trace/Trace/Views/TimelineView.swift",
                "file:///Users/dev/Trace/Trace/TraceApp.swift",
            ]
        )

        let lines = SessionAppDisplay.displayLines(for: xcode)
        let texts = lines.map(\.text)

        #expect(!texts.contains(where: { $0.contains(".xcodeproj") }))
        #expect(texts.contains(where: { $0.hasSuffix("TimelineView.swift") }))
        #expect(lines.count == 2)
    }

    @Test func summaryPrefersSourceFileOverProjectBundle() {
        let xcode = app(
            titles: ["Trace — TraceApp.swift", "Trace.xcodeproj"],
            urls: [
                "file:///Users/dev/Trace/Trace.xcodeproj",
                "file:///Users/dev/Trace/Trace/TraceApp.swift",
            ]
        )
        let line = SessionAppDisplay.bestDisplayLine(for: xcode)
        #expect(line?.text == "TraceApp.swift")
    }

    @Test func inferredProjectPrefersXcodeProjectOverFolder() {
        let xcode = app(
            titles: ["Trace — SessionCardView.swift"],
            urls: ["file:///Users/dev/xcode/Trace/Trace/Views/SessionCardView.swift"]
        )

        #expect(SessionAppDisplay.inferredProject(for: xcode) == "Trace")
    }

    @Test func showsPerplexityQueryFromMacV3Bundle() {
        let perplexity = app(
            bundleId: "ai.perplexity.macv3",
            appName: "Perplexity",
            titles: ["ElevenLabs pronunciation — Perplexity"],
            urls: ["https://www.perplexity.ai/search/elevenlabs-pronunciation"]
        )

        let lines = SessionAppDisplay.displayLines(for: perplexity)
        #expect(lines.map(\.text) == ["ElevenLabs pronunciation"])
    }

    @Test func showsStockTickerAsContext() {
        let stocks = app(
            bundleId: "com.apple.stocks",
            appName: "Stocks",
            titles: ["INTC"],
            count: 2
        )

        #expect(SessionAppDisplay.displayLines(for: stocks).map(\.text) == ["INTC"])
    }

    @Test func filtersNoiseTitles() {
        let chrome = app(
            bundleId: "com.google.Chrome",
            appName: "Google Chrome",
            titles: ["Sign in to perplexity.ai with google.com"],
            urls: ["https://accounts.google.com/signin"],
            count: 1
        )

        #expect(SessionAppDisplay.displayLines(for: chrome).isEmpty)
        #expect(!SessionAppDisplay.shouldShowInDetail(chrome))
    }

    @Test func hidesConversationURLsWhenChatTitleExists() {
        let claude = app(
            bundleId: "com.anthropic.claude",
            appName: "Claude",
            titles: ["Fix session splitting — Claude"],
            urls: ["https://claude.ai/chat/123e4567-e89b-12d3-a456-426614174000"]
        )
        let lines = SessionAppDisplay.displayLines(for: claude)
        #expect(lines.map(\.text) == ["Fix session splitting"])

        let untitled = app(
            bundleId: "com.anthropic.claude",
            appName: "Claude",
            titles: [],
            urls: ["https://claude.ai/chat/123e4567-e89b-12d3-a456-426614174000"]
        )
        #expect(!SessionAppDisplay.displayLines(for: untitled).isEmpty)
    }

    @Test func ranksPrimaryAppFirst() {
        let apps = [
            app(bundleId: "com.apple.systempreferences", appName: "System Settings", titles: ["Full Disk Access"], count: 2),
            app(titles: ["Trace — TimelineView.swift"], count: 20),
            app(bundleId: "com.anthropic.claude", appName: "Claude", count: 5),
        ]

        let ranked = SessionAppDisplay.rankedApps(apps)
        #expect(ranked.first?.appName == "Xcode")
    }
}
