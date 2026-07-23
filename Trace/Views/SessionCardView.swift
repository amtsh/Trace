import SwiftUI

struct SessionCardView: View {
    let session: Session
    @Environment(AppState.self) private var appState
    @State private var isExpanded = false
    @State private var isRestoring = false
    @State private var restoreMessage: String?
    @State private var isHovering = false

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

    private var secondaryApps: [SessionApp] {
        collapsedApps.count > 1 ? Array(collapsedApps.dropFirst()) : []
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

    var body: some View {
        if isHidden {
            hiddenPill
        } else {
            card
        }
    }

    private var hiddenPill: some View {
        Button {
            appState.setSession(session, hidden: false)
        } label: {
            Text("Hidden activity")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(VisualEffectBackground())
                .clipShape(Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            // NC-style collapsed header: large icon left, content right
            HStack(alignment: .top, spacing: 12) {
                if let app = primaryApp {
                    AppIconBadge(app: app, size: 40)
                        .padding(.top, 1)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 6) {
                        Text(sessionTitle)
                            .font(.body.weight(.bold))
                            .lineLimit(1)
                        Spacer()
                        Text(SessionDisplay.relativeTimeLabel(for: session))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }

                    if let summary = displaySummary {
                        Text(summary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if !secondaryApps.isEmpty {
                        HStack(spacing: 5) {
                            ForEach(secondaryApps.prefix(5)) { app in
                                AppIconBadge(app: app, size: 18)
                            }
                            if secondaryApps.count > 5 {
                                Text("+\(secondaryApps.count - 5)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 3)
                    }

                    if let timeRange = SessionDisplay.timeRangeWithDurationLabel(for: session) {
                        Text(timeRange)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                }
            }
            .padding(14)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !session.apps.isEmpty else { return }
                withAnimation(.smooth(duration: 0.25)) {
                    isExpanded.toggle()
                    if !isExpanded { restoreMessage = nil }
                }
            }

            if isExpanded {
                Divider()
                    .padding(.horizontal, 14)

                VStack(alignment: .leading, spacing: 10) {
                    if let restoreMessage {
                        Text(restoreMessage)
                            .font(.caption2)
                            .foregroundStyle(restoreMessage.contains("Couldn't") ? .orange : .secondary)
                    }

                    if showAppList {
                        Text("Apps in this session")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.55))

                        VStack(spacing: 0) {
                            ForEach(listApps) { app in
                                AppDetailRow(
                                    app: app,
                                    session: session,
                                    showOpenAction: true
                                )
                                if app.id != listApps.last?.id {
                                    Divider().padding(.leading, 36)
                                }
                            }
                        }
                    } else {
                        HStack {
                            Spacer()
                            Button {
                                Task { await restoreSession() }
                            } label: {
                                if isRestoring {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 11, weight: .medium))
                                }
                            }
                            .foregroundStyle(.secondary)
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(14)
                .transition(.blurReplace)
            }

            if !appState.hasAccessibilityPermission {
                Label("Grant Accessibility for window details", systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }
        }
        .glassEffect(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
        .overlay(alignment: .topTrailing) {
            if isHovering {
                Button {
                    withAnimation(.smooth(duration: 0.2)) {
                        appState.setSession(session, hidden: true)
                    }
                } label: {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(VisualEffectBackground())
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(8)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.15)) { isHovering = hovering }
        }
    }

    private var isHidden: Bool {
        appState.isSessionHidden(session)
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
    var showOpenAction = true

    @Environment(AppState.self) private var appState
    @State private var isRestoring = false

    private var displayLines: [SessionAppDisplay.Line] {
        SessionAppDisplay.contextLines(for: app)
    }

    private var timeShare: String? {
        SessionDisplay.appTimeShare(for: app, in: session)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            AppIconBadge(app: app, size: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(app.appName)
                        .font(.callout.weight(.medium))
                    if let timeShare {
                        Text(timeShare)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if !displayLines.isEmpty {
                    ForEach(displayLines.prefix(3)) { line in
                        Text(line.text)
                            .font(.caption)
                            .foregroundStyle(line.isPath ? Color.blue.opacity(0.9) : Color.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    if displayLines.count > 3 {
                        Text("+\(displayLines.count - 3) more")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(minHeight: 24, alignment: .leading)

            Spacer()

            if showOpenAction {
                Button {
                    Task { await openWithState() }
                } label: {
                    if isRestoring {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .disabled(isRestoring)
                .help(SessionAppDisplay.hasRestorableContent(app)
                      ? "Reopen \(app.appName) with its tabs and documents"
                      : "Open \(app.appName)")
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func openWithState() async {
        if SessionAppDisplay.hasRestorableContent(app) {
            isRestoring = true
            _ = await appState.restoreApp(app)
            isRestoring = false
        } else {
            appState.openApp(bundleId: app.bundleId)
        }
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
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
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
