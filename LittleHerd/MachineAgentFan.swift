import SwiftUI

/// A machine's agents, fanned out above it.
///
/// **An overlay on the herd, not a part of a column.** A fan of six is most of
/// the window wide, so it cannot be drawn inside the sixty-odd points its
/// machine occupies — it would be clipped by its own column, and the layout
/// that keeps it inside the window has nothing to measure against. The overview
/// draws it over everything, which is also the only place that knows which
/// machine is being pointed at and can dim the rest.
struct MachineAgentFan: View {
    let sessions: [AgentSession]
    /// The middle of the animal the fan belongs to, in the overview's own
    /// coordinates.
    let animalCentre: CGFloat
    let width: CGFloat
    let tile: CGFloat
    /// Opens the machine's AI page — where the ones that did not fit are.
    var onOpenAll: () -> Void = {}
    /// Carrying one of them: the session, and where it is now in the window.
    var onCarry: (AgentSession, CGFloat) -> Void = { _, _ in }
    var onDrop: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0 while the icons are still stacked behind the animal, 1 once they have
    /// risen and spread. Animated on appear, so the fan comes *out of* the
    /// machine rather than materialising above it — a cross-fade at the
    /// destination reads as a popover, which is the one thing this design is
    /// trying not to be.
    @State private var spread: CGFloat = 0
    /// Whether this machine's deck is up.
    ///
    /// **This view is never unmounted, and that is the whole point.** It used
    /// to be created when a machine was hovered and destroyed when the deck
    /// landed, with `MachineAgentStack` drawing the resting state in between —
    /// two views describing one object, handing over at the exact moment
    /// nothing is supposed to change. Three attempts at making that hand-over
    /// invisible each fixed a real difference and left a shift behind, because
    /// the swap itself is the defect: a spring is still moving when its
    /// nominal duration is up, and there is no correct moment to exchange one
    /// view for another mid-flight.
    ///
    /// So there is one deck now. It rises and settles; nothing is created or
    /// destroyed, and the resting position is simply where the animation ends.
    /// Sessions this deck must not draw, because they are somewhere else —
    /// in transit to another machine. The deck closes around them exactly as
    /// it does around one being carried.
    var excluding: Set<String> = []
    var raised: Bool = false
    /// How far below the fan's row the resting deck sits. Worked out by
    /// `CPUOverviewView`, which is the only thing that knows how a column is
    /// stacked — see `deckRise` there.
    var rise: CGFloat = 0
    /// The machine these belong to, for the menu on a card. Optional so the
    /// fan can still be drawn in a test without inventing a configuration.
    var machine: MachineConfiguration?
    /// Where each session lives, from the registry. Only the unusual cases
    /// say anything — see `AgentSessionOrigin.label`.
    var origins: [String: AgentSessionOrigin] = [:]
    /// The machine's own menu, for the part of this view that covers its
    /// animal. **The hover column spans the animal on purpose** — so reaching
    /// for an agent does not lose the pointer — which also means it is the
    /// view a right-click over that animal lands on. Without this, a machine
    /// with agents had no menu at all while one without agents did, because
    /// only the busy one had this column over it.
    /// Where this session could go, and why not, for each machine.
    var moveTo: (AgentSession) -> [AppKitMenuItem] = { _ in [] }
    var machineMenu: [AppKitMenuItem] = []
    /// Whether the deck has finished coming down.
    ///
    /// **Not the same question as `spread == 0`.** `spread` is set to nought
    /// the moment the pointer leaves; it is the *animation* that takes time,
    /// so anything keyed on the value alone happens while the icons are still
    /// travelling. The count came back a third of the way down for exactly
    /// that reason.
    @State private var settled = true
    @State private var settling: Task<Void, Never>?
    @State private var carrying: Int?
    @State private var carried: CGSize = .zero

    /// **A spring with some mass in it.** Longer and looser than the app's
    /// usual 0.22s, and allowed to overshoot: these are objects being lifted
    /// off an animal's back, and something weightless arriving instantly reads
    /// as a menu opening.
    static let rising = Animation.spring(duration: 0.46, bounce: 0.30)

    /// Going back down.
    ///
    /// **The deck used to be removed rather than lowered**, so the rise had no
    /// answering movement: the icons appeared to be plucked away and the
    /// resting stack popped back in their place. Coming down is now a real
    /// movement, and a different one from going up — less bounce, because a
    /// thing settling onto a surface does not overshoot the way a thing being
    /// lifted off one does, and a little quicker, since nobody is waiting to
    /// read it any more.
    static let settlingCurve = Animation.spring(duration: 0.34, bounce: 0.12)

