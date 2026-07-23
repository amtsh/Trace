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
                    .safeAreaInset(edge: .top, spacing: 0) { header }
                    .scrollEdgeEffectStyle(.soft, for: .top)
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
        HStack(spacing: 8) {
            Text("Trace")
                .font(.title3.weight(.semibold))
            if appState.isTracking {
                PollCountdownRing(lastPoll: appState.lastPollDate)
            } else {
                Text("Paused")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
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
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(.quaternary.opacity(0.5), in: Circle())
                    .contentShape(Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
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
        ContentUnavailableView {
            Label("No Activity Yet", systemImage: "clock.arrow.circlepath")
        } description: {
            Text("Trace records what you're working on.\nCheck back shortly.")
        }
    }

    // MARK: - Session list

    private var sessionList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(dayGroups, id: \.label) { group in
                    Text(group.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.top, 6)

                    ForEach(group.sessions) { session in
                        SessionCardView(session: session)
                    }
                }

                if appState.hiddenSessionCount > 0 {
                    hiddenRowsFooter
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 14)
        }
    }

    private var hiddenRowsFooter: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                appState.showHiddenSessions.toggle()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: appState.showHiddenSessions ? "eye" : "eye.slash")
                let count = appState.hiddenSessionCount
                Text(appState.showHiddenSessions
                     ? "Hide \(count) hidden \(count == 1 ? "row" : "rows")"
                     : "Show \(count) hidden \(count == 1 ? "row" : "rows")")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.5), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // MARK: - Day grouping

    private var dayGroups: [DayGroup] {
        var groups: [DayGroup] = []
        var currentKey = ""
        var currentLabel = ""
        var currentSessions: [Session] = []

        for session in appState.visibleSessions {
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
