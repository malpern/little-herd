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
        process.environment = Self.environment

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

    /// A deliberately built environment rather than this app's own.
    ///
    /// **The two runners were not equivalent and that was the point of the
    /// type.** `ssh host 'command'` runs in a fresh session on the far machine
    /// and cannot see a variable Little Herd happens to be holding; a local
    /// `Process` inherits every one of them. So a step that behaved one way
    /// remotely could behave another way here, decided by whatever launched
    /// the app.
    ///
    /// Measured, and not hypothetically: an agent started from a terminal that
    /// exported `ANTHROPIC_BASE_URL` inherited it and answered "Not logged in"
    /// with perfectly good credentials sitting on disk. It reads exactly like
    /// a signed-out machine, and the same account answers immediately from a
    /// clean environment. Little Herd would have reported a machine as needing
    /// a sign-in it did not need.
    ///
    /// An allowlist rather than a denylist, because the failure mode of
    /// missing a variable is a command that cannot find something and says so,
    /// while the failure mode of leaking one is a confident wrong answer.
    /// `~/.local/bin` leads the path because that is where both agents install
    /// themselves.
    ///
    /// **Every entry here was tested, and one that looked obviously harmless
    /// was not.** The first version also carried `USER`, `LOGNAME` and
    /// `TMPDIR`, on the reasoning that a process with no user is a stranger
    /// shape than one with a plain environment and that none of them can carry
    /// a credential. `USER` makes `claude` report **"Not logged in"** with
    /// valid credentials on disk — deterministically, three runs out of three,
    /// while the same command without it answers immediately. The mechanism is
    /// not known and does not matter; what matters is that an allowlist is only
    /// as safe as the testing of each entry, and this one was assembled partly
    /// on taste.
    ///
    /// `LOGNAME` and `TMPDIR` were both measured as harmless and are still
    /// gone: nothing needed them, and the point of a list nobody can justify
    /// entry by entry is that it grows.
    static var environment: [String: String] {
        let home = NSHomeDirectory()
        return [
            "HOME": home,
            "PATH": "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin"
                + ":/usr/bin:/bin:/usr/sbin:/sbin",
            "SHELL": "/bin/sh",
            "LANG": "en_US.UTF-8",
            // Something rather than nothing, so a tool that consults it does
            // not reach for a terminal that is not there.
            "TERM": "dumb",
        ]
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
