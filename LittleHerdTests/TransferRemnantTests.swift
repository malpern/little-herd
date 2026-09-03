import Foundation
import Testing

@testable import LittleHerd

/// What a failed transfer left behind, and whether the interface says so.
///
/// The seven-step order — quiesce, summarise, verify, and only then retire the
/// source — is a safety property, and it was only half of one while a
/// half-finished move was visible in a log and nowhere else. The departure
/// builds a branch and pushes it *before* the destination is asked to do
/// anything, so most ways of failing leave the work sitting on a branch.
///
/// **The bug this suite is written against was a sentence.** `couldNotStart`
/// read "It never started, so nothing was changed anywhere" for all three of
/// its causes, one of which is a departure that fully succeeded — and the diff
/// window prints that sentence directly above the name of the branch holding
/// the work. It told you nothing had happened, above the evidence that it had.
struct TransferRemnantTests {
    // MARK: - Where it stopped decides what survives

    /// The branch is created by the last command of the capture step, so
    /// anything that fails at or before it created nothing at all. This is the
    /// only genuinely clean failure a transfer has.
    @Test
    func afailureBeforeTheBranchExistsLeavesNothing() {
        #expect(TransferPilot.Failure.departure(.brief, "").remnant == .nothing)
        #expect(TransferPilot.Failure.departure(.capture, "").remnant == .nothing)
    }

    /// `git branch -f` is the end of the capture chain and the push is the
    /// step after it, so a push that fails is a branch that exists and went
    /// nowhere. Whoever ran this has their work gathered up on one machine and
    /// no way to know it from a log.
    @Test
    func aFailedPushLeavesTheBranchOnTheSource() {
        #expect(TransferPilot.Failure.departure(.push, "").remnant == .localBranch)
    }

    /// It pushed and then said nothing a sha could be read out of. The branch
    /// is on the remote; the only thing missing is our knowledge of it, which
    /// is not the same as the work being missing.
    @Test
    func aPushWithNoShaStillPushed() {
        #expect(TransferPilot.Failure.noCommitReported.remnant == .pushedBranch)
    }

    /// A refusal comes from planning the arrival, which only happens once the
    /// departure has completely succeeded — so this is the case that used to
    /// claim nothing had been changed anywhere.
    @Test
    func aRefusedDestinationIsAFullySucceededDeparture() {
        #expect(
            TransferPilot.Failure.refused(.agentNotRecognised).remnant == .pushedBranch
        )
    }

    /// Everything the executor produces is past the push by definition — the
    /// run does not begin until a commit exists — so the default is the one
    /// that is always right for it.
    @Test
    func anOutcomeFromTheRunIsAlwaysPastThePush() {
        let outcome = SuccessorOutcome(
            result: .agentFailed,
            failingStep: .agent,
            output: ""
        )
        #expect(outcome.remnant == .pushedBranch)
    }

    // MARK: - And the sentence says it

    /// **The regression this suite exists for.** Three different states shared
    /// one sentence and it was the sentence for the rarest of them.
    @Test
    func couldNotStartSaysWhichOfItsThreeStatesThisWas() {
        func detail(_ remnant: TransferRemnant) -> String {
            TransferPhase.finished(
                SuccessorOutcome(
                    result: .couldNotStart,
                    failingStep: nil,
                    output: "",
                    remnant: remnant
                )
            ).detail
        }

        #expect(detail(.nothing) == "It never started, so nothing was changed anywhere.")

        let local = detail(.localBranch)
        #expect(local != detail(.nothing), "a branch exists and this says otherwise")
        #expect(local.contains("branch"))
        #expect(!local.contains("nothing was changed anywhere"))

        let pushed = detail(.pushedBranch)
        #expect(pushed != detail(.nothing))
        #expect(pushed.contains("branch"))
        #expect(!pushed.contains("nothing was changed anywhere"))
    }

    /// The other sentence that was false. The departure pushes the branch
    /// before the agent is asked for anything, so "Nothing was pushed" sent a
    /// reader away from work that was sitting on the remote.
    @Test
    func anAgentThatStoppedDoesNotClaimNothingWasPushed() {
        let detail = TransferPhase.finished(
            SuccessorOutcome(result: .agentFailed, failingStep: .agent, output: "")
        ).detail

        #expect(!detail.contains("Nothing was pushed"))
        #expect(detail.contains("branch"))
    }

    // MARK: - What the window draws

    /// The branch name is selectable text somebody will paste into a shell, so
    /// drawing it is a promise that it resolves. It must not appear for the
    /// one failure that made no branch.
    @Test
    func theBranchNameIsDrawnOnlyWhenThereIsABranch() {
        func left(_ remnant: TransferRemnant) -> Bool {
            TransferPhase.finished(
                SuccessorOutcome(
                    result: .couldNotStart,
                    failingStep: nil,
                    output: "",
                    remnant: remnant
                )
            ).leftABranch
        }

        #expect(left(.nothing) == false)
        #expect(left(.localBranch))
        #expect(left(.pushedBranch))
    }

    /// **A running transfer always has a branch**, because the run does not
    /// begin until the push has reported a commit — the same fact the
    /// `remnant` default rests on. Preparing is the departure itself, which is
    /// what builds the branch, so during it there may not be one yet.
    @Test
    func aRunningTransferIsAlwaysPastThePush() {
        #expect(TransferPhase.preparing.leftABranch == false)
        #expect(TransferPhase.running(.worktree).leftABranch)
        #expect(TransferPhase.running(.agent).leftABranch)
        #expect(TransferPhase.running(.cleanup).leftABranch)
    }

    /// A landed transfer has one too, and the window is mostly opened on those.
    @Test
    func aLandedTransferLeavesItsBranch() {
        let landed = TransferPhase.finished(
            SuccessorOutcome(result: .landed, failingStep: nil, output: "")
        )
        #expect(landed.leftABranch)
        #expect(landed.detail.contains("not merged"))
    }
}
