import Foundation
import Testing

@testable import LittleHerd

@Suite("Transfer strip")
struct TransferStripTests {
    private func finished(_ result: SuccessorOutcome.Result) -> TransferPhase {
        .finished(
            SuccessorOutcome(result: result, failingStep: nil, output: "")
        )
    }

    /// **A running transfer offers to stop; a finished one offers to go away.**
    /// Stopping work on another machine and clearing a row you have read are
    /// different enough that one control must not do both.
    @Test
    func theControlMatchesWhatIsPossible() {
        #expect(TransferPhase.preparing.control == .stop)
        #expect(TransferPhase.running(.agent).control == .stop)
        #expect(finished(.landed).control == .dismiss)
        #expect(finished(.cancelled).control == .dismiss)
    }

    /// A red check is not an error to be cleared away — it is work waiting on
    /// a branch — so it reads as something to look at rather than something
    /// that went wrong.
    @Test
    func aRedCheckAsksToBeRead() {
        #expect(finished(.checkFailed).tint == .wantsReading)
        #expect(finished(.agentFailed).tint == .wantsReading)
        #expect(finished(.couldNotStart).tint == .wantsReading)
        #expect(finished(.landed).tint == .landed)
    }

    /// **Cancelling is not failing.** The person who stopped it already knows,
    /// so it is neither coloured like a problem nor asks for attention.
    @Test
    func cancellingIsNotAFailure() {
        #expect(finished(.cancelled).tint == .quiet)
        #expect(!finished(.cancelled).wantsAttention)
        #expect(finished(.checkFailed).wantsAttention)
    }

    /// **The strip's line fits and the detail says what became of the work.**
    /// The two exist separately because the useful half of a one-line summary
    /// is the half that gets truncated in a 324-point window.
    @Test
    func theShortLineFitsAndTheLongOneExplains() {
        let red = finished(.checkFailed)
        #expect(red.summary.count <= 16)
        #expect(red.detail.contains("still on the branch"))
        #expect(finished(.couldNotStart).detail.contains("nothing was changed"))
        #expect(TransferPhase.running(.agent).detail.contains("working"))
    }

    /// Every phase says something a person would recognise, and none of them
    /// says the step's own name.
    @Test
    func everyPhaseHasWordsForIt() {
        let phases: [TransferPhase] = [
            .preparing,
            .running(.worktree), .running(.prompt), .running(.agent),
            .running(.verification), .running(.delivery), .running(.cleanup),
            finished(.landed), finished(.checkFailed), finished(.agentFailed),
            finished(.couldNotStart), finished(.cancelled),
        ]
        for phase in phases {
            #expect(!phase.summary.isEmpty)
            #expect(!phase.summary.contains("("))
        }
    }
}
