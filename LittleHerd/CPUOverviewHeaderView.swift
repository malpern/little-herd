import AppKit
import SwiftUI

/// The bar across the top of the overview: which metric the herd is being read
/// through, and how much of the AI allowance is left.
///
/// It lives apart from `DashboardView` because it is the one piece of the
/// dashboard that reaches into AppKit — the metric picker is a SwiftUI face
/// with an invisible `NSPopUpButton` laid over it, so the menu is the system's
/// while the label is ours — and that machinery has nothing to say about the
/// page hosting it.

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
    let onSelect: (OverviewMetric) -> Void

    var body: some View {
        CPUOverviewHeader(
            liveMachineCount: machines.count(where: { $0.state == .live }),
            machineCount: machines.count,
            activeAgentCount: agentSessions.count { $0.session.state == .active },
            agentCount: agentSessions.count,
            aiUsageLimits: aiUsageLimits,
            metric: metric,
            onSelect: onSelect
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
    let onSelect: (OverviewMetric) -> Void

    var body: some View {
        HStack(spacing: 8) {
            OverviewMetricMenu(
                selection: metric,
                liveMachineCount: liveMachineCount,
                machineCount: machineCount,
                activeAgentCount: activeAgentCount,
                agentCount: agentCount,
                onSelect: onSelect
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 8)

            AIUsageLimitsSummary(model: aiUsageLimits)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }
}

struct OverviewMetricMenu: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let selection: OverviewMetric
    let liveMachineCount: Int
    let machineCount: Int
    let activeAgentCount: Int
    let agentCount: Int
    let onSelect: (OverviewMetric) -> Void

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
                    HStack(spacing: 4) {
                        Text(selection.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }

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
            .allowsHitTesting(false)

            OverviewMetricPopUpButton(selection: selection, onSelect: onSelect)
                .frame(width: 142, height: 44)
        }
        .frame(width: 142, alignment: .leading)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.18),
            value: selection
        )
        .help("Choose metric")
    }
}

struct OverviewMetricPopUpButton: NSViewRepresentable {
    let selection: OverviewMetric
    let onSelect: (OverviewMetric) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: selection, onSelect: onSelect)
    }

    func makeNSView(context: Context) -> InvisibleMenuButton {
        let button = InvisibleMenuButton(frame: .zero)
        button.target = context.coordinator
        button.action = #selector(Coordinator.showMenu(_:))
        button.setAccessibilityRole(.menuButton)
        button.setAccessibilityLabel("Metric")
        return button
    }

    func updateNSView(_ button: InvisibleMenuButton, context: Context) {
        context.coordinator.selection = selection
        context.coordinator.onSelect = onSelect
        button.setAccessibilityValue(String(localized: selection.title))
        button.toolTip = "Choose metric"
    }

    final class Coordinator: NSObject {
        var selection: OverviewMetric
        var onSelect: (OverviewMetric) -> Void

        init(selection: OverviewMetric, onSelect: @escaping (OverviewMetric) -> Void) {
            self.selection = selection
            self.onSelect = onSelect
        }

        @objc func showMenu(_ sender: NSButton) {
            let menu = NSMenu()
            menu.autoenablesItems = false

            for metric in OverviewMetric.allCases {
                let title = String(localized: metric.title)
                let item = NSMenuItem(
                    title: title,
                    action: #selector(didSelectMetric(_:)),
                    keyEquivalent: ""
                )
                let image = NSImage(
                    systemSymbolName: metric.symbolName,
                    accessibilityDescription: title
                )
                image?.size = NSSize(width: 15, height: 15)
                image?.isTemplate = true
                if let image {
                    let attachment = NSTextAttachment()
                    attachment.image = image
                    attachment.bounds = NSRect(x: 0, y: -2, width: 15, height: 15)
                    let attributedTitle = NSMutableAttributedString(attachment: attachment)
                    attributedTitle.append(NSAttributedString(string: "  \(title)"))
                    item.attributedTitle = attributedTitle
                }
                item.state = metric == selection ? .on : .off
                item.representedObject = metric.rawValue
                item.target = self
                menu.addItem(item)
            }

            let selectedItem = menu.items.first { $0.state == .on }
            menu.popUp(
                positioning: selectedItem,
                at: NSPoint(x: 0, y: sender.bounds.midY),
                in: sender
            )
        }

        @objc func didSelectMetric(_ item: NSMenuItem) {
            guard
                let rawValue = item.representedObject as? String,
                let metric = OverviewMetric(rawValue: rawValue)
            else { return }
            onSelect(metric)
        }
    }

    final class InvisibleMenuButton: NSButton {
        override var intrinsicContentSize: NSSize {
            NSSize(width: 142, height: 44)
        }

        override func draw(_ dirtyRect: NSRect) {}
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
