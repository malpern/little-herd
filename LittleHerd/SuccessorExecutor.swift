import Foundation

/// How a run ended, in the terms a person would ask about it.
///
/// The distinction that matters is *which* step failed. "The agent gave up"
/// and "the agent finished and the tests went red" are the same exit status
/// and completely different news: one is a transfer that did not happen, the
/// other is work waiting on a branch for somebody to read.
nonisolated struct SuccessorOutcome: Equatable {
    enum Result: Equatable {
        /// Everything ran and the work is on the branch.
        case landed
        /// The agent finished; the check did not pass. The branch still holds
        /// the edits, deliberately — they are the useful part of a red run.
        case checkFailed
        /// The agent itself failed or refused.
        case agentFailed
        /// Never got as far as the agent.
        ///
        /// **This does not mean nothing happened**, and saying so was a real
        /// defect: the departure builds a branch and pushes it before the
        /// destination is asked to do anything, so a run that dies on the way
        /// can still have left the work on a branch. What survives is
        /// `remnant`, and it is the thing a person actually needs.
        case couldNotStart
        /// Called off part-way.
        case cancelled
    }

    let result: Result
    /// The last thing that ran, and whatever it said.
    let failingStep: SuccessorRun.Step.Purpose?
    let output: String
    /// What is left on the machine the work came from.
    ///
    /// Defaulted to `.pushedBranch` because every outcome the executor
    /// produces is one the departure already got past — the run does not begin
    /// until a commit has been pushed. Only the failures that happen *before*
    /// that, in `MonitorModel.beginTransfer`, have anything else to say, and
    /// they say it explicitly.
    var remnant: TransferRemnant = .pushedBranch
}

/// What a transfer leaves behind on the machine it was leaving.
///
/// The order in `SuccessorRun` is a safety property — quiesce, summarise,
/// verify, and only then retire the source — and it was only half of one while
/// the interface could not say where a half-finished move had got to. The diff
/// window prints this above the branch name, which is where the contradiction
/// showed: it read "nothing was changed anywhere" directly above the name of
/// the branch holding the work.
///
/// The source session is never touched by any of this. Nothing retires it, so
/// "leave you where you started" holds for the session itself; what varies is
/// how much of the branch exists.
nonisolated enum TransferRemnant: Equatable, Sendable {
    /// Nothing was created anywhere. The only genuinely clean failure.
    case nothing
    /// The branch was built on the source and never pushed, so the work is
    /// gathered up and sitting on one machine.
    case localBranch
    /// The branch is on the source and on the remote, which is where every
    /// failure from the destination's side leaves things.
    case pushedBranch
}

/// Runs the steps and says how it went.
///
/// The command runner is a parameter rather than a call to `SSHCommandRunner`
/// because the interesting behaviour here is *ordering under failure* — what
/// still runs after something goes wrong — and that cannot be asserted against
/// a real machine without breaking one on purpose.
nonisolated enum SuccessorExecutor {
    struct StepOutput: Equatable, Sendable {
        let text: String
        let succeeded: Bool
    }

    typealias Run = @Sendable (SuccessorRun.Step) async -> StepOutput

    /// **Cleanup runs whatever happened, including cancellation.** A fatal
    /// failure abandons the rest of the work, but the worktree it left behind
    /// on somebody else's machine is not part of the work — it is litter, and
    /// a failed run is exactly when it would otherwise be forgotten.
    static func execute(
        steps: [SuccessorRun.Step],
        run: Run,
        progress: @Sendable (SuccessorRun.Step.Purpose) async -> Void = { _ in }
    ) async -> SuccessorOutcome {
        var transcript: [String] = []
        var failure: (SuccessorRun.Step.Purpose, String)?
        var wasCancelled = false

        for step in steps where step.isFatal {
            if Task.isCancelled {
                wasCancelled = true
                break
            }
            if failure != nil { break }

            await progress(step.purpose)
            let output = await run(step)
            if !output.text.isEmpty { transcript.append(output.text) }
            if !output.succeeded { failure = (step.purpose, output.text) }
        }

        // Then everything that is not fatal — cleanup — regardless.
        for step in steps where !step.isFatal {
            await progress(step.purpose)
            let output = await run(step)
            if !output.text.isEmpty { transcript.append(output.text) }
        }

        let joined = transcript.joined(separator: "\n")

        if wasCancelled {
            return SuccessorOutcome(
                result: .cancelled,
                failingStep: nil,
                output: joined
            )
        }

        guard let failure else {
            return SuccessorOutcome(
                result: .landed,
                failingStep: nil,
                output: joined
            )
        }

        let result: SuccessorOutcome.Result = switch failure.0 {
        case .worktree, .prompt: .couldNotStart
        case .agent: .agentFailed
        // A failed push is not a failed check, but it leaves you in the same
        // place — edits made, nothing delivered — so it reads as one rather
        // than inventing a fifth word for it.
        case .verification, .delivery: .checkFailed
        case .cleanup: .landed
        }

        return SuccessorOutcome(
            result: result,
            failingStep: failure.0,
            output: joined
        )
    }
}
