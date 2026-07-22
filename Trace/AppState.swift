import AppKit
import Observation

@Observable
final class AppState {
    var sessions: [Session] = []
    var isTracking = true
    var hasCompletedOnboarding: Bool
    var hasAccessibilityPermission: Bool
    var lastPollDate: Date = .now

    private let database: SnapshotDatabase
    private let tracker: ActivityTracker
    private let restorer = RestoreService()
    private let summarizer = SummaryService()

    init() {
        let db = try! SnapshotDatabase()
        self.database = db
        self.tracker = ActivityTracker(database: db)
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
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
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        do {
            let snapshots = try await database.fetchSnapshots(since: cutoff)
            var built = SessionBuilder.buildSessions(from: snapshots)
            for i in built.indices {
                built[i].apps = built[i].apps.filter { app in
                    !ActivityTracker.ignoredBundles.contains(app.bundleId)
                }
                let summary = await summarizer.summarize(
                    apps: built[i].apps,
                    durationMinutes: built[i].durationMinutes
                )
                built[i].summary = summary.isEmpty ? nil : summary
            }
            self.sessions = built.filter { !$0.apps.isEmpty }
        } catch {
            // Keep existing sessions on failure
        }
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

    private var lastRefresh: Date = .distantPast

    private func refreshIfStale() async {
        guard Date().timeIntervalSince(lastRefresh) > 15 else { return }
        lastRefresh = Date()
        await refreshTimeline()
    }

    private func pruneAndLoad() async {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        try? await database.pruneOlderThan(cutoff)
        await refreshTimeline()
        lastRefresh = Date()
    }
}
