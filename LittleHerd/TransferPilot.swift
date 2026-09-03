import Foundation

/// Joins the two halves: ask the source for a branch, then hand the
/// destination the sha it must find.
///
/// Only one value crosses between them, and it is the whole reason the halves
/// can be built and tested apart — the source produces a commit, the
/// destination is pinned to it, and nothing else is shared.
nonisolated enum TransferPilot {
    enum Failure: Equatable, Error {
        /// The source could not produce a branch. Carries whatever the step
        /// said, because "couldn't prepare it" on its own is not something
        /// anybody can act on.
        case departure(TransferDeparture.Step.Purpose, String)
        /// It pushed, and then said nothing a sha could be read out of.
        case noCommitReported
        /// The destination was refused before anything ran there.
        case refused(SuccessorLaunch.Refusal)

        /// What this failure left on the source.
        ///
        /// Derived from *where* it stopped rather than recorded as it went,
        /// because the departure's order is what decides it and that order is
        /// right here: the branch is created at the end of `capture`, so a
        /// failure at or before that point created nothing, and everything
        /// after it is looking at a branch that exists.
        var remnant: TransferRemnant {
            switch self {
            case .departure(.brief, _), .departure(.capture, _):
                .nothing
            // `branch -f` is the last thing the capture chain does, so a push
            // that fails is a branch that exists and went nowhere.
            case .departure(.push, _):
                .localBranch
            // Cleanup is not fatal and cannot produce a failure here, but it
            // runs after the push either way, so the branch is out.
            case .departure(.cleanup, _):
                .pushedBranch
            // It pushed and then said nothing a sha could be read from — the
            // branch is on the remote, and only our knowledge of it is missing.
            case .noCommitReported:
                .pushedBranch
            // A refusal comes from planning the arrival, which only happens
            // once the departure has fully succeeded.
            case .refused:
                .pushedBranch
            }
        }
    }

    /// The sha a push reported, or nothing.
    ///
    /// Read from the end, and only a full sha is accepted. `git push` writes
    /// its progress to the same stream — branch names, remote counting
    /// objects, a `->` line — and a loose match against that will happily find
    /// something that looks close enough. `rev-parse` is the last thing the
    /// step runs, so the last line that *is* a sha is the answer.
    static func commit(inPushOutput output: String) -> String? {
        output
            .split(whereSeparator: \.isNewline)
            .reversed()
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first {
                $0.count == 40 && $0.allSatisfy(\.isHexDigit)
            }
    }

    /// Runs the departure and returns the commit it pushed.
    ///
    /// The ordering rule is the successor's — fatal steps stop the run,
    /// cleanup happens regardless — but this is not `SuccessorExecutor`
    /// because it needs something that one deliberately does not provide: the
    /// output of one particular step, kept apart from the transcript.
    static func depart(
        steps: [TransferDeparture.Step],
        run: @Sendable (TransferDeparture.Step) async -> SuccessorExecutor.StepOutput
    ) async -> Result<String, Failure> {
        var pushOutput = ""
        var failure: Failure?

        for step in steps where step.isFatal {
            if failure != nil { break }
            let output = await run(step)
            if step.purpose == .push { pushOutput = output.text }
            if !output.succeeded {
                failure = .departure(step.purpose, output.text)
            }
        }

        for step in steps where !step.isFatal {
            _ = await run(step)
        }

        if let failure { return .failure(failure) }
        guard let commit = commit(inPushOutput: pushOutput) else {
            return .failure(.noCommitReported)
        }
        return .success(commit)
    }

    /// And what the destination is then asked to do, pinned to that commit.
    ///
    /// A pure function on purpose: given a sha, the whole of the destination
    /// side is decided without touching a machine, so the refusals can be
    /// asserted rather than provoked.
    static func arrival(
        commit: String,
        briefPath: String,
        briefText: String,
        branch: String,
        repository: String,
        scratchRoot: String,
        provider: AgentTaskProvider,
        reportedAgentPath: String,
        check: RepositoryCheck,
        commitMessage: String
    ) -> Result<[SuccessorRun.Step], Failure> {
        let plan = SuccessorLaunch.plan(
            briefPath: briefPath,
            briefText: briefText,
            branch: branch,
            repository: repository,
            scratchRoot: scratchRoot,
            provider: provider,
            reportedAgentPath: reportedAgentPath,
            expectedCommit: commit
        )

        switch plan {
        case .failure(let refusal):
            return .failure(.refused(refusal))
        case .success(let plan):
            return .success(
                SuccessorRun.steps(
                    plan: plan,
                    repository: repository,
                    branch: branch,
                    promptFile: "\(plan.workingDirectory).prompt",
                    check: check,
                    commitMessage: commitMessage
                )
            )
        }
    }
}
