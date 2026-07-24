import SwiftUI

struct SessionCardView: View {
    let session: Session
    @Environment(AppState.self) private var appState
    @State private var isHovering = false

    private var isExpanded: Bool {
        appState.expandedSessionId == session.id
    }

    private var detailApps: [SessionApp] {
        session.apps.filter { SessionAppDisplay.shouldShowInDetail($0, in: session) }
    }

    private var collapsedApps: [SessionApp] {
        if !detailApps.isEmpty { return detailApps }
        return SessionAppDisplay.rankedApps(session.apps)
    }

    private var primaryApp: SessionApp? {
        SessionDisplay.featuredApp(for: session) ?? collapsedApps.first ?? session.apps.first
    }

    private var secondaryApps: [SessionApp] {
        guard let primary = primaryApp else {
            return collapsedApps.count > 1 ? Array(collapsedApps.dropFirst()) : []
        }
        let others = collapsedApps.filter { $0.bundleId != primary.bundleId }
        return others
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

    private var expandedApps: [SessionApp] {
        SessionDisplay.expandedApps(for: session)
    }

    private var hasRichDetail: Bool {
        SessionDisplay.hasRichDetail(session.apps)
    }

    private var showAppList: Bool {
        !expandedApps.isEmpty
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
                .foregroundStyle(DS.Text.cardMuted)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.xs)
                .traceControlGlass(cornerRadius: DS.Radius.pill)
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
                    VStack(spacing: DS.Spacing.xxs) {
                        AppIconBadge(app: app, size: DS.IconSize.primary)
                            .padding(.top, 1)

                        if isHovering {
                            Button {
                                withAnimation(DS.Animation.hideButton) {
                                    appState.setSession(session, hidden: true)
                                }
                            } label: {
                                Text("Hide")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(DS.Text.cardMuted)
                            }
                            .buttonStyle(.plain)
                            .transition(.opacity)
                        }
                    }
                    .frame(width: DS.IconSize.primary)
                }

                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    HStack(alignment: .center, spacing: DS.Spacing.xs) {
                        Text(sessionTitle)
                            .font(.body.weight(.bold))
                            .lineLimit(1)

                        Spacer()
                        Text(SessionDisplay.relativeTimeLabel(for: session))
                            .font(.callout)
                            .foregroundStyle(DS.Text.cardMuted)
                        Image(systemName: "chevron.right")
                            .font(.system(size: DS.IconSize.chevron, weight: .bold))
                            .foregroundStyle(DS.Text.cardMuted)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }

                    if appState.isSummarizingSession(session), session.summary == nil {
                        SummaryLoadingDots()
                    } else if let summary = displaySummary {
                        SummarySubtitleRow(session: session, summary: summary)
                    }

                    if !secondaryApps.isEmpty {
                        HStack(spacing: DS.Spacing.xs) {
                            ForEach(secondaryApps.prefix(DS.Card.maxSecondaryIcons)) { app in
                                AppIconBadge(app: app, size: DS.IconSize.secondary)
                            }
                            if secondaryApps.count > DS.Card.maxSecondaryIcons {
                                Text("+\(secondaryApps.count - DS.Card.maxSecondaryIcons)")
                                    .font(.caption)
                                    .foregroundStyle(DS.Text.cardMuted)
                            }
                        }
                        .padding(.top, 3)
                    }

