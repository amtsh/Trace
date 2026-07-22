import SwiftUI

struct TimelineView: View {
    @Environment(AppState.self) private var appState
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if appState.sessions.isEmpty {
                emptyState
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
        HStack {
            Text("Trace")
                .font(.headline)
            if appState.isTracking {
                PollCountdownRing(lastPoll: appState.lastPollDate)
            } else {
                Text("Paused")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.15), in: Capsule())
            }
            Spacer()
            Menu {
                Toggle(appState.isTracking ? "Tracking is ON" : "Tracking is OFF", isOn: .init(
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
                Image(systemName: "ellipsis")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No activity yet")
                .font(.headline)
            Text("Trace records what you're working on.\nCheck back shortly.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }

    // MARK: - Session list

    private var sessionList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(dayGroups, id: \.label) { group in
                    Section {
                        ForEach(group.sessions) { session in
                            SessionCardView(session: session)
                            if session.id != group.sessions.last?.id {
                                Divider().padding(.leading, 16)
                            }
                        }
                    } header: {
                        daySectionHeader(group.label)
                    }
                }
            }
        }
    }

    private func daySectionHeader(_ label: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
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
                .foregroundStyle(.quaternary)
                .rotationEffect(.degrees(-90))
                .frame(width: 10, height: 10)
                .animation(.linear(duration: 1), value: remaining)
        }
    }
}
