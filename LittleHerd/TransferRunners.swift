import Foundation

/// How to say a transfer's commands out loud on a given machine.
///
/// **Built from the configuration rather than from a view model**, so the
/// dashboard and the command line reach for the same two functions. They used
/// to be private to `MonitorModel`, which was fine while a drag was the only
/// way to start a transfer; the moment a second caller existed, keeping them
/// there would have meant a second description of "how do I run a command on
/// that machine" — and this project has already paid for two descriptions of
/// one object, in the fan and the resting deck that disagreed about where the
/// deck was.
///
/// The local case is not a convenience. This Mac was once refused outright,
/// which made the machine somebody is sitting at the only one in the herd that
/// could neither send work nor receive it.
nonisolated enum TransferRunners {
    /// The source's half: the steps that write the brief and push the branch.
    ///
    /// The purpose mapping matters. Asking a session for its own account of
    /// itself is an agent-sized wait; everything else is bookkeeping that
    /// either happens quickly or is wrong.
    static func departure(
        for machine: MachineConfiguration
    ) -> @Sendable (TransferDeparture.Step) async -> SuccessorExecutor.StepOutput {
        guard machine.connection != .local else {
            return SuccessorLocal.departureRunner()
        }
        let host = machine.sshDestination
        let identity = machine.identityFile
        return { step in
            let result = await SSHCommandRunner.runReportingStatus(
                host: host,
                command: step.command,
                identityFile: identity,
                timeout: SuccessorSSH.timeout(
                    for: step.purpose == .brief ? .agent : .worktree
                )
            )
            return SuccessorExecutor.StepOutput(
                text: result.output,
                succeeded: result.succeeded
            )
        }
    }

    /// The destination's half: fetch, worktree, brief, agent, check, deliver,
    /// clean up.
    static func arrival(for machine: MachineConfiguration) -> SuccessorExecutor.Run {
        guard machine.connection != .local else { return SuccessorLocal.runner() }
        return SuccessorSSH.runner(
            host: machine.sshDestination,
            identityFile: machine.identityFile
        )
    }
}
