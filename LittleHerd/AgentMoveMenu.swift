import Foundation

/// "Move to…", listing every machine and saying why each one can or cannot.
///
/// **The menu can explain a refusal and the drag cannot.** Dropping an agent
/// on a machine that lacks the checkout simply does not take — the animal
/// never lights, nothing happens, and the honest reading of that silence is
/// "transfers must be switched off". Here the machine is listed, greyed, with
/// the reason beside it. Same rule, same answer, said out loud.
///
/// It is also the only way to move work without a steady hand on a
/// twenty-point icon, and the only way to reach a machine that has scrolled
/// out of view.
nonisolated enum AgentMoveMenu {
    /// Why a machine will not take this work, in a few words.
    static func reason(_ eligibility: DestinationEligibility) -> String? {
        switch eligibility {
        case .eligible: nil
        case .excluded: "not allowed to host work"
        case .unknown: "not reachable"
        case .noAgent: "no agent installed"
        case .noCheckout(let repository): "no checkout of \(repository)"
        case .signedOut(_, let reason): reason
        }
    }

    static func items(
        moving session: AgentSession,
        from origin: MachineID,
        in herd: [DestinationAccount],
        requiresApproval: Bool,
        name: (MachineID) -> String,
        move: @escaping (MachineID) -> Void
    ) -> [AppKitMenuItem] {
        let activity = MachineAgentActivity(
            provider: session.provider,
            sessions: [session]
        )

        return herd
            .filter { $0.machine != origin }
            .map { account in
                let eligibility = AgentDropEligibility.eligibility(
                    of: account.machine,
                    carrying: activity,
                    from: origin,
                    in: herd,
                    requiresApproval: requiresApproval
                )
                let why = reason(eligibility)
                return AppKitMenuItem(
                    // The reason rides in the title because a menu row has
                    // nowhere else to put it.
                    title: why.map { "\(name(account.machine)) — \($0)" }
                        ?? name(account.machine),
                    isEnabled: why == nil,
                    action: why == nil
                        ? { move(account.machine) }
                        : nil
                )
            }
    }
}
