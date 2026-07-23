import SwiftUI

struct StatsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let stats = StatsBuilder.build(from: appState.sessions)
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            overviewCard(stats)
            dailyCard(stats)
            if !stats.topProjects.isEmpty {
                projectsCard(stats)
            }
            if stats.deepWorkCount > 0 || stats.averageFocusStars != nil {
                focusCard(stats)
            }
        }
    }

    // MARK: - Overview

    private func overviewCard(_ stats: TimelineStats) -> some View {
        StatCard {
            HStack(alignment: .top, spacing: 0) {
                StatTile(
                    label: "Today",
                    value: StatsBuilder.durationLabel(stats.todayActiveSeconds)
                )
                tileDivider
                StatTile(
                    label: "This week",
                    value: StatsBuilder.durationLabel(stats.weekActiveSeconds)
                )
                tileDivider
                StatTile(
                    label: "Sessions",
                    value: "\(stats.sessionCount)"
                )
            }
        }
    }

    // MARK: - Daily activity

    private func dailyCard(_ stats: TimelineStats) -> some View {
        let peak = max(stats.dailyActivity.map(\.activeSeconds).max() ?? 0, 1)
        return StatCard {
            CardTitle("Activity by day")
            VStack(spacing: DS.Spacing.xs) {
                ForEach(stats.dailyActivity) { day in
                    HStack(spacing: DS.Spacing.md) {
                        Text(day.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .leading)

                        StatBar(fraction: Double(day.activeSeconds) / Double(peak))

                        Text(day.activeSeconds == 0 ? "—" : StatsBuilder.durationLabel(day.activeSeconds))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(day.activeSeconds == 0 ? .secondary : .primary)
                            .frame(width: 56, alignment: .trailing)
                    }
                }
            }
        }
    }

    // MARK: - Top projects

    private func projectsCard(_ stats: TimelineStats) -> some View {
        let peak = max(stats.topProjects.map(\.activeSeconds).max() ?? 0, 1)
        return StatCard {
            CardTitle("Where time went")
            VStack(spacing: DS.Spacing.sm) {
                ForEach(stats.topProjects) { project in
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        HStack(spacing: DS.Spacing.xs) {
                            Text(project.name)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                            Spacer()
                            Text(StatsBuilder.durationLabel(project.activeSeconds))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        StatBar(fraction: Double(project.activeSeconds) / Double(peak))
                    }
                }
            }
        }
    }

    // MARK: - Focus

    private func focusCard(_ stats: TimelineStats) -> some View {
        StatCard {
            CardTitle("Focus")
            HStack(alignment: .top, spacing: 0) {
                StatTile(
                    label: "Deep-work blocks",
                    value: "\(stats.deepWorkCount)"
                )
                tileDivider
                StatTile(
                    label: "Longest",
                    value: StatsBuilder.durationLabel(stats.longestSessionSeconds)
                )
                tileDivider
                StatTile(
                    label: "Avg focus",
                    value: stats.averageFocusStars.map { String(format: "%.1f★", $0) } ?? "—"
                )
            }
        }
    }

    // MARK: - Building blocks

    private var tileDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1, height: 34)
    }
}

// MARK: - Reusable pieces

private struct StatCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            content
        }
        .padding(DS.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .traceCardGlass()
    }
}

private struct CardTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.white.opacity(DS.Opacity.sectionLabel))
    }
}

private struct StatTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: DS.Spacing.xxs) {
            Text(value)
                .font(.title2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct StatBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(Color.accentColor.opacity(0.85))
                    .frame(width: fillWidth(in: geo.size.width))
            }
        }
        .frame(height: 6)
    }

    private func fillWidth(in total: CGFloat) -> CGFloat {
        let clamped = max(0, min(fraction, 1))
        guard clamped > 0 else { return 0 }
        return max(total * clamped, 3)
    }
}
