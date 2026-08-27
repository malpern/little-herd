import SwiftUI

/// The agents working on a machine, drawn as a token that sits on it.
///
/// Deliberately an object rather than an annotation, and that is a decision
/// about where this is going rather than how it looks now. Moving work between
/// machines is meant to become one of the things this app is *for*, with a
/// session eventually dragged from one column to another — and you cannot drag
/// a badge. A badge is a property of the thing it is stuck to; a token is a
/// thing in its own right that happens to be resting somewhere.
///
/// So it has a container, an edge and a shadow: the three cues that say a
/// surface is liftable rather than printed on. It is sized to be grabbed
/// comfortably rather than merely noticed, while staying plainly smaller than
/// the animal, which is the machine itself and the place a token rests.
///
/// It is not draggable yet. The interaction is deliberately not built — but
/// the shape it will need is, so that adding the gesture later does not mean
/// redrawing what people have already learned to read.
struct MachineAgentBadge: View {
    let activity: MachineAgentActivity
    let machineName: String
    /// Derived from the avatar, so the machine stays plainly primary whatever
    /// size the herd forces it to.
    var size: CGFloat = 22

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    private var iconSize: CGFloat { size * 0.62 }

    var body: some View {
        HStack(spacing: size * 0.14) {
            Image(nsImage: AgentProviderIcons.icon(for: activity.provider))
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .clipShape(RoundedRectangle(cornerRadius: iconSize * 0.22))
                // The token breathes rather than carrying a separate dot: at
                // this size a third element made a crowd, and the pulse says
                // the same thing — happening now, not remembered.
                //
                // Never below two-thirds. Half read as disabled rather than
                // busy, caught in a still frame of the render, which is the
                // one place the bottom of a pulse can be judged.
                .opacity(reduceMotion ? 1 : (isPulsing ? 0.68 : 1))
                .animation(
                    reduceMotion
                        ? nil
                        : .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                    value: isPulsing
                )

            if activity.showsCount {
                Text("\(activity.count)")
                    .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, size * 0.24)
        .padding(.vertical, size * 0.16)
        .background {
            RoundedRectangle(cornerRadius: size * 0.34, style: .continuous)
                .fill(.background.secondary)
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.34, style: .continuous)
                        .stroke(.separator, lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.12), radius: 1.5, y: 0.5)
        }
        .onAppear { isPulsing = true }
        .help(summary)
        .accessibilityLabel(Text(summary))
    }

    /// The popover's content as one string, which is what `help` can carry.
    ///
    /// Named sessions, in the order the badge ranked them, so the first line
    /// is the one that earned the mark.
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
    /// The name as a sentence uses it, which is shorter than the display name
    /// in one case and identical in the other.
    var shortName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }
}
