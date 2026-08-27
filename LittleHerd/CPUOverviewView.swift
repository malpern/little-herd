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

    /// Whether this overview is allowed to announce arrivals. False by
    /// default so nothing announces from a render, a preview, or any surface
    /// that is not the dashboard window.
    var announcesArrivals = false

    @AppStorage(LittleHerdPreferences.requiresDestinationApprovalKey)
    private var requiresDestinationApproval = false

    /// Whether this window is the one the person is looking at. An
    /// announcement into a window that is behind three others is a card
    /// nobody sees and a timer nobody can replay.
    @Environment(\.controlActiveState) private var windowActivity

    @State private var arrivals = AgentArrivalWatch()
    /// Noticed, waiting for somebody to be looking.
    @State private var pending: AgentAnnouncement?
    @State private var announcing: AgentArrival?
    /// The width this is laid out in. A constant here would go on dividing the
    /// old window into columns after the window grew, quietly leaving the
    /// right-hand margin twice the left.
    var width: CGFloat = DashboardMetrics.overviewContent.width

    #if DEBUG
    /// A drag to draw instead of a real one. Only the render harness sets
    /// this: a drag lives in `@State`, so without a seam the only frames
    /// anyone could ever look at are the two ends of the gesture — and the
    /// states worth arguing about are all in the middle.
    ///
    /// Debug only, because it is a hole in the view's own story about where a
    /// drag comes from, and a hole nobody can reach from a shipping build is
    /// not one anybody has to reason about.
    var previewDrag: AgentDragSession?
    #endif

    /// The drag in progress, owned here because a drag spans columns and no
    /// column can see its neighbours.
    @State private var drag: AgentDragSession?

    /// The drag that was just refused, held briefly so the refusal is visible
    /// after the pointer has let go. The whole session rather than the machine
    /// that said no, because a refusal has two halves: the target tints, and
    /// the token that came back shakes.
    @State private var refusal: AgentDragSession?

    private var activeDrag: AgentDragSession? {
        #if DEBUG
        drag ?? previewDrag
        #else
        drag
        #endif
    }

    var body: some View {
        HStack(alignment: .top, spacing: columnSpacing) {
            ForEach(Array(machines.enumerated()), id: \.element.id) { index, machine in
                CPUThermometerColumn(
                    machine: machine,
                    metric: metric,
                    columnWidth: columnWidth,
                    avatarSize: avatarSize,
                    namespace: namespace,
                    onSelectMetric: onSelectMetric,
                    onSelectMachine: onSelectMachine,
                    agents: AgentTokenContext(
                        agentCPU: agentCPU,
                        padState: padState(for: machine.machine),
                        onSelectAgents: onSelectAgents,
                        announcing: announcing?.machine == machine.machine
                            ? announcing?.session
                            : nil,
                        isCarried: activeDrag?.origin == machine.machine,
                        wasRefused: refusal?.origin == machine.machine,
                        cardSide: AgentCardSide.side(
                            forMachineAt: index,
                            inHerdOf: machines.count
                        ),
                        onDragChanged: { activity, dx in
                            beginOrUpdate(from: machine.machine, activity: activity, by: dx)
                        },
                        onDragEnded: endDrag
                    )
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
        .onChange(of: sessionFingerprint) { _, _ in noticeArrivals() }
        // The moment the herd is being looked at is the moment an arrival can
        // be shown. Without this the announcement waits for a session change
        // that may not come for minutes.
        .onChange(of: windowActivity) { _, _ in showPendingArrival() }
        // Both timers hang off the state they are counting down, so SwiftUI
        // cancels them when the value changes and again when the view goes
        // away. The loose `Task`s these replace outlived the window: one was
        // not even held, so nothing could cancel it, and it came back to clear
        // state on a view that had already gone.
        .task(id: announcing?.session) { await holdAnnouncement() }
        .task(id: refusal) { await holdRefusal() }
    }

    /// Something to watch that changes when the sessions do. `onChange` needs
    /// an `Equatable`, and the machines are reference types whose contents
    /// change underneath a view that is already looking at them.
    private var sessionFingerprint: [String] {
        machines.flatMap { machine in
            machine.agentSessions
                .filter { $0.state == .active }
                .map { "\(machine.machine.rawValue)/\($0.id)" }
        }
    }

    /// Shows the card over a token that has just appeared, briefly.
    ///
    /// The reveal is the card rather than a wider column: a column that grew
    /// would push its neighbours, so a session starting on one machine would
    /// move the thermometers, avatars and click targets of the other three.
    /// A popover overlays and nothing else moves.
    ///
    /// **Hover is deliberately kept.** This is an announcement, and an
    /// announcement you missed is gone — the same defect that retired the
    /// hovered header, which was information nobody could point at. Pointing
    /// at the token is how you ask again.
    /// **Bookkeeping first, and never behind the focus check.** The first
    /// version guarded on the window being focused before it looked at the
    /// sessions at all, which broke it twice over: sessions are started from a
    /// terminal, so the dashboard is essentially never focused at that instant
    /// — nothing was announced — and the watch never recorded them either, so
    /// it could not tell a new session from one it had already passed over.
    private func noticeArrivals() {
        guard announcesArrivals else { return }
        let herdSessions = machines.map {
            (machine: $0.machine, sessions: $0.agentSessions)
        }
        guard let arrival = arrivals.arrival(in: herdSessions, at: .now) else {
            return
        }
        pending = AgentAnnouncement(arrival: arrival, noticedAt: .now)
        showPendingArrival()
    }

    /// Shows a waiting arrival, if there is one and it is still true.
    private func showPendingArrival() {
        guard announcesArrivals, windowActivity == .key, let pending else {
            return
        }
        self.pending = nil
        guard pending.isFresh(at: .now) else { return }
        announcing = pending.arrival
    }

    /// Takes an announcement away again after long enough to read it.
    private func holdAnnouncement() async {
        guard announcing != nil else { return }
        try? await Task.sleep(for: .seconds(4))
        guard !Task.isCancelled else { return }
        announcing = nil
    }

    /// Holds a refusal after the gesture that caused it.
    ///
    /// Long enough to read as an answer, short enough that it is not a state
    /// the person has to dismiss.
    private func holdRefusal() async {
        guard refusal != nil else { return }
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.25)) { refusal = nil }
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
            in: herd,
            requiresApproval: requiresDestinationApproval
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
        HerdAvatarSize.forColumn(ofWidth: columnWidth)
    }
}

