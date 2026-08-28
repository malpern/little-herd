import Foundation

/// The adapter between the steps and a real machine.
///
/// Deliberately thin. Everything worth arguing about — what runs, in what
/// order, and what happens when one fails — lives in `SuccessorRun` and
/// `SuccessorExecutor`, where it can be tested without a second Mac. This part
/// only knows how to say a command out loud.
nonisolated enum SuccessorSSH {
    /// How long each kind of step is given before it is assumed wedged.
    ///
    /// One number cannot serve all of these. A worktree either exists in a
    /// second or something is wrong, while an agent working through a real
    /// brief legitimately takes half an hour and a full test suite on a laptop
    /// takes ten minutes. Time them all like the probe and every useful
    /// transfer is killed; time them all like the agent and a wedged `git`
    /// holds the herd for half an hour.
    static func timeout(for purpose: SuccessorRun.Step.Purpose) -> TimeInterval {
        switch purpose {
        case .worktree, .prompt, .cleanup: 60
        case .agent: 30 * 60
        case .verification: 15 * 60
        // A push can be slow on a big branch, but not agent-slow.
        case .delivery: 5 * 60
        }
    }

    /// A runner bound to one machine, ready to hand to the executor.
    static func runner(
        host: String,
        identityFile: String? = nil
    ) -> SuccessorExecutor.Run {
        { step in
            let result = await SSHCommandRunner.runReportingStatus(
                host: host,
                command: step.command,
                identityFile: identityFile,
                timeout: timeout(for: step.purpose)
            )
            return SuccessorExecutor.StepOutput(
                text: result.output,
                succeeded: result.succeeded
            )
        }
    }
}
