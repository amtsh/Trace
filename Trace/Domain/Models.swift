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
    let durationMinutes: Int
    var apps: [SessionApp]
    var summary: String?
    let activity: String
}

struct SessionApp: Sendable, Identifiable {
    var id: String { bundleId }
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
}

struct RestoreResult: Sendable {
    let restored: [String]
    let failed: [(item: String, reason: String)]
}
