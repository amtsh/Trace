import Foundation

/// Captures foreground-app context and persists snapshots on a schedule.
protocol ActivityTracking: AnyObject {
    func start()
    func stop()
    var onSnapshotCaptured: (() -> Void)? { get set }
}

/// Persists captured snapshots and serves them back for session building.
protocol SessionPersisting: Sendable {
    func save(_ snapshot: CapturedContext) async throws
    func load(since: Date) async throws -> [Snapshot]
    func load(afterId: Int64) async throws -> [Snapshot]
    func prune(before: Date) async throws
    func lastSnapshot() async throws -> Snapshot?
}

protocol Summarizer: Sendable {
    func summarize(apps: [SessionApp], durationMinutes: Int) async -> String
    func regenerate(apps: [SessionApp], durationMinutes: Int, previousSummary: String?) async -> String
}
