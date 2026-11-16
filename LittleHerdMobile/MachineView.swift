import Charts
import SwiftUI

/// One machine through one lens — where tapping a column lands.
///
/// The Mac's focused-machine page, turned upright: the figure, thermometer and
/// animal you tapped stand at the top as a rail does on the Mac, and under them
/// is the detail that lens is for — load, memory, volumes, or sessions. The
/// lens comes from the tabs, so pressing Memory here re-lenses this machine
/// instead of returning to the herd.
///
/// Looked up by id on every redraw, so the page follows the herd rather than
/// the reading it was opened with.
struct MachineLensView: View {
    let machineID: String
    let lens: HerdLens
    let client: HerdClient
    var onMove: (MoveIntent) -> Void = { _ in }

    var body: some View {
        Group {
            if let machine = client.snapshot?.machines.first(where: { $0.id == machineID }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        MachineLensHero(machine: machine, lens: lens)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                            .padding(.bottom, 20)
                        Divider().padding(.horizontal, 20)
                        MachineLensDetail(
                            machine: machine,
                            lens: lens,
                            snapshot: client.snapshot,
                            canWrite: client.canWrite,
                            onMove: onMove
                        )
                            .padding(.top, 8)
                            .padding(.bottom, 32)
                    }
                    .animation(.smooth(duration: 0.3), value: lens)
                }
                .refreshable { await client.refresh() }
                .navigationTitle(machine.name)
            } else {
                ContentUnavailableView(
                    "Not in the herd",
                    systemImage: "questionmark.circle",
                    description: Text("The watcher no longer reports this machine.")
                )
            }
        }
        .background(HerdTheme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The rail: the machine's figure and thermometer for this lens beside its
/// animal and how it is.
struct MachineLensHero: View {
    let machine: HerdWire.Machine
    let lens: HerdLens

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            if lens != .ai {
                VStack(spacing: 10) {
                    LensValue(machine: machine, lens: lens, font: .system(size: 34, weight: .bold))
                    SegmentedThermometer(
                        value: lens.value(for: machine),
                        blockWidth: 64,
                        blockHeight: 11,
                        spacing: 3
                    )
                }
                .frame(width: 110)
            }
            VStack(alignment: lens == .ai ? .center : .leading, spacing: 6) {
                MachineAvatar(machine: machine, size: lens == .ai ? 96 : 88)
                HStack(spacing: 6) {
                    StateDot(state: machine.state)
                    Text(stateWord)
                        .font(.subheadline.weight(.medium))
                }
                if let reason = machine.unavailability {
                    Text(reason)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let updated = machine.lastUpdated {
                    Text("Sampled \(updated, style: .relative) ago")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: lens == .ai ? .center : .leading)
        }
    }

    private var stateWord: String {
        switch machine.state {
        case "live": machine.isWatcher ? "Live · the watcher" : "Live"
        case "connecting": "Connecting"
        case "offline": "Offline"
        default: machine.state.capitalized
        }
    }
}

/// What each lens is for, on one machine.
struct MachineLensDetail: View {
    let machine: HerdWire.Machine
    let lens: HerdLens
    var snapshot: HerdWire.Snapshot?
    var canWrite = false
    var onMove: (MoveIntent) -> Void = { _ in }

    @State private var carrying: CarriedSession?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let alerts = (snapshot?.alerts ?? []).filter { $0.machine == machine.id }
            if !alerts.isEmpty {
                AlertsCallout(alerts: alerts, onOpen: { _ in })
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
            }
            switch lens {
            case .cpu: cpu
            case .memory: memory
            case .disk: disk
            case .ai: sessions
            }
        }
    }

    // MARK: CPU

    @ViewBuilder
    private var cpu: some View {
        DetailSection(title: "LOAD") {
            if machine.state == "live" {
                if let now = machine.cpuPercent {
                    DetailRow(label: "Now", value: percent(now))
                }
                if let sustained = machine.sustainedCPUPercent {
                    DetailRow(label: "Last few minutes", value: percent(sustained))
                }
                DetailRow(label: "Sessions working", value: "\(machine.activeSessionCount)")
            } else {
                unavailable
            }
        }
        if let history = machine.cpuHistory, history.count > 1 {
            HistoryChart(points: history, tint: HerdTheme.loadTeal)
        }
        if let processes = machine.processes, !processes.isEmpty {
            DetailSection(title: "WHAT’S RUNNING") {
                ForEach(processes) { process in
                    HStack(spacing: 10) {
                        Image(systemName: process.agent == nil ? "gearshape" : "sparkles")
                            .foregroundStyle(process.agent == nil ? Color.secondary : Color.orange)
                            .frame(width: 22)
                        Text(process.name).lineLimit(1)
                        Spacer()
                        Text(process.percent.map { "\(Int($0.rounded()))%" }
                            ?? String(format: "%.1fc", process.cores))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 5)
                }
            }
        }
    }

    // MARK: Memory

    @ViewBuilder
    private var memory: some View {
        DetailSection(title: "MEMORY") {
            if machine.state == "live" {
                if let pressure = machine.memoryPressure {
                    DetailRow(
                        label: "Pressure",
                        value: pressure.capitalized,
                        tint: pressure == "critical" ? .red : pressure == "warning" ? .orange : nil
                    )
                }
                if let used = machine.memoryUsedBytes, let total = machine.memoryTotalBytes {
                    DetailRow(label: "In use", value: "\(bytes(used)) of \(bytes(total))")
                }
                Text("Pressure is the reading that matters: a Mac can be calm at 70% and swapping at 60%.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
            } else {
                unavailable
            }
        }
        if let history = machine.memoryHistory, history.count > 1 {
            HistoryChart(points: history, tint: .purple)
        }
        if let consumers = machine.memoryConsumers, !consumers.isEmpty {
            DetailSection(title: "WHAT’S USING MEMORY") {
                ForEach(consumers) { consumer in
                    HStack(spacing: 10) {
                        Text(consumer.name).lineLimit(1)
                        if let growing = consumer.growingBytes, growing > 0 {
                            Label("+\(bytes(growing))", systemImage: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .labelStyle(.titleAndIcon)
                        }
                        Spacer()
                        Text(bytes(consumer.bytes))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 5)
                }
            }
        }
    }

    // MARK: Disk

    @ViewBuilder
    private var disk: some View {
        DetailSection(title: "VOLUMES") {
            if machine.volumes.isEmpty {
                if let used = machine.diskUsedPercent, machine.state == "live" {
                    DetailRow(label: "Startup disk", value: percent(used))
                } else {
                    unavailable
                }
            } else {
                ForEach(machine.volumes) { volume in
                    VolumeRow(volume: volume)
                    Divider().padding(.leading, 20)
                }
            }
        }
    }

    // MARK: AI

    @ViewBuilder
    private var sessions: some View {
        if machine.isStorage {
            DetailSection(title: "SESSIONS") {
                Text("Storage runs no sessions.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            }
        } else if machine.sessions.isEmpty {
            DetailSection(title: "SESSIONS") {
                Text("Nothing running here.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            }
        } else {
            VStack(alignment: .leading, spacing: 18) {
                sessionGroup("WAITING ON YOU", state: "waiting")
                sessionGroup("STALLED", state: "stalled")
                sessionGroup("WORKING", state: "active")
                sessionGroup("FINISHED", state: "completed")
            }
        }
    }

    @ViewBuilder
    private func sessionGroup(_ title: String, state: String) -> some View {
        let matching = machine.sessions
            .filter { $0.state == state }
            .sorted { $0.updatedAt < $1.updatedAt }
        if !matching.isEmpty {
            DetailSection(title: title) {
                ForEach(matching) { session in
                    VStack(alignment: .leading, spacing: 0) {
                        AISessionRow(session: session)
                            .movable(
                                session,
                                from: machine,
                                in: snapshot ?? HerdWire.Snapshot(watcher: "", generatedAt: .now, machines: [machine]),
                                canWrite: canWrite,
                                carrying: $carrying,
                                onMove: onMove
                            )
                        SessionFacts(session: session)
                            .padding(.leading, 64)
                            .padding(.trailing, 20)
                            .padding(.bottom, 6)
                        Divider().padding(.leading, 64)
                    }
                }
            }
        }
    }

    // MARK: Shared

    private var unavailable: some View {
        Text(machine.unavailability ?? "No reading from this machine right now.")
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
    }

    private func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    private func bytes(_ value: Double) -> String {
        Int64(value).formatted(.byteCount(style: .memory))
    }
}

/// A small-caps label over its rows — the Mac's `SectionLabel`.
struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .kerning(0.6)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 14)
            content
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    var tint: Color?

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(tint ?? .secondary)
                .fontWeight(tint == nil ? .regular : .semibold)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }
}

/// A volume with its own ten-block bar laid on its side.
struct VolumeRow: View {
    let volume: HerdWire.Volume

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(volume.name)
                    .lineLimit(1)
                Spacer()
                Text("\(Int(volume.usedPercent.rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 3) {
                let filled = ThermometerBand.filledBlocks(for: volume.usedPercent)
                ForEach(0 ..< ThermometerBand.blockCount, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(level < filled
                            ? ThermometerBand.forLevel(level).color
                            : HerdTheme.emptyBlock)
                        .frame(height: 8)
                }
            }
            HStack(spacing: 4) {
                Text("\(bytes(volume.totalBytes - volume.usedBytes)) free of \(bytes(volume.totalBytes))")
                if let health = volume.health, health != "normal" {
                    Text("· \(health)").foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private func bytes(_ value: Double) -> String {
        Int64(value).formatted(.byteCount(style: .file))
    }
}

/// The line under a session on a machine's page: context and model.
struct SessionFacts: View {
    let session: HerdWire.Session

    var body: some View {
        let facts = [
            session.contextTokens.map { "\($0.formatted()) tokens" },
            session.model,
        ].compactMap(\.self)
        if !facts.isEmpty {
            Text(facts.joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }
}

/// The last few minutes of a reading, as the Mac's detail pane draws it: an
/// area under a line, scaled to the whole 0–100 so a flat 12% looks flat.
struct HistoryChart: View {
    let points: [HerdWire.Point]
    let tint: Color

    var body: some View {
        Chart(points, id: \.t) { point in
            AreaMark(x: .value("Time", point.t), y: .value("Percent", point.v))
                .foregroundStyle(tint.opacity(0.18))
                .interpolationMethod(.monotone)
            LineMark(x: .value("Time", point.t), y: .value("Percent", point.v))
                .foregroundStyle(tint)
                .interpolationMethod(.monotone)
        }
        .chartYScale(domain: 0 ... 100)
        .chartYAxis {
            AxisMarks(values: [0, 50, 100]) { value in
                AxisGridLine()
                AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%") }
            }
        }
        .chartXAxis(.hidden)
        .frame(height: 110)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .accessibilityLabel("Recent history")
        .accessibilityValue(points.last.map { "\(Int($0.v.rounded())) percent now" } ?? "")
    }
}
