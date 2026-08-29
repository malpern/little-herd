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
            // **Above the card, not on it.** A bar over the art hides the one
            // thing that says whose work this is, and a spinner said only
            // "something is happening" — which you already knew, because you
            // just dropped it there. This says how far.
            .overlay(alignment: .top) { bar }
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
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.black.opacity(0.22))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(size * 0.06, size * 0.86 * fraction))
            }
            .frame(width: size * 0.86, height: max(3, size * 0.075))
            .offset(y: -size * 0.30)
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
