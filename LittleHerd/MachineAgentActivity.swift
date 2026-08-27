import Foundation

/// What a machine's AI work looks like from the overview: which agent, how
/// many sessions, and what they are called.
///
/// This is the CPU screen becoming a dashboard rather than four bars. A
/// machine that is busy tells you *what* is making it busy, without opening
/// anything — and stops telling you the moment it is not.
nonisolated struct MachineAgentActivity: Equatable, Sendable {
    /// The provider to draw, which is the one doing the most work. A machine
    /// running both gets the busier one's mark and a count that covers both:
    /// two icons in a thirty-point column would be two things to squint at.
    let provider: AgentTaskProvider
    /// Every session behind the badge, busiest first, so the popover reads in
    /// the order the badge was decided.
    let sessions: [AgentSession]

    var count: Int { sessions.count }

    /// A badge is worth drawing for a second session and misleading for the
    /// first: a "1" on every working machine is a number nobody reads.
    var showsCount: Bool { count > 1 }
}

nonisolated enum MachineAgentActivityReader {
    /// - Parameters:
    ///   - sessions: this machine's sessions, in any order.
    ///   - cpuBySession: share of the *whole machine* per session id, where
    ///     two samples exist. Used to rank, never to exclude.
    ///
    /// **Liveness is the signal; CPU only decides the order.** The first
    /// instinct was to require a session to be burning the panel's usual two
    /// percent of a machine before it earned a mark, and that would have
    /// hidden precisely the work this exists to surface. A session running a
    /// long tool call — a test suite, a build — is nearly idle *as a process*
    /// while a compiler underneath it saturates a core, and the reading needs
    /// two samples so it arrives seconds late even when it is coming.
    ///
    /// `active` is now a strict claim rather than a guess: a process that is
    /// registered and answers `kill -0`, part-way through a turn. That is
    /// already the question the badge is asking. CPU is left to rank the
    /// sessions, so the busiest one's provider is the mark and the popover
    /// reads in the order the badge was decided.
    static func activity(
        for sessions: [AgentSession],
        cpuBySession: [String: Double]
    ) -> MachineAgentActivity? {
        let working = sessions
            .filter { $0.state == .active }
            .sorted { left, right in
                let leftShare = cpuBySession[left.id] ?? 0
                let rightShare = cpuBySession[right.id] ?? 0
                if leftShare == rightShare {
                    return left.updatedAt > right.updatedAt
                }
                return leftShare > rightShare
            }

        guard let busiest = working.first else { return nil }
        return MachineAgentActivity(
            provider: busiest.provider,
            sessions: working
        )
    }
}
