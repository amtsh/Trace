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
                try? await Task.sleep(for: .seconds(30))
                await appState.refreshTimeline()
            }
        }
        .onAppear {
            appState.checkAccessibility()
        }
        // Consistent destructive confirmation using SwiftUI, not NSAlert.runModal()
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
            HStack(spacing: 10) {
                Text("Trace")
                    .font(.title.weight(.bold))
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                if appState.isTracking {
                    PollCountdownRing(lastPoll: appState.lastPollDate)
                } else {
                    Text("Paused")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(VisualEffectBackground())
                        .clipShape(Capsule())
                }
                Spacer()
                Menu {
                    Toggle(appState.isTracking ? "Tracking is ON" : "Turn ON Tracking", isOn: .init(
                        get: { appState.isTracking },
                        set: { _ in appState.toggleTracking() }
                    ))
                    Divider()
                    Button("Clear All Data\u2026", role: .destructive) {
                        showClearConfirmation = true
                    }
                    Divider()
                    Button("Quit Trace") {
                        NSApplication.shared.terminate(nil)
                    }
                } label: {
                    Text("Menu")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Capsule())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.top, 8)
            .padding(.bottom, 10)

            // Single accessibility warning — shown once here, not per-card.
            if !appState.hasAccessibilityPermission {
                Button {
                    appState.requestAccessibility()
                } label: {
                    Label("Grant Accessibility for window details", systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 6)
            }
        }
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
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.top, 4)

            Spacer()
        }
    }

    // MARK: - Session list

    private var sessionList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                header

                ForEach(dayGroups, id: \.label) { group in
                    if group.label != "Today" {
                        Text(group.label)
                            .font(.title3.weight(.bold))
                            .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                            .padding(.top, 10)
                    }

                    ForEach(group.sessions) { session in
                        SessionCardView(session: session)
                    }
                }
            }
            .padding(.bottom, 16)
        }
    }

    // MARK: - Day grouping

    private var dayGroups: [DayGroup] {
        // Explicit sort: newest first, so grouping is always correct
        // regardless of the order sessions arrive from AppState.
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

/// Countdown ring showing time until next poll.
/// Uses a single `TimelineView` that only runs while tracking is active,
/// avoiding a constant 1Hz redraw when the panel is hidden but hosting view persists.
private struct PollCountdownRing: View {
    let lastPoll: Date
    private let interval: TimeInterval = 30

    var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = context.date.timeIntervalSince(lastPoll)
            let remaining = max(0, 1.0 - elapsed / interval)

            Circle()
                .trim(from: 0, to: remaining)
                .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(-90))
                .frame(width: 10, height: 10)
                .animation(.linear(duration: 1), value: remaining)
        }
    }
}
