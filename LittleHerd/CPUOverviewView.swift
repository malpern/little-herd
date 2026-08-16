import SwiftUI

struct CPUOverviewView: View {
    let machines: [MachineMonitorModel]
    let metric: OverviewMetric
    var namespace: Namespace.ID?
    var onSelectMetric: ((MachineID) -> Void)?
    var onSelectMachine: ((MachineID) -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: columnSpacing) {
            ForEach(machines) { machine in
                CPUThermometerColumn(
                    machine: machine,
                    metric: metric,
                    columnWidth: columnWidth,
                    avatarSize: avatarSize,
                    namespace: namespace,
                    onSelectMetric: onSelectMetric,
                    onSelectMachine: onSelectMachine
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
    var onSelectMetric: ((MachineID) -> Void)?
    var onSelectMachine: ((MachineID) -> Void)?

    var body: some View {
        // A real Button, not a tap gesture: the window is movable by its
        // background, which swallows plain mouse-down in ordinary views, and a
        // control is what this should be anyway — it gets focus and hit
        // behaviour for free.
        VStack(spacing: 3) {
            // The bar opens this machine's view of the current metric…
            Button {
                onSelectMetric?(machine.machine)
            } label: {
                VStack(spacing: 4) {
                    OverviewMetricValue(
                        metric: metric,
                        value: liveMetricValue,
                        memoryPressure: liveMemoryPressure
                    )

                    SegmentedThermometer(
                        value: liveThermometerValue,
                        blockHeight: 6,
                        spacing: 2.25
                    )
                    .padding(.vertical, 1)
                    .matchedThermometer(namespace, machine: machine.machine)

                    if metric == .disk, let volume = fullestVolume {
                        VStack(spacing: 0) {
                            Text(
                                Int64(volume.availableBytes),
                                format: .byteCount(style: .file)
                            )
                            .font(.caption2.weight(.medium))
                            Text("free")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(machine.name) \(String(localized: metric.title))"))
            .accessibilityHint(columnHelp)

            // …the icon opens everything about the machine.
            Button {
                onSelectMachine?(machine.machine)
            } label: {
                MachineStatusLabel(
                    machine: machine,
                    avatarSize: avatarSize,
                    namespace: namespace
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(machine.name) details"))
        }
        .frame(width: columnWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.vertical, 4)
    }

    private var liveMetricValue: Double? {
        guard machine.state == .live || machine.isStorage else { return nil }

        switch metric {
        case .cpu: return machine.cpu.value
        case .memory: return machine.memory.value
        case .disk: return fullestVolume?.usedPercent
        case .ai: return nil
        }
    }

    /// The volume that will run out first — what "how full is this machine"
    /// means when a machine has several.
    private var fullestVolume: StorageVolume? {
        machine.storageVolumes.max { $0.usedPercent < $1.usedPercent }
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
        case .disk:
            fullestVolume?.usedPercent
        case .ai:
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

struct OverviewMetricValue: View {
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
        case .disk:
            CPUPercentage(value: value)
                .font(.title3.weight(.semibold).monospacedDigit())
        case .ai:
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
                // A drive in trouble is worth seeing under every metric, not
                // only Disk: the machine is reachable and its volumes may look
                // fine while the hardware underneath is failing.
                .overlay(alignment: .topTrailing) {
                    if let health = worstStorageHealth {
                        Image(systemName: health.symbolName)
                            .font(.system(size: avatarSize * 0.34))
                            .foregroundStyle(.white, health.tint)
                            .background(
                                Circle()
                                    .fill(.background)
                                    .frame(
                                        width: avatarSize * 0.34,
                                        height: avatarSize * 0.34
                                    )
                            )
                            .offset(x: avatarSize * 0.08, y: -avatarSize * 0.04)
                            .accessibilityLabel(
                                Text("\(machine.name): drive \(health.label)")
                            )
                    }
                }

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

    /// Only trouble earns a badge. Healthy or unreported storage shows nothing,
    /// so the badge means something when it does appear. Volumes count as well
    /// as drives: a pool can be degraded while every drive still reads normal.
    private var worstStorageHealth: SynologyHealth? {
        let reported = machine.drives.map(\.health)
            + machine.storageVolumes.compactMap(\.health)
        let worst = reported.max { $0.severity < $1.severity }
        guard let worst, worst == .warning || worst == .critical else {
            return nil
        }
        return worst
    }

    private var statusColor: Color {
        // A machine that has never connected is waiting to be set up, not
        // broken. Red is for something that was working and stopped.
        if machine.hasNeverConnected { return .secondary }
        switch machine.state {
        case .connecting: return .orange
        case .live: return .green
        case .offline: return .red
        case .stopped: return .secondary
        }
    }

    private var statusDescription: LocalizedStringResource {
        if machine.hasNeverConnected { return "Not set up yet" }
        switch machine.state {
        case .connecting: return "Connecting"
        case .live: return "Live"
        case .offline: return "Unreachable"
        case .stopped: return "Paused"
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
