import SwiftUI

struct TimelineView: View {
    @Environment(AppState.self) private var appState
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
    }

    // MARK: - Header

    private var header: some View {
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
                Button("Clear All Data…", role: .destructive) {
                    confirmAndClearData()
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
    }

    private func confirmAndClearData() {
        let alert = NSAlert()
        alert.messageText = "Clear All Data?"
        alert.informativeText = "This will permanently delete all recorded activity. This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            Task { await appState.wipeAllData() }
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
        var groups: [DayGroup] = []
        var currentKey = ""
        var currentLabel = ""
        var currentSessions: [Session] = []

        for session in appState.sessions {
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