    /// The stagger between one card leaving and the next.
    static let cardDelay: Double = 0.04

    /// How long to wait before the deck may actually be taken away.
    ///
    /// **Comfortably longer than the descent, on purpose.** The obvious value
    /// is the animation's own duration, and it is wrong twice over: the last
    /// icon does not start until `0.04 × index` after the first, and a spring
    /// keeps moving after its nominal duration — that number describes how
    /// long it *reads* as taking, not when it stops. Hand over on 460ms and
    /// the stack replaces a deck that is still travelling, so it appears at
    /// the final position and the remaining distance is covered in one frame.
    /// Which looks exactly like what it is: a shift, right at the end of an
    /// otherwise continuous movement.
    ///
    /// Waiting longer costs nothing. The fan at rest and the resting stack are
    /// the same picture, so the extra time is invisible — and coming back to
    /// the machine during it catches the deck rather than starting again.
    static let descent: Duration = .milliseconds(900)

    /// How big a raised icon is, against the animal it came from. Larger than
    /// the deck it rose from — it is the thing being read now, and the growth
    /// is what makes the rise feel like a rise rather than a slide.
    static let raisedScale: CGFloat = 0.78

    /// Clear space, and enough of it to read as separate objects rather than a
    /// strip. A quarter of a tile is the smallest gap that still does.
    private var gap: CGFloat { tile * 0.26 }

    /// The size an icon starts and ends at, as a share of its raised size:
    /// exactly the resting deck's, so the first frame of the rise and the last
    /// frame of the fall match what is behind the animal.
    private var restingShare: CGFloat {
        MachineAgentStack.iconSize(forAvatar: tile / Self.raisedScale) / tile
    }

    /// One card: which session it is, where it sits, and how deep in the deck.
    ///
    /// Exists so the `ForEach` can be keyed by the session rather than by a
    /// position — and so the icon can be built in a function of its own, which
    /// the type-checker needs once a view has this many modifiers on it.
    nonisolated struct Placed: Identifiable {
        let session: AgentSession
        let rect: CGRect
        let index: Int
        var id: String { session.id }
    }

    /// When the deck has landed — which is when the **last** card has, that
    /// being both the one the count is drawn on and the one that starts last.
    ///
    /// A flat number was wrong in both directions: too long for a single card,
    /// too short for a deep deck. This is the settling curve plus that card's
    /// own share of the stagger, so the count arrives as the card arrives
    /// rather than a beat after everything has stopped.
    private var settleWait: Duration {
        let seconds = 0.34 + Self.cardDelay * Double(max(sessions.count - 1, 0))
        return .milliseconds(Int(seconds * 1000))
    }

    /// **The deck heals around a card that has been picked up.**
    ///
    /// Two layouts: the full one, which is where the carried card was and so
    /// where it starts from, and one for the cards left behind, laid out as
    /// though the missing one had never been there. They slide into the gap
    /// while it is in hand and slide back out when it returns.
    private var shown: [AgentSession] {
        sessions.filter { !excluding.contains($0.id) }
    }

    private var placed: [Placed] {
        let full = layout.icons
        let healed = carrying == nil ? full : AgentFanLayout.lay(
            out: max(sessions.count - 1, 1),
            centredOn: animalCentre,
            inWindowOfWidth: width,
            tile: tile,
            gap: gap
        ).icons

        var slot = 0
        return shown.enumerated().map { index, session in
            guard index != carrying else {
                return Placed(
                    session: session,
                    rect: full[min(index, full.count - 1)],
                    index: index
                )
            }
            let rect = healed[min(slot, healed.count - 1)]
            slot += 1
            return Placed(session: session, rect: rect, index: index)
        }
    }

    private var layout: AgentFanLayout {
        AgentFanLayout.lay(
            out: sessions.count,
            centredOn: animalCentre,
            inWindowOfWidth: width,
            tile: tile,
            gap: gap
        )
    }

