import AppKit
import Observation
import OSLog

@Observable
final class AppState {
    var sessions: [Session] = []
    var isTracking = true
    var hasCompletedOnboarding: Bool
    var hasAccessibilityPermission: Bool
    var lastPollDate: Date = .now
    var expandedSessionId: String?
    var databaseError: String? = nil
    private(set) var panelPresentationGeneration = 0
    var isHeaderMenuOpen = false
    private(set) var isOutsideDismissBlocked = false
    private(set) var dismissBlockGeneration = 0
    private(set) var hiddenSessionIds: Set<String>
    private(set) var summarizingSessionIds: Set<String> = []

    private let database: SnapshotDatabase?
    private let tracker: ActivityTracker?
    private let restorer = RestoreService()
    private let summarizer = SummaryService()

    init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        self.hiddenSessionIds = Set(UserDefaults.standard.stringArray(forKey: "hiddenSessionIds") ?? [])
        self.hasAccessibilityPermission = PermissionManager.hasAccessibilityPermission

        let db: SnapshotDatabase
        let activityTracker: ActivityTracker
        do {
            db = try SnapshotDatabase()
            activityTracker = ActivityTracker(database: db)
        } catch {
            self.database = nil
            self.tracker = nil
            self.databaseError = error.localizedDescription
            Logger.db.error("Database init failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        self.database = db
        self.tracker = activityTracker

        activityTracker.onPollCompleted = { [weak self] in
            Task { @MainActor in self?.lastPollDate = .now }
        }

        activityTracker.onSnapshotCaptured = { [weak self] in
            Task { @MainActor in
                await self?.refreshIfStale()
            }
        }

        Task {
            await pruneAndLoad()
            activityTracker.start()
        }
    }

    func refreshTimeline() async {
        guard database != nil else { return }
        refreshGeneration += 1
        let generation = refreshGeneration

        await maybePrune()

        do {
            let (snapshots, hasChanges) = try await loadSnapshots(forceFullReload: false)
            guard hasChanges else { return }

            var built = SessionBuilder.buildSessions(from: snapshots)
            for i in built.indices {
                built[i].apps = built[i].apps.filter { !ActivityTracker.ignoredBundles.contains($0.bundleId) }
            }
            var initial = built.filter { !$0.apps.isEmpty }

            let existingSummaries = Dictionary(
                uniqueKeysWithValues: sessions.compactMap { s in s.summary.map { (s.id, $0) } }
            )
            for i in initial.indices {
                initial[i].summary = existingSummaries[initial[i].id]
            }

            guard generation == refreshGeneration else { return }
            self.sessions = initial
            if expandedSessionId == nil, let latest = initial.first {
                expandedSessionId = latest.id
            }

            let recentCutoff = Date().addingTimeInterval(-30 * 60)
            for session in initial where session.summary == nil || session.endTime > recentCutoff {
                let needsSummary = session.summary == nil
                if needsSummary {
                    summarizingSessionIds.insert(session.id)
                }

                let summary = await summarizer.summarize(
                    apps: session.apps,
                    durationMinutes: session.durationMinutes
                )

                if needsSummary {
                    summarizingSessionIds.remove(session.id)
                }

                guard generation == refreshGeneration, !summary.isEmpty else { continue }
                if let idx = self.sessions.firstIndex(where: { $0.id == session.id }) {
                    self.sessions[idx].summary = summary
                }
            }
        } catch {
            Logger.sessions.error("Timeline refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func panelDidPresent() {
        panelPresentationGeneration += 1
        isHeaderMenuOpen = false
        isOutsideDismissBlocked = false

        let defaultExpanded = sessions
            .sorted { $0.startTime > $1.startTime }
            .first(where: { !hiddenSessionIds.contains($0.id) })

        expandedSessionId = defaultExpanded?.id
    }

    func updateOutsideDismissBlock(menuOpen: Bool, clearDialogOpen: Bool) {
        isHeaderMenuOpen = menuOpen
        let blocked = menuOpen || clearDialogOpen
        if blocked {
            isOutsideDismissBlocked = true
            return
        }

        guard isOutsideDismissBlocked else { return }
        isOutsideDismissBlocked = false
        dismissBlockGeneration += 1
    }

    func isSessionHidden(_ session: Session) -> Bool {
        hiddenSessionIds.contains(session.id)
    }

    func isSummarizingSession(_ session: Session) -> Bool {
        summarizingSessionIds.contains(session.id)
    }

    func regenerateSummary(for session: Session) async {
        guard let idx = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        let current = sessions[idx]
        guard current.summary != nil else { return }

        summarizingSessionIds.insert(current.id)
        defer { summarizingSessionIds.remove(current.id) }

        let summary = await summarizer.regenerate(
            apps: current.apps,
            durationMinutes: current.durationMinutes,
            previousSummary: current.summary
        )

        guard !summary.isEmpty,
              let updateIdx = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[updateIdx].summary = summary
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
        if isTracking { tracker?.stop() } else { tracker?.start() }
        isTracking.toggle()
    }

    func wipeAllData() async {
        guard let database else { return }
        tracker?.stop()
        try? await database.prune(before: Date.distantFuture)
        snapshotCache = []
        lastPruneDate = Date()
        needsSnapshotReload = false
        sessions = []
        tracker?.start()
        isTracking = true
    }

    func resetDatabase() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbURL = appSupport.appendingPathComponent("Trace/trace.db")
        try? FileManager.default.removeItem(at: dbURL)
        databaseError = nil
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Private

    private var refreshGeneration = 0
    private var lastRefresh: Date = .distantPast
    private var lastPruneDate: Date = .distantPast
    private var snapshotCache: [Snapshot] = []
    private var needsSnapshotReload = false

    private func retentionCutoff() -> Date {
        Calendar.current.date(byAdding: .day, value: -DS.Storage.retentionDays, to: Date())!
    }

    private func refreshIfStale() async {
        guard Date().timeIntervalSince(lastRefresh) > 15 else { return }
        lastRefresh = Date()
        await refreshTimeline()
    }

    private func pruneAndLoad() async {
        await performPrune(force: true)
        snapshotCache = []
        await refreshTimeline()
        lastRefresh = Date()
    }

    private func maybePrune() async {
        guard Date().timeIntervalSince(lastPruneDate) >= DS.Storage.pruneInterval else { return }
        await performPrune(force: false)
    }

    private func performPrune(force: Bool) async {
        guard let database else { return }
        if !force, Date().timeIntervalSince(lastPruneDate) < DS.Storage.pruneInterval { return }

        let cutoff = retentionCutoff()
        do {
            try await database.prune(before: cutoff)
        } catch {
            Logger.db.error("Scheduled prune failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        lastPruneDate = Date()
        pruneHiddenIds(before: cutoff)
        snapshotCache.removeAll { $0.timestamp < cutoff }
        needsSnapshotReload = true
    }

    private func loadSnapshots(forceFullReload: Bool) async throws -> (snapshots: [Snapshot], hasChanges: Bool) {
        guard let database else { return ([], false) }

        let cutoff = retentionCutoff()

        if forceFullReload || needsSnapshotReload || snapshotCache.isEmpty {
            needsSnapshotReload = false
            snapshotCache = try await database.load(since: cutoff)
            return (snapshotCache, true)
        }

        guard let lastCachedId = snapshotCache.last?.id else {
            snapshotCache = try await database.load(since: cutoff)
            return (snapshotCache, true)
        }

        let delta = try await database.load(afterId: lastCachedId)
        guard !delta.isEmpty else {
            return (snapshotCache, false)
        }

        snapshotCache.append(contentsOf: delta)
        snapshotCache.removeAll { $0.timestamp < cutoff }
        return (snapshotCache, true)
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
