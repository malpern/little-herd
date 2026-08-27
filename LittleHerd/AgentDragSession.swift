import Foundation

/// The whole of a token drag, as data.
///
/// Kept out of the view bodies for the reason everything else in
/// `MachinePresentation` is: a drag has more states than it looks like — at
/// rest, in hand, over a machine that will take it, over one that will not,
/// over the machine it came from — and every one of them has to be decided
/// somewhere that can be tested. Deciding them inside a gesture handler is how
/// you get a target that stays lit after the pointer has left.
nonisolated struct AgentDragSession: Equatable, Sendable {
    /// The machine the token was picked up from.
    let origin: MachineID
    /// What is in hand.
    let activity: MachineAgentActivity
    /// Where the pointer is now, if it is over a machine at all.
    var over: MachineID?

    /// Whether releasing here would do anything.
    ///
    /// A token dropped back where it came from is a no-op rather than a
    /// refusal: nothing happened, and telling somebody off for changing their
    /// mind is a bad way to teach a gesture.
    func outcome(canAccept: (MachineID) -> Bool) -> Outcome {
        guard let over else { return .cancelled }
        if over == origin { return .cancelled }
        return canAccept(over) ? .accepted(over) : .refused(over)
    }

    enum Outcome: Equatable {
        case accepted(MachineID)
        case refused(MachineID)
        /// Released over nothing, or back where it started.
        case cancelled
    }

    /// How a given machine's pad should look while this drag is happening.
    func padState(
        for machine: MachineID,
        canAccept: (MachineID) -> Bool
    ) -> AgentPadState {
        // The machine it came from is never a target. Its pad stays quiet so
        // the token has somewhere obvious to fall back to, and so the herd
        // does not light up as though every machine were a choice.
        if machine == origin { return .idle }
        guard canAccept(machine) else { return .refused }
        return over == machine ? .targeted : .available
    }
}
