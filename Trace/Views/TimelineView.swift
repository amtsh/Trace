import SwiftUI

struct TimelineView: View {
    @Environment(AppState.self) private var appState
    @State private var showClearConfirmation = false
    @State private var showStats = false
    @State private var showMenu = false
    @State private var visibleCount = 10
    @State private var cachedDayGroups: [DayGroup] = []

    private static let pageSize = 10

    var body: some View {
        Group {
            if appState.sessions.isEmpty {
                VStack(spacing: 0) {
                    header
                    emptyState
                }
            } else {
                sessionList
            }
        }
        .task {
            await appState.refreshTimeline()
            rebuildDayGroups()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(DS.Poll.timelineRefreshSeconds))
                await appState.refreshTimeline()
            }
        }
        .onAppear {
            appState.checkAccessibility()
        }
        .onChange(of: appState.sessions.map(\.id)) {
            rebuildDayGroups()
        }
        .onChange(of: appState.panelPresentationGeneration) {
            resetForPresentation()
        }
        .onChange(of: showMenu) {
            syncOutsideDismissBlock()
        }
        .onChange(of: showClearConfirmation) {
            syncOutsideDismissBlock()
        }
        .confirmationDialog(
            "Clear All Data?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Everything", role: .destructive) {
                Task { await appState.wipeAllData() }
            }
        } message: {
            Text("This permanently deletes all recorded activity. This cannot be undone.")
        }
    }

    private func resetForPresentation() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            visibleCount = Self.pageSize
            showMenu = false
            showStats = false
            showClearConfirmation = false
        }
        syncOutsideDismissBlock()
    }

    private func syncOutsideDismissBlock() {
        appState.updateOutsideDismissBlock(
            menuOpen: showMenu,
            clearDialogOpen: showClearConfirmation
        )
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: DS.Spacing.md) {
                Text("Trace")
                    .font(.title.weight(.bold))
                    .shadow(
                        color: .black.opacity(DS.Opacity.shadowText),
                        radius: DS.Shadow.textRadius,
                        y: DS.Shadow.textY
                    )
                    .alignmentGuide(VerticalAlignment.center) { dimensions in
                        dimensions[VerticalAlignment.center] - 1
                    }

                if !appState.isTracking {
                    Text("Paused")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.orange)
                        .headerControl(height: DS.Header.controlHeight)
                        .background(VisualEffectBackground())
                        .clipShape(Capsule())
                }

                Spacer(minLength: 0)

                HStack(alignment: .center, spacing: DS.Spacing.xs) {
                    if !appState.sessions.isEmpty {
                        statsToggle
                    }
                    headerMenu
                    dismissButton
                }
            }
            .frame(minHeight: DS.Header.controlHeight)
            .padding(.top, DS.Spacing.sm)
            .padding(.bottom, DS.Spacing.md)

            if !appState.hasAccessibilityPermission {
                Button {
                    appState.requestAccessibility()
                } label: {
                    Label("Grant Accessibility for window details", systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.xs)
                        .background(Color.orange.opacity(DS.Opacity.accessoryBannerBg))
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.bottom, DS.Spacing.xs)
            }
        }
    }

    private var statsToggle: some View {
        Button {
            withAnimation(DS.Animation.cardExpand) { showStats.toggle() }
        } label: {
            headerPill(showStats ? "See Activity" : "See Stats")
        }
        .buttonStyle(.plain)
        .help(showStats ? "Back to timeline" : "Show stats")
        .accessibilityLabel(showStats ? "Back to timeline" : "Show stats")
    }

    private var headerMenu: some View {
        Button {
            showMenu.toggle()
        } label: {
            headerPill("Menu")
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showMenu, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Toggle(
                    appState.isTracking ? "Tracking is ON" : "Turn ON Tracking",
                    isOn: .init(
                        get: { appState.isTracking },
                        set: { _ in appState.toggleTracking() }
                    )
                )
                Divider()
                Button("Clear All Data…", role: .destructive) {
                    showMenu = false
                    showClearConfirmation = true
                }
                .buttonStyle(.plain)
                Divider()
                Button("Quit Trace") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
            }
            .padding(DS.Spacing.md)
            .frame(minWidth: 200, alignment: .leading)
        }
        .help("Trace menu")
    }

    private var dismissButton: some View {
        Button {
            showMenu = false
            SidebarPanelController.shared.hide()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: DS.Header.controlHeight, height: DS.Header.controlHeight)
                .background(VisualEffectBackground())
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Close")
        .accessibilityLabel("Close")
    }

    private func headerPill(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .headerControl(height: DS.Header.controlHeight)
            .background(VisualEffectBackground())
            .clipShape(Capsule())
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 0) {
            ContentUnavailableView {
                Label("No Activity Yet", systemImage: "clock")
            } description: {
                Text("Trace records what you're working on.\nCheck back shortly.")
            }
            .padding(.vertical, 20)
            .background(VisualEffectBackground())
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .padding(.top, DS.Spacing.xxs)

            Spacer()
        }
    }

    // MARK: - Session list

    private var sessionList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    header
                        .id("timelineTop")

                    if showStats {
                        StatsView()
                    } else {
                        ForEach(pagedDayGroups) { group in
                            if group.label != "Today" {
                                Text(group.label)
                                    .font(.title3.weight(.bold))
                                    .shadow(
                                        color: .black.opacity(DS.Opacity.shadowText),
                                        radius: DS.Shadow.textRadius,
                                        y: DS.Shadow.textY
                                    )
                                    .padding(.top, DS.Spacing.md)
                            }

                            ForEach(group.sessions) { session in
                                SessionCardView(session: session)
                            }
                        }

                        if hasMoreSessions {
                            Button {
                                loadMore()
                            } label: {
                                Text("Show more")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, DS.Spacing.sm)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.xxl)
            }
            .scrollIndicators(.hidden)
            .scrollIndicatorsFlash(onAppear: false)
            .onAppear { hideNSScrollViewIndicators() }
            .onChange(of: appState.panelPresentationGeneration) {
                proxy.scrollTo("timelineTop", anchor: .top)
            }
        }
    }

    private func hideNSScrollViewIndicators() {
        DispatchQueue.main.async {
            for window in NSApplication.shared.windows {
                for case let scrollView as NSScrollView in window.contentView?.descendants ?? [] {
                    scrollView.hasVerticalScroller = false
                    scrollView.hasHorizontalScroller = false
                }
            }
        }
    }

    // MARK: - Pagination

    private var totalSessionCount: Int {
        cachedDayGroups.reduce(0) { $0 + $1.sessions.count }
    }

    private var hasMoreSessions: Bool {
        visibleCount < totalSessionCount
    }

    private func loadMore() {
        visibleCount += Self.pageSize
    }

    private func rebuildDayGroups() {
        let sorted = appState.sessions.sorted { $0.startTime > $1.startTime }
        var groups: [DayGroup] = []
        var currentKey = ""
        var currentLabel = ""
        var currentSessions: [Session] = []

        for session in sorted {
            let key = dayKey(session.startTime)
            if key != currentKey {
                if !currentSessions.isEmpty {
                    groups.append(DayGroup(key: currentKey, label: currentLabel, sessions: currentSessions))
                }
                currentKey = key
                currentLabel = dayLabel(session.startTime)
                currentSessions = [session]
            } else {
                currentSessions.append(session)
            }
        }
        if !currentSessions.isEmpty {
            groups.append(DayGroup(key: currentKey, label: currentLabel, sessions: currentSessions))
        }
        cachedDayGroups = groups
    }

    private var pagedDayGroups: [DayGroup] {
        var remaining = visibleCount
        var result: [DayGroup] = []
        for group in cachedDayGroups {
            guard remaining > 0 else { break }
            if group.sessions.count <= remaining {
                result.append(group)
                remaining -= group.sessions.count
            } else {
                let sliced = Array(group.sessions.prefix(remaining))
                result.append(DayGroup(key: group.key, label: group.label, sessions: sliced))
                remaining = 0
            }
        }
        return result
    }

    private func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year!)-\(c.month!)-\(c.day!)"
    }

    private func dayLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

private extension View {
    func headerControl(height: CGFloat) -> some View {
        frame(height: height)
            .padding(.horizontal, DS.Spacing.sm)
    }
}

private struct DayGroup: Identifiable {
    let key: String
    let label: String
    let sessions: [Session]

    var id: String { key }
}
