import SwiftUI

struct HoveredMachineMetricHeader: View {
    let machine: MachineMonitorModel
    let metric: OverviewMetric

    var body: some View {
        switch metric {
        case .cpu:
            HoveredMachineActivityHeader(machine: machine)
        case .memory:
            HoveredMachineMemoryHeader(machine: machine)
        case .disk:
            HoveredMachineDiskHeader(machine: machine)
        case .ai:
            EmptyView()
        }
    }
}

private struct HoveredMachineMemoryHeader: View {
    let machine: MachineMonitorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                HoveredMachineIdentity(
                    machine: machine
                )

                Spacer(minLength: 8)

                Text("MEMORY PRESSURE")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.35)
                    .foregroundStyle(.secondary)

                MemoryPressureSymbol(
                    level: machine.state == .live ? machine.memoryPressure : nil,
                    explanation: machine.memoryPressureExplanation
                )
                .font(.caption.weight(.semibold))

                // The verdict said out loud. A coloured glyph on its own is a
                // shape with no name, and this is the slot where the CPU
                // header puts a number you can read.
                if machine.state == .live, let level = machine.memoryPressure {
                    Text(level.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(level.tint)
                        .contentTransition(.identity)
                        .accessibilityHidden(true)
                }
            }

            HoveredMemoryDetails(
                state: machine.state,
                consumers: machine.memoryConsumers
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

private struct HoveredMemoryDetails: View {
    let state: MonitorConnectionState
    let consumers: [MemoryConsumer]

    var body: some View {
        if state == .live, !consumers.isEmpty {
            HStack(spacing: 8) {
                ForEach(consumers.prefix(3)) { consumer in
                    HoveredMemoryConsumer(consumer: consumer)
                }
            }
        } else {
            HoveredMetricStateLabel(
                state: state,
                liveLabel: "No large user applications detected"
            )
        }
    }
}

private struct HoveredMemoryConsumer: View {
    let consumer: MemoryConsumer

    var body: some View {
        HStack(spacing: 5) {
            // The real icon, the way the machine's own memory page shows it.
            // Nothing resolves for a remote machine — a Linux process carries
            // no bundle — so those keep the generic glyph rather than a gap.
            ApplicationIcon(
                bundlePath: consumer.bundlePath,
                fallbackSymbol: "square.stack.3d.up",
                tint: MetricKind.memory.color,
                size: 15
            )

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(consumer.name)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    if let evidence = consumer.growthEvidence {
                        SuspectedMemoryLeakIndicator(evidence: evidence)
                    }
                }

                Text(
                    Int64(consumer.residentBytes),
                    format: .byteCount(
                        style: .memory,
                        allowedUnits: .all,
                        spellsOutZero: false
                    )
                )
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("Approximate resident memory. Quitting this app can reduce pressure.")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(consumer.name), \(Int64(consumer.residentBytes).formatted(.byteCount(style: .memory)))"
        )
    }
}

private struct SuspectedMemoryLeakIndicator: View {
    let evidence: MemoryGrowthEvidence

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 6, height: 6)
            .help(evidenceDescription)
            .accessibilityLabel(evidenceDescription)
    }

    private var evidenceDescription: Text {
        let minutes = max(1, Int((evidence.duration / 60).rounded()))
        return Text(
            "Possible memory leak: grew by \(Int64(evidence.growthBytes), format: .byteCount(style: .memory)) over \(minutes) minutes. Memory rose in \(evidence.risingIntervalCount) of \(evidence.observedIntervalCount) observed intervals across \(evidence.sampleCount) samples. This sustained-growth signal is evidence, not proof."
        )
    }
}

private struct HoveredMachineDiskHeader: View {
    let machine: MachineMonitorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                HoveredMachineIdentity(
                    machine: machine
                )

                Spacer(minLength: 8)

