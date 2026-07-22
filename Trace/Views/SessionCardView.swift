import SwiftUI

struct SessionCardView: View {
    let session: Session
    @Environment(AppState.self) private var appState
    @State private var isExpanded = false
    @State private var isRestoring = false
    @State private var restoreMessage: String?

    private var detailApps: [SessionApp] {
        session.apps.filter { SessionAppDisplay.shouldShowInDetail($0, in: session) }
    }

    private var collapsedApps: [SessionApp] {
        if !detailApps.isEmpty { return detailApps }
        return SessionAppDisplay.rankedApps(session.apps)
    }

    private var primaryApp: SessionApp? {
        collapsedApps.first ?? session.apps.first
    }

    private var displaySummary: String? {
        SessionDisplay.contextSubtitle(for: session)
    }

    private var sessionTitle: String {
        SessionDisplay.sessionTitle(for: session)
    }

    private var isSingleApp: Bool {
        session.apps.count <= 1
    }

    private var listApps: [SessionApp] {
        if !detailApps.isEmpty { return detailApps }
        return SessionAppDisplay.rankedApps(session.apps)
    }

    private var hasRichDetail: Bool {
        SessionDisplay.hasRichDetail(session.apps)
    }

    private var showAppList: Bool {
        !(isSingleApp && !hasRichDetail) && !listApps.isEmpty
    }

    private var reopenLabel: String {
        if isSingleApp, let app = primaryApp {
            return "Reopen \(app.appName)"
        }
        return "Reopen session"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(sessionTitle)
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Text(SessionDisplay.relativeTimeLabel(for: session))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                if let timeRange = SessionDisplay.timeRangeWithDurationLabel(for: session) {
                    Text(timeRange)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let summary = displaySummary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if !collapsedApps.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(collapsedApps.prefix(5)) { app in
                            AppIconBadge(app: app)
                        }
                        if collapsedApps.count > 5 {
                            Text("+\(collapsedApps.count - 5)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !session.apps.isEmpty else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                    if !isExpanded { restoreMessage = nil }
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        Task { await restoreSession() }
                    } label: {
                        if isRestoring {
                            ProgressView()
                                .controlSize(.small)
                                .frame(maxWidth: .infinity)
                        } else {
                            Label(reopenLabel, systemImage: "arrow.uturn.backward")
                                .font(.caption.weight(.medium))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isRestoring)

                    if let restoreMessage {
                        Text(restoreMessage)
                            .font(.caption2)
                            .foregroundStyle(restoreMessage.contains("Couldn't") ? .orange : .secondary)
                    }

                    if showAppList {
                        Text("Apps in this session")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        VStack(spacing: 0) {
                            ForEach(listApps) { app in
                                AppDetailRow(
                                    app: app,
                                    session: session,
                                    showSessionActions: !isSingleApp
                                ) { result in
                                    restoreMessage = result
                                }
                                if app.id != listApps.last?.id {
                                    Divider().padding(.leading, 36)
                                }
                            }
                        }
                    } else if isSingleApp, let app = primaryApp {
                        Button {
                            appState.openApp(bundleId: app.bundleId)
                        } label: {
                            Label("Open \(app.appName)", systemImage: "arrow.up.forward.app")
                                .font(.caption.weight(.medium))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(10)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            }

            if !appState.hasAccessibilityPermission {
                Label("Grant Accessibility for window details", systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func restoreSession() async {
        isRestoring = true
        restoreMessage = nil
        let result = await appState.restoreSession(session)
        restoreMessage = RestoreFeedback.message(for: result)
        isRestoring = false
    }
}

// MARK: - Per-app detail row

struct AppDetailRow: View {
    let app: SessionApp
    let session: Session
    var showSessionActions = true
    let onRestoreFeedback: (String) -> Void

    @Environment(AppState.self) private var appState
    @State private var isRestoring = false

    private var displayLines: [SessionAppDisplay.Line] {
        SessionAppDisplay.contextLines(for: app)
    }

    private var timeShare: String? {
        SessionDisplay.appTimeShare(for: app, in: session)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AppIconBadge(app: app, size: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(app.appName)
                        .font(.callout.weight(.medium))
                    if let timeShare {
                        Text(timeShare)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                if !displayLines.isEmpty {
                    ForEach(displayLines.prefix(3)) { line in
                        Text(line.text)
                            .font(.caption)
                            .foregroundStyle(line.isPath ? .blue : .secondary)
                            .lineLimit(1)
                    }
                    if displayLines.count > 3 {
                        Text("+\(displayLines.count - 3) more")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            if showSessionActions {
                Menu {
                    if SessionAppDisplay.hasRestorableContent(app) {
                        Button {
                            Task { await reopenWindows() }
                        } label: {
                            Label("Reopen windows", systemImage: "arrow.uturn.backward")
                        }
                        .disabled(isRestoring)
                    }
                    Button {
                        appState.openApp(bundleId: app.bundleId)
                    } label: {
                        Label("Open app", systemImage: "arrow.up.forward.app")
                    }
                } label: {
                    Image(systemName: isRestoring ? "hourglass" : "ellipsis.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(.vertical, 6)
    }

    private func reopenWindows() async {
        isRestoring = true
        let result = await appState.restoreApp(app)
        onRestoreFeedback(RestoreFeedback.message(for: result, appName: app.appName))
        isRestoring = false
    }
}

enum RestoreFeedback {
    static func message(for result: RestoreResult, appName: String? = nil) -> String {
        let opened = result.restored.count
        let failed = result.failed.count

        if opened == 0 && failed > 0 {
            let prefix = appName.map { "Couldn't reopen \($0)" } ?? "Couldn't reopen session"
            return "\(prefix) — \(result.failed[0].reason)"
        }
        if failed == 0 {
            let prefix = appName.map { "Reopened \($0)" } ?? "Reopened session"
            let detail = opened > 1 ? " (\(opened) items)" : ""
            return prefix + detail
        }
        let prefix = appName.map { "Reopened \($0)" } ?? "Reopened session"
        return "\(prefix) — \(opened) opened, \(failed) couldn't"
    }
}

// MARK: - App icon

struct AppIconBadge: View {
    let app: SessionApp
    var size: CGFloat = 20

    var body: some View {
        Group {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: size * 0.7))
                    .foregroundStyle(.secondary)
                    .frame(width: size, height: size)
            }
        }
        .help(app.appName)
    }

    private var appIcon: NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: app.bundleId
        ) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
