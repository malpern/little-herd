import Foundation

/// Whether a session can be sent somewhere else, and what has to happen first.
///
/// The destination side of this question is `AgentDropEligibility`. This is
/// the source side, and it is a different question: not "could that machine
/// run this" but "can this be picked up at all without breaking it".
nonisolated enum TransferEligibility {
    enum Verdict: Equatable {
        /// It is holding for a person. Nothing is in flight, so it can be
        /// asked to write down where it got to and stopped cleanly.
        case ready
        /// Mid-turn. The transfer waits for it to reach the end of what it is
        /// doing, and only then asks.
        case afterItFinishes
        case refused(Refusal)
    }

    enum Refusal: Equatable {
        /// Finished. There is no work in flight to move, and a transfer would
        /// be starting something new somewhere else while pretending to
        /// continue something.
        case nothingInFlight
        /// **Stopped inside a tool call and not coming back.** This is the one
        /// worth refusing loudly. A stalled session cannot be asked where it
        /// got to — that is what stalled means — so any brief written for it
        /// would be assembled from the outside and presented as its own
        /// account of itself. Its working tree may also be half-written by
        /// whatever was interrupted, and that would travel on the branch as
        /// though it were finished work.
        case cannotBeAsked
        /// No checkout, so nothing to carry it on. A branch is how work
        /// travels here; without a repository there is no transfer to make.
        case noRepository
    }

    static func verdict(
        for session: AgentSession,
        hasRepository: Bool
    ) -> Verdict {
        guard hasRepository else { return .refused(.noRepository) }

        return switch session.state {
        case .waiting: .ready
        // Interrupting mid-turn can leave a half-written file or a git
        // operation part-done, and the state already flips to `waiting` at the
        // turn boundary — so waiting for it is both safer and cheap, rather
        // than refusing work that will be movable in a minute.
        case .active: .afterItFinishes
        case .completed: .refused(.nothingInFlight)
        case .stalled: .refused(.cannotBeAsked)
        }
    }

    /// What to tell somebody who has just dropped one of these.
    static func explanation(for refusal: Refusal) -> String {
        switch refusal {
        case .nothingInFlight:
            "This one has finished — there’s nothing in flight to move."
        case .cannotBeAsked:
            "This one stopped part-way and can’t say where it got to."
        case .noRepository:
            "This one isn’t in a repository, so there’s no branch to send."
        }
    }
}
