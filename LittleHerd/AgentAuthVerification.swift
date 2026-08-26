import Foundation

/// Runs the authentication challenge on a machine and reads the answer.
///
/// This is the caller `AgentAuthProbe` was written for. Until it existed the
/// probe could describe a refusal and never provoke one, so every account read
/// "sign-in not checked" for ever — true, and not much use.
///
/// **It costs a model call, so nothing calls it on a timer.** The thirty-second
/// sample must not spend the budget it is reporting on. It is asked
/// deliberately, at the moment the answer would change a decision: before a
/// session is offered a destination.
nonisolated enum AgentAuthVerifier {
    /// - Parameters:
    ///   - install: which agent, and its absolute path. Never the PATH — not
    ///     one machine in this herd has an agent on the PATH ssh sees.
    ///   - isLocal: this Mac runs it directly; anything else goes over the SSH
    ///     connection the sampler already uses.
    static func verify(
        install: AgentInstallation,
        isLocal: Bool,
        host: String,
        identityFile: String?,
        now: Date = .now
    ) async -> AgentAuthState {
        let command = AgentAuthProbe.command(for: install)
        let result = isLocal
            ? await runLocally(command)
            : await SSHCommandRunner.runCapturingAll(
                host: host,
                command: command,
                identityFile: identityFile
            )

        // A destination that never answers reads as unverified rather than as
        // a refusal, because that is what happened: nothing was learned. The
        // alternative is to call a machine signed out on the strength of its
        // silence, which is the same mistake as reading a licensing state as
        // an outage — it sends someone to fix the wrong thing.
        guard !result.timedOut else { return .unverified }
        return AgentAuthProbe.outcome(from: result.output, at: now)
    }

    /// Long enough for a model to answer a one-line prompt over a tailnet, and
    /// short enough that a wedged destination does not hold the caller. Both
    /// halves were measured: an answer takes about thirty seconds, and without
    /// a limit at all a hung ssh held a test until it was killed ten minutes
    /// later.
    static let timeout: TimeInterval = 90

    /// Standard output and standard error together, whatever the exit status.
    ///
    /// `LocalProcessRunner` discards standard error and answers nil for a
    /// non-zero exit, which is right for a sampler: a probe that half-ran is
    /// not a reading. It is exactly wrong here. Every refusal measured on this
    /// herd arrived on standard error with a non-zero status, so a runner that
    /// treats non-zero as "no output" turns "Not logged in" into silence — and
    /// silence would parse as a refusal nobody has seen, which is the one
    /// answer this must never invent.
    private static func runLocally(_ command: String) async -> ProbeOutput {
        await Task.detached(priority: .utility) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
            // One pipe for both, so the two streams cannot deadlock against
            // each other and the order they interleave in does not matter —
            // the parser reads whichever line answers first.
            process.standardOutput = pipe
            process.standardError = pipe
            // Stdin must be closed, not inherited. An agent that finds an
            // open stdin waits on it: measured here, the same `codex exec`
            // that answers in thirty seconds from a shell ran into the
            // ninety-second watchdog when launched from the app, because the
            // app's own stdin never reaches EOF. /dev/null answers at once.
            process.standardInput = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                return ProbeOutput(output: "", timedOut: false)
            }

            let watchdog = ProbeWatchdog(process: process, after: timeout)
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return ProbeOutput(
                output: String(decoding: data, as: UTF8.self),
                timedOut: watchdog.finish()
            )
        }.value
    }
}

nonisolated struct ProbeOutput: Sendable {
    let output: String
    let timedOut: Bool
}

/// Kills a probe that has stopped answering, so the read on its pipe can
/// return instead of blocking for ever.
///
/// `readDataToEndOfFile` waits for the write end to close, and a child that is
/// simply slow never closes it. Terminating the process is what closes it.
nonisolated final class ProbeWatchdog: @unchecked Sendable {
    private let lock = NSLock()
    private var didFire = false
    private var isFinished = false

    init(process: Process, after seconds: TimeInterval) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + seconds) {
            [weak self] in
            guard let self else { return }
            lock.lock()
            let shouldFire = !isFinished
            if shouldFire { didFire = true }
            lock.unlock()
            guard shouldFire, process.isRunning else { return }
            // SIGTERM first, because it lets the agent close down tidily.
            process.terminate()

            // Then SIGKILL, because "not going to be reasoned with" was the
            // whole assumption behind stopping at SIGTERM, and a process that
            // ignores it holds the pipe open — which is exactly the state the
            // watchdog exists to end. A watchdog that can be ignored is
            // decoration.
            let pid = process.processIdentifier
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) {
                if process.isRunning { kill(pid, SIGKILL) }
            }
        }
    }

    /// - Returns: whether the watchdog had already fired.
    func finish() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        isFinished = true
        return didFire
    }
}