                    if !isExpanded {
                        Text(SessionDisplay.compactDurationLabel(for: session))
                            .font(.caption)
                            .foregroundStyle(DS.Text.cardMuted)
                            .padding(.top, 2)
                    }
                }
            }
            .padding(DS.Spacing.xl)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !session.apps.isEmpty else { return }
                withAnimation(DS.Animation.cardExpand) {
                    appState.expandedSessionId = isExpanded ? nil : session.id
                }
            }

            if isExpanded {
                Divider()
                    .padding(.horizontal, DS.Spacing.xl)

                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    SessionMetaSection(session: session)

                    if showAppList {
                        if SessionMetaSection.hasContent(for: session) {
                            Divider()
                        }

                        if expandedApps.count > 1 {
                            Text("Apps in this session")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(DS.Text.cardSection)
                        }

                        VStack(spacing: 0) {
                            ForEach(expandedApps) { app in
                                AppDetailRow(
                                    app: app,
                                    session: session,
                                    showOpenAction: true
                                )
                                if app.id != expandedApps.last?.id {
                                    Divider().padding(.leading, 36)
                                }
                            }
                        }
                    }
                }
                .padding(DS.Spacing.xl)
                .transition(.blurReplace)
            }
        }
        .traceCardGlass()
        .onHover { hovering in
            withAnimation(DS.Animation.hover) { isHovering = hovering }
        }
    }

    private var isHidden: Bool {
        appState.isSessionHidden(session)
    }
}

// MARK: - Session meta

private struct SessionMetaSection: View {
    let session: Session

    static func hasContent(for session: Session) -> Bool {
        SessionDisplay.timeRangeWithDurationLabel(for: session) != nil
            || SessionDisplay.contextContinuity(for: session) != nil
    }

    var body: some View {
        let timeRange = SessionDisplay.timeRangeWithDurationLabel(for: session)
        let continuity = SessionDisplay.contextContinuity(for: session)

        if timeRange != nil || continuity != nil {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                if let timeRange {
                    SessionMetaRow(label: "Duration", value: timeRange)
                }
                if let continuity {
                    SessionMetaRow(
                        label: "Focus",
                        value: continuity.starLabel,
                        detail: continuity.explanation
                    )
                    .help("How consistently this session stayed on one task")
                    .accessibilityLabel(
                        "Focus score: \(continuity.stars) out of five stars. \(continuity.explanation)"
                    )
                }
            }
        }
    }
}

private struct SessionMetaRow: View {
    let label: String
    let value: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.md) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DS.Text.cardSection)
                .frame(width: 58, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)

                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(DS.Text.cardMuted)
                }
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Summary subtitle

private struct SummarySubtitleRow: View {
    let session: Session
    let summary: String

    @Environment(AppState.self) private var appState
    @State private var isHovering = false

    private var canRegenerate: Bool {
        session.summary != nil
    }

    private var isRegenerating: Bool {
        appState.isSummarizingSession(session)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xxs) {
            Text(summary)
                .font(.callout)
                .foregroundStyle(DS.Text.cardMuted)
                .lineLimit(2)

            if canRegenerate {
                if isRegenerating {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 14, height: 14)
                } else if isHovering {
                    Button {
                        Task { await appState.regenerateSummary(for: session) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DS.Text.cardMuted)
                    }
                    .buttonStyle(.plain)
                    .help("Regenerate summary")
                    .transition(.opacity)
                }
            }
        }
        .onHover { hovering in
            withAnimation(DS.Animation.hover) { isHovering = hovering }
        }
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
                        .fill(DS.Text.cardMuted.opacity(0.55))
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
                    Text(SessionAppDisplay.displayName(for: app))
                        .font(.callout.weight(.medium))
                    if let timeShare {
                        Text(timeShare)
                            .font(.caption2)
                            .foregroundStyle(DS.Text.cardMuted)
                    }
                }

                if !displayLines.isEmpty {
                    ForEach(displayLines.prefix(DS.Card.maxContextLines)) { line in
                        Text(line.text)
                            .font(.caption)
                            .foregroundStyle(
                                line.isPath
                                    ? Color.blue.opacity(0.9)
                                    : DS.Text.cardContext
                            )
                            .lineLimit(1)
                    }
                    if displayLines.count > DS.Card.maxContextLines {
                        Text("+\(displayLines.count - DS.Card.maxContextLines) more")
                            .font(.caption2)
                            .foregroundStyle(DS.Text.cardMuted)
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
                .foregroundStyle(DS.Text.cardMuted)
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
                    .foregroundStyle(DS.Text.cardMuted)
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
