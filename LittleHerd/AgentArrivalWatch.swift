import Foundation

/// One session that has just started, and where.
nonisolated struct AgentArrival: Equatable, Sendable {
    let machine: MachineID
    let session: String
}

/// An arrival that has been noticed but not yet shown to anybody.
///
/// Sessions are started from a terminal, so the dashboard is virtually never
/// the focused window at the instant one begins — an announcement that could
/// only fire at that exact moment fired essentially never, which is how the
/// first version of this shipped and looked like nothing at all. The arrival
/// waits instead, and is shown when the person next looks at the herd.
nonisolated struct AgentAnnouncement: Equatable, Sendable {
    let arrival: AgentArrival
    let noticedAt: Date

    /// After this, "just started" is a lie and the card would be claiming
    /// something happened now that happened while you were away. Long enough
    /// to cover starting a session and switching windows to watch it; short
    /// enough that coming back from lunch says nothing.
    static let staleAfter: TimeInterval = 45

    func isFresh(at now: Date) -> Bool {
        now.timeIntervalSince(noticedAt) < Self.staleAfter
    }
}

/// Notices when a session appears, so the herd can say what started rather than
/// only that something did.
///
/// Kept out of the view because every rule in it is a judgement that would
/// otherwise be invisible inside an `onChange`, and each one is the difference
/// between an announcement and a nuisance.
nonisolated struct AgentArrivalWatch: Equatable, Sendable {
    /// Every session id ever seen, and **never pruned**. A session that drops
    /// out of a sample and comes back has not started — the probe blinked —
    /// and announcing it again would be the app reporting its own noise. Ids
    /// are short and a herd produces a few hundred in a long day.
    private var seen: Set<String> = []
    /// Whether anything has been observed at all.
    private var hasSeeded = false
    private var lastAnnounced: Date?

    /// The minimum gap between announcements. Four sessions starting together
    /// is one event to a person, not four.
    var quietPeriod: TimeInterval = 8

    /// - Parameters:
    ///   - machines: each machine's sessions, in the order the herd draws
    ///     them, so the leftmost new session is the one announced.
    ///   - now: passed in rather than read, so the quiet period can be tested
    ///     without waiting through it.
    ///
    /// **The first call announces nothing.** It records what is already
    /// running and returns nil, because everything is new to a process that
    /// has just started — without this, opening Little Herd would announce the
    /// entire herd at once, which is precisely the noise this is meant to
    /// avoid.
    ///
    /// **Sessions passed over during the quiet period are dropped, not
    /// queued.** A queue would deliver an announcement about something that
    /// started half a minute ago as though it had just happened, and the whole
    /// value of this is that it is about *now*.
    mutating func arrival(
        in machines: [(machine: MachineID, sessions: [AgentSession])],
        at now: Date
    ) -> AgentArrival? {
        let running = machines.map { machine in
            (machine.machine, machine.sessions.filter { $0.state == .active })
        }

        guard hasSeeded else {
            hasSeeded = true
            for (_, sessions) in running { seen.formUnion(sessions.map(\.id)) }
            return nil
        }

        var arrival: AgentArrival?
        for (machine, sessions) in running {
            for session in sessions where !seen.contains(session.id) {
                seen.insert(session.id)
                if arrival == nil {
                    arrival = AgentArrival(machine: machine, session: session.id)
                }
            }
        }

        guard let arrival else { return nil }
        if let lastAnnounced, now.timeIntervalSince(lastAnnounced) < quietPeriod {
            return nil
        }
        lastAnnounced = now
        return arrival
    }
}
