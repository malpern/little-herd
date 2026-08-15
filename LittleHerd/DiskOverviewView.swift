import SwiftUI

struct DiskOverviewView: View {
    let machines: [MachineMonitorModel]

    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            ForEach(machines) { machine in
                DiskMachineColumn(
                    machine: machine,
                    columnWidth: columnWidth,
                    avatarSize: avatarSize
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 6)
    }

    private var machineCount: CGFloat { CGFloat(max(machines.count, 1)) }
    private var columnSpacing: CGFloat { 2 }
    private var horizontalPadding: CGFloat { machines.count <= 3 ? 16 : 8 }
    private var columnWidth: CGFloat {
        let available = 300 - horizontalPadding * 2
            - columnSpacing * CGFloat(max(machines.count - 1, 0))
        return min(80, max(40, available / machineCount))
    }
    private var avatarSize: CGFloat {
        machines.count <= 3 ? 30 : (machines.count == 4 ? 24 : 21)
    }
}

private struct DiskMachineColumn: View {
    let machine: MachineMonitorModel
    let columnWidth: CGFloat
    let avatarSize: CGFloat

    var body: some View {
        VStack(spacing: 2) {
            DiskThermometerGroup(
                state: machine.state,
                volumes: machine.storageVolumes,
                columnWidth: columnWidth
            )

            MachineStatusLabel(
                machine: machine,
                avatarSize: avatarSize
            )
        }
        .frame(width: columnWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityHint(storageHelp)
    }

    private var storageHelp: Text {
        switch machine.state {
        case .connecting:
            Text("Checking storage…")
        case .live:
            if machine.storageVolumes.isEmpty {
                Text("No mounted local disks")
            } else {
                Text(
                    machine.storageVolumes
                        .map {
                            let available = Int64($0.availableBytes).formatted(
                                .byteCount(style: .file)
                            )
                            return "\($0.name): \(available) free"
                        }
                        .joined(separator: "\n")
                )
            }
        case .offline:
            if machine.isStorage {
                Text("Connect this network share in Finder")
            } else {
                Text("Machine unreachable")
            }
        case .stopped:
            Text("Monitoring paused")
        }
    }
}

private struct DiskThermometerGroup: View {
    let state: MonitorConnectionState
    let volumes: [StorageVolume]
    let columnWidth: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            if state == .live, !volumes.isEmpty {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 1) {
                        ForEach(volumes) { volume in
                            DiskVolumeThermometer(
                                volume: volume,
                                thermometerWidth: thermometerWidth,
                                labelWidth: labelWidth
                            )
                        }
                    }
                    .frame(minWidth: columnWidth)
                }
                .scrollIndicators(.hidden)

                Text("free")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Spacer()
                if state == .live {
                    Text("No disks")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("—")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var thermometerWidth: CGFloat {
        switch volumes.count {
        case 0 ... 1: 30
        case 2: 28
        case 3: 22
        default: 17
        }
    }

    private var labelWidth: CGFloat {
        switch volumes.count {
        case 0 ... 1: min(72, columnWidth)
        case 2: 38
        case 3: 24
        default: 18
        }
    }
}

private struct DiskVolumeThermometer: View {
    let volume: StorageVolume
    let thermometerWidth: CGFloat
    let labelWidth: CGFloat

    var body: some View {
        VStack(spacing: 2) {
            Text(volume.name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityHidden(true)

            Text(
                volume.usedPercent / 100,
                format: .percent.precision(.fractionLength(0))
            )
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(
                volume.usedPercent > 99 ? Color.red : Color.primary
            )
            .lineLimit(1)
            .minimumScaleFactor(0.65)

            SegmentedThermometer(
                value: volume.usedPercent,
                blockWidth: thermometerWidth,
                blockHeight: 5.5,
                spacing: 1.75
            )

            DiskFreeCapacityLabel(bytes: volume.availableBytes)
        }
        .frame(width: labelWidth)
        .help(
            Text(
                "\(volume.name): \(Int64(volume.availableBytes), format: .byteCount(style: .file)) free"
            )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(volume.name))
        .accessibilityValue(
            Text(
                "\(volume.usedPercent / 100, format: .percent.precision(.fractionLength(0))) used, \(Int64(volume.availableBytes), format: .byteCount(style: .file)) free"
            )
        )
        .accessibilityHint(Text(volume.mountPath))
    }
}

private struct DiskFreeCapacityLabel: View {
    let bytes: Double

    var body: some View {
        VStack(spacing: -2) {
            Text(value, format: numberFormat)
                .font(.caption2.weight(.medium).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)
    }

    private var value: Double {
        bytes / unitScale
    }

    private var unitScale: Double {
        switch bytes {
        case 1_000_000_000_000...: 1_000_000_000_000
        case 1_000_000_000...: 1_000_000_000
        case 1_000_000...: 1_000_000
        default: 1_000
        }
    }

    private var unit: LocalizedStringResource {
        switch bytes {
        case 1_000_000_000_000...: "TB"
        case 1_000_000_000...: "GB"
        case 1_000_000...: "MB"
        default: "KB"
        }
    }

    private var numberFormat: FloatingPointFormatStyle<Double> {
        if value < 10 {
            return .number.precision(.fractionLength(1))
        }

        return .number.precision(.fractionLength(0))
    }
}
