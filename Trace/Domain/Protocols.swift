import Foundation

protocol SnapshotStore: Sendable {
    func append(_ context: CapturedContext) async throws
    func fetchSnapshots(since date: Date) async throws -> [Snapshot]
    func pruneOlderThan(_ date: Date) async throws
    func lastSnapshot() async throws -> Snapshot?
}

protocol Summarizer: Sendable {
    func summarize(apps: [SessionApp], durationMinutes: Int) async -> String
}
