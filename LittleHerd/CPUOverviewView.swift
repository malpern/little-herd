import SwiftUI

struct CPUOverviewView: View {
    let machines: [MachineMonitorModel]
    let metric: OverviewMetric
    var namespace: Namespace.ID?
    var onSelectMetric: ((MachineID) -> Void)?
    var onSelectMachine: ((MachineID) -> Void)?
    var onSelectAgents: ((MachineID) -> Void)?
    var agentCPU: [String: Double] = [:]
    /// Every account, so a drag can ask what each machine could actually take.
    var herd: [DestinationAccount] = []
    /// The width this is laid out in. A constant here would go on dividing the
    /// old window into columns after the window grew, quietly leaving the
    /// right-hand margin twice the left.
    var width: CGFloat = 324

    /// A drag to draw instead of a real one. Only the render harness sets
    /// this: a drag lives in `@State`, so without a seam the only frames
    /// anyone could ever look at are the two ends of the gesture — and the
    /// states worth arguing about are all in the middle.
    var previewDrag: AgentDragSession?

    /// The drag in progress, owned here because a drag spans columns and no
    /// column can see its neighbours.
    @State private var drag: AgentDragSession?

    /// The drag that was just refused, held briefly so the refusal is visible
    /// after the pointer has let go. The whole session rather than the machine
    /// that said no, because a refusal has two halves: the target tints, and
    /// the token that came back shakes.
    @State private var refusal: AgentDragSession?

