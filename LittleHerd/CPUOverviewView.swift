import SwiftUI

struct CPUOverviewView: View {
    let machines: [MachineMonitorModel]
    let metric: OverviewMetric
    var namespace: Namespace.ID?
    var onSelectMetric: ((MachineID) -> Void)?
    var onSelectMachine: ((MachineID) -> Void)?
    var onSelectAgents: ((MachineID) -> Void)?
    /// A session was dropped on a machine that will take it.
    ///
    /// The view reports the drop and does not act on it. Deciding whether a
    /// transfer is possible needs the checkouts and agents of every machine,
    /// and running one outlives this window — neither belongs in a gesture
    /// handler.
    var onTransfer: ((AgentSession, MachineID, MachineID) -> Void)?
    /// How the transfer of a given session is going, if one is running.
    var transferState: ((AgentSession) -> TransitState?)?
    /// Something to run on a machine, which the model confirms first.
    var onRunCommand: ((MachineCommand, MachineID) -> Void)?
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

    /// The machine whose deck is raised, and why it went up.
    ///
    /// **Two reasons, and they differ in one visible way.** Pointing at a
    /// machine is a question about that machine, so the rest of the herd steps
    /// back to answer it. A session *arriving* is news, and dimming three
    /// machines to deliver it would be the herd flinching every time work
    /// starts somewhere.
    @State private var fanned: MachineID?
    /// Whether the raise answers a pointer or announces an arrival. They no
    /// longer look different — the herd used to dim for the first — but they
    /// still behave differently: an arrival takes itself away, and a pointer
    /// outranks one that is still up.
    @State private var fanIsAnswerToAPointer = true
    /// Clears an arrival's raise after it has been seen.
    @State private var arrivalRaise: Task<Void, Never>?

    /// An agent in hand, and the machine the pointer is over.
    @State private var carrying: CarriedAgent?
    /// The machine whose deck is waiting for a card to come home.
    @State private var returning: MachineID?
    @State private var returnAfterDrop: Task<Void, Never>?

    /// A card that has been dropped on another machine and is neither in the
    /// deck it left nor in the one it is joining.
    @State private var transit: TransitCard?
    @State private var transitWatch: Task<Void, Never>?

    nonisolated struct TransitCard: Equatable {
        let session: AgentSession
        let from: MachineID
        let to: MachineID
        var state: TransitState
        /// Set while it is on its way back to the deck it came from.
        var goingHome = false
    }

    struct CarriedAgent: Equatable {
        let session: AgentSession
        let from: MachineID
        var over: MachineID?
    }

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

    /// See `LittleHerdPreferences.recedesBarsUnderFanKey`. Off by default.
    @AppStorage(LittleHerdPreferences.recedesBarsUnderFanKey)
    private var recedesBarsUnderFan = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Whether a fan is up to be *read* — which is the only thing the recede
    /// answers.
    ///
    /// **A drag is deliberately excluded, and it is the interesting case.**
    /// The deck is raised while a card is being carried too, so counting that
    /// pushed the herd away at precisely the moment somebody was aiming at it:
    /// you cannot pick a machine to drop on while the machines are at the far
    /// end of a dark tunnel. Reading a fan is a passive, narrow moment and the
    /// room can go; a carry is an active one and the room has to stay.
    ///
    /// `returning` counts as a carry for the same reason — the card is still
    /// in the air on its way home.
    private var somethingIsRaised: Bool {
        fanned != nil && carrying == nil && returning == nil
    }

    /// One column's aim, hoisted out of the body: `CPUOverviewView`'s view
    /// builder is at the type checker's limit and pays for every expression
    /// written inline there.
    private func recession(forColumn index: Int) -> Recession {
        herdRecession.converging(
            column: index,
            of: machines.count,
            width: columnWidth,
            spacing: columnSpacing
        )
    }


    /// How far back the herd sits while a fan is raised.
    ///
    /// **One value for the whole row, because it is one object.** Applied per
    /// column it was four objects: each drew its own dark veil, so the gaps
    /// between them stayed the window's cream and you could count the columns
    /// receding rather than watch a room move. One transform over the lot
    /// gives one continuous dark space, which is the thing being described.
    ///
    /// The fan is unaffected — it is an overlay applied after this — so the
    /// herd goes back and the agents stay at the front of the room.
    private var herdRecession: Recession {
        Recession(
            away: recedesBarsUnderFan && somethingIsRaised && !somethingIsShouting,
            reduceMotion: reduceMotion,
            // Straight back, and slightly down: the far end of the tunnel sits
            // below the herd rather than behind its middle, so the row tips
            // away from you instead of contracting toward its own centre.
            vanishing: UnitPoint(x: 0.5, y: 1.35)
        )
    }

