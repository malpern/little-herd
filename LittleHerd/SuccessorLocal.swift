import Foundation

/// The same adapter as `SuccessorSSH`, for the machine Little Herd is running
/// on.
///
/// **This exists because the most likely transfer in a herd was the one that
/// could not happen.** Both halves of a transfer refused `isLocal` — the
/// comment on the guard said a local departure "does not exist yet" — so the
/// Mac somebody is actually sitting at could neither send work nor receive it.
/// Every other machine could. Reading that as a testing inconvenience was a
/// mistake: "I am working here and want to hand this to the mini" is the
/// ordinary case, not the exotic one.
///
/// Deliberately thin, for the same reason `SuccessorSSH` is: what runs, in what
/// order, and what happens when a step fails all live in `SuccessorRun` and
/// `SuccessorExecutor`, where they can be tested without any machine at all.
/// This only knows how to say a command out loud on this one.
nonisolated enum SuccessorLocal {
    /// Runs a step's command and reports what it said and whether it worked.
    ///
    /// The shape mirrors `SSHCommandRunner.runReportingStatus` exactly —
    /// combined output, a watchdog, cancellation — because the executor cannot
    /// tell the two apart and must not have to.
    ///
    /// **The command goes to `/bin/sh -c`, and that is the same shell the far
    /// side gets.** An `ssh host 'command'` runs the command in the remote
    /// login shell, so the steps are already written to be shell text rather
    /// than argument lists. Running them through a shell here is what keeps
    /// the two paths identical rather than subtly divergent — a departure that
    /// worked remotely and failed locally on quoting would be a miserable bug
    /// to find.
    static func runReportingStatus(
        command: String,
        timeout: TimeInterval
    ) async -> (output: String, succeeded: Bool) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        // One pipe for both streams, as the SSH path does: two would have to
        // be drained concurrently to avoid the 64 KiB deadlock, and somebody
        // reading a failed build wants them interleaved anyway.
        process.standardOutput = pipe
        process.standardError = pipe
        // Closed, not inherited. The app's own standard input never reaches
        // EOF, and an agent that finds an open one waits on it — measured, and
        // the reason `AgentAuthVerifier` does the same.
        process.standardInput = FileHandle.nullDevice

        return await withTaskCancellationHandler {
            await Task.detached(priority: .utility) {
                do {
                    try process.run()
                } catch {
                    return ("", false)
                }

                let watchdog = ProbeWatchdog(process: process, after: timeout)
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let timedOut = watchdog.finish()

                return (
                    String(decoding: data, as: UTF8.self),
                    process.terminationStatus == 0 && !timedOut
                )
            }.value
        } onCancel: {
            // Safe before `run()` too: terminating a process that has not
            // started does nothing.
            process.terminate()
        }
    }

    /// A runner for the destination's half, ready to hand to the executor.
    static func runner() -> SuccessorExecutor.Run {
        { step in
            let result = await runReportingStatus(
                command: step.command,
                timeout: SuccessorSSH.timeout(for: step.purpose)
            )
            return SuccessorExecutor.StepOutput(
                text: result.output,
                succeeded: result.succeeded
            )
        }
    }

    /// And one for the source's half.
    ///
    /// The purpose mapping matches the SSH departure runner: asking a session
    /// for its brief is an agent-sized wait, and everything else is
    /// bookkeeping that either happens quickly or is wrong.
    static func departureRunner() -> @Sendable (TransferDeparture.Step) async
        -> SuccessorExecutor.StepOutput
    {
        { step in
            let result = await runReportingStatus(
                command: step.command,
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
}