/// Which way the card over a token opens.
///
/// A side of its own rather than SwiftUI's `Edge` because the rule is
/// arithmetic over the herd, and arithmetic belongs where it can be argued
/// with — the same reason `HerdColumns` is not inside the gesture handler that
/// once hid an off-by-one in it. The view maps this onto an edge at the one
/// place it presents the popover.
nonisolated enum AgentCardSide: Equatable, Sendable {
    case leading
    case trailing

    /// The card opens into the emptier half of the window rather than over the
    /// herd: a machine on the left opens right, one on the right opens left.
    /// Vertically it would cover the avatars and names, which is the row the
    /// card is asking you to keep your place in.
    ///
    /// The middle machine of an odd herd opens right, and so does a machine
    /// this herd does not contain — with nothing to weigh, the side that works
    /// for a herd of one is the safe answer.
    static func side(forMachineAt index: Int, inHerdOf count: Int) -> AgentCardSide {
        guard count > 1, index >= 0, index < count else { return .trailing }
        return index < (count + 1) / 2 ? .trailing : .leading
    }
}

/// Everything a column has to hand its token that is about the token rather
/// than about the machine.
///
/// One value instead of eight parameters, because every one of them was
/// forwarded untouched through a view that has no opinion about any of it, and
/// a forwarding list that long is a place for two arguments to swap places
/// unnoticed.
struct AgentTokenContext {
    /// Share of the whole machine per session, so the badge can tell working
    /// from merely open.
    var agentCPU: [String: Double] = [:]
    var padState: AgentPadState = .idle
    var onSelectAgents: ((MachineID) -> Void)?
    /// The session that has just started here, while the herd is saying so.
    var announcing: String?
    /// Whether the drag in progress started here. Told rather than inferred:
    /// the offset the token draws with is the view's business, but *being
    /// carried* is a fact about the drag, and deriving it twice is how the two
    /// disagree.
    var isCarried = false
    /// Whether the drop this token just came back from was refused.
    var wasRefused = false
    var cardSide: AgentCardSide = .trailing
    var onDragChanged: ((MachineAgentActivity, CGFloat) -> Void)?
    var onDragEnded: (() -> Void)?
}