    var body: some View {
        let fan = layout
        ZStack(alignment: .topLeading) {
            // **Keyed by session, not by position.** With an index for an
            // identity, a finished session does not leave — every card after
            // it simply becomes a different session, so there is nothing for
            // SwiftUI to animate out and the deck changes between frames.
            ForEach(placed) { card in
                icon(for: card, isLast: card.index == placed.count - 1)
            }

            if let overflow = fan.overflow, spread > 0.4 {
                Button(action: onOpenAll) {
                    Text("+\(overflow.count)")
                        .font(.system(size: tile * 0.34, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(width: tile, height: tile)
                        // Round, where the agents are square: it is a control,
                        // not a fourth agent nobody can identify.
                        .background(Circle().fill(.quaternary))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .offset(x: overflow.rect.minX)
                .help(Text("\(overflow.count) more — open this machine's AI page"))
                .accessibilityLabel(
                    Text("\(overflow.count) more agents, open this machine's AI page")
                )
            }
        }
        // The departure itself, and the shuffle the others do to close the
        // gap. Keyed on the sessions rather than their number so that one
        // finishing while another starts still moves rather than cutting.
        .animation(
            reduceMotion ? nil : .spring(duration: 0.42, bounce: 0.18),
            value: sessions.map(\.id)
        )
        // Tall enough to hold the deck at rest as well as raised. Offsets
        // reaching outside a frame still draw but stop being hit-testable,
        // which is why the resting icons could not be pointed at.
        .frame(
            width: width,
            height: tile + max(rise, 0),
            alignment: .topLeading
        )
        // **A target that does not move when the icons do.**
        //
        // Hover otherwise lands on the icons themselves, and the first thing
        // they do when hovered is leave: the deck rises out from under the
        // pointer, the hover ends, it starts back down, the pointer catches it
        // again — a machine you are holding still over flickers between up and
        // down. This is an invisible column over the animal, spanning the
        // whole climb, so the answer to "is the pointer here" does not depend
        // on where the deck has got to.
        .background(alignment: .topLeading) {
            Color.clear
                .overlay { AppKitContextMenu(items: machineMenu) }
                .frame(
                    width: tile * 2.1,
                    // Down past the animal as well, so the deck and the animal
                    // it rides on are **one** region rather than two adjacent
                    // ones. With a seam between them, moving from the animal
                    // to the cards left the first before entering the second:
                    // the deck began to lower and immediately rose again, and
                    // the depth cue on the cards behind the top one — which is
                    // keyed on how far up they are — blinked as it went. The
                    // travel was too small to notice; the fade was not.
                    height: tile + max(rise, 0) + animalHeight
                )
                .contentShape(Rectangle())
                .offset(x: animalCentre - tile * 1.05)
        }
        .onAppear {
            spread = raised ? 1 : 0
            settled = !raised
        }
        // Both directions, and interruptible: a deck caught on its way down
        // turns round from wherever it is, because a spring given a new
        // target keeps the velocity it already had.
        .onChange(of: raised) { _, isRaised in
            spread = isRaised ? 1 : 0
            settling?.cancel()
            guard !isRaised else {
                // Going up, the count goes at once — see the mark itself.
                settled = false
                return
            }
            settling = Task {
                // Long enough for the last icon, which starts a beat after
                // the first and is still moving when the spring's nominal
                // duration is up.
                try? await Task.sleep(for: settleWait)
                guard !Task.isCancelled else { return }
                settled = true
            }
        }
    }

    @ViewBuilder
    private func icon(for card: Placed, isLast: Bool) -> some View {
        let index = card.index
        Image(nsImage: AgentProviderIcons.icon(for: card.session.provider))
            .resizable()
            .scaledToFit()
            .frame(width: tile, height: tile)
            // **Inside the scaling, not on top of it.** Attached after
            // `scaleEffect` the mark kept its full size and hung off the
            // corner of an unscaled frame — a large circle floating above the
            // deck it belonged to.
            .overlay(alignment: .topTrailing) {
                // On the bottom card of the deck, and only once the deck has
                // actually landed. It says how many are stacked out of sight,
                // so it goes the instant they begin to fan out: by then you
                // can see them, and a number counting things in front of you
                // is just more to read.
                if isLast, sessions.count > 1, settled {
                    AgentDeckCountMark(count: sessions.count, iconSize: tile)
                }
            }
            // No card. The icon is already one.
            .opacity(index == 0 ? 1 : 0.85 + 0.15 * spread)
            .shadow(
                color: .black.opacity(0.22 + 0.02 * spread),
                radius: tile * (0.068 + 0.092 * spread),
                y: 1 + spread
            )
            // Each icon starts where the deck was — stacked at the animal,
            // smaller and lower — and travels to its place.
            .scaleEffect(restingShare + (1 - restingShare) * spread)
            // **Each icon carries its own weight.** They leave the animal a
            // beat apart and settle a beat apart, which is what a handful of
            // objects does and what one sheet of glass does not.
            .animation(
                reduceMotion
                    ? nil
                    : (spread == 0 ? Self.settlingCurve : Self.rising)
                        .delay(Double(index) * Self.cardDelay),
                value: spread
            )
            .offset(
                x: stackedX(index)
                    + (card.rect.minX - stackedX(index)) * spread
                    + (carrying == index ? carried.width : 0),
                y: stackedY(index) * (1 - spread)
                    + (carrying == index ? carried.height : 0)
            )
            // Lifted while it is in hand, and above its neighbours.
            .scaleEffect(carrying == index ? 1.12 : 1)
            .zIndex(
                carrying == index
                    ? Double(sessions.count + 1)
                    : Double(sessions.count - index)
            )
            // Nothing while it is in hand — it belongs to the pointer then —
            // and a heavier spring on the way home.
            .animation(
                carrying == index ? nil : .spring(duration: 0.42, bounce: 0.34),
                value: carried
            )
            // **Finishing is worth watching.** A session that ends used to be
            // gone between one frame and the next, the same non-event as an
            // agent appearing out of nothing. It collapses to a point at its
            // own centre and fades as it goes, so what you see is the thing
            // leaving rather than the absence afterwards.
            .transition(
                .scale(scale: 0.01, anchor: .center).combined(with: .opacity)
            )
            // Closing the gap, and opening it again when the card comes back.
            .animation(
                reduceMotion ? nil : .spring(duration: 0.36, bounce: 0.20),
                value: carrying
            )
            // **The pointer says what the thing under it does.** An open hand
            // over a card that can be picked up, a closed one while it is
            // being carried.
            .pointerStyle(carrying == index ? .grabActive : .grabIdle)
            // The card cannot say which project it is in twenty points of
            // width. The menu can, and it is where somebody would ask —
            // through AppKit, like the machine's, so the agent's own icon is
            // beside its name.
            .overlay {
                if let machine {
                    AppKitContextMenu(
                        items: AgentMenuItems.items(
                            for: card.session,
                            on: machine,
                            origin: origins[card.session.id],
                            moveTo: moveTo(card.session),
                            onOpenAgents: onOpenAll
                        )
                    )
                }
            }
            .gesture(carry(card.session, index: index, restingAt: card.rect.midX))
            .help(Text(card.session.displayTitle))
            .accessibilityLabel(Text(card.session.displayTitle))
    }

    /// Picking one up and carrying it across the herd.
    ///
    /// A minimum distance so a press is still a press: without one every click
    /// became a one-pixel drag, which is the lesson the token that came before
    /// this taught.
    private func carry(_ session: AgentSession, index: Int, restingAt x: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                carrying = index
                carried = value.translation
                onCarry(session, x + value.translation.width)
            }
            .onEnded { _ in
                onDrop()
                carrying = nil
                // Home with a spring, always: nothing moves yet, and an icon
                // that stayed where it was dropped would claim otherwise.
                withAnimation(.spring(duration: 0.34, bounce: 0.35)) { carried = .zero }
            }
    }

    /// Where an icon sits before it rises: stacked at the animal, leaning the
    /// way the resting deck leans, so the two states are the same object.
    /// **Where the deck actually is when it is not raised.**
    ///
    /// These used to be invented here — a lean of 0.22 and a drop of 1.15
    /// tiles — while `MachineAgentStack` drew the resting deck with a lean of
    /// 0.11 and sat it `peek` above the animal. Two descriptions of the same
    /// object, and they disagreed, so the hand-over between them was a jump:
    /// the fan appeared to snap into being, and on the way back it sank about
    /// a third of a tile too far and vanished into the animal instead of
    /// coming to rest on its shoulder.
    ///
    /// They are one description now. Everything below is the stack's own
    /// geometry converted from avatar units into tile units, so the first and
    /// last frame of the rise *are* the resting deck rather than something
    /// that looks nearly like it.
    private var avatarSize: CGFloat { tile / Self.raisedScale }

    /// Roughly the animal, plus the name under it, so the region reaches the
    /// bottom of what a person would call "that machine".
    private var animalHeight: CGFloat { avatarSize * 1.35 }

    private func stackedX(_ index: Int) -> CGFloat {
        animalCentre - tile / 2
            + CGFloat(index) * avatarSize * MachineAgentStack.lean
    }

    /// Each card behind the top one sits very slightly higher, as it does at
    /// rest.
    private func stackedY(_ index: Int) -> CGFloat {
        rise - CGFloat(index) * avatarSize * MachineAgentStack.stagger
    }

}
