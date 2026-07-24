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
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let fromPath = SessionBuilder.buildSessions(from: [
            snapshot(
                id: 1,
                at: base,
                title: "TimelineView.swift",
                url: "file:///Users/dev/xcode/Trace/Trace/Views/TimelineView.swift"
            ),
        ])
        #expect(fromPath.first?.activity == "Trace")

        let fromProject = SessionBuilder.buildSessions(from: [
            snapshot(
                id: 2,
                at: base,
                title: "Trace.xcodeproj",
                url: "file:///Users/dev/xcode/Trace/Trace.xcodeproj"
            ),
        ])
        #expect(fromProject.first?.activity == "Trace")
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
        // Substantial detour needs ≥4 unrelated snaps spanning ≥8 minutes.
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
            snapshot(id: 5, at: base.addingTimeInterval(480), title: "Weather elsewhere",
                     url: "https://www.perplexity.ai/search/weather", bundle: "com.google.Chrome",
                     appName: "Google Chrome"),
            snapshot(id: 6, at: base.addingTimeInterval(620), title: "Cooking rice",
                     url: "https://www.perplexity.ai/search/rice", bundle: "com.google.Chrome",
                     appName: "Google Chrome"),
            snapshot(id: 7, at: base.addingTimeInterval(780), title: "Trace — SessionCardView.swift",
                     url: "file:///Users/dev/Trace/Trace/Views/SessionCardView.swift"),
        ]

        let sessions = SessionBuilder.buildSessions(from: snapshots)

        #expect(sessions.count == 3)
        #expect(sessions[0].activity == "Trace")
        #expect(sessions[0].apps.contains { $0.appName == "Xcode" })
        #expect(sessions[1].apps.contains { $0.appName == "Google Chrome" })
        #expect(sessions[2].activity == "Trace")
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
            snapshot(id: 4, at: base.addingTimeInterval(400), title: "AAPL",
                     bundle: "com.apple.stocks", appName: "Stocks"),
            snapshot(id: 5, at: base.addingTimeInterval(560), title: "Mumbai",
                     bundle: "com.apple.weather", appName: "Weather"),
            snapshot(id: 6, at: base.addingTimeInterval(720), title: "Trace — TimelineView.swift",
                     url: "file:///Users/dev/Trace/Trace/Views/TimelineView.swift"),
        ]

        let sessions = SessionBuilder.buildSessions(from: snapshots)

        #expect(sessions.count == 3)
        #expect(sessions[0].activity == "Trace")
        #expect(sessions[1].apps.contains { $0.appName == "Weather" || $0.appName == "Stocks" })
        #expect(sessions[2].activity == "Trace")
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

    @Test func splitsDetourWithoutSpanningGapInWorkSession() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshots = [
            snapshot(id: 1, at: base, title: "Trace — TraceApp.swift",
                     url: "file:///Users/dev/Trace/Trace/TraceApp.swift"),
            snapshot(id: 2, at: base.addingTimeInterval(600), title: "Trace — TimelineView.swift",
                     url: "file:///Users/dev/Trace/Trace/Views/TimelineView.swift"),
            snapshot(id: 3, at: base.addingTimeInterval(660), title: nil,
                     bundle: "ai.perplexity.macv3", appName: "Perplexity"),
            snapshot(id: 4, at: base.addingTimeInterval(720), title: "scrambled eggs in rice cooker",
                     bundle: "company.thebrowser.dia", appName: "Dia"),
            snapshot(id: 5, at: base.addingTimeInterval(900), title: nil,
                     bundle: "ai.perplexity.macv3", appName: "Perplexity"),
            snapshot(id: 6, at: base.addingTimeInterval(1080), title: "more recipes",
                     bundle: "company.thebrowser.dia", appName: "Dia"),
            snapshot(id: 7, at: base.addingTimeInterval(1200), title: "Trace — SessionCardView.swift",
                     url: "file:///Users/dev/Trace/Trace/Views/SessionCardView.swift"),
        ]

        let sessions = SessionBuilder.buildSessions(from: snapshots)

        #expect(sessions.count == 3)
        #expect(sessions[0].activity == "Trace")
        #expect(sessions[1].apps.contains { $0.appName == "Dia" || $0.appName == "Perplexity" })
        #expect(sessions[2].activity == "Trace")
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

    @Test func mergesCursorAgentAndWarpIntoOneSession() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let cursor = "com.todesktop.230313mzl4w4u92"
        let warp = "dev.warp.Warp-Stable"
        let snapshots = [
            snapshot(id: 1, at: base, title: "zsh", bundle: warp, appName: "Warp"),
            snapshot(id: 2, at: base.addingTimeInterval(30), title: "grok", bundle: warp, appName: "Warp"),
            snapshot(
                id: 3, at: base.addingTimeInterval(60),
                title: ".: - Thinking - What Does the App Do",
                bundle: cursor, appName: "Cursor"
            ),
            snapshot(
                id: 4, at: base.addingTimeInterval(120),
                title: "What Does the App Do Overview",
                bundle: cursor, appName: "Cursor"
            ),
            snapshot(
                id: 5, at: base.addingTimeInterval(180),
                title: ".: - Running: ContextContin…",
                bundle: warp, appName: "Warp"
            ),
            snapshot(
                id: 6, at: base.addingTimeInterval(240),
                title: ".: - Responding - What Does the App Do",
                bundle: cursor, appName: "Cursor"
            ),
            snapshot(
                id: 7, at: base.addingTimeInterval(300),
                title: "What Does the App Do Overview",
                url: "file:///Users/dev/xcode/Trace/Trace/Domain/SessionBuilder.swift",
                bundle: cursor, appName: "Cursor"
            ),
            snapshot(
                id: 8, at: base.addingTimeInterval(420),
                title: ".: - Responding - What Does the App Do",
                bundle: cursor, appName: "Cursor"
            ),
        ]

        let sessions = SessionBuilder.buildSessions(from: snapshots)

        #expect(sessions.count == 1)
        #expect(sessions[0].apps.contains { $0.bundleId == cursor })
        #expect(sessions[0].apps.contains { $0.bundleId == warp })
        #expect(sessions[0].activity == "Trace")
    }

    @Test func terminalShellTitlesAreNotProjects() {
        #expect(SessionBuilder.projectFromURL("file:///Users/dev/Trace/foo.swift") == "Trace")
        #expect(SessionBuilder.isStrongProjectName("zsh") == false)
        #expect(SessionBuilder.isStrongProjectName("grok") == false)
        #expect(SessionBuilder.isStrongProjectName("ContextContin") == false)
        #expect(SessionBuilder.isStrongProjectName("Trace") == true)
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
                durationSeconds: 120,
                apps: [],
                activity: "Trace"
            )
        }

        let justNow = now.addingTimeInterval(-15)
        let justNowLabel = SessionDisplay.relativeTimeLabel(for: session(endingAt: justNow), now: now)
        #expect(justNowLabel == justNow.formatted(Date.FormatStyle().hour().minute()))

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
            durationSeconds: 120,
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
            durationSeconds: 120,
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
            durationSeconds: 45,
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
            durationSeconds: 120,
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
            durationSeconds: 60,
            apps: apps,
            activity: "Cursor"
        )
        #expect(SessionDisplay.shouldShowAppTimeShares(for: session) == false)
        #expect(SessionDisplay.appTimeShare(for: apps[0], in: session) == nil)
    }

    @Test func showsPerAppTimeForLongSessions() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let apps = [
            SessionApp(appName: "Cursor", bundleId: "a", windowTitles: [], urls: [], snapshotCount: 8, activeSeconds: 288),
            SessionApp(appName: "Claude", bundleId: "b", windowTitles: [], urls: [], snapshotCount: 2, activeSeconds: 72),
        ]
        let session = Session(
            id: "s4",
            startTime: start,
            endTime: start.addingTimeInterval(360),
            durationSeconds: 360,
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
            durationSeconds: 300,
            apps: [cursor, claude],
            activity: "Cursor"
        )

        #expect(SessionDisplay.sessionTitle(for: session) == "Trace")
        let context = SessionDisplay.builtInContext(for: session)
        #expect(context?.contains("SessionCardView.swift") == true)
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

    private func focusSession(
        apps: [(name: String, bundle: String, seconds: Int)],
        activity: String? = nil,
        durationSeconds: Int = 600
    ) -> Session {
        Session(
            id: "focus",
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: Date(timeIntervalSince1970: 1_700_000_000 + Double(durationSeconds)),
            durationSeconds: durationSeconds,
            apps: apps.map { app in
                SessionApp(
                    appName: app.name,
                    bundleId: app.bundle,
                    windowTitles: [],
                    urls: [],
                    snapshotCount: max(app.seconds / 30, 1),
                    activeSeconds: app.seconds
                )
            },
            activity: activity ?? apps.first?.name ?? "Activity"
        )
    }

    @Test func focusScoreAllOnTask() {
        let session = focusSession(apps: [
            ("Xcode", "com.apple.dt.Xcode", 300),
            ("Cursor", "com.todesktop.230313mzl4w4u92", 200),
            ("Claude", "com.anthropic.claude", 100),
        ], activity: "Trace")
        let rating = SessionDisplay.contextContinuity(for: session)
        #expect(rating?.stars == 5)
    }

    @Test func focusScoreMostlyOnTask() {
        let session = focusSession(apps: [
            ("Xcode", "com.apple.dt.Xcode", 420),
            ("Cursor", "com.todesktop.230313mzl4w4u92", 120),
            ("Messages", "com.apple.MobileSMS", 60),
        ], activity: "Trace")
        let rating = SessionDisplay.contextContinuity(for: session)
        #expect(rating?.stars == 4)
    }

    @Test func focusScoreSomeUnrelated() {
        let session = focusSession(apps: [
            ("Xcode", "com.apple.dt.Xcode", 300),
            ("Messages", "com.apple.MobileSMS", 150),
            ("Stocks", "com.apple.stocks", 150),
        ], activity: "Trace")
        let rating = SessionDisplay.contextContinuity(for: session)
        #expect(rating?.stars == 3)
    }

    @Test func focusScoreSplitBetweenTasks() {
        let session = focusSession(apps: [
            ("Xcode", "com.apple.dt.Xcode", 200),
            ("Messages", "com.apple.MobileSMS", 200),
            ("Stocks", "com.apple.stocks", 200),
        ], activity: "Trace")
        let rating = SessionDisplay.contextContinuity(for: session)
        #expect(rating?.stars == 2)
    }

    @Test func focusScoreMostlyUnrelated() {
        let session = focusSession(apps: [
            ("Messages", "com.apple.MobileSMS", 200),
            ("Stocks", "com.apple.stocks", 200),
            ("Music", "com.apple.Music", 200),
        ], activity: "Trace")
        let rating = SessionDisplay.contextContinuity(for: session)
        #expect(rating?.stars == 1)
    }

    @Test func focusScoreSkipsShortSessions() {
        let session = focusSession(
            apps: [("Xcode", "com.apple.dt.Xcode", 120)],
            activity: "Trace",
            durationSeconds: 120
        )
        #expect(SessionDisplay.contextContinuity(for: session) == nil)
    }

    @Test func focusScoreHandlesZeroActiveSeconds() {
        let session = Session(
            id: "empty",
            startTime: Date(),
            endTime: Date().addingTimeInterval(600),
            durationSeconds: 600,
            apps: [
                SessionApp(
                    appName: "Xcode",
                    bundleId: "com.apple.dt.Xcode",
                    windowTitles: [],
                    urls: [],
                    snapshotCount: 1,
                    activeSeconds: 0
                ),
            ],
            activity: "Xcode"
        )
        #expect(SessionDisplay.contextContinuity(for: session) == nil)
    }

    @Test func focusScoreStarLabelFormatting() {
        #expect(ContextContinuity(stars: 1, explanation: "test").starLabel == "★☆☆☆☆")
        #expect(ContextContinuity(stars: 4, explanation: "test").starLabel == "★★★★☆")
        #expect(ContextContinuity(stars: 5, explanation: "test").starLabel == "★★★★★")
    }

    @Test func focusScoreAvoidsJudgmentLabels() {
        let explanations = [
            SessionDisplay.contextContinuity(for: focusSession(
                apps: [("Xcode", "com.apple.dt.Xcode", 480)], activity: "Trace"
            ))?.explanation,
            SessionDisplay.contextContinuity(for: focusSession(
                apps: [("Xcode", "com.apple.dt.Xcode", 420), ("Messages", "com.apple.MobileSMS", 120)],
                activity: "Trace"
            ))?.explanation,
            SessionDisplay.contextContinuity(for: focusSession(
                apps: [("A", "a", 150), ("B", "b", 150), ("C", "c", 150), ("D", "d", 150)]
            ))?.explanation,
        ].compactMap { $0 }

        for explanation in explanations {
            let lower = explanation.lowercased()
            #expect(!lower.contains("productivity"))
            #expect(!lower.contains("good"))
            #expect(!lower.contains("bad"))
            #expect(!lower.contains("distracted"))
        }
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
            appName: "Cursor",
            bundleId: "com.todesktop.230313mzl4w4u92",
            windowTitles: ["SessionBuilder.swift"],
            urls: ["file:///Users/dev/Trace/SessionBuilder.swift"],
            snapshotCount: 5
        )
        let keyA = SummaryPrompt.cacheKey(for: [app], durationMinutes: 5)
        let keyB = SummaryPrompt.cacheKey(for: [app], durationMinutes: 10)
        #expect(keyA != keyB)

        let other = SessionApp(
            appName: "Cursor",
            bundleId: "com.todesktop.230313mzl4w4u92",
            windowTitles: ["TimelineView.swift"],
            urls: ["file:///Users/dev/Trace/TimelineView.swift"],
            snapshotCount: 5
        )
        #expect(keyA != SummaryPrompt.cacheKey(for: [other], durationMinutes: 5))
        #expect(
            SummaryPrompt.cacheKey(for: [app], durationMinutes: 5, activity: "Trace")
                != SummaryPrompt.cacheKey(for: [app], durationMinutes: 5, activity: "Other")
        )
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
        let prompt = SummaryPrompt.build(
            apps: apps,
            durationMinutes: 5,
            activity: "Trace",
            budget: .standard
        )
        #expect(prompt.contains("6–14 words"))
        #expect(prompt.contains("Project: Trace"))
        #expect(prompt.contains("+ 2 more apps"))
        #expect(!prompt.contains("App4"))
    }

    @Test func stripsAgentChromeFromContext() {
        #expect(SummaryPrompt.stripAgentChrome("Responding - What Does the App Do") == "What Does the App Do")
        #expect(SummaryPrompt.stripAgentChrome(".: - Thinking - Session split") == "Session split")
        #expect(SummaryPrompt.stripAgentChrome("Running: ContextContin") == "ContextContin")
        #expect(SummaryPrompt.isNoiseContext("zsh"))
        #expect(SummaryPrompt.isNoiseContext("Thinking"))
        #expect(!SummaryPrompt.isNoiseContext("SessionBuilder.swift"))
    }

    @Test func fallbackIsShortSentenceWithProjectAndFile() {
        let apps = [
            SessionApp(
                appName: "Cursor",
                bundleId: "com.todesktop.230313mzl4w4u92",
                windowTitles: [
                    "Responding - What Does the App Do",
                    "SessionBuilder.swift",
                ],
                urls: ["file:///Users/dev/xcode/Trace/Trace/Domain/SessionBuilder.swift"],
                snapshotCount: 8,
                activeSeconds: 300
            ),
            SessionApp(
                appName: "Warp",
                bundleId: "dev.warp.Warp-Stable",
                windowTitles: ["zsh", "Running: ContextContin"],
                urls: [],
                snapshotCount: 3,
                activeSeconds: 60
            ),
        ]
        let text = SummaryPrompt.fallback(apps: apps, durationMinutes: 8, activity: "Trace")
        #expect(text.hasSuffix("."))
        #expect(text.split(separator: " ").count <= 16)
        #expect(!text.lowercased().contains("zsh"))
        #expect(!text.lowercased().contains("responding"))
        #expect(
            text.localizedCaseInsensitiveContains("Trace")
                || text.localizedCaseInsensitiveContains("SessionBuilder")
                || text.localizedCaseInsensitiveContains("What Does")
        )
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

    @Test func keepsSoleProjectAppInExpandedList() {
        let xcode = SessionApp(
            appName: "Xcode",
            bundleId: "com.apple.dt.Xcode",
            windowTitles: ["Trace — TimelineView.swift"],
            urls: ["file:///Users/dev/Trace/Trace/Views/TimelineView.swift"],
            snapshotCount: 8,
            activeSeconds: 240
        )
        let session = Session(
            id: "trace",
            startTime: Date(),
            endTime: Date().addingTimeInterval(240),
            durationSeconds: 240,
            apps: [xcode],
            activity: "Trace"
        )

        let expanded = SessionDisplay.expandedApps(for: session)
        #expect(expanded.count == 1)
        #expect(expanded[0].appName == "Xcode")
        #expect(SessionDisplay.shouldShowAppInList(xcode, session: session))
    }

    @Test func showsProjectAppAlongsideSecondaryApps() {
        let xcode = SessionApp(
            appName: "Xcode",
            bundleId: "com.apple.dt.Xcode",
            windowTitles: ["Trace — TimelineView.swift"],
            urls: ["file:///Users/dev/Trace/Trace/Views/TimelineView.swift"],
            snapshotCount: 8,
            activeSeconds: 120
        )
        let cursor = SessionApp(
            appName: "Cursor",
            bundleId: "com.todesktop.230313mzl4w4u92",
            windowTitles: ["Cursor Agents"],
            urls: [],
            snapshotCount: 2,
            activeSeconds: 60
        )
        let session = Session(
            id: "trace-mixed",
            startTime: Date(),
            endTime: Date().addingTimeInterval(180),
            durationSeconds: 180,
            apps: [xcode, cursor],
            activity: "Trace"
        )

        let expanded = SessionDisplay.expandedApps(for: session)
        #expect(expanded.contains(where: { $0.appName == "Xcode" }))
        #expect(expanded.contains(where: { $0.appName == "Cursor" }))
    }

    @Test func usesContextualTitleForDetourSession() {
        let dia = SessionApp(
            appName: "Dia",
            bundleId: "company.thebrowser.dia",
            windowTitles: ["scrambled eggs in rice cooker"],
            urls: [],
            snapshotCount: 2,
            activeSeconds: 120
        )
        let perplexity = SessionApp(
            appName: "Perplexity",
            bundleId: "ai.perplexity.macv3",
            windowTitles: [],
            urls: [],
            snapshotCount: 4,
            activeSeconds: 180
        )
        let session = Session(
            id: "detour",
            startTime: Date(),
            endTime: Date().addingTimeInterval(480),
            durationSeconds: 480,
            apps: [perplexity, dia],
            activity: "Perplexity"
        )

        #expect(SessionDisplay.sessionTitle(for: session) == "scrambled eggs in rice cooker")
        #expect(SessionDisplay.featuredApp(for: session)?.bundleId == dia.bundleId)
        #expect(!SessionDisplay.shouldShowAppInList(dia, session: session))
        #expect(SessionDisplay.shouldShowAppInList(perplexity, session: session))
    }

    @Test func normalizesGitHubDesktopRepositoryTitle() {
        let github = app(
            bundleId: "com.github.GitHubClient",
            appName: "GitHub Desktop",
            titles: ["Trace — GitHub Desktop"],
            urls: ["file:///Users/dev/Developer/xcode/Trace"],
            count: 3
        )

        #expect(SessionAppDisplay.displayLines(for: github).map(\.text) == ["Trace"])
    }

    @Test func displayNameMapsDiaToArc() {
        let dia = SessionApp(
            appName: "Dia",
            bundleId: "company.thebrowser.dia",
            windowTitles: ["Example"],
            urls: [],
            snapshotCount: 1
        )
        #expect(SessionAppDisplay.displayName(for: dia) == "Arc")
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

struct StatsBuilderTests {
    private func session(
        id: String = UUID().uuidString,
        startingAt start: Date,
        durationSeconds: Int,
        activity: String = "Trace"
    ) -> Session {
        Session(
            id: id,
            startTime: start,
            endTime: start.addingTimeInterval(TimeInterval(durationSeconds)),
            durationSeconds: durationSeconds,
            apps: [],
            activity: activity
        )
    }

    @Test func todayAndWeekTotalsSumDurations() {
        let calendar = Calendar.current
        let now = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: Date())!
        let earlierToday = calendar.date(byAdding: .hour, value: -2, to: now)!
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: now)!

        let stats = StatsBuilder.build(
            from: [
                session(startingAt: earlierToday, durationSeconds: 600),
                session(startingAt: earlierToday, durationSeconds: 300),
                session(startingAt: twoDaysAgo, durationSeconds: 1200),
            ],
            now: now
        )

        #expect(stats.todayActiveSeconds == 900)
        #expect(stats.weekActiveSeconds == 2100)
        #expect(stats.sessionCount == 3)
    }

    @Test func dailyActivityAlwaysHasSevenBucketsOldestFirst() {
        let now = Date()
        let stats = StatsBuilder.build(
            from: [session(startingAt: now, durationSeconds: 600)],
            now: now
        )

        #expect(stats.dailyActivity.count == 7)
        #expect(stats.dailyActivity.last?.label == "Today")
        #expect(stats.dailyActivity.last?.activeSeconds == 600)
        // Days with no sessions still appear, at zero.
        #expect(stats.dailyActivity.first?.activeSeconds == 0)
        let ordered = stats.dailyActivity.map(\.date)
        #expect(ordered == ordered.sorted())
    }

    @Test func deepWorkCountsOnlyLongSessions() {
        let now = Date()
        let stats = StatsBuilder.build(
            from: [
                session(startingAt: now, durationSeconds: StatsBuilder.deepWorkThresholdSeconds),
                session(startingAt: now, durationSeconds: StatsBuilder.deepWorkThresholdSeconds - 1),
                session(startingAt: now, durationSeconds: 60),
            ],
            now: now
        )

        #expect(stats.deepWorkCount == 1)
        #expect(stats.longestSessionSeconds == StatsBuilder.deepWorkThresholdSeconds)
    }

    @Test func topProjectsAggregateByTitleSortedByTime() {
        let now = Date()
        let stats = StatsBuilder.build(
            from: [
                session(startingAt: now, durationSeconds: 300, activity: "Trace"),
                session(startingAt: now, durationSeconds: 600, activity: "Trace"),
                session(startingAt: now, durationSeconds: 1200, activity: "Landing"),
            ],
            now: now
        )

        #expect(stats.topProjects.first?.name == "Landing")
        #expect(stats.topProjects.first?.activeSeconds == 1200)
        let trace = stats.topProjects.first { $0.name == "Trace" }
        #expect(trace?.activeSeconds == 900)
        #expect(trace?.sessionCount == 2)
    }

    @Test func durationLabelFormatsHoursAndMinutes() {
        #expect(StatsBuilder.durationLabel(0) == "0m")
        #expect(StatsBuilder.durationLabel(42 * 60) == "42m")
        #expect(StatsBuilder.durationLabel(60 * 60) == "1h")
        #expect(StatsBuilder.durationLabel(125 * 60) == "2h 5m")
    }

    @Test func emptyInputProducesEmptyStats() {
        let stats = StatsBuilder.build(from: [], now: Date())
        #expect(stats.isEmpty)
        #expect(stats.dailyActivity.count == 7)
        #expect(stats.topProjects.isEmpty)
        #expect(stats.averageFocusStars == nil)
    }
}

