import SwiftUI

struct CPUOverviewView: View {
    let machines: [MachineMonitorModel]
    let metric: OverviewMetric
    var namespace: Namespace.ID?
    var onSelect: ((MachineID) -> Void)?
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: columnSpacing) {
            ForEach(machines) { machine in
                CPUThermometerColumn(
                    machine: machine,
                    metric: metric,
                    columnWidth: columnWidth,
                    avatarSize: avatarSize,
                    namespace: namespace,
                    onSelect: onSelect
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 10)
    }

    private var machineCount: CGFloat { CGFloat(max(machines.count, 1)) }
    private var columnSpacing: CGFloat { machines.count <= 3 ? 10 : 4 }
    private var horizontalPadding: CGFloat { machines.count <= 3 ? 16 : 8 }
    private var columnWidth: CGFloat {
        let available = 300 - horizontalPadding * 2
            - columnSpacing * CGFloat(max(machines.count - 1, 0))
        return min(68, max(40, available / machineCount))
    }
    private var avatarSize: CGFloat {
        switch machines.count {
        case ...3: 38
        case 4: 30
        default: 24
        }
    }
}

private struct CPUThermometerColumn: View {
    let machine: MachineMonitorModel
    let metric: OverviewMetric
    let columnWidth: CGFloat
    let avatarSize: CGFloat
    var namespace: Namespace.ID?
    var onSelect: ((MachineID) -> Void)?
    @State private var isHovered = false

    var body: some View {
        // A real Button, not a tap gesture: the window is movable by its
        // background, which swallows plain mouse-down in ordinary views, and a
        // control is what this should be anyway — it gets focus and hit
        // behaviour for free.
        Button {
            onSelect?(machine.machine)
        } label: {
            column
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(machine.name) details"))
        .accessibilityHint(columnHelp)
    }

    private var column: some View {
        VStack(spacing: 4) {
            OverviewMetricValue(
                metric: metric,
                value: liveMetricValue,
                memoryPressure: liveMemoryPressure
            )

            VStack(spacing: 3) {
                SegmentedThermometer(
                    value: liveThermometerValue,
                    blockHeight: 6,
                    spacing: 2.25
                )
                .padding(.vertical, 1)

                MachineStatusLabel(
                    machine: machine,
                    avatarSize: avatarSize,
                    namespace: namespace
                )
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(width: columnWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(isHovered ? 0.06 : 0))
        )
        .contentShape(Rectangle())
    }

    private var liveMetricValue: Double? {
        guard machine.state == .live else { return nil }

        switch metric {
        case .cpu: return machine.cpu.value
        case .memory: return machine.memory.value
        case .disk, .ai: return nil
        }
    }

    private var liveMemoryPressure: MemoryPressureLevel? {
        guard metric == .memory, machine.state == .live else { return nil }
        return machine.memoryPressure
    }

    private var liveThermometerValue: Double? {
        switch metric {
        case .cpu:
            liveMetricValue
        case .memory:
            liveMemoryPressure?.visualizationPercent
        case .disk, .ai:
            nil
        }
    }

    private var columnHelp: Text {
        switch metric {
        case .cpu:
            activityHelp
        case .memory:
            memoryHelp
        case .disk:
            Text("Storage details")
        case .ai:
            Text("AI agent details")
        }
    }

    private var memoryHelp: Text {
        switch machine.state {
        case .connecting:
            return Text("Checking memory pressure…")
        case .live:
            if let pressure = machine.memoryPressure {
                let pressureTitle = String(localized: pressure.title)
                if machine.memoryConsumers.isEmpty {
                    return Text("\(pressureTitle) memory pressure")
                } else {
                    let consumers = machine.memoryConsumers
                        .map { "\($0.name): \(Int64($0.residentBytes).formatted(.byteCount(style: .memory)))" }
                        .joined(separator: "\n")
                    return Text("\(pressureTitle) memory pressure\n\(consumers)")
                }
            } else {
                return Text("Measuring memory pressure…")
            }
        case .offline:
            return Text("Machine unreachable")
        case .stopped:
            return Text("Monitoring paused")
        }
    }

    private var activityHelp: Text {
        switch machine.state {
        case .connecting:
            Text("Checking activity…")
        case .live:
            if machine.activities.isEmpty {
                Text("No active processes in the latest sample")
            } else {
                Text(
                    machine.activities
                        .map { String(localized: $0.tooltip) }
                        .joined(separator: "\n")
                )
            }
        case .offline:
            Text("Machine unreachable")
        case .stopped:
            Text("Monitoring paused")
        }
    }
}

private struct OverviewMetricValue: View {
    let metric: OverviewMetric
    let value: Double?
    let memoryPressure: MemoryPressureLevel?

    var body: some View {
        switch metric {
        case .cpu:
            CPUPercentage(value: value)
                .font(.title3.weight(.semibold).monospacedDigit())
        case .memory:
            MemoryPressureSymbol(level: memoryPressure)
                .font(.title3.weight(.semibold))
        case .disk, .ai:
            Text("—")
                .foregroundStyle(.tertiary)
        }
    }
}

struct MachineStatusLabel: View {
    let machine: MachineMonitorModel
    var avatarSize: CGFloat = 32
    var namespace: Namespace.ID?

    var body: some View {
        VStack(spacing: 1) {
            MachineAvatarView(avatar: machine.avatar, size: avatarSize)
                .matchedAvatar(namespace, machine: machine.machine)

            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                    .accessibilityLabel(statusDescription)

                Text(machine.shortName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
        }
    }

    private var statusColor: Color {
        switch machine.state {
        case .connecting: .orange
        case .live: .green
        case .offline: .red
        case .stopped: .secondary
        }
    }

    private var statusDescription: LocalizedStringResource {
        switch machine.state {
        case .connecting: "Connecting"
        case .live: "Live"
        case .offline: "Unreachable"
        case .stopped: "Paused"
        }
    }
}

private struct CPUPercentage: View {
    let value: Double?

    var body: some View {
        if let value {
            Text(value / 100, format: .percent.precision(.fractionLength(0)))
                .contentTransition(.numericText(value: value))
                .foregroundStyle(value > 99 ? Color.red : Color.primary)
        } else {
            Text("—")
                .foregroundStyle(.tertiary)
        }
    }
}

struct SegmentedThermometer: View {
    let value: Double?
    var blockWidth: CGFloat = 30
    var blockHeight: CGFloat = 6
    var spacing: CGFloat = 3

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(0 ..< 10, id: \.self) { position in
                let level = 9 - position
                RoundedRectangle(cornerRadius: 1.75, style: .continuous)
                    .fill(
                        level < filledBlockCount
                            ? blockColor(for: level)
                            : LittleHerdTheme.emptyBlock
                    )
                    .frame(width: blockWidth, height: blockHeight)
            }
        }
        .animation(.smooth(duration: 0.45), value: value)
        .accessibilityHidden(true)
    }

    private var filledBlockCount: Int {
        guard let value else { return 0 }
        return min(max(Int(ceil(value / 10)), 0), 10)
    }

    private func blockColor(for level: Int) -> Color {
        switch level {
        case 0 ... 3: LittleHerdTheme.loadGreen
        case 4 ... 6: .yellow
        case 7 ... 8: .orange
        default: .red
        }
    }
}
