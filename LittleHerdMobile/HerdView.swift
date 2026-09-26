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

    /// After this long without a successful read, what is on screen is a
    /// memory rather than a report, and it has to look like one. Three of the
    /// Mac's sampling intervals: one missed read is a blip, three is news.
    private static let staleAfter: TimeInterval = 30

    private func herd(_ snapshot: HerdWire.Snapshot) -> some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            let stale = client.lastFetched.map {
                context.date.timeIntervalSince($0) > Self.staleAfter
            } ?? false
            List {
                if stale {
                    Section {
                        StaleBanner(since: client.lastFetched, error: client.lastError)
                    }
                    .listRowBackground(Color.orange.opacity(0.12))
                }

                let needsYou = Self.needingYou(in: snapshot)
                if !needsYou.isEmpty {
                    Section("Waiting on you") {
                        ForEach(needsYou, id: \.session.id) { item in
                            NavigationLink(value: item.machine) {
                                NeedsYouRow(machine: item.machine, session: item.session)
                                    .saturation(stale ? 0.2 : 1)
                            }
                        }
                    }
                }

                Section {
                    ForEach(snapshot.machines) { machine in
                        NavigationLink(value: machine) {
                            MachineRow(machine: machine)
                                .saturation(stale ? 0.2 : 1)
                        }
                    }
                } header: {
                    if !needsYou.isEmpty { Text("The herd") }
                } footer: {
                    // The banner has already said why; saying it twice on one
                    // screen is how a person learns to read neither.
                    footer(snapshot, showsError: !stale)
                }
            }
            .listStyle(.plain)
            .navigationDestination(for: HerdWire.Machine.self) { machine in
                MachineView(machine: machine)
            }
            .refreshable { await client.refresh() }
        }
    }

    /// Every session across the herd that is holding for a person, oldest
    /// first — the one you have kept waiting longest is the one to answer.
    /// Stalled sessions ride along: they also need a person, for a different
    /// reason, and a phone is where "did that die?" gets asked.
    ///
    /// This is the herd-level question the phone exists for. Per-machine
    /// counts say *where* work is waiting; this says *what*, without opening
    /// four pages to find out.
    static func needingYou(
        in snapshot: HerdWire.Snapshot
    ) -> [(machine: HerdWire.Machine, session: HerdWire.Session)] {
        snapshot.machines
            .flatMap { machine in
                machine.sessions
                    .filter { $0.state == "waiting" || $0.state == "stalled" }
                    .map { (machine: machine, session: $0) }
            }
            .sorted { $0.session.updatedAt < $1.session.updatedAt }
    }

    private func footer(_ snapshot: HerdWire.Snapshot, showsError: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("From \(snapshot.watcher)")
            if let fetched = client.lastFetched {
                TimelineView(.periodic(from: fetched, by: 10)) { context in
                    Text("Read \(fetched, style: .relative) ago")
                        .foregroundStyle(context.date.timeIntervalSince(fetched) > 30
                            ? .orange : .secondary)
                }
            }
            if showsError, let error = client.lastError {
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

/// One session that needs a person, and where it is.
struct NeedsYouRow: View {
    let machine: HerdWire.Machine
    let session: HerdWire.Session

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(machine.avatar)
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.title)
                    .font(.body)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    Text(session.state == "stalled" ? "Stalled" : "Waiting")
                        .foregroundStyle(session.state == "stalled" ? .orange : .secondary)
                    Text("· \(machine.shortName) · \(session.updatedAt, style: .relative)")
                        .foregroundStyle(.secondary)
                }
                .font(.footnote)
            }
        }
        .padding(.vertical, 2)
    }
}

/// What is on screen is old, and here is why. Shown above the herd rather
/// than instead of it: the last good reading is still worth more than a
/// blank page, as long as it is plainly marked as the last good reading.
struct StaleBanner: View {
    let since: Date?
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                if let since {
                    Text("Not updating — last read \(since, style: .relative) ago")
                        .font(.subheadline.weight(.medium))
                } else {
                    Text("Not updating")
                        .font(.subheadline.weight(.medium))
                }
            }
            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
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