struct SnapshotDatabaseTests {
    private func tempDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("trace-test-\(UUID().uuidString).db")
    }

    @Test func roundTripWriteAndRead() async throws {
        let url = tempDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let db = try SnapshotDatabase(databaseURL: url)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let context = CapturedContext(
            appName: "Xcode",
            appBundle: "com.apple.dt.Xcode",
            windowTitle: "Trace — AppState.swift",
            documentURL: "file:///Users/dev/Trace/Trace/AppState.swift",
            timestamp: timestamp
        )

        try await db.save(context)
        let loaded = try await db.load(since: timestamp.addingTimeInterval(-60))

        #expect(loaded.count == 1)
        #expect(loaded[0].appName == "Xcode")
        #expect(loaded[0].windowTitle == "Trace — AppState.swift")
    }

    @Test func incrementalLoadAfterId() async throws {
        let url = tempDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let db = try SnapshotDatabase(databaseURL: url)
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        try await db.save(CapturedContext(
            appName: "Xcode", appBundle: "com.apple.dt.Xcode", timestamp: base
        ))
        try await db.save(CapturedContext(
            appName: "Safari",
            appBundle: "com.apple.Safari",
            timestamp: base.addingTimeInterval(60)
        ))

        let all = try await db.load(since: .distantPast)
        #expect(all.count == 2)

        let delta = try await db.load(afterId: all[0].id)
        #expect(delta.count == 1)
        #expect(delta[0].appName == "Safari")
    }

    @Test func pruneRemovesOlderSnapshots() async throws {
        let url = tempDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let db = try SnapshotDatabase(databaseURL: url)
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        let recent = Date(timeIntervalSince1970: 1_700_000_000)

        try await db.save(CapturedContext(appName: "Old", appBundle: "old", timestamp: old))
        try await db.save(CapturedContext(appName: "Recent", appBundle: "recent", timestamp: recent))

        try await db.prune(before: Date(timeIntervalSince1970: 1_650_000_000))

        let remaining = try await db.load(since: .distantPast)
        #expect(remaining.count == 1)
        #expect(remaining[0].appName == "Recent")
    }
}

struct BundleRegistryTests {
    @Test func detectsCommonBrowsers() {
        let registry = BundleRegistry.defaults
        #expect(registry.browsers.contains("com.google.Chrome"))
        #expect(registry.browsers.contains("com.apple.Safari"))
    }

    @Test func detectsChatApps() {
        let registry = BundleRegistry.defaults
        #expect(registry.chatApps.contains("ai.perplexity.macv3"))
        #expect(registry.chatApps.contains("com.anthropic.claude"))
    }

    @Test func detectsTerminals() {
        let registry = BundleRegistry.defaults
        #expect(registry.terminals.contains("com.apple.Terminal"))
        #expect(registry.terminals.contains("com.googlecode.iterm2"))
    }
}