/// Whether the card over a token is open, and which of the two reasons it is
/// open for.
///
/// A value rather than a pair of `@State` flags because the binding it feeds
/// had a bug that only shows up in the combination: the getter answered for
/// both reasons and the setter wrote only one, so dismissing an announcement
/// left it open and there was nothing to do but wait out its timer.
nonisolated struct AgentCardVisibility: Equatable, Sendable {
    /// Open because the pointer settled on the token.
    var isHovering = false
    /// The announcement that has already been waved away.
    ///
    /// The announcement itself belongs to the overview, which owns the timer
    /// and the herd it is announcing for, so a token cannot clear it — but it
    /// can remember which one it has been told to stop showing. That is a
    /// smaller thing to pass down than a callback, and it cannot be wired to
    /// the wrong machine.
    var dismissed: String?

    func isShowing(announcing: String?) -> Bool {
        if isHovering { return true }
        guard let announcing else { return false }
        return announcing != dismissed
    }

    /// The pointer arriving or leaving, which never touches an announcement:
    /// pointing at a token mid-announcement and then looking away is not the
    /// same as being done with what the herd was saying.
    mutating func hover(_ hovering: Bool) {
        isHovering = hovering
    }

    /// Being done with the card, whichever reason it was open for.
    mutating func dismiss(announcing: String?) {
        isHovering = false
        dismissed = announcing
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
    var agents = AgentTokenContext()

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

                    // **Drawn on every screen, and only sometimes visible.**
                    // Twice now this block has been left out where it had
                    // nothing to say, and twice the column above it collapsed
                    // by two lines: first for a machine with no capacity to
                    // report, which floated half a row above its neighbours,
                    // and then for every metric that is not Disk, which moved
                    // the whole herd up and down as you changed tab. The
                    // window is one size for all four metrics, so the machines
                    // should sit in one place in it.
                    VStack(spacing: 0) {
                        Text(
                            HerdByteCount.storage(
                                Int64(fullestVolume?.availableBytes ?? 0)
                            )
                        )
                        .font(.caption2.weight(.medium))

                        Text("free")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .opacity(showsCapacity ? 1 : 0)
                    .accessibilityHidden(!showsCapacity)
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
            // **The same sentence, to the pointer as well as to VoiceOver.**
            // This column has always built a full explanation — what the
            // memory pressure means and what to do about it — and has only
            // ever offered it as an accessibility hint, so hovering the one
            // thing on the dashboard that asks a question of you produced
            // nothing at all. The symbol inside the column carries the same
            // text, but a tooltip declared inside a button's label never gets
            // a region of its own: the button owns the whole label, so the
            // help has to be declared out here.
            .help(columnHelp)

            // …the icon opens everything about the machine.
            Button {
                onSelectMachine?(machine.machine)
            } label: {
                MachineStatusLabel(
                    machine: machine,
                    avatarSize: avatarSize,
                    namespace: namespace,
                    agents: agents
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

    /// Whether there is a capacity to show, as opposed to a space held for one.
    private var showsCapacity: Bool { metric == .disk && fullestVolume != nil }

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
    /// Everything about the token this machine is carrying. Defaulted, because
    /// the machine's own page draws this label with no token at all.
    var agents = AgentTokenContext()

    @State private var carried: CGSize = .zero
    @State private var isReady = false
    @State private var isDragging = false
    @State private var card = AgentCardVisibility()
    /// How many refused drops this token has come back from, which is what the
    /// jitter is triggered off. A count rather than the refusal itself: the
    /// refusal is cleared again when it expires, and a trigger fires on every
    /// change, so the token would have shaken a second time on the way out.
    @State private var refusals = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Two points between the animal and its name, seven before the agent
        // mark: the machine's identity is one group, and what is running on it
        // is another.
        VStack(spacing: HerdAvatarSize.captionSpacing) {
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

            // The hidden template is what keeps the four names on one
            // baseline. A long name shrinks to fit its column, a smaller font
            // draws a shorter line, and the row rides up by the difference —
            // so "Synology" sat three points above its neighbours while every
            // frame in the layout was the same size. The template holds the
            // height of an unshrunk line whatever the name does.
            ZStack {
                Text(verbatim: "Ag")
                    .font(.caption.weight(.medium))
                    .hidden()
                    .accessibilityHidden(true)

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

            // Appears when work starts and leaves when it stops, rather than
            // holding a slot that is empty most of the time. The column is
            // thirty points wide; a permanent gap under every name would cost
            // more than the mark is worth.
            // The pad is drawn whenever there is something on it or a drag is
            // asking where things could go. At rest under an idle machine it
            // would be a permanent empty box.
            if DashboardChrome.showsAgentTokens,
               activity != nil || agents.padState != .idle {
                MachineAgentPad(state: agents.padState, height: avatarSize * 0.64 + 10) {
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
                        .offset(x: carried.width, y: carried.height)
                        // Implicit, and keyed on the offset, so a token grabbed
                        // again while it is still flying home retargets from
                        // where it is on screen. `withAnimation` around the
                        // release animates *toward* a value the next gesture
                        // then overwrites, which is the classic way to get a
                        // jump at exactly the moment the person is watching.
                        .animation(homeward, value: carried)
                        .keyframeAnimator(
                            initialValue: CGFloat.zero,
                            trigger: refusals
                        ) { token, jitter in
                            token.offset(x: jitter)
                        } keyframes: { _ in
                            // Five stops in a little over a quarter second,
                            // each smaller than the last: a refusal, not a
                            // wobble.
                            CubicKeyframe(-5, duration: 0.055)
                            CubicKeyframe(4, duration: 0.055)
                            CubicKeyframe(-3, duration: 0.055)
                            CubicKeyframe(2, duration: 0.055)
                            CubicKeyframe(0, duration: 0.055)
                        }
                        .zIndex(1)
                        .onHover { hovering in
                            isReady = hovering
                            // Immediately on the way out, and after a pause on
                            // the way in — the delay exists so that crossing
                            // the token on the way to something else does not
                            // throw a panel over the herd, and a matching
                            // delay leaving would leave the card sitting over
                            // the machine you were actually reaching for.
                            if !hovering { card.hover(false) }
                        }
                        // Says the token is a target in its own right, not a
                        // decoration on the button underneath it.
                        .pointerStyle(.link)
                        .popover(isPresented: showsCard, arrowEdge: cardEdge) {
                            MachineAgentCard(
                                activity: activity,
                                machineName: machine.shortName,
                                agentCPU: agents.agentCPU,
                                leading: card.isHovering ? nil : agents.announcing
                            )
                        }
                        // Before the drag, so a click on the token opens the
                        // AI page instead of falling through to the button
                        // that opens the machine's summary. They are different
                        // destinations and the token points at the nearer one.
                        .onTapGesture {
                            card.dismiss(announcing: agents.announcing)
                            agents.onSelectAgents?(machine.machine)
                        }
                        .gesture(dragGesture(for: activity))
                    }
                }
                .padding(.top, 7)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.32), value: activity)
        // A refusal shakes the token on its way back. Guarded here rather than
        // inside the animation, so reduced motion leaves the trigger alone and
        // there is nothing to play at all.
        .onChange(of: agents.wasRefused) { _, refused in
            if refused, !reduceMotion { refusals += 1 }
        }
        // The pointer settling on the token, held for long enough to be an
        // ask. Hung off the hover state rather than run from a loose `Task`,
        // so leaving the token — or the window going away underneath it —
        // cancels the pending card instead of letting it arrive over whatever
        // is there by then.
        .task(id: wantsCard) { await showCardIfStillWanted() }
    }

    /// Open because the pointer asked, or because something just started.
    ///
    /// One binding rather than two popovers: a view can present only one at a
    /// time, and pointing at a token mid-announcement is a person asking the
    /// question the announcement was already answering. The pointer wins, so
    /// the card stops being on a timer the moment it is being read.
    ///
    /// Dismissing has to reach both reasons. When the setter wrote only the
    /// hover half, a getter that still saw the announcement pulled the card
    /// straight back up, and the only way to close it was to wait.
    private var showsCard: Binding<Bool> {
        Binding(
            get: { card.isShowing(announcing: agents.announcing) },
            set: { showing in
                if showing {
                    card.hover(true)
                } else {
                    card.dismiss(announcing: agents.announcing)
                }
            }
        )
    }

    /// Which side of the token the card opens on, decided by where this
    /// machine sits in the herd.
    private var cardEdge: Edge {
        switch agents.cardSide {
        case .leading: .leading
        case .trailing: .trailing
        }
    }

    /// Whether the pointer is asking for the card. A drag cancels the ask: the
    /// card is anchored to a token that is now moving, and it is answering a
    /// question the person has stopped asking.
    private var wantsCard: Bool { isReady && !isDragging }

    private func showCardIfStillWanted() async {
        guard wantsCard else { return }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        card.hover(true)
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

    private var lift: MachineAgentToken.TokenLift {
        if agents.isCarried || carried != .zero { return .carried }
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
                card.dismiss(announcing: agents.announcing)
                // One to one with the pointer, and deliberately not animated:
                // a token that eased toward the cursor would be following it
                // rather than being held.
                carried = value.translation
                agents.onDragChanged?(activity, value.translation.width)
            }
            .onEnded { _ in
                agents.onDragEnded?()
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
            cpuBySession: agents.agentCPU
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
