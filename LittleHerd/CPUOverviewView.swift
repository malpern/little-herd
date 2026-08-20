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
                        value: presentation.value,
                        memoryPressure: presentation.memoryPressure
                    )

                    SegmentedThermometer(
                        value: presentation.thermometerValue,
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

    /// A storage machine keeps its column when it is not answering: its numbers
    /// change slowly and the last known ones are still worth reading, whereas a
    /// Mac's are stale the moment it stops reporting.
    private var presentation: OverviewMetricPresentation {
        machine.metricPresentation(
            for: metric,
            isReporting: machine.state == .live || machine.isStorage
        )
    }

    private var fullestVolume: StorageVolume? { machine.fullestVolume }

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
        switch MetricValueDisplay.resolve(
            metric: metric,
            value: value,
            memoryPressure: memoryPressure
        ) {
        case .pressure(let level):
            MemoryPressureSymbol(level: level)
                .font(.title3.weight(.semibold))
        case .percent(let percent):
            CPUPercentage(value: percent)
                .font(.title3.weight(.semibold).monospacedDigit())
        // Neither reaches the overview: it has no network column, and a metric
        // with nothing behind it falls through to the same dash.
        case .bytesPerSecond, .unavailable:
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
                    .fill(machine.status.tint)
                    .frame(width: 6, height: 6)
                    .accessibilityLabel(machine.status.label)

                Text(machine.shortName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
        }
    }

    /// One definition of "storage is in trouble", shared with the machine's
    /// own page and the menu bar.
    private var worstStorageHealth: SynologyHealth? {
        machine.storageConcern?.health
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

/// The same thermometer, lying down.
///
/// A row is thirty-three points tall and three hundred wide, so the column form
/// cannot go in one — but a session's CPU is the same quantity as a machine's,
/// read off the same scale and coloured by the same bands, and it should not
/// arrive in the interface as an unrelated-looking percentage. Same blocks,
/// same colours, turned ninety degrees.
///
/// Fewer blocks than the column on purpose. Ten segments across forty points
/// is a dotted line rather than a reading; five carries the shape of the number
/// at a glance, which is all a row has room to say.
struct InlineSegmentedThermometer: View {
    let value: Double?
    var blockCount = 5
    var blockWidth: CGFloat = 5
    var blockHeight: CGFloat = 9
    var spacing: CGFloat = 1.5

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0 ..< blockCount, id: \.self) { position in
                RoundedRectangle(cornerRadius: 1.25, style: .continuous)
                    .fill(
                        position < filledBlockCount
                            ? ThermometerScale.band(
                                // Mapped back onto the ten-level scale the
                                // bands are defined against, so a session at
                                // 95% is the same red a machine at 95% is.
                                forLevel: Int(
                                    (Double(position) + 0.5)
                                        / Double(blockCount) * 10
                                )
                            ).color
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
        return min(
            max(Int(ceil(value / (100 / Double(blockCount)))), 0),
            blockCount
        )
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
                            ? ThermometerScale.band(forLevel: level).color
                            : LittleHerdTheme.emptyBlock
                    )
                    .frame(width: blockWidth, height: blockHeight)
            }
        }
        .animation(.smooth(duration: 0.45), value: value)
        .accessibilityHidden(true)
    }

    private var filledBlockCount: Int {
        ThermometerScale.filledBlockCount(for: value)
    }
}
