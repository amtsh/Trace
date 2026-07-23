import SwiftUI

struct TimelineView: View {
    @Environment(AppState.self) private var appState
    @State private var showClearConfirmation = false

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
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(DS.Poll.timelineRefreshSeconds))
                await appState.refreshTimeline()
            }
        }
        .onAppear {
            appState.checkAccessibility()
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

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Spacing.md) {
                Text("Trace")
                    .font(.title.weight(.bold))
                    .shadow(
                        color: .black.opacity(DS.Opacity.shadowText),
                        radius: DS.Shadow.textRadius,
                        y: DS.Shadow.textY
                    )

                headerMenu

                if !appState.isTracking {
                    Text("Paused")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, 3)
                        .background(VisualEffectBackground())
                        .clipShape(Capsule())
                }

                Spacer()
            }
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

    private var headerMenu: some View {
        Menu {
            Toggle(
                appState.isTracking ? "Tracking is ON" : "Turn ON Tracking",
                isOn: .init(
                    get: { appState.isTracking },
                    set: { _ in appState.toggleTracking() }
                )
            )
            Divider()
            Button("Clear All Data…", role: .destructive) {
                showClearConfirmation = true
            }
            Divider()
            Button("Quit Trace") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Trace menu")
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 0) {
            ContentUnavailableView {
                Label("No Activity Yet", systemImage: "clock.arrow.circlepath")
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.Spacing.sm) {
                header

                ForEach(dayGroups, id: \.label) { group in
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
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.xxl)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Day grouping

    private var dayGroups: [DayGroup] {
        let sorted = appState.sessions.sorted { $0.startTime > $1.startTime }
        var groups: [DayGroup] = []
        var currentKey = ""
        var currentLabel = ""
        var currentSessions: [Session] = []

        for session in sorted {
            let key = dayKey(session.startTime)
            if key != currentKey {
                if !currentSessions.isEmpty {
                    groups.append(DayGroup(label: currentLabel, sessions: currentSessions))
                }
                currentKey = key
                currentLabel = dayLabel(session.startTime)
                currentSessions = [session]
            } else {
                currentSessions.append(session)
            }
        }
        if !currentSessions.isEmpty {
            groups.append(DayGroup(label: currentLabel, sessions: currentSessions))
        }
        return groups
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

private struct DayGroup {
    let label: String
    let sessions: [Session]
}
