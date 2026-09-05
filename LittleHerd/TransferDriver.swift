import Foundation

/// Everything a transfer does before its destination starts working, in one
/// place both callers use.
///
/// **The point is that there is only one of these.** The dashboard drives a
/// transfer from a drop and the command line drives one from `move`, and if
/// each carried its own copy of the order — verify, depart, plan the arrival —
/// then an end-to-end test through the CLI would prove the CLI works and say
/// nothing whatever about dragging. That is the trap this project keeps
/// finding: the fan and the resting deck were two descriptions of one object
/// and they disagreed.
///
/// It stops at the point the two genuinely diverge. Handing the arrival's
/// steps to a coordinator that draws a progress bar is a different job from
/// running them and printing what happened, so the steps are where this ends.
/// Five of the six bugs that turning transfers on actually cost were inside
/// what is above that line.
nonisolated enum TransferDriver {
    /// What preparing a transfer came to.
    enum Prepared {
        /// It did not get far enough to run anything on the destination. The
        /// outcome carries **what survives on the source**, which is the whole
        /// reason this is not just an error string: a failed push leaves a
        /// branch on one machine, and a refused destination leaves one on the
        /// remote.
        case blocked(SuccessorOutcome)
        /// The departure succeeded and the arrival is planned. `commit` is
        /// kept because the diff is everything after it — the branch carries
        /// the departure too, so diffing from the branch's parent would
        /// present the brief as the successor's work.
        case ready(commit: String, steps: [SuccessorRun.Step])
    }

    /// - Parameters:
    ///   - request: what `TransferAssembly` said the move consists of. Refusals
    ///     happen before this and are the caller's to report — a refusal is not
    ///     a transfer that failed, it is one that never started.
    ///   - authRefusal: why the destination cannot sign in, when it definitely
    ///     cannot. **Asked by the caller and passed in as a value**, because
    ///     asking differs where it should: the dashboard's probe also updates
    ///     the machine's own state so the herd shows it, and the command line
    ///     has no state to update. What must not differ is what happens next,
    ///     and that is here.
    ///   - departure: runs a step on the source.
    static func prepare(
        _ request: TransferAssembly.Request,
        authRefusal: String? = nil,
        departure: @Sendable (TransferDeparture.Step) async -> SuccessorExecutor.StepOutput
    ) async -> Prepared {
        // **Before anything leaves this machine.**
        //
        // Measured on the first live transfers: the mini's token had expired
        // six days earlier, and the transfer pushed a branch, fetched it on the
        // far side, built a worktree, staged a brief and started an agent
        // before failing on something knowable in one step.
        //
        // Only a definite refusal stops it. A probe that times out means
        // nothing was learned, and refusing on silence would ground the herd
        // whenever a machine was slow.
        if let reason = authRefusal {
            return .blocked(
                SuccessorOutcome(
                    result: .couldNotStart,
                    failingStep: nil,
                    output: reason,
                    // Nothing has been built or pushed yet, and this is the one
                    // refusal that can still say so honestly.
                    remnant: .nothing
                )
            )
        }

        let departed = await TransferPilot.depart(
            steps: request.departure,
            run: departure
        )

        switch departed {
        case .failure(let failure):
            return .blocked(
                SuccessorOutcome(
                    result: .couldNotStart,
                    failingStep: nil,
                    output: String(describing: failure),
                    // Where it stopped decides what survives, and only the
                    // failure knows where it stopped.
                    remnant: failure.remnant
                )
            )
        case .success(let commit):
            let arrival = TransferPilot.arrival(
                commit: commit,
                briefPath: request.briefPath,
                briefText: "",
                branch: request.transfer.branch,
                repository: request.destinationRepository,
                scratchRoot: TransferAssembly.scratchRoot,
                provider: request.provider,
                reportedAgentPath: request.destinationAgentPath,
                check: request.check,
                commitMessage: "Successor work on \(request.transfer.branch)"
            )
            switch arrival {
            case .failure(let failure):
                return .blocked(
                    SuccessorOutcome(
                        result: .couldNotStart,
                        failingStep: nil,
                        output: String(describing: failure),
                        // The departure fully succeeded to get here: the work
                        // is pushed and only the destination was refused.
                        remnant: .pushedBranch
                    )
                )
            case .success(let steps):
                return .ready(commit: commit, steps: steps)
            }
        }
    }
}
