import SwiftUI

/// The herd, laid out the way the Mac dashboard lays it out.
///
/// **The Mac's navigation, held in a hand.** Four lenses along the bottom —
/// CPU, Memory, Disk, AI — that stay under every screen; the herd as columns,
/// each a figure, a thermometer and an animal; and a tap on a column opens that
/// machine through the same lens. Changing lens on a machine's page re-lenses
/// the machine rather than returning to the herd, which is what the Mac does
/// and why the tabs sit outside the navigation stack.
///
/// The path holds machine ids, not machines: a page pushed with a copy of a
/// machine would freeze at the reading it was opened with while the herd
/// underneath kept moving.
struct HerdView: View {
    let client: HerdClient
    @AppStorage("herdLens") private var lens: HerdLens = .cpu
    @State private var choosingWatcher = false
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let snapshot = client.snapshot {
                    HerdOverview(
                        snapshot: snapshot,
                        lens: lens,
                        client: client,
                        onOpen: { path.append($0) }
                    )
                } else {
                    waiting
                }
            }
            .background(HerdTheme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        choosingWatcher = true
                    } label: {
                        Label("Watcher", systemImage: "desktopcomputer")
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { id in
                MachineLensView(machineID: id, lens: lens, client: client)
            }
        }
        .tint(HerdTheme.forest)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let snapshot = client.snapshot {
                HerdLensTabs(
                    selection: lens,
                    alarms: alarms(in: snapshot),
                    onSelect: { chosen in
                        withAnimation(.smooth(duration: 0.3)) { lens = chosen }
                    }
                )
            }
        }
        .sheet(isPresented: $choosingWatcher) {
            WatcherPicker(client: client)
        }
        .task { await client.keepFresh() }
        .onAppear(perform: applyHarness)
        // A screen nobody has looked at is a screen with a defect in it, and
        // the simulator cannot be tapped from a script. These open a lens and
        // the first machine on arrival so each page can be captured; they are
        // set by nothing but a test harness.
        .onChange(of: client.snapshot?.machines.first?.id) { _, first in
            guard path.isEmpty, let first,
                  ProcessInfo.processInfo.environment["LITTLE_HERD_OPEN_FIRST_MACHINE"] == "1"
            else { return }
            path = [first]
        }
    }

    private func applyHarness() {
        if let raw = ProcessInfo.processInfo.environment["LITTLE_HERD_LENS"],
           let chosen = HerdLens(rawValue: raw) {
            lens = chosen
        }
    }

    private func alarms(in snapshot: HerdWire.Snapshot) -> [HerdLens: ThermometerBand] {
        var result: [HerdLens: ThermometerBand] = [:]
        for lens in HerdLens.allCases {
            result[lens] = lens.alarm(in: snapshot)
        }
        return result
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One lens on the whole herd: the header, then columns — or, for AI, the
/// sessions grouped by machine.
struct HerdOverview: View {
    let snapshot: HerdWire.Snapshot
    let lens: HerdLens
    let client: HerdClient
    let onOpen: (String) -> Void

    /// After this long without a successful read, what is on screen is a
    /// memory rather than a report, and it has to look like one. Three of the
    /// Mac's sampling intervals: one missed read is a blip, three is news.
    static let staleAfter: TimeInterval = 30

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            let stale = client.lastFetched.map {
                context.date.timeIntervalSince($0) > Self.staleAfter
            } ?? false
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    OverviewHeader(snapshot: snapshot, lens: lens)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 14)

                    Divider().padding(.horizontal, 20)

                    if stale {
                        StaleBanner(since: client.lastFetched, error: client.lastError)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                    }

                    Group {
                        if lens == .ai {
                            AIOverview(snapshot: snapshot, onOpen: onOpen)
                        } else {
                            HerdColumnsView(snapshot: snapshot, lens: lens, onOpen: onOpen)
                        }
                    }
                    .saturation(stale ? 0.2 : 1)
                    // Identity changes between the columns and the list and
                    // nowhere else: CPU, Memory and Disk are the same columns
                    // showing different numbers, so the bars slide rather than
                    // the page being rebuilt on every tab press.
                    .id(lens == .ai)
                    .transition(.opacity)

                    footer(showsError: !stale)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 24)
                }
            }
            .refreshable { await client.refresh() }
        }
    }

    private func footer(showsError: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let fetched = client.lastFetched {
                Text("From \(snapshot.watcher) · read \(fetched, style: .relative) ago")
            } else {
                Text("From \(snapshot.watcher)")
            }
            if showsError, let error = client.lastError {
                Text(error).foregroundStyle(.orange)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

/// The metric's mark, its name, and how much of the herd is answering — the
/// Mac's header, word for word.
struct OverviewHeader: View {
    let snapshot: HerdWire.Snapshot
    let lens: HerdLens

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: lens.symbol)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(HerdTheme.forest)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(lens.title)
                    .font(.title2.weight(.bold))
                HStack(spacing: 6) {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 7, height: 7)
                    Text(subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private var live: Int { snapshot.machines.filter { $0.state == "live" }.count }
    private var sessions: [HerdWire.Session] { snapshot.machines.flatMap(\.sessions) }

    private var subtitle: String {
        if lens == .ai {
            let active = sessions.filter { $0.state == "active" }.count
            let waiting = sessions.filter(\.needsYou).count
            return waiting > 0
                ? "\(active) active · \(waiting) waiting on you"
                : "\(active) active · \(sessions.count) tracked"
        }
        return "\(live) of \(snapshot.machines.count) live"
    }

    private var dotColor: Color {
        if lens == .ai {
            return sessions.contains(where: \.needsYou) ? .orange : .green
        }
        return live == snapshot.machines.count ? .green : .orange
    }
}

/// The herd as columns: figure, thermometer, animal, name.
struct HerdColumnsView: View {
    let snapshot: HerdWire.Snapshot
    let lens: HerdLens
    let onOpen: (String) -> Void

    var body: some View {
        let count = min(max(snapshot.machines.count, 1), 4)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: count)
        LazyVGrid(columns: columns, spacing: 28) {
            ForEach(snapshot.machines) { machine in
                Button {
                    onOpen(machine.id)
                } label: {
                    HerdColumn(machine: machine, lens: lens, blockWidth: blockWidth(count))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 28)
    }

    private func blockWidth(_ count: Int) -> CGFloat {
        switch count {
        case 1, 2: 72
        case 3: 60
        default: 52
        }
    }
}

struct HerdColumn: View {
    let machine: HerdWire.Machine
    let lens: HerdLens
    var blockWidth: CGFloat = 52

    var body: some View {
        VStack(spacing: 10) {
            // Fixed height, so a column showing a word lines up with its
            // neighbours showing figures.
            LensValue(machine: machine, lens: lens, font: .system(size: 26, weight: .bold))
                .frame(height: 34)
            SegmentedThermometer(value: lens.value(for: machine), blockWidth: blockWidth)
            VStack(spacing: 4) {
                MachineAvatar(machine: machine, size: 60)
                HStack(spacing: 5) {
                    StateDot(state: machine.state)
                    Text(machine.shortName)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(machine.name), \(accessibilityValue)")
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityValue: String {
        if lens == .memory, let word = HerdLens.pressureWord(for: machine) {
            return "memory pressure \(word)"
        }
        guard let value = lens.value(for: machine) else { return "no reading" }
        return "\(lens.title) \(Int(value.rounded())) percent"
    }
}

/// The figure above a thermometer. A dash when there is no reading, and for
/// memory under pressure, the verdict instead of the percentage.
struct LensValue: View {
    let machine: HerdWire.Machine
    let lens: HerdLens
    var font: Font

    var body: some View {
        Group {
            if lens == .memory, machine.state == "live",
               let word = HerdLens.pressureWord(for: machine) {
                // A word is wider than a figure, so it steps down a size to
                // stay inside its column rather than shoving the neighbours.
                Text(word)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(machine.memoryPressure == "critical" ? .red : .orange)
            } else if let value = lens.value(for: machine) {
                Text("\(Int(value.rounded()))%")
                    .contentTransition(.numericText(value: value))
            } else {
                Text("—").foregroundStyle(.tertiary)
            }
        }
        .font(font)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

struct MachineAvatar: View {
    let machine: HerdWire.Machine
    let size: CGFloat

    var body: some View {
        Image(machine.avatar)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .saturation(machine.state == "live" ? 1 : 0.15)
            .opacity(machine.state == "live" ? 1 : 0.55)
            .accessibilityHidden(true)
    }
}

/// The AI lens: every session the herd is carrying, grouped by machine, the
/// machines with someone waiting first and, inside each, the one you have kept
/// waiting longest first.
struct AIOverview: View {
    let snapshot: HerdWire.Snapshot
    let onOpen: (String) -> Void

    var body: some View {
        let groups = Self.groups(in: snapshot)
        VStack(alignment: .leading, spacing: 22) {
            if groups.isEmpty {
                Text("Nothing running across the herd.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            }
            ForEach(groups, id: \.machine.id) { group in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        MachineAvatar(machine: group.machine, size: 22)
                        Text(group.machine.shortName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)

                    ForEach(group.sessions) { session in
                        Button {
                            onOpen(group.machine.id)
                        } label: {
                            AISessionRow(session: session)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 64)
                    }
                    if group.finished > 0 {
                        Text("^[\(group.finished) finished](inflect: true)")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 64)
                            .padding(.top, 2)
                    }
                }
            }
        }
        .padding(.top, 18)
    }

    struct SessionGroup {
        let machine: HerdWire.Machine
        let sessions: [HerdWire.Session]
        let finished: Int
    }

    static func groups(in snapshot: HerdWire.Snapshot) -> [SessionGroup] {
        let groups = snapshot.machines
            .filter { !$0.isStorage }
            .compactMap { machine -> SessionGroup? in
                let open = machine.sessions
                    .filter { $0.state != "completed" }
                    .sorted(by: order)
                guard !open.isEmpty else { return nil }
                return SessionGroup(
                    machine: machine,
                    sessions: open,
                    finished: machine.sessions.count - open.count
                )
            }
        // Stable: machines keep the herd's order within each half.
        return groups.filter { $0.sessions.contains(where: \.needsYou) }
            + groups.filter { !$0.sessions.contains(where: \.needsYou) }
    }

    /// Waiting, then stalled, then working; oldest first within each, since
    /// the session kept waiting longest is the one to answer.
    static func order(_ a: HerdWire.Session, _ b: HerdWire.Session) -> Bool {
        let rank = ["waiting": 0, "stalled": 1, "active": 2]
        let ra = rank[a.state] ?? 3
        let rb = rank[b.state] ?? 3
        return ra != rb ? ra < rb : a.updatedAt < b.updatedAt
    }
}

/// One session, the way the Mac's AI panel draws it: the provider's mark with
/// a state dot on its corner, the title, what it is doing, and how long ago.
struct AISessionRow: View {
    let session: HerdWire.Session

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ProviderMark(provider: session.provider)
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(stateColor)
                        .frame(width: 11, height: 11)
                        .overlay(Circle().stroke(HerdTheme.background, lineWidth: 2))
                        .offset(x: 3, y: 3)
                }
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(session.title)
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Text(session.updatedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                }
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(session.state == "stalled" ? .orange : .secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private var detail: String {
        switch session.state {
        case "waiting": "Waiting on you"
        case "stalled": "Stalled — no word for a while"
        default: session.activity ?? "Working"
        }
    }

    private var stateColor: Color {
        switch session.state {
        case "active": .green
        case "waiting": .orange
        case "stalled": .red
        default: .gray
        }
    }
}

/// Claude's orange or Codex's black, as a rounded square: the Mac draws the
/// provider's own icon here, which a phone reading JSON does not have.
struct ProviderMark: View {
    let provider: String

    var body: some View {
        let isClaude = provider == "claude"
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isClaude ? Color(red: 0.80, green: 0.47, blue: 0.36) : Color.primary)
            .frame(width: 32, height: 32)
            .overlay {
                Image(systemName: isClaude ? "asterisk" : "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isClaude ? Color.white : Color(uiColor: .systemBackground))
            }
            .accessibilityLabel(isClaude ? "Claude" : "Codex")
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
    }
}

struct StateDot: View {
    let state: String

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
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
