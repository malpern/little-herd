import SwiftUI

/// Everything the watcher knows about one machine.
///
/// Sessions first, because they are the reason to open this at all — and
/// grouped by what they need from you, which is the ordering the Mac's own
/// panel settled on: a waiting session wants a message, a stalled one wants a
/// look, a working one wants to be left alone.
struct MachineView: View {
    let machine: HerdWire.Machine

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    Image(machine.avatar)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 88, height: 88)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            StateDot(state: machine.state)
                            Text(machine.state.capitalized)
                        }
                        .font(.subheadline)
                        if let updated = machine.lastUpdated {
                            Text("Sampled \(updated, style: .relative) ago")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if let reason = machine.unavailability {
                            Text(reason)
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .listRowSeparator(.hidden)
            }

            if !machine.isStorage {
                sessions("Waiting on you", state: "waiting")
                sessions("Working", state: "active")
                sessions("Stalled", state: "stalled")
            }

            if machine.state == "live" {
                Section("Load") {
                    if let cpu = machine.cpuPercent {
                        LabeledContent("CPU now", value: "\(Int(cpu.rounded()))%")
                    }
                    if let sustained = machine.sustainedCPUPercent {
                        LabeledContent("CPU, last 5 min", value: "\(Int(sustained.rounded()))%")
                    }
                    if let used = machine.memoryUsedBytes, let total = machine.memoryTotalBytes {
                        LabeledContent(
                            "Memory",
                            value: "\(bytes(used)) of \(bytes(total))"
                        )
                    }
                    if let pressure = machine.memoryPressure {
                        LabeledContent("Memory pressure", value: pressure.capitalized)
                    }
                }
            }

            if !machine.volumes.isEmpty {
                Section("Storage") {
                    ForEach(machine.volumes) { volume in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(volume.name)
                                Spacer()
                                Text("\(Int(volume.usedPercent.rounded()))%")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            ProgressView(value: volume.usedPercent, total: 100)
                                .tint(volume.usedPercent >= 90 ? .red : .accentColor)
                            HStack {
                                Text("\(bytes(volume.totalBytes - volume.usedBytes)) free of \(bytes(volume.totalBytes))")
                                if let health = volume.health, health != "normal" {
                                    Text("· \(health)")
                                        .foregroundStyle(.orange)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            if !machine.isStorage, machine.sessions.contains(where: { $0.state == "completed" }) {
                sessions("Finished", state: "completed")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(machine.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func sessions(_ title: String, state: String) -> some View {
        let matching = machine.sessions.filter { $0.state == state }
        if !matching.isEmpty {
            Section(title) {
                ForEach(matching) { session in
                    SessionRow(session: session)
                }
            }
        }
    }

    private func bytes(_ value: Double) -> String {
        Int64(value).formatted(.byteCount(style: .memory))
    }
}

struct SessionRow: View {
    let session: HerdWire.Session

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.title)
                    .font(.body)
                    .lineLimit(2)
                Spacer()
                Text(session.provider == "claude" ? "Claude" : "Codex")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let activity = session.activity, session.state == "active" {
                Text(activity)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 6) {
                Text(session.updatedAt, style: .relative)
                if let tokens = session.contextTokens {
                    Text("· \(tokens.formatted()) tokens")
                }
                if let model = session.model {
                    Text("· \(model)")
                        .lineLimit(1)
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
