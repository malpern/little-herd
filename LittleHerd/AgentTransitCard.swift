import AppKit
import SwiftUI

/// What is happening to a card that has been dropped on another machine.
nonisolated enum TransitState: Equatable {
    /// Under way, and this far along. See `TransferPhase.progress`.
    case working(Double)
    case succeeded
    case failed

    var isWorking: Bool {
        if case .working = self { return true }
        return false
    }
}

/// A sound for an outcome nobody may be watching.
///
/// **System sounds rather than bundled ones.** They obey the user's alert
/// volume and their "play user interface sound effects" setting, which a
/// bundled file played through `AVAudioPlayer` would not — and a transfer
/// finishing is exactly the kind of thing somebody may have deliberately
/// silenced.
nonisolated enum TransitSound {
    static func play(_ state: TransitState) {
        let name = switch state {
        case .succeeded: "Glass"
        case .failed: "Basso"
        case .working: ""
        }
        guard !name.isEmpty else { return }
        NSSound(named: name)?.play()
    }
}

/// The card in transit: the one that was dragged, drawn while it is neither in
/// the deck it left nor in the deck it is joining.
///
/// It exists because the journey is the feedback. A card that springs home the
/// instant it is released has said nothing about whether the work moved, and a
/// row of text somewhere else is not the same as watching the thing you just
/// dragged sit on the machine you dragged it to.
struct AgentTransitCard: View {
    let session: AgentSession
    let state: TransitState
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(nsImage: AgentProviderIcons.icon(for: session.provider))
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.26), radius: size * 0.16, y: 2)
            .overlay { mark }
            // **Across the foot of the card, the way the Dock shows a
            // download.** Floating it above the card put it over whatever
            // happened to be behind — on this screen, the thermometer blocks —
            // where a short coloured bar among other short coloured bars reads
            // as one more segment of the chart. Inside the card's own bounds
            // it cannot collide with anything, it is an idiom people already
            // know from the Dock, and it costs only a sliver of the art.
            .overlay(alignment: .bottom) { bar }
            .accessibilityLabel(Text(label))
    }

    @ViewBuilder
    private var mark: some View {
        switch state {
        case .working:
            EmptyView()
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.56, height: size * 0.56)
                .foregroundStyle(.white, .green)
                .transition(.scale(scale: 0.4).combined(with: .opacity))
        case .failed:
            EmptyView()
        }
    }

    @ViewBuilder
    private var bar: some View {
        if case .working(let fraction) = state {
            let width = size * 0.76
            ZStack(alignment: .leading) {
                // A dark track with a pale edge, so it holds up over a light
                // icon and a dark one alike — these are application icons and
                // this app cannot choose their colour.
                Capsule()
                    .fill(.black.opacity(0.45))
                    .overlay(
                        Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.5)
                    )
                Capsule()
                    .fill(Color.accentColor)
                    .padding(0.5)
                    .frame(width: max(size * 0.08, width * fraction))
            }
            .frame(width: width, height: max(3, size * 0.085))
            // Clear of the corner radius: sat flush to the bottom the track
            // was clipped at both ends by the card's own rounding.
            .offset(y: -size * 0.24)
            // Eased rather than sprung: it never goes backwards, and a bar
            // that overshoots its own fill reads as a mistake.
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.45),
                value: fraction
            )
            .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
        }
    }

    private var label: String {
        switch state {
        case .working(let fraction):
            "\(session.displayTitle), moving, \(Int(fraction * 100)) per cent"
        case .succeeded: "\(session.displayTitle), moved"
        case .failed: "\(session.displayTitle), did not move"
        }
    }
}