    /// **Nothing recedes while a machine is shouting.**
    ///
    /// The per-column version could exempt one machine and let its neighbours
    /// go; one object cannot, so the rule becomes a herd-level one — and it is
    /// the better rule anyway. A reading that says something is wrong is not
    /// backdrop, and if any of them is saying it, this is not the moment to
    /// move the room.
    private var somethingIsShouting: Bool {
        machines.contains { machine in
            MetricAlarm.severity(
                machine.metricPresentation(
                    for: metric,
                    isReporting: machine.state == .live || machine.isStorage
                )
            ) != nil
        }
    }

    /// The point a column must scale toward so the whole row converges.
    ///
    /// **This is the difference between receding and shrinking.** Scaling each
    /// column about its own edge makes four bars get smaller where they stand,
    /// which reads as exactly that. Things that move away from you converge on
    /// a vanishing point, so every column scales toward the same place on
    /// screen — expressed here in that column's own unit space, since that is
    /// what `scaleEffect(anchor:)` takes.
    ///
    /// Column `i` of `n` sits `(i − (n−1)/2)` steps from the middle, each step
    /// being a column plus its spacing. Dividing by the column's own width
    /// turns that into unit space, and `0.5 −` that puts the anchor where the
    /// row's centre falls inside this column. The end columns therefore get
    /// anchors well outside `0...1`, which is correct: their vanishing point is
    /// not inside them.

