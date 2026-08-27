import SwiftUI

/// What a machine's agent token says when you point at it.
///
/// A real view rather than a `.help` string, and that is the whole reason it
/// exists. The tooltip this replaces could only be one run of plain text: the
/// session's name and what it was doing had to be flattened into the same line
/// at the same weight, several sessions became a bulleted list nobody could
/// scan, and macOS decided when it appeared. The most interesting thing on the
/// dashboard was the one thing that could not be typeset.
struct MachineAgentCard: View {
    let activity: MachineAgentActivity
    let machineName: String
    /// Share of the whole machine per session, so a session with no plan to
    /// report can still say what it is costing.
    var agentCPU: [String: Double] = [:]

    /// Four, then a count. A card that grows without limit stops being a
    /// glance and becomes a panel — and the panel already exists, one click
    /// away, which is what the last line points at.
    private static let listed = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            VStack(alignment: .leading, spacing: 9) {
                ForEach(activity.sessions.prefix(Self.listed)) { session in
                    session_(session)
                }
            }

            if activity.count > Self.listed {
                Text("and \(activity.count - Self.listed) more")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Divider().opacity(0.6)

            Text("Click for this machine\u{2019}s AI page")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(width: 268, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(nsImage: AgentProviderIcons.icon(for: activity.provider))
                .resizable()
                .scaledToFit()
                .frame(width: 15, height: 15)
                .clipShape(RoundedRectangle(cornerRadius: 3.5))

            Text(headline)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var headline: String {
        activity.count == 1
            ? "\(activity.provider.shortName) on \(machineName)"
            : "\(activity.count) \(activity.provider.shortName) sessions on \(machineName)"
    }

    /// Name over line, because they answer different questions — which piece
    /// of work this is, and what it is doing this second — and a tooltip that
    /// ran them together made you read the whole string to find either.
    @ViewBuilder
    private func session_(_ session: AgentSession) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.displayTitle)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                // Tail, not middle: a session's name is prose and its first
                // words carry it. Middle truncation is for paths, where the
                // ends are the informative part.
                .lineLimit(1)

            if let line = statusLine(for: session) {
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// What it is doing, and if it will not say, what it is costing.
    ///
    /// The fallback is the AI panel's own: a session part-way through a long
    /// tool call reports no step and no phrase for minutes at a time, and a
    /// card that went blank exactly then would look broken at the moment the
    /// work is heaviest.
    private func statusLine(for session: AgentSession) -> String? {
        if let line = session.statusLine { return line }
        guard let share = agentCPU[session.id],
              share >= AgentRowMetrics.meterFloorPercent
        else { return nil }
        return "Working — \(Int(share.rounded()))% of the machine"
    }
}
