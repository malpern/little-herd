import SwiftUI

/// The bar across the top of the overview: which metric the herd is being read
/// through, and how much of the AI allowance is left.
///
/// It lives apart from `DashboardView` because the page hosting it has nothing
/// to say about how a header is put together. It used to be the one piece of
/// the dashboard that reached into AppKit, for a menu that no longer exists.

/// The header, which now says the same thing whatever the pointer is over.
///
/// It used to swap for whichever row or column was hovered, showing that one
/// machine's activity or that one session's plan. The detail view is where
/// that belongs: a header that rewrites itself under the pointer cannot be
/// read deliberately, cannot be pointed at, and is invisible to anyone
/// navigating by keyboard.
struct CPUOverviewHeaderArea: View {
    let machines: [MachineMonitorModel]
    let agentSessions: [MachineAgentSession]
    let aiUsageLimits: AIUsageLimitsModel
    let metric: OverviewMetric

    var body: some View {
        CPUOverviewHeader(
            liveMachineCount: machines.count(where: { $0.state == .live }),
            machineCount: machines.count,
            activeAgentCount: agentSessions.count { $0.session.state == .active },
            agentCount: agentSessions.count,
            aiUsageLimits: aiUsageLimits,
            metric: metric
        )
        .frame(maxWidth: .infinity)
        .frame(height: 68)
    }
}

struct CPUOverviewHeader: View {
    let liveMachineCount: Int
    let machineCount: Int
    let activeAgentCount: Int
    let agentCount: Int
    let aiUsageLimits: AIUsageLimitsModel
    let metric: OverviewMetric

    var body: some View {
        HStack(spacing: 8) {
            OverviewMetricMenu(
                selection: metric,
                liveMachineCount: liveMachineCount,
                machineCount: machineCount,
                activeAgentCount: activeAgentCount,
                agentCount: agentCount
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 8)

            if DashboardChrome.showsUsageMarksInHeader {
                AIUsageLimitsSummary(model: aiUsageLimits)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }
}

/// The header's title: which metric the herd is being read through, and one
/// line about it.
///
/// It used to be a control — a SwiftUI face with an invisible `NSPopUpButton`
/// over it — and choosing the metric is the tab row's job now, so what is left
/// is a label. The AppKit machinery went with the menu rather than being left
/// wired to nothing.
struct OverviewMetricMenu: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let selection: OverviewMetric
    let liveMachineCount: Int
    let machineCount: Int
    let activeAgentCount: Int
    let agentCount: Int

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 8) {
                ZStack {
                    Image(systemName: selection.symbolName)
                        .font(.system(size: 20, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(LittleHerdTheme.forest)
                        .id(selection)
                        .transition(.opacity)
                }
                .frame(width: 24, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(selection.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    OverviewMetricStatusLine(
                        metric: selection,
                        liveMachineCount: liveMachineCount,
                        machineCount: machineCount,
                        activeAgentCount: activeAgentCount,
                        agentCount: agentCount
                    )
                }
                .id(selection)
                .transition(.opacity)
            }
        }
        .frame(width: 142, alignment: .leading)
        .frame(minHeight: 44)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.18),
            value: selection
        )
    }
}

struct OverviewMetricStatusLine: View {
    let metric: OverviewMetric
    let liveMachineCount: Int
    let machineCount: Int
    let activeAgentCount: Int
    let agentCount: Int

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 5, height: 5)
                .accessibilityHidden(true)

            if metric == .ai {
                Text("\(activeAgentCount) active · \(agentCount) tracked")
            } else {
                Text("\(liveMachineCount) of \(machineCount) live")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private var statusColor: Color {
        if metric == .ai {
            return activeAgentCount > 0 ? .green : .blue
        }
        return liveMachineCount == machineCount ? .green : .orange
    }
}