    private var activeDrag: AgentDragSession? { drag ?? previewDrag }

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
                    onSelectMachine: onSelectMachine,
                    agentCPU: agentCPU,
                    padState: padState(for: machine.machine),
                    onSelectAgents: onSelectAgents,
                    isCarried: activeDrag?.origin == machine.machine,
                    wasRefused: refusal?.origin == machine.machine,
                    onDragChanged: { activity, dx in
                        beginOrUpdate(from: machine.machine, activity: activity, by: dx)
                    },
                    onDragEnded: endDrag
                )
                // The token being carried has to draw over the pads it is
                // passing across. Without this its own column stacks in
                // source order and a neighbour's lit pad covers the thing in
                // hand exactly when it is closest to landing.
                .zIndex(activeDrag?.origin == machine.machine ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, 16)
    }

    /// Which machines could take what is in hand.
    ///
    /// A measurement now, not a placeholder: the destination has an agent this
    /// account can run, a checkout of the repository the work is in, and
    /// credentials its provider has not refused. `AgentDropEligibility` holds
    /// the reasoning, including the one part of the question it deliberately
    /// does not ask yet.
    private func canAccept(_ machine: MachineID) -> Bool {
        guard let drag = activeDrag else { return false }
        return AgentDropEligibility.canAccept(
            machine,
            carrying: drag.activity,
            from: drag.origin,
            in: herd
        )
    }

    private func padState(for machine: MachineID) -> AgentPadState {
        guard let drag = activeDrag else {
            // A refusal outlives the gesture that caused it. Letting go is the
            // moment a person looks up for an answer, and if the pads all went
            // dark on release then dropping on a machine that will not take it
            // would look exactly like changing your mind.
            return machine == refusal?.over ? .refused : .idle
        }
        return drag.padState(for: machine, canAccept: canAccept)
    }

    private func beginOrUpdate(
        from origin: MachineID,
        activity: MachineAgentActivity,
        by dx: CGFloat
    ) {
        var session = drag ?? AgentDragSession(origin: origin, activity: activity, over: nil)
        session.over = columns.machine(draggedFrom: origin, displacedBy: dx)
        drag = session
    }

    /// Which column the pointer is over, worked out from the drag's own
    /// translation rather than from a preference key.
    ///
    /// The columns are equal width and evenly spaced, so the arithmetic is
    /// exact and needs no geometry reader — and a reader here would have to
    /// publish four frames on every frame of a drag.
    private var columns: HerdColumns {
        HerdColumns(ids: machines.map(\.machine), stride: columnWidth + columnSpacing)
    }

    private func endDrag() {
        // Nothing moves yet, and the token springs home. The outcome is
        // computed all the same, because it is the thing the transfer work
        // will act on and it is better to have it wrong here, where it can be
        // seen, than absent until the day it matters.
        let ending = drag
        let outcome = drag?.outcome(canAccept: canAccept)
        drag = nil

        guard case .refused = outcome else {
            refusal = nil
            return
        }
        withAnimation(.easeOut(duration: 0.15)) { refusal = ending }
        // Long enough to read as an answer, short enough that it is not a
        // state the person has to dismiss.
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            withAnimation(.easeOut(duration: 0.25)) { refusal = nil }
        }
    }

    private var machineCount: CGFloat { CGFloat(max(machines.count, 1)) }
    private var columnSpacing: CGFloat { machines.count <= 3 ? 10 : 6 }
    /// The pads reach the full width of their column, so this is the margin
    /// between a surface and the window edge rather than between text and the
    /// edge — it has to look like a deliberate inset.
    private var horizontalPadding: CGFloat { machines.count <= 3 ? 18 : 14 }
    private var columnWidth: CGFloat {
        let available = width - horizontalPadding * 2
            - columnSpacing * CGFloat(max(machines.count - 1, 0))
        return min(68, max(40, available / machineCount))
    }
    /// The animal is the machine, and it is the primary mark on this screen.
    /// Grown a little now that a second, smaller mark sits under it: the
    /// hierarchy has to be obvious at a glance or it reads as two things of
    /// roughly equal weight, which is the one arrangement that says nothing.
    private var avatarSize: CGFloat {
        switch machines.count {
        case ...3: 42
        case 4: 34
        default: 27
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
    var agentCPU: [String: Double] = [:]
    var padState: AgentPadState = .idle
    var onSelectAgents: ((MachineID) -> Void)?
    var isCarried = false
    var wasRefused = false
    var onDragChanged: ((MachineAgentActivity, CGFloat) -> Void)?
    var onDragEnded: (() -> Void)?

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
                        memoryPressure: presentation.memoryPressure,
                        memoryExplanation: machine.memoryPressureExplanation
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
            // Says the bar is a target. The hovered header used to do this
            // job by changing when you crossed a column, which told you the
            // app had noticed the pointer rather than what a click would do.
            .pointerStyle(.link)
            .accessibilityLabel(Text("\(machine.name) \(String(localized: metric.title))"))
            .accessibilityHint(columnHelp)

            // …the icon opens everything about the machine.
            Button {
                onSelectMachine?(machine.machine)
            } label: {
                MachineStatusLabel(
                    machine: machine,
                    avatarSize: avatarSize,
                    namespace: namespace,
                    agentCPU: agentCPU,
                    padState: padState,
                    onSelectAgents: onSelectAgents,
                    isCarried: isCarried,
                    wasRefused: wasRefused,
                    onDragChanged: onDragChanged,
                    onDragEnded: onDragEnded
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
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
            // The same sentence the symbol inside this column shows, from the
            // same place. They used to be built separately and say different
            // things, and only the symbol's was ever read.
            if let explanation = machine.memoryPressureExplanation {
                return Text(explanation)
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
    var memoryExplanation: String?

    var body: some View {
        switch MetricValueDisplay.resolve(
            metric: metric,
            value: value,
            memoryPressure: memoryPressure
        ) {
        case .pressure(let level):
            MemoryPressureSymbol(level: level, explanation: memoryExplanation)
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
    /// Share of the whole machine per session, so the badge can tell working
    /// from merely open.
    var agentCPU: [String: Double] = [:]
    var padState: AgentPadState = .idle
    var onSelectAgents: ((MachineID) -> Void)?
    /// Whether the drag in progress started here. Told rather than inferred:
    /// the offset below is this view's business, but *being carried* is a fact
    /// about the drag, and deriving it twice is how the two disagree.
    var isCarried = false
    /// Whether the drop this token just came back from was refused.
    var wasRefused = false
    var onDragChanged: ((MachineAgentActivity, CGFloat) -> Void)?
    var onDragEnded: (() -> Void)?

    @State private var carried: CGSize = .zero
    @State private var isReady = false
    @State private var isDragging = false
    @State private var isShowingCard = false
    /// The pending "the pointer has settled, show the card" work, kept so
    /// crossing the token on the way somewhere else cancels it.
    @State private var hoverIntent: Task<Void, Never>?
    /// Sideways jitter after a refused drop.
    @State private var shake: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Two points between the animal and its name, seven before the agent
        // mark: the machine's identity is one group, and what is running on it
        // is another.
        VStack(spacing: 2) {
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

            // Appears when work starts and leaves when it stops, rather than
            // holding a slot that is empty most of the time. The column is
            // thirty points wide; a permanent gap under every name would cost
            // more than the mark is worth.
            // The pad is drawn whenever there is something on it or a drag is
            // asking where things could go. At rest under an idle machine it
            // would be a permanent empty box.
            if activity != nil || padState != .idle {
                MachineAgentPad(state: padState, height: avatarSize * 0.64 + 10) {
                    if let activity {
                        MachineAgentToken(
                            activity: activity,
                            machineName: machine.shortName,
                            // Derived, so the hierarchy survives a herd of two
                            // and a herd of six alike — and big enough to grab
                            // comfortably, because this is a thing you pick up.
                            size: avatarSize * 0.64,
                            lift: lift
                        )
                        .offset(x: carried.width + shake, y: carried.height)
                        // Implicit, and keyed on the offset, so a token grabbed
                        // again while it is still flying home retargets from
                        // where it is on screen. `withAnimation` around the
                        // release animates *toward* a value the next gesture
                        // then overwrites, which is the classic way to get a
                        // jump at exactly the moment the person is watching.
                        .animation(homeward, value: carried)
                        .zIndex(1)
                        .onHover { hovering in
                            isReady = hovering
                            cardHover(hovering)
                        }
                        // Says the token is a target in its own right, not a
                        // decoration on the button underneath it.
                        .pointerStyle(.link)
                        .popover(isPresented: $isShowingCard, arrowEdge: .bottom) {
                            MachineAgentCard(
                                activity: activity,
                                machineName: machine.shortName,
                                agentCPU: agentCPU
                            )
                        }
                        // Before the drag, so a click on the token opens the
                        // AI page instead of falling through to the button
                        // that opens the machine's summary. They are different
                        // destinations and the token points at the nearer one.
                        .onTapGesture {
                            isShowingCard = false
                            onSelectAgents?(machine.machine)
                        }
                        .gesture(dragGesture(for: activity))
                    }
                }
                .padding(.top, 7)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.32), value: activity)
        .onChange(of: wasRefused) { _, refused in
            if refused { shakeOff() }
        }
    }

    /// Shows the card once the pointer has settled, and takes it away at once
    /// when the pointer leaves.
    ///
    /// Asymmetric on purpose: the delay exists so that crossing the token on
    /// the way to something else does not throw a panel over the herd, and a
    /// matching delay on the way out would leave the card sitting over the
    /// machine you were actually reaching for.
    private func cardHover(_ hovering: Bool) {
        hoverIntent?.cancel()
        guard hovering else {
            isShowingCard = false
            return
        }
        hoverIntent = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            isShowingCard = true
        }
    }

    /// Nothing while it is in hand — the token belongs to the pointer then —
    /// and a spring on the way back. Reduced motion keeps the return but drops
    /// the bounce, which is the part that is decoration rather than answer.
    private var homeward: Animation? {
        if isDragging { return nil }
        return reduceMotion
            ? .easeOut(duration: 0.2)
            : .spring(duration: 0.34, bounce: 0.35)
    }

    /// A refused drop shakes the token on its way back.
    ///
    /// The target machine tinting says *which* one said no; this says the drop
    /// itself was rejected. Without it a refusal and a change of mind are the
    /// same picture — the token returns home either way.
    private func shakeOff() {
        guard !reduceMotion else { return }
        let steps: [CGFloat] = [-5, 4, -3, 2, 0]
        Task {
            for step in steps {
                withAnimation(.easeOut(duration: 0.055)) { shake = step }
                try? await Task.sleep(for: .milliseconds(55))
            }
        }
    }

    private var lift: MachineAgentToken.TokenLift {
        if isCarried || carried != .zero { return .carried }
        return isReady ? .ready : .resting
    }

    /// Picking up, carrying, and letting go.
    ///
    /// A minimum distance so a click on the token is still a click: without
    /// one, every press became a one-pixel drag and the token twitched under
    /// the pointer instead of behaving like a button.
    private func dragGesture(for activity: MachineAgentActivity) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                isDragging = true
                // The card is anchored to a token that is now moving, and it
                // is answering a question the person has stopped asking.
                isShowingCard = false
                hoverIntent?.cancel()
                // One to one with the pointer, and deliberately not animated:
                // a token that eased toward the cursor would be following it
                // rather than being held.
                carried = value.translation
                onDragChanged?(activity, value.translation.width)
            }
            .onEnded { _ in
                onDragEnded?()
                isDragging = false
                // Home with a spring, always. Nothing moves yet, and a token
                // that stayed where it was dropped would be claiming something
                // had happened.
                carried = .zero
            }
    }

    /// What this machine's agents are doing, or nothing when they are not.
    private var activity: MachineAgentActivity? {
        guard machine.state == .live else { return nil }
        return MachineAgentActivityReader.activity(
            for: machine.agentSessions,
            cpuBySession: agentCPU
        )
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
