import SwiftUI

/// The mark under a machine's name that says an agent is working on it.
///
/// Deliberately a badge and not another header. What was removed from these
/// panels was a header that rewrote itself as the pointer swept across —
/// unpointable, unreadable on purpose, invisible from the keyboard. This is
/// the opposite shape: a small target you aim at, which answers about itself
/// and takes nothing else off the screen while it does.
struct MachineAgentBadge: View {
    let activity: MachineAgentActivity
    let machineName: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    private static let iconSize: CGFloat = 15

    var body: some View {
        Image(nsImage: AgentProviderIcons.icon(for: activity.provider))
            .resizable()
            .scaledToFit()
            .frame(width: Self.iconSize, height: Self.iconSize)
            .clipShape(RoundedRectangle(cornerRadius: Self.iconSize * 0.22))
            // The work, not the state. A session that is running is doing
            // something now, and a mark that only sat there would say the same
            // as one on a machine that had finished an hour ago.
            .overlay(alignment: .bottomLeading) {
                Circle()
                    .fill(LittleHerdTheme.loadGreen)
                    .frame(width: 5, height: 5)
                    .opacity(reduceMotion ? 1 : (isPulsing ? 0.35 : 1))
                    .offset(x: -1, y: 1)
                    .animation(
                        reduceMotion
                            ? nil
                            : .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                        value: isPulsing
                    )
            }
            .overlay(alignment: .topTrailing) {
                if activity.showsCount {
                    Text("\(activity.count)")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor))
                        .overlay(
                            Capsule()
                                .stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1)
                        )
                        .offset(x: 5, y: -4)
                }
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
