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
    /// Set while the deck is on its way back down. The view stays alive until
    /// it has arrived; removing it any earlier is what made the rise look
    /// one-directional.
    var lowering: Bool = false
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
    static let settling = Animation.spring(duration: 0.34, bounce: 0.12)

    /// How long the descent takes altogether, delays included, so a caller
    /// knows when the deck may actually be taken away.
    static let descent: Duration = .milliseconds(460)

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
            ForEach(Array(fan.icons.enumerated()), id: \.offset) { index, rect in
                Image(nsImage: AgentProviderIcons.icon(for: sessions[index].provider))
                    .resizable()
                    .scaledToFit()
                    .frame(width: tile, height: tile)
                    // No card. The icon is already one.
                    .shadow(
                        color: .black.opacity(0.10 + 0.14 * spread),
                        radius: tile * 0.16,
                        y: 2
                    )
                    // Each icon starts where the deck was — stacked at the
                    // animal, smaller and lower — and travels to its place.
                    .scaleEffect(restingShare + (1 - restingShare) * spread)
                    // **Each icon carries its own weight.** They leave the
                    // animal a beat apart and settle a beat apart, which is
                    // what a handful of objects does and what one sheet of
                    // glass does not. The delay is small enough to read as
                    // heft rather than as a queue.
                    .animation(
                        reduceMotion
                            ? nil
                            : (spread == 0 ? Self.settling : Self.rising)
                                .delay(Double(index) * 0.04),
                        value: spread
                    )
                    .offset(
                        x: stackedX(index) + (rect.minX - stackedX(index)) * spread
                            + (carrying == index ? carried.width : 0),
                        y: stackedY(index) * (1 - spread)
                            + (carrying == index ? carried.height : 0)
                    )
                    // Lifted while it is in hand, and above its neighbours.
                    .scaleEffect(carrying == index ? 1.12 : 1)
                    // The resting deck draws its top card in front; so must
                    // this, or the hand-over between them restacks the icons.
                    .zIndex(
                        carrying == index
                            ? Double(sessions.count + 1)
                            : Double(sessions.count - index)
                    )
                    // Nothing while it is in hand — it belongs to the pointer
                    // then — and a heavier spring on the way home, because it
                    // is being put down rather than snapped back.
                    .animation(
                        carrying == index ? nil : .spring(duration: 0.42, bounce: 0.34),
                        value: carried
                    )
                    .gesture(carry(sessions[index], index: index, restingAt: rect.midX))
                    .help(Text(sessions[index].displayTitle))
                    .accessibilityLabel(Text(sessions[index].displayTitle))
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
        .frame(width: width, height: tile, alignment: .topLeading)
        .onAppear {
            guard !reduceMotion else { spread = 1; return }
            // No `withAnimation` here: each icon animates on its own delay,
            // above. Setting the value is enough.
            spread = 1
        }
        // Both directions, so a deck caught on its way down goes back up
        // rather than finishing its descent and having to be asked again.
        .onChange(of: lowering) { _, isLowering in
            spread = isLowering ? 0 : 1
        }
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

    private func stackedX(_ index: Int) -> CGFloat {
        animalCentre - tile / 2
            + CGFloat(index) * avatarSize * MachineAgentStack.lean
    }

    /// Each card behind the top one sits very slightly higher, as it does at
    /// rest.
    private func stackedY(_ index: Int) -> CGFloat {
        rise - CGFloat(index) * avatarSize * MachineAgentStack.stagger
    }

    /// The distance from the fan's row down to where the deck rests.
    ///
    /// The counterpart of `CPUOverviewView.fanY`, which places that row by
    /// leaving exactly this much space above the animal. The two are the same
    /// measurement seen from either end, and they have to stay that way or the
    /// deck lands somewhere other than where it lives.
    private var rise: CGFloat { avatarSize * CPUOverviewView.deckDrop }
}
