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
    @State private var carrying: Int?
    @State private var carried: CGSize = .zero

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
                    .offset(
                        x: stackedX(index) + (rect.minX - stackedX(index)) * spread
                            + (carrying == index ? carried.width : 0),
                        y: rise * (1 - spread) + (carrying == index ? carried.height : 0)
                    )
                    // Lifted while it is in hand, and above its neighbours.
                    .scaleEffect(carrying == index ? 1.12 : 1)
                    .zIndex(carrying == index ? 1 : 0)
                    .animation(carrying == index ? nil : .spring(duration: 0.3), value: carried)
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
            withAnimation(.spring(duration: 0.34, bounce: 0.22)) { spread = 1 }
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
    private func stackedX(_ index: Int) -> CGFloat {
        animalCentre - tile / 2 + CGFloat(index) * tile * 0.22
    }

    /// How far below its place each icon starts — roughly the distance from
    /// the fan's row down to the animal's back.
    private var rise: CGFloat { tile * 1.15 }
}
