import SwiftUI

/// One agent token, resting on a machine's pad.
///
/// Deliberately an object rather than an annotation. Moving work between
/// machines is meant to become one of the things this app is *for*, with a
/// session dragged from one machine onto another — and you cannot drag a
/// badge. A badge is a property of the thing it is stuck to; a token is a
/// thing in its own right that happens to be resting somewhere.
///
/// **One shape, always.** An earlier version grew a capsule when it carried a
/// count and stayed a square when it did not, so the same object appeared in
/// two silhouettes depending on data — which is exactly the thing a person
/// learns to recognise, changing under them. The tile is a fixed square and
/// the count is a mark on its corner, the way a tile with a notification is
/// still that tile.
struct MachineAgentToken: View {
    let activity: MachineAgentActivity
    let machineName: String
    var size: CGFloat = 22
    /// How this token is being handled right now.
    var lift: TokenLift = .resting

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    enum TokenLift: Equatable {
        /// Sitting on its pad.
        case resting
        /// The pointer is over it and it could be picked up.
        case ready
        /// In hand, following the pointer.
        case carried
    }

    private var iconSize: CGFloat { size * 0.66 }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(.background)
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .stroke(.separator, lineWidth: 0.5)
            }
            .overlay {
                Image(nsImage: AgentProviderIcons.icon(for: activity.provider))
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: iconSize * 0.22))
                    // The token breathes rather than carrying a separate dot:
                    // at this size a third element made a crowd, and the pulse
                    // says the same thing — happening now, not remembered.
                    //
                    // Never below two thirds. Half read as disabled rather
                    // than busy, which only a still frame of a pulse showed.
                    .opacity(pulseOpacity)
                    .animation(pulse, value: isPulsing)
            }
            .frame(width: size, height: size)
            .overlay(alignment: .topTrailing) { countMark }
            // Lifting is drawn with shadow and scale rather than colour: it is
            // the same object throughout, held at different heights.
            .scaleEffect(scale)
            .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: shadowY)
            .animation(.spring(duration: 0.22), value: lift)
            .onAppear { isPulsing = true }
            // No `.help`. A tooltip and a hover card are two answers to one
            // gesture, and macOS would decide which arrived first.
            .accessibilityLabel(Text(summary))
            .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var countMark: some View {
        if activity.showsCount {
            Text("\(activity.count)")
                .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: size * 0.46, height: size * 0.46)
                .background(Circle().fill(Color.accentColor))
                .overlay(
                    Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1)
                )
                .offset(x: size * 0.18, y: -size * 0.18)
        }
    }

    private var scale: CGFloat {
        switch lift {
        case .resting: 1
        case .ready: 1.08
        case .carried: 1.18
        }
    }

    private var shadowOpacity: Double {
        switch lift {
        case .resting: 0.12
        case .ready: 0.2
        case .carried: 0.32
        }
    }

    private var shadowRadius: CGFloat {
        switch lift {
        case .resting: 1.5
        case .ready: 3
        case .carried: 7
        }
    }

    private var shadowY: CGFloat {
        switch lift {
        case .resting: 0.5
        case .ready: 1.5
        case .carried: 4
        }
    }

    private var pulseOpacity: Double {
        guard !reduceMotion, lift != .carried else { return 1 }
        return isPulsing ? 0.68 : 1
    }

    private var pulse: Animation? {
        guard !reduceMotion, lift != .carried else { return nil }
        return .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
    }

    /// What the token says when you point at it.
    ///
    /// Named sessions in the order the token ranked them, so the first line is
    /// the one that earned the mark.
    private var summary: String {
        let names = activity.sessions.prefix(4).map(\.displayTitle)
        let more = activity.count - names.count
        var lines = [
            activity.count == 1
                ? "\(activity.provider.shortName) is working on \(machineName)."
                : "\(activity.count) \(activity.provider.shortName) sessions are working on \(machineName).",
        ]
        lines.append(contentsOf: names.map { "• \($0)" })
        if more > 0 { lines.append("• and \(more) more") }
        return lines.joined(separator: "\n")
    }
}

extension AgentTaskProvider {
    /// The name as a sentence uses it.
    var shortName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }
}
