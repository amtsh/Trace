import AppKit
import Observation

@Observable
final class AppState {
    var sessions: [Session] = []
    var isTracking = true
    var hasCompletedOnboarding: Bool
    var hasAccessibilityPermission: Bool
    var lastPollDate: Date = .now
    private(set) var hiddenSessionIds: Set<String>

    private let database: SnapshotDatabase
    private let tracker: ActivityTracker
    private let restorer = RestoreService()
    private let summarizer = SummaryService()

    init() {
        let db = try! SnapshotDatabase()
        self.database = db
        self.tracker = ActivityTracker(database: db)
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        self.hiddenSessionIds = Set(UserDefaults.standard.stringArray(forKey: "hiddenSessionIds") ?? [])
        self.hasAccessibilityPermission = PermissionManager.hasAccessibilityPermission

        tracker.onPollCompleted = { [weak self] in
            Task { @MainActor in self?.lastPollDate = .now }
        }

        tracker.onSnapshotCaptured = { [weak self] in
            Task { @MainActor in
                await self?.refreshIfStale()
            }
        }

        Task {
            await pruneAndLoad()
            tracker.start()
        }
    }

    // MARK: - Public

    func refreshTimeline() async {
        refreshGeneration += 1
        let generation = refreshGeneration

        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        do {
            let snapshots = try await database.fetchSnapshots(since: cutoff)
            var built = SessionBuilder.buildSessions(from: snapshots)
            for i in built.indices {
                built[i].apps = built[i].apps.filter { !ActivityTracker.ignoredBundles.contains($0.bundleId) }
            }
            var initial = built.filter { !$0.apps.isEmpty }

            // Carry over existing summaries so the UI never flashes to empty
            let existingSummaries = Dictionary(
                uniqueKeysWithValues: sessions.compactMap { s in s.summary.map { (s.id, $0) } }
            )
            for i in initial.indices {
                initial[i].summary = existingSummaries[initial[i].id]
            }

            guard generation == refreshGeneration else { return }
            self.sessions = initial

            // Only (re)generate summaries for recent sessions or those still missing one.
            // Older closed sessions are stable — their summary is already cached on disk.
            let recentCutoff = Date().addingTimeInterval(-30 * 60)
            for session in initial where session.summary == nil || session.endTime > recentCutoff {
                let summary = await summarizer.summarize(
                    apps: session.apps,
                    durationMinutes: session.durationMinutes
                )
                guard generation == refreshGeneration, !summary.isEmpty else { continue }
                if let idx = self.sessions.firstIndex(where: { $0.id == session.id }) {
                    self.sessions[idx].summary = summary
                }
            }
        } catch {
            // Keep existing sessions on failure
        }
    }

    func isSessionHidden(_ session: Session) -> Bool {
        hiddenSessionIds.contains(session.id)
    }

    func setSession(_ session: Session, hidden: Bool) {
        if hidden {
            hiddenSessionIds.insert(session.id)
        } else {
            hiddenSessionIds.remove(session.id)
        }
        UserDefaults.standard.set(Array(hiddenSessionIds), forKey: "hiddenSessionIds")
    }

    func restoreSession(_ session: Session) async -> RestoreResult {
        await restorer.restore(session)
    }

    func restoreApp(_ app: SessionApp) async -> RestoreResult {
        await restorer.restore(app: app)
    }

    func openApp(bundleId: String) {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleId
        ) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
    }

    func requestAccessibility() {
        PermissionManager.requestAccessibilityPermission()
    }

    func checkAccessibility() {
        hasAccessibilityPermission = PermissionManager.hasAccessibilityPermission
    }

    func toggleTracking() {
        if isTracking { tracker.stop() } else { tracker.start() }
        isTracking.toggle()
    }

    func wipeAllData() async {
        tracker.stop()
        try? await database.pruneOlderThan(Date.distantFuture)
        sessions = []
        tracker.start()
        isTracking = true
    }

    // MARK: - Private

    private var refreshGeneration = 0
    private var lastRefresh: Date = .distantPast

    private func refreshIfStale() async {
        guard Date().timeIntervalSince(lastRefresh) > 15 else { return }
        lastRefresh = Date()
        await refreshTimeline()
    }

    private func pruneAndLoad() async {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        try? await database.pruneOlderThan(cutoff)
        pruneHiddenIds(before: cutoff)
        await refreshTimeline()
        lastRefresh = Date()
    }

    private func pruneHiddenIds(before cutoff: Date) {
        let cutoffTimestamp = Int(cutoff.timeIntervalSince1970)
        let pruned = hiddenSessionIds.filter { id in
            guard let ts = Int(id.dropFirst("session-".count)) else { return true }
            return ts >= cutoffTimestamp
        }
        if pruned != hiddenSessionIds {
            hiddenSessionIds = pruned
            UserDefaults.standard.set(Array(pruned), forKey: "hiddenSessionIds")
        }
    }
}
