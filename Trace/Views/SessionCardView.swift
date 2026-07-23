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
        HStack {
            Spacer(minLength: 0)
            Button {
                withAnimation(DS.Animation.hideButton) {
                    appState.setSession(session, hidden: false)
                }
            } label: {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: DS.IconSize.glyphSm, weight: .bold))
                    Text("Hidden activity")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.xs)
                .background(VisualEffectBackground())
                .clipShape(Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: DS.Spacing.lg) {
                if let app = primaryApp {
                    AppIconBadge(app: app, size: DS.IconSize.primary)
                        .padding(.top, 1)
                }

                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    HStack(alignment: .center, spacing: DS.Spacing.xs) {
                        Text(sessionTitle)
                            .font(.body.weight(.bold))
                            .lineLimit(1)

                        if isHovering {
                            Button {
                                withAnimation(DS.Animation.hideButton) {
                                    appState.setSession(session, hidden: true)
                                }
                            } label: {
                                Text("Hide")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .transition(.opacity)
                        }

                        Spacer()
                        Text(SessionDisplay.relativeTimeLabel(for: session))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: DS.IconSize.chevron, weight: .bold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }

                    if appState.isSummarizingSession(session), session.summary == nil {
                        SummaryLoadingDots()
                    } else if let summary = displaySummary {
                        Text(summary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if !secondaryApps.isEmpty {
                        HStack(spacing: DS.Spacing.xs) {
                            ForEach(secondaryApps.prefix(DS.Card.maxSecondaryIcons)) { app in
                                AppIconBadge(app: app, size: DS.IconSize.secondary)
                            }
                            if secondaryApps.count > DS.Card.maxSecondaryIcons {
                                Text("+\(secondaryApps.count - DS.Card.maxSecondaryIcons)")
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
            .padding(DS.Spacing.xl)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !session.apps.isEmpty else { return }
                withAnimation(DS.Animation.cardExpand) {
                    isExpanded.toggle()
                    if !isExpanded { restoreMessage = nil }
                }
            }

            if isExpanded {
                Divider()
                    .padding(.horizontal, DS.Spacing.xl)

                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    if let restoreMessage {
                        Text(restoreMessage)
                            .font(.caption2)
                            .foregroundStyle(restoreMessage.contains("Couldn't") ? .orange : .secondary)
                    }

                    if showAppList {
                        Text("Apps in this session")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(DS.Opacity.sectionLabel))

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
                                        .font(.system(size: DS.IconSize.glyphMd, weight: .medium))
                                }
                            }
                            .foregroundStyle(.secondary)
                            .buttonStyle(.plain)
                            .disabled(isRestoring)
                        }
                    }
                }
                .padding(DS.Spacing.xl)
                .transition(.blurReplace)
            }
        }
        .glassEffect(in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .shadow(
            color: .black.opacity(DS.Opacity.shadowCard),
            radius: DS.Shadow.cardRadius,
            x: 0,
            y: DS.Shadow.cardY
        )
        .onHover { hovering in
            withAnimation(DS.Animation.hover) { isHovering = hovering }
        }
    }

    private var isHidden: Bool {
        appState.isSessionHidden(session)
    }

    private func restoreSession() async {
        isRestoring = true
        restoreMessage = nil
        let result = await appState.restoreSession(session)
        isRestoring = false
        restoreMessage = RestoreFeedback.message(for: result)
    }
}

// MARK: - Summary loading

private struct SummaryLoadingDots: View {
    var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 0.18)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.secondary.opacity(0.45))
                        .frame(width: 4, height: 4)
                        .opacity(opacity(for: index, time: time))
                }
            }
        }
        .accessibilityLabel("Generating summary")
    }

    private func opacity(for index: Int, time: TimeInterval) -> Double {
        let wave = sin(time * 2.8 + Double(index) * 0.9)
        return 0.25 + 0.65 * ((wave + 1) / 2)
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
        HStack(alignment: .center, spacing: DS.Spacing.md) {
            AppIconBadge(app: app, size: DS.IconSize.detail)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: DS.Spacing.xs) {
                    Text(app.appName)
                        .font(.callout.weight(.medium))
                    if let timeShare {
                        Text(timeShare)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if !displayLines.isEmpty {
                    ForEach(displayLines.prefix(DS.Card.maxContextLines)) { line in
                        Text(line.text)
                            .font(.caption)
                            .foregroundStyle(
                                line.isPath
                                    ? Color.blue.opacity(0.9)
                                    : Color.white.opacity(DS.Opacity.contextLine)
                            )
                            .lineLimit(1)
                    }
                    if displayLines.count > DS.Card.maxContextLines {
                        Text("+\(displayLines.count - DS.Card.maxContextLines) more")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(minHeight: DS.IconSize.detail, alignment: .leading)

            Spacer()

            if showOpenAction {
                Button {
                    Task { await openWithState() }
                } label: {
                    if isRestoring {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: DS.IconSize.glyphMd, weight: .medium))
                    }
                }
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .disabled(isRestoring)
                .help(
                    SessionAppDisplay.hasRestorableContent(app)
                        ? "Reopen \(app.appName) with its tabs and documents"
                        : "Open \(app.appName)"
                )
            }
        }
        .padding(.vertical, DS.Spacing.xs)
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

// MARK: - App icon badge

struct AppIconBadge: View {
    let app: SessionApp
    var size: CGFloat = 20
    @State private var icon: NSImage? = nil

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: size, height: size)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: size * DS.Radius.iconBadgeFactor,
                            style: .continuous
                        )
                    )
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: size * 0.7))
                    .foregroundStyle(.secondary)
                    .frame(width: size, height: size)
            }
        }
        .help(app.appName)
        .task(id: app.bundleId) {
            icon = await loadIcon(bundleId: app.bundleId)
        }
    }

    private func loadIcon(bundleId: String) async -> NSImage? {
        await Task.detached(priority: .utility) {
            guard let url = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleId
            ) else { return nil }
            return NSWorkspace.shared.icon(forFile: url.path)
        }.value
    }
}
