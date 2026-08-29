import AppKit
import SwiftUI

/// What is happening to a card that has been dropped on another machine.
nonisolated enum TransitState: Equatable {
    case working
    case succeeded
    case failed
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
    @State private var spinning = false

    var body: some View {
        Image(nsImage: AgentProviderIcons.icon(for: session.provider))
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.26), radius: size * 0.16, y: 2)
            .overlay { mark }
            .accessibilityLabel(Text(label))
    }

    @ViewBuilder
    private var mark: some View {
        switch state {
        case .working:
            // Over the card rather than beside it: the card is the subject,
            // and a spinner next to it would read as something else's.
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(
                    Color.white,
                    style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round)
                )
                .frame(width: size * 0.52, height: size * 0.52)
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(
                    reduceMotion
                        ? nil
                        : .linear(duration: 0.9).repeatForever(autoreverses: false),
                    value: spinning
                )
                .shadow(color: .black.opacity(0.5), radius: 2)
                .onAppear { spinning = true }
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

    private var label: String {
        switch state {
        case .working: "\(session.displayTitle), moving"
        case .succeeded: "\(session.displayTitle), moved"
        case .failed: "\(session.displayTitle), did not move"
        }
    }
}
