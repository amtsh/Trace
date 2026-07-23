import Foundation

struct Snapshot: Sendable, Identifiable {
    let id: Int64
    let timestamp: Date
    let appBundle: String
    let appName: String
    let windowTitle: String?
    let documentURL: String?
    let isIdle: Bool
}

struct Session: Sendable, Identifiable {
    let id: String
    let startTime: Date
    let endTime: Date
    /// Total elapsed seconds (precise). Use this for display.
    let durationSeconds: Int
    /// Derived from durationSeconds for backward compat with SummaryService.
    var durationMinutes: Int { max(durationSeconds / 60, 1) }
    var apps: [SessionApp]
    var summary: String?
    let activity: String
}

struct SessionApp: Sendable, Identifiable {
    /// Composite key: unique per session even if the same app bundle appears
    /// with different snapshot counts (prevents ForEach identity collisions).
    var id: String { "\(bundleId)-\(snapshotCount)" }
    let appName: String
    let bundleId: String
    let windowTitles: [String]
    let urls: [String]
    let snapshotCount: Int
}

struct CapturedContext: Sendable {
    let appName: String
    let appBundle: String
    let windowTitle: String?
    let documentURL: String?
    let isIdle: Bool
    /// Captured at call-site so DB insert reflects actual event time,
    /// not the (potentially later) moment the actor processes the write.
    let timestamp: Date

    init(
        appName: String,
        appBundle: String,
        windowTitle: String? = nil,
        documentURL: String? = nil,
        isIdle: Bool = false,
        timestamp: Date = Date()
    ) {
        self.appName = appName
        self.appBundle = appBundle
        self.windowTitle = windowTitle
        self.documentURL = documentURL
        self.isIdle = isIdle
        self.timestamp = timestamp
    }
}

struct RestoreResult: Sendable {
    let restored: [String]
    let failed: [(item: String, reason: String)]
}