                Text("STORAGE")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.35)
                    .foregroundStyle(.secondary)

                if machine.state == .live {
                    if machine.storageVolumes.count == 1 {
                        Text("1 disk")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(machine.storageVolumes.count) disks")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HoveredDiskDetails(
                state: machine.state,
                volumes: machine.storageVolumes
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

private struct HoveredDiskDetails: View {
    let state: MonitorConnectionState
    let volumes: [StorageVolume]

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        if state == .live, !volumes.isEmpty {
            if volumes.count == 1, let volume = volumes.first {
                HoveredPrimaryDiskDetail(volume: volume)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 1) {
                    ForEach(volumes.prefix(volumes.count > 4 ? 3 : 4)) { volume in
                        HoveredDiskVolumeDetail(volume: volume)
                    }

                    if volumes.count > 4 {
                        HoveredAdditionalDisks(count: volumes.count - 3)
                    }
                }
            }
        } else {
            HoveredMetricStateLabel(
                state: state,
                liveLabel: "No mounted local disks"
            )
        }
    }
}

private struct HoveredPrimaryDiskDetail: View {
    let volume: StorageVolume

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(volume.name)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(
                    "\(volume.usedPercent / 100, format: .percent.precision(.fractionLength(0))) used"
                )
                .font(.caption2.weight(.semibold).monospacedDigit())
            }

            HStack(spacing: 7) {
                DiskUsageProgress(usedPercent: volume.usedPercent)

                DiskCapacitySummary(
                    availableBytes: volume.availableBytes,
                    totalBytes: volume.totalBytes
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text(volume.mountPath))
    }
}

private struct DiskUsageProgress: View {
    let usedPercent: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.12))

                Capsule()
                    .fill(fillColor)
                    .frame(
                        width: max(
                            3,
                            proxy.size.width * min(max(usedPercent / 100, 0), 1)
                        )
                    )
            }
        }
        .frame(width: 52)
        .frame(height: 4)
        .accessibilityHidden(true)
    }

    private var fillColor: Color {
        switch usedPercent {
        case 95...: .red
        case 85...: .orange
        case 70...: .yellow
        default: .green
        }
    }
}

private struct DiskCapacitySummary: View {
    let availableBytes: Double
    let totalBytes: Double

    var body: some View {
        Group {
            switch totalBytes {
            case 1_000_000_000_000...:
                Text(
                    "\(availableBytes / 1_000_000_000_000, format: format) TB free of \(totalBytes / 1_000_000_000_000, format: format) TB"
                )
            case 1_000_000_000...:
                Text(
                    "\(availableBytes / 1_000_000_000, format: format) GB free of \(totalBytes / 1_000_000_000, format: format) GB"
                )
            case 1_000_000...:
                Text(
                    "\(availableBytes / 1_000_000, format: format) MB free of \(totalBytes / 1_000_000, format: format) MB"
                )
            default:
                Text(
                    "\(availableBytes / 1_000, format: format) KB free of \(totalBytes / 1_000, format: format) KB"
                )
            }
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }

    private var format: FloatingPointFormatStyle<Double> {
        let scaledTotal: Double
        switch totalBytes {
        case 1_000_000_000_000...: scaledTotal = totalBytes / 1_000_000_000_000
        case 1_000_000_000...: scaledTotal = totalBytes / 1_000_000_000
        case 1_000_000...: scaledTotal = totalBytes / 1_000_000
        default: scaledTotal = totalBytes / 1_000
        }
        return .number.precision(.fractionLength(scaledTotal < 10 ? 1 : 0))
    }
}

private struct HoveredDiskVolumeDetail: View {
    let volume: StorageVolume

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 3) {
                Text(volume.name)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 2)

                Text(
                    volume.usedPercent / 100,
                    format: .percent.precision(.fractionLength(0))
                )
                .monospacedDigit()
            }
            .font(.caption2.weight(.semibold))

            Text(
                "\(Int64(volume.availableBytes), format: .byteCount(style: .file)) free"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct HoveredAdditionalDisks: View {
    let count: Int

    var body: some View {
        Text("\(count) more disks")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HoveredMachineIdentity: View {
    let machine: MachineMonitorModel

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(machine.status.tint)
                .frame(width: 5, height: 5)
                .accessibilityLabel(machine.status.label)

            MachineAvatarView(avatar: machine.avatar, size: 18)

            Text(machine.shortName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
    }
}

private struct HoveredMetricStateLabel: View {
    let state: MonitorConnectionState
    let liveLabel: LocalizedStringResource

    var body: some View {
        Text(stateLabel)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stateLabel: LocalizedStringResource {
        switch state {
        case .connecting: "Checking…"
        case .live: liveLabel
        case .offline: "Unreachable"
        case .stopped: "Monitoring paused"
        }
    }
}
