import SwiftUI

/// The herd, at a glance.
///
/// One row per machine: the animal, the name, whether it is answering, and
/// the three figures the Mac's menu bar shows — CPU, memory, disk — with the
/// count of sessions working and waiting. The order is the watcher's order,
/// which is the order the dashboard draws, so the phone and the Mac agree on
/// where the Linux box is.
struct HerdView: View {
    let client: HerdClient
    @State private var choosingWatcher = false
    @State private var path: [HerdWire.Machine] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let snapshot = client.snapshot {
                    herd(snapshot)
                } else {
                    waiting
                }
            }
            .navigationTitle("Little Herd")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        choosingWatcher = true
                    } label: {
                        Label("Watcher", systemImage: "desktopcomputer")
                    }
                }
            }
            .sheet(isPresented: $choosingWatcher) {
                WatcherPicker(client: client)
            }
        }
        .task { await client.keepFresh() }
        // The simulator cannot be tapped from a script, and a screen nobody
        // has looked at is a screen with a defect in it — the Mac app learned
        // that the hard way. This opens the first machine on arrival so the
        // detail page can be captured and judged; it is set by nothing but a
        // test harness.
        .onChange(of: client.snapshot?.machines.first) { _, first in
            guard path.isEmpty, let first,
                  ProcessInfo.processInfo.environment["LITTLE_HERD_OPEN_FIRST_MACHINE"] == "1"
            else { return }
            path = [first]
        }
    }

    private func herd(_ snapshot: HerdWire.Snapshot) -> some View {
        List {
            Section {
                ForEach(snapshot.machines) { machine in
                    NavigationLink(value: machine) {
                        MachineRow(machine: machine)
                    }
                }
            } footer: {
                footer(snapshot)
            }
        }
        .listStyle(.plain)
        .navigationDestination(for: HerdWire.Machine.self) { machine in
            MachineView(machine: machine)
        }
        .refreshable { await client.refresh() }
    }

    private func footer(_ snapshot: HerdWire.Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("From \(snapshot.watcher)")
            if let fetched = client.lastFetched {
                TimelineView(.periodic(from: fetched, by: 10)) { context in
                    Text("Read \(fetched, style: .relative) ago")
                        .foregroundStyle(context.date.timeIntervalSince(fetched) > 30
                            ? .orange : .secondary)
                }
            }
            if let error = client.lastError {
                Text(error).foregroundStyle(.orange)
            }
        }
        .font(.footnote)
        .padding(.top, 8)
    }

    /// Nothing to draw yet. Says which of the three reasons applies, because
    /// "no watcher", "watcher not answering" and "still looking" want three
    /// different things from a person.
    private var waiting: some View {
        VStack(spacing: 16) {
            Image("chick-laptop")
                .resizable()
                .scaledToFit()
                .frame(width: 120)
                .opacity(0.9)

            if let error = client.lastError {
                Text(error)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            } else if let watcher = client.current {
                ProgressView()
                Text("Asking “\(watcher.displayName)”…")
                    .foregroundStyle(.secondary)
            } else {
                Text("Looking for the Mac that watches your herd…")
                    .foregroundStyle(.secondary)
                Text("It announces itself on this network when "
                    + "“This Mac watches the herd continuously” is on in "
                    + "Little Herd’s settings. Off this network, type its "
                    + "Tailscale name.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.tertiary)
            }

            Button("Choose a watcher") { choosingWatcher = true }
                .buttonStyle(.bordered)
        }
        .padding(32)
    }
}

/// One machine, in a line.
struct MachineRow: View {
    let machine: HerdWire.Machine

    var body: some View {
        HStack(spacing: 14) {
            Image(machine.avatar)
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .saturation(machine.state == "live" ? 1 : 0.15)
                .opacity(machine.state == "live" ? 1 : 0.55)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(machine.name)
                        .font(.headline)
                    Spacer()
                    StateDot(state: machine.state)
                }
                statusLine
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if machine.state == "live" {
                    gauges
                }
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var statusLine: some View {
        if let reason = machine.unavailability {
            Text(reason)
        } else if machine.isStorage {
            Text(machine.volumes.isEmpty
                ? "Storage"
                : "^[\(machine.volumes.count) volume](inflect: true)")
        } else {
            Text(sessionsSummary)
        }
    }

    private var sessionsSummary: String {
        let working = machine.activeSessionCount
        let waiting = machine.waitingSessionCount
        switch (working, waiting) {
        case (0, 0): return "Nothing running"
        case (_, 0): return "\(working) working"
        case (0, _): return "\(waiting) waiting on you"
        default: return "\(working) working · \(waiting) waiting on you"
        }
    }

    private var gauges: some View {
        HStack(spacing: 10) {
            if let cpu = machine.cpuPercent {
                MiniGauge(label: "CPU", percent: cpu, warn: 85)
            }
            if let used = machine.memoryUsedBytes, let total = machine.memoryTotalBytes, total > 0 {
                MiniGauge(
                    label: "Mem",
                    percent: used / total * 100,
                    warn: 90,
                    forced: machine.memoryPressure == "critical"
                )
            }
            if let disk = machine.diskUsedPercent {
                MiniGauge(label: "Disk", percent: disk, warn: 90)
            }
        }
    }
}

/// A word and a bar. Red only when the figure would worry the Mac too.
struct MiniGauge: View {
    let label: String
    let percent: Double
    let warn: Double
    var forced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Text(label)
                Text("\(Int(percent.rounded()))%")
                    .monospacedDigit()
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            ProgressView(value: min(max(percent, 0), 100), total: 100)
                .tint(forced || percent >= warn ? .red : .accentColor)
        }
        .frame(maxWidth: .infinity)
    }
}

struct StateDot: View {
    let state: String

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .accessibilityLabel(state)
    }

    private var color: Color {
        switch state {
        case "live": .green
        case "connecting": .yellow
        case "offline": .red
        default: .gray
        }
    }
}
