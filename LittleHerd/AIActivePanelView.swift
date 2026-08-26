import SwiftUI

/// The panel's row, rebuilt around what a person actually looks for.
///
/// Three changes from the row it replaces. The provider's own icon leads it at
/// twenty-six points, where the old row led with a four-point state dot and
/// kept the provider's identity behind a hover. Progress is shown **in the
/// row** while the session works, rather than on hover after it stops. And the
/// state moved to a badge on the icon's corner, because a row led by a large
/// mark saying only "Claude" would have lost what that dot was carrying.
/// One running session.
struct AIActiveAgentRow: View {
    let row: AgentPanelRow
    var cpuPercent: Double?

    /// Large enough to be identified rather than merely noticed. The old row's
    /// provider icon was fifteen points and only appeared on hover; the state
    /// it led with was a four-point dot. A person glancing at this panel wants
    /// to know *which agent* is working before they want anything else.
    static let iconSize: CGFloat = 26
    /// Where the text column starts, so dividers and every line inside a row
    /// share one vertical edge.
    static let titleInset: CGFloat = iconSize + 10

    private var session: AgentSession { row.session.session }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AgentProviderBadge(
                provider: session.provider,
                state: session.state,
                size: Self.iconSize
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(session.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    // Only set when another visible row carries the same
                    // title, and then it is the difference between them.
                    // A session with no title of its own falls back to the
                    // project, the project comes from the working directory,
                    // and six sessions started in one home directory are six
                    // rows all called "Clawd" — which is the case this was
                    // written for, and which came straight back when the row
                    // was redrawn without it.
                    if let disambiguator = row.disambiguator {
                        Text(disambiguator)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                            .fixedSize()
                    }

                    Spacer(minLength: 4)

                    Text(AgentRowMetrics.compactAge(of: session.updatedAt))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                }

                if let statusLine = session.statusLine {
                    Text(statusLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                AIActiveProgressLine(
                    progress: session.progress,
                    cpuPercent: cpuPercent
                )
            }
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}

/// What the session has got through, or — when it publishes no plan — that it
/// is working at all.
///
/// The distinction is deliberate and predates this view: an agent that does
/// not publish structured progress must not be given an invented percentage.
/// So a plan gets a real bar, and everything else gets the one honest measure
/// there is, which is how much of the machine the session is using.
struct AIActiveProgressLine: View {
    let progress: AgentSessionProgress?
    var cpuPercent: Double?

    var body: some View {
        if let progress {
            HStack(spacing: 6) {
                SegmentedProgressBar(fraction: progress.fractionCompleted)

                Text("\(progress.currentStepIndex) of \(progress.totalStepCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            .padding(.top, 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "Step \(progress.currentStepIndex) of \(progress.totalStepCount)"
            )
        } else if let cpuPercent, cpuPercent >= AgentRowMetrics.meterFloorPercent {
            // No plan to report, so this says what can be measured instead of
            // guessing at a fraction. The floor is the panel's existing one: a
            // mark that is always lit is a mark nobody reads.
            Text("Working — \(Int(cpuPercent.rounded()))% of the machine")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 1)
        }
    }
}

/// Progress drawn in the same blocks the CPU, memory and disk columns use.
///
/// Borrowed on purpose. This app already teaches one way to read a quantity at
/// a glance, and a second visual language for the same idea would be a thing
/// to learn twice.
private struct SegmentedProgressBar: View {
    let fraction: Double

    private static let blockCount = 10

    var body: some View {
        let filled = ThermometerScale.filledBlockCount(for: fraction * 100)

        HStack(spacing: 2) {
            ForEach(0 ..< Self.blockCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(
                        index < filled
                            ? LittleHerdTheme.loadGreen
                            : Color.secondary.opacity(0.16)
                    )
                    .frame(height: 5)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// The provider's icon, with the state as a badge on its corner.
///
/// The state has to survive the icon growing: a row led by a large mark that
/// says only "Claude" would have lost the one thing the old four-point dot was
/// carrying. As a badge it stays readable and stops competing for the leading
/// edge.
private struct AgentProviderBadge: View {
    let provider: AgentTaskProvider
    let state: AgentSessionState
    let size: CGFloat

    var body: some View {
        Image(nsImage: AgentProviderIcons.icon(for: provider))
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5)
                    )
                    .offset(x: 2, y: 2)
            }
            .accessibilityLabel(Text(provider.displayName))
    }

    /// The same three colours the old state dot used. A waiting session is
    /// the one that needs a person, and it has to stay tellable from a
    /// working one at a glance — which is the whole reason the state did not
    /// simply disappear when the icon took the leading column.
    private var tint: Color {
        switch state {
        case .active: LittleHerdTheme.loadGreen
        case .waiting: .orange
        case .completed: .blue
        }
    }
}

struct AIActivePanelEmptyState: View {
    var machineName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Nothing running")
                .font(.subheadline.weight(.medium))

            // Says where it looked. A panel that shows only active work is
            // empty most of the time, and an empty panel that does not say
            // what it was looking for reads as a broken one.
            Text(
                machineName.map { "No agent is working on \($0) right now." }
                    ?? "No agent is working in the herd right now."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
    }
}