    /// One machine's column, lifted out of `body`.
    ///
    /// **Not a tidiness change.** This view builder sits at the Swift type
    /// checker's limit: adding a single argument to the column tipped it into
    /// "unable to type-check this expression in reasonable time", and the error
    /// pointed at an unrelated overlay thirty lines away — naming neither the
    /// cause nor the place. Anything added to the herd's layout from here on
    /// belongs in a function, not inline.
    @ViewBuilder
    private func column(
        _ index: Int,
        _ machine: MachineMonitorModel
    ) -> some View {
            CPUThermometerColumn(
                machine: machine,
                metric: metric,
                recession: recession(forColumn: index),
                columnWidth: columnWidth,
                avatarSize: avatarSize,
                namespace: namespace,
                onSelectMetric: onSelectMetric,
                onSelectMachine: onSelectMachine,
                agents: AgentTokenContext(
                    agentCPU: agentCPU,
                    padState: padState(for: machine.machine),
                    onSelectAgents: onSelectAgents,
                    // The deck does not stay behind while the fan is out:
                    // it *is* what rose, and drawing both showed the same
                    // agent twice, once peeking and once above.
                    isFanned: fanned == machine.machine,
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
            // **The herd no longer dims for a hover.** Three machines
            // fading every time the pointer crossed one was a large
            // gesture for a small question, and the rise turns out to be
            // enough on its own — an icon lifting out of an animal is
            // already unambiguous about whose it is. Kept out rather than
            // tuned down: a subtler fade is the same idea, quieter.
            // An animal that could take what is being carried lifts to
            // meet it; one that could not simply does not answer, which is
            // a quieter no than a mark and needs no surface to paint on.
            // **And it lights.** The lift alone was legible while you
            // were watching the animal, and easy to miss while you were
            // watching the card in your hand — which is where a person
            // dragging is actually looking. A soft ground behind the
            // column says "here" without drawing a box around it.
            .background {
                if welcomes(machine.machine) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    Color.accentColor.opacity(0.35),
                                    lineWidth: 1
                                )
                        )
                        .padding(.horizontal, -4)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .offset(y: welcomes(machine.machine) ? -5 : 0)
            .animation(.spring(duration: 0.34, bounce: 0.38), value: carrying)
            // The deck owns the hover now: its own region covers the
            // animal as well, so there is no seam to fall through between
            // pointing at a machine and reaching for its agents. Two
            // adjacent regions here is what made them blink.
            // The things you go and do after looking at a machine,
            // put where you are already pointing — through AppKit, so the
            // animal can be in the menu. See `AppKitContextMenu`.
            // **Behind, never in front.** As an overlay this swallowed every
            // left-click in the herd: the `NSView` sits above the buttons, its
            // `hitTest` returns nil for anything but a right-click intending
            // the event to fall through, and SwiftUI drops it instead of
            // offering it to the button underneath. Measured — with the
            // overlay made transparent to hit testing, machines became
            // clickable again. As a background the buttons get the event
            // first and a right-click, which no `Button` consumes, still
            // reaches the menu. `MachineAgentFan` already did it this way.
            .background {
                AppKitContextMenu(
                    items: MachineMenuItems.items(
                        for: machine.configuration,
                        onOpenPage: { onSelectMachine?(machine.machine) },
                        onOpenAgents: { onSelectAgents?(machine.machine) },
                        open: { NSWorkspace.shared.open($0) },
                        run: { onRunCommand?($0, machine.machine) }
                    )
                )

            }
            .zIndex(activeDrag?.origin == machine.machine ? 1 : 0)
    }

    var body: some View {
        HStack(alignment: .top, spacing: columnSpacing) {
            ForEach(Array(machines.enumerated()), id: \.element.id) { index, machine in
                column(index, machine)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .overlay(alignment: .topLeading) { fanOverlay }
        .overlay(alignment: .topLeading) { transitOverlay }
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

    /// Whether this machine is the one an agent is being held over, and would
    /// take it.
    private func welcomes(_ machine: MachineID) -> Bool {
        guard let carrying, carrying.over == machine else { return false }
        // A rehearsal answers from every machine, for the reason in
        // `canCarry`: real eligibility refuses most of this herd, and a target
        // that never lights is a target nobody can judge.
        if DashboardChrome.rehearsesTransfers, !DashboardChrome.startsTransfers {
            return machine != carrying.from
        }
        return AgentDropEligibility.canAccept(
            machine,
            carrying: MachineAgentActivity(
                provider: carrying.session.provider,
                sessions: [carrying.session]
            ),
            from: carrying.from,
            in: herd,
            requiresApproval: requiresDestinationApproval
        )
    }

    /// Raises a machine's deck because something just started on it, for long
    /// enough to be read and no longer.
    private func raise(forArrival machine: MachineID) {
        arrivalRaise?.cancel()
        withAnimation(MachineAgentFan.rising) {
            fanIsAnswerToAPointer = false
            fanned = machine
        }
        arrivalRaise = Task {
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            // A pointer may have arrived meanwhile and taken it over.
            guard !fanIsAnswerToAPointer else { return }
            lowerFan()
        }
    }

    /// Lowering is one assignment, and there is no timer.
    ///
    /// It used to wait out the descent before taking the deck away, and there
    /// was no correct moment to do that: a spring is still moving when its
    /// nominal duration is up. Nothing is taken away now.
    private func lowerFan() {
        fanned = nil
    }

    private func raiseFan(on machine: MachineID) {
        guard let model = machines.first(where: { $0.machine == machine }),
              agentActivity(on: model) != nil
        else { return }
        // A pointer outranks an arrival: you have asked.
        arrivalRaise?.cancel()
        fanIsAnswerToAPointer = true
        fanned = machine
    }

    /// Every machine's deck, all of them mounted all of the time.
    ///
    /// Drawn across the herd rather than inside a column because a raised deck
    /// fans wider than the column it belongs to — and drawn for every machine,
    /// not just the hovered one, so that raising and lowering is a change of
    /// state rather than a change of view.
    ///
    /// **The removal transition this used to carry was the shift.** It faded
    /// and shrank the deck towards a different anchor while a second view took
    /// its place behind the animal, which is why the descent always ended in a
    /// jump however exactly the geometry was matched. Nothing is inserted or
    /// removed now, so there is no transition to get right.
    @ViewBuilder
    private var fanOverlay: some View {
        if DashboardChrome.showsAgentTokens {
            ForEach(machines, id: \.id) { machine in
                if let activity = agentActivity(on: machine) {
                    MachineAgentFan(
                        sessions: activity.sessions,
                        animalCentre: centreOfColumn(for: machine.machine),
                        width: width,
                        tile: avatarSize * MachineAgentFan.raisedScale,
                        onOpenAll: { onSelectAgents?(machine.machine) },
                        onOpenMachine: { onSelectMachine?(machine.machine) },
                        onCarry: { session, x in
                            carrying = CarriedAgent(
                                session: session,
                                from: machine.machine,
                                over: columns.machine(
                                    atX: x,
                                    leadingInset: horizontalPadding
                                )
                            )
                        },
                        onDrop: {
                            // Hold the deck up until the card is back in it.
                            if let from = carrying?.from {
                                returning = from
                                returnAfterDrop?.cancel()
                                returnAfterDrop = Task {
                                    try? await Task.sleep(for: .milliseconds(460))
                                    guard !Task.isCancelled else { return }
                                    returning = nil
                                }
                            }
                            if let carried = carrying,
                               let over = carried.over,
                               over != carried.from,
                               canCarry(to: over, carried.session) {
                                beginTransit(carried, to: over)
                            }
                            carrying = nil
                        },
                        // **Up while one of its cards is away.** A card
                        // released over another machine springs home over
                        // about four-tenths of a second, and if the deck
                        // lowers underneath it in the meantime the depth cue
                        // on the cards behind the top one drops to 0.85 —
                        // which is the flash of transparency after a snap
                        // back. The deck waits for its card.
                        excluding: transit.map {
                            $0.from == machine.machine && !$0.goingHome
                                ? [$0.session.id] : []
                        } ?? [],
                        raised: fanned == machine.machine
                            || carrying?.from == machine.machine
                            || returning == machine.machine,
                        rise: deckRise,
                        machine: machine.configuration,
                        moveTo: { session in
                            AgentMoveMenu.items(
                                moving: session,
                                from: machine.machine,
                                in: herd,
                                requiresApproval: requiresDestinationApproval,
                                name: { id in
                                    machines.first { $0.machine == id }?
                                        .shortName ?? id.rawValue
                                },
                                move: { destination in
                                    onTransfer?(
                                        session, machine.machine, destination
                                    )
                                }
                            )
                        },
                        machineMenu: MachineMenuItems.items(
                            for: machine.configuration,
                            onOpenPage: { onSelectMachine?(machine.machine) },
                            onOpenAgents: { onSelectAgents?(machine.machine) },
                            open: { NSWorkspace.shared.open($0) },
                            run: { onRunCommand?($0, machine.machine) }
                        )
                    )
                    .offset(y: fanY)
                    // **The deck is part of its machine's target.** Reaching
                    // for an agent means leaving the animal, and the icons sit
                    // above it, so without this going for one was what put it
                    // away.
                    .onHover { over in
                        if over {
                            raiseFan(on: machine.machine)
                        } else if fanned == machine.machine,
                                  fanIsAnswerToAPointer {
                            lowerFan()
                        }
                    }
                    .zIndex(fanned == machine.machine ? 1 : 0)
                }
            }
        }
    }

    /// Sends the card to the machine it was dropped on and watches what
    /// becomes of it.
    ///
    /// **The card is the progress indicator.** It settles onto the destination
    /// and spins there; a tick and a chime if the work lands, and if it does
    /// not, it goes home and the deck it left opens to take it back. The strip
    /// says the same thing in words for anyone who missed it.
    private func beginTransit(_ carried: CarriedAgent, to destination: MachineID) {
        transitWatch?.cancel()
        withAnimation(.spring(duration: 0.42, bounce: 0.22)) {
            transit = TransitCard(
                session: carried.session,
                from: carried.from,
                to: destination,
                state: .working(0)
            )
        }
        onTransfer?(carried.session, carried.from, destination)

        transitWatch = Task {
            // Watched rather than awaited: the outcome is owned by the
            // coordinator, which outlives this view, and the view may be
            // rebuilt any number of times while a transfer runs.
            while !Task.isCancelled {
                let state = transferState?(carried.session)
                if let state, !state.isWorking {
                    await finishTransit(state)
                    return
                }
                // The bar has to be told how far along it is, not merely that
                // it is still going.
                if let state { transit?.state = state }
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }

    private func finishTransit(_ state: TransitState) async {
        TransitSound.play(state)
        withAnimation(.spring(duration: 0.3, bounce: 0.3)) {
            transit?.state = state
        }

        if state == .succeeded {
            // Long enough to read the tick, then it belongs to the machine it
            // is standing on and this stops drawing it.
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(.easeOut(duration: 0.3)) { transit = nil }
        } else {
            // Home again, and the deck it left opens to receive it: the
            // exclusion lifts as it arrives rather than after, so the gap is
            // already there when it lands.
            try? await Task.sleep(for: .milliseconds(420))
            withAnimation(.spring(duration: 0.46, bounce: 0.24)) {
                transit?.goingHome = true
            }
            try? await Task.sleep(for: .milliseconds(500))
            transit = nil
        }
    }

    /// The card in transit, drawn over the herd.
    @ViewBuilder
    private var transitOverlay: some View {
        if let transit {
            let machine = transit.goingHome ? transit.from : transit.to
            AgentTransitCard(
                session: transit.session,
                state: transit.state,
                size: avatarSize * MachineAgentFan.raisedScale
            )
            .offset(
                x: centreOfColumn(for: machine)
                    - avatarSize * MachineAgentFan.raisedScale / 2,
                y: fanY + deckRise
            )
            .allowsHitTesting(false)
        }
    }

    /// Where a machine's animal sits across the window.
    private func centreOfColumn(for machine: MachineID) -> CGFloat {
        guard let index = machines.firstIndex(where: { $0.machine == machine })
        else { return width / 2 }
        let stride = columnWidth + columnSpacing
        let firstCentre = horizontalPadding + columnWidth / 2
        return firstCentre + CGFloat(index) * stride
    }

    /// The fan's top, measured from the top of the overview: above the animals
    /// and clear of the row of names underneath them.
    private var fanY: CGFloat {
        10 + DashboardMetrics.thermometerColumnHeight
            - avatarSize * Self.deckDrop
            - MachineAgentStack.clearance(forAvatar: avatarSize)
    }

    /// How far the fan's row sits above the resting deck, as a share of the
    /// avatar.
    static let deckDrop: CGFloat = 0.62

    /// The column's own insets, above the animal, which the fan has to know
    /// about to land on it.
    ///
    /// **Every one of these was missed at least once**, and each time the deck
    /// landed a few points out and then shifted as the resting stack took
    /// over. They are written down here rather than folded into a constant so
    /// that the next person to change the column's padding can see what else
    /// depends on it.
    private static let columnInset: CGFloat = 4      // .padding(.vertical, 4)
    private static let barsToAnimal: CGFloat = 3     // VStack(spacing: 3)
    private static let overviewTop: CGFloat = 10     // .padding(.top, 10)

    /// Where the resting deck's icons are centred, measured from the top of
    /// the overview.
    private var deckCentreY: CGFloat {
        let icon = MachineAgentStack.iconSize(forAvatar: avatarSize)
        let animalTop = Self.overviewTop + Self.columnInset
            + DashboardMetrics.thermometerColumnHeight + Self.barsToAnimal
        // The deck sits `peek` of an icon above the animal's top edge, and
        // this is its centre rather than its top.
        return animalTop + icon / 2 - icon * MachineAgentStack.peek
    }

    /// How far a raised icon has to travel to arrive exactly where the resting
    /// deck already is.
    ///
    /// Given to the fan rather than worked out inside it, because this is the
    /// one place that knows how the column is built. An icon keeps its raised
    /// frame and is scaled about its centre, so `tile / 2` converts from the
    /// frame's top to what is actually drawn.
    private var deckRise: CGFloat {
        let tile = avatarSize * MachineAgentFan.raisedScale
        return deckCentreY - fanY - tile / 2
    }

    private func agentActivity(on machine: MachineMonitorModel) -> MachineAgentActivity? {
        guard machine.state == .live else { return nil }
        return MachineAgentActivityReader.activity(
            for: machine.agentSessions,
            cpuBySession: agentCPU
        )
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

    /// Whether a single carried session may be dropped here. The deck drag
    /// asks `canAccept`, which is phrased in terms of a whole activity; one
    /// icon carries one session, so it is wrapped in the activity the rest of
    /// the eligibility code expects.
    private func canCarry(to machine: MachineID, _ session: AgentSession) -> Bool {
        // **A rehearsal takes anything.** Real eligibility asks whether the
        // destination has a checkout of the repository the work is in, and on
        // this herd the answer is usually no — the mini is sampled as one
        // account and the checkout belongs to another, which is the
        // account-qualified-machine problem still open on the roadmap. That is
        // a correct refusal and it makes the interface unreachable, so a
        // rehearsal skips it.
        if DashboardChrome.rehearsesTransfers, !DashboardChrome.startsTransfers {
            return machine != carrying?.from
        }

        return AgentDropEligibility.canAccept(
            machine,
            carrying: MachineAgentActivity(
                provider: session.provider,
                sessions: [session]
            ),
            from: carrying?.from ?? machine,
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
        let ending = drag
        let outcome = drag?.outcome(canAccept: canAccept)
        drag = nil

        if case .accepted(let destination) = outcome, let ending {
            // The busiest session, which is the one the badge was already
            // showing — dragging a deck of several means moving the one it
            // is standing for, not all of them.
            if let session = ending.activity.sessions.first {
                onTransfer?(session, ending.origin, destination)
            }
        }

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
    /// Whether this machine's deck has risen into the fan.
    var isFanned = false
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

/// How far back a column's reading sits, and toward where.
///
/// One value rather than three arguments: `CPUOverviewView`'s body is at the
/// type checker's limit, and each argument added to the column is paid for
/// there — the first attempt tipped it over and the error pointed at an
/// unrelated overlay thirty lines away, naming neither the cause nor the place.
struct Recession: Equatable {
    var away = false
    var reduceMotion = false
    /// The point this column scales toward, in its own unit space.
    var vanishing: UnitPoint = .bottom

    /// The same recession, aimed so that every column converges on one point.
    ///
    /// **This is the difference between receding and shrinking.** Scaling each
    /// column about its own edge makes four bars get smaller where they stand,
    /// which is exactly what it was called the first time. Things that move
    /// away converge on a vanishing point, so each column scales toward the
    /// same place on screen — expressed in that column's own unit space, since
    /// that is what `scaleEffect(anchor:)` takes.
    ///
    /// Column `i` of `n` sits `(i − (n−1)/2)` steps off centre, each step a
    /// column plus its spacing; dividing by the column's width puts that in
    /// unit space. The end columns get anchors well outside `0...1`, which is
    /// correct — their vanishing point is not inside them.
    func converging(
        column index: Int,
        of count: Int,
        width: CGFloat,
        spacing: CGFloat
    ) -> Recession {
        guard count > 1, width > 0 else { return self }
        // Explicit types at each step: as one expression this defeats the
        // type checker outright.
        let middle: CGFloat = CGFloat(count - 1) / 2
        let stepsFromCentre: CGFloat = CGFloat(index) - middle
        let stride: CGFloat = width + spacing
        let offsetInColumns: CGFloat = stepsFromCentre * stride / width
        let x: CGFloat = 0.5 - offsetInColumns
        var aimed = self
        // Below the readings, toward the animals: the far end of the tunnel is
        // down there, so the band tips away rather than closing on its middle.
        aimed.vanishing = UnitPoint(x: x, y: 1.35)
        return aimed
    }

    /// Shared by the columns and the veil so the two cannot drift apart —
    /// a band that darkened on one curve while its bars moved on another
    /// would read as two effects rather than one.
    var curve: Animation {
        reduceMotion
            ? .easeOut(duration: 0.2)
            : .spring(duration: away ? 0.46 : 0.34, bounce: 0)
    }
}

/// The reading, sliding back down a dark tunnel while a fan is raised.
///
/// Two things separate receding from shrinking, and the first attempt had
/// neither. Every column scales toward **one shared vanishing point** rather
/// than its own edge: four bars getting smaller where they stand read as
/// exactly that, which is what it was called. And it goes **dark rather than
/// transparent** — this window's ground is cream, so opacity alone walks the
/// segments toward a pale wash, the opposite of distance in an unlit space. A
/// black veil dims everything uniformly and leaves the lit blocks the
/// brightest thing left, so they keep glowing as they go.
private struct RecedingReading: ViewModifier {
    let recession: Recession

    private var away: Bool { recession.away }

    func body(content: Content) -> some View {
        content
            .scaleEffect(
                away && !recession.reduceMotion ? 0.62 : 1,
                anchor: away ? recession.vanishing : .bottom
            )
            // **The air between here and there, and nothing else.** An
            // earlier version laid a black veil across the whole band to make
            // an unlit tunnel, which worked and cost too much: it darkened the
            // window's own ground, so the room changed colour every time a
            // pointer crossed a machine. The ground stays cream and the
            // readings recede into it — which is what distance looks like in
            // daylight anyway, things going pale rather than going black.
            .opacity(away ? 0.05 : 1)
            // **A reading that has gone is not something to click.** While the
            // fan is up the bars are backdrop, and leaving them live meant
            // aiming at a faint, shrunken target that had moved — so they stop
            // taking clicks until they come forward again. The animal keeps
            // its own click throughout: it never recedes and it is how you
            // open the machine.
            .allowsHitTesting(!away)
            .animation(recession.curve, value: away)
    }
}

private struct CPUThermometerColumn: View {
    let machine: MachineMonitorModel
    let metric: OverviewMetric
    /// How far back this column's reading sits, and toward where.
    ///
    /// **Only the reading moves.** The animal and its name stay where they
    /// are — they are the machine's identity and what you are pointing at, so
    /// a herd whose animals slid away would be answering a different question
    /// than the one asked.
    var recession = Recession()
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
                        spacing: 2.25,
                        fillsHeight: true
                    )
                    .padding(.vertical, 1)
                    // Room under the bars for the agent deck to peek into.
                    // Held for every machine, so the bars are one height across
                    // the herd whether or not a machine is working.
                    .padding(
                        .bottom,
                        DashboardChrome.showsAgentTokens
                            ? MachineAgentStack.clearance(forAvatar: avatarSize)
                            : 0
                    )
                    .matchedThermometer(namespace, machine: machine.machine)

                    // **Only where there is a capacity to write.** This block
                    // used to be drawn everywhere and hidden where it had
                    // nothing to say, because leaving it out collapsed the
                    // column and moved the machines — twice. The stack around
                    // it is a fixed height now, so the machines below hold
                    // their place whatever is in here, and the room this does
                    // not use goes to the thermometer instead of showing as a
                    // gap.
                    if metric == .disk {
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
                        // Space held on Disk for every machine, filled only by
                        // those with a volume to report. Per metric and not
                        // per machine: keying it on the machine let an
                        // unreachable one grow a bar half a row taller than
                        // its neighbours', which is the same collapse as
                        // before wearing the opposite sign.
                        .opacity(showsCapacity ? 1 : 0)
                        .accessibilityHidden(!showsCapacity)
                    }
                }
                // **Inside the frame, and inside the hit shape.**
                //
                // This started on the `Button` itself and broke clicking the
                // bars, which is worse than it sounds: `scaleEffect` moves
                // SwiftUI's hit region along with the drawing, so pointing at
                // a machine shrank its own control and slid it toward the
                // vanishing point — out from under the pointer that was
                // asking for it. You cannot click a thing that retreats
                // because you looked at it.
                //
                // A render transform changes no layout, so wrapping only the
                // contents leaves the frame and `contentShape` exactly where
                // they were: the reading recedes, the target does not move.
                .modifier(RecedingReading(recession: recession))
                .frame(maxWidth: .infinity)
                .frame(height: DashboardMetrics.thermometerColumnHeight)
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

    /// Whether there is a capacity to write, as opposed to a space held for
    /// one. The space is held by every column on Disk; only the machines that
    /// answered fill it.
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
        // A figure and a warning symbol are different kinds of thing, so
        // moving between them is the one place in this column that cross-fades
        // rather than animating a value. Everything else — the digits, the
        // bars, the capacity lines — travels.
        case .pressure(let level):
            MemoryPressureSymbol(level: level, explanation: memoryExplanation)
                .font(.title3.weight(.semibold))
                .transition(.opacity)
        case .percent(let percent):
            CPUPercentage(value: percent)
                .font(.title3.weight(.semibold).monospacedDigit())
                .transition(.opacity)

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
                // Behind the animal, and drawn as a background so the animal
                // occludes it — the deck is being carried, not worn.
                // No deck here any more: there is one per machine, mounted
                // for the life of the overview in `fanOverlay`. A second copy
                // behind the animal is what the raised one used to hand over
                // to, and the hand-over was the defect.
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
    /// Divide whatever height it is given between the ten blocks, rather than
    /// standing at `blockHeight` and leaving the remainder empty.
    ///
    /// The overview uses this so a metric with nothing written under its bar
    /// spends that room on the bar itself: CPU and Memory are the same column
    /// as Disk minus two lines of capacity, and those two lines were showing
    /// as a hole rather than as a taller thermometer.
    var fillsHeight = false

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
                    .frame(width: blockWidth)
                    .frame(
                        height: fillsHeight ? nil : blockHeight,
                        alignment: .center
                    )
                    .frame(maxHeight: fillsHeight ? .infinity : nil)
            }
        }
        .animation(.smooth(duration: 0.45), value: value)
        .accessibilityHidden(true)
    }

    private var filledBlockCount: Int {
        ThermometerScale.filledBlockCount(for: value)
    }
}
