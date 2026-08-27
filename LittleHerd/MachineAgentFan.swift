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

    /// Clear space, and enough of it to read as separate objects rather than a
    /// strip. A quarter of a tile is the smallest gap that still does.
    private var gap: CGFloat { tile * 0.26 }

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
                    .shadow(color: .black.opacity(0.24), radius: tile * 0.16, y: 2)
                    .offset(x: rect.minX)
                    .help(Text(sessions[index].displayTitle))
                    .accessibilityLabel(Text(sessions[index].displayTitle))
            }

            if let overflow = fan.overflow {
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
    }
}
