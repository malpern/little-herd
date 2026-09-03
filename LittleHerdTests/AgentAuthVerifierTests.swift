import Foundation
import Testing

@testable import LittleHerd

/// The verifier's process plumbing, run for real against a fake agent.
///
/// This is the harness the handoff asked for before anything else is built
/// here. `AgentAuthVerifier.runLocally`, `ProbeWatchdog` and the runners around
/// them were roughly a hundred and ninety lines that no test touched, and
/// **four bugs in them were found by running the thing and none by the suite**:
/// stdin inherited rather than closed, no watchdog at all, silence read as a
/// refusal, and a cancelled probe that did not stop the work it started. That
/// code now sits directly under the agent drag — it decides whether a machine
/// lifts to meet you — so "it has never been wrong in a way we noticed" stopped
/// being good enough.
///
/// **The seam is the agent's own path.** `AgentAuthProbe.command(for:)` quotes
/// `install.path` and hands the result to `/bin/sh -c`, so an installation
/// pointed at a script is a real subprocess doing whatever that script says.
/// Nothing had to be made injectable to test any of this.
///
/// **The watchdog is tested directly rather than through `verify`.**
/// `AgentAuthVerifier.timeout` is ninety seconds and is deliberately not
/// configurable — it was measured, and a test-only knob on it would be a
/// second answer to the question the constant already settles. Driving a
/// ninety-second wait through `verify` to observe the watchdog would trade
/// ninety seconds of everybody's suite for coverage the watchdog's own tests
/// give in under four.
struct AgentAuthVerifierTests {
    // MARK: - The answer

    /// The ordinary case, and the only one where the machine is offered.
    @Test
    func anAgentThatAnswersIsVerified() async throws {
        let agent = try FakeAgent(#"printf '%s\n' "AUTH_OK""#)
        let when = Date(timeIntervalSince1970: 1_000)

        let state = await AgentAuthVerifier.verify(
            install: agent.installation,
            isLocal: true,
            host: "unused",
            identityFile: nil,
            now: when
        )

        #expect(state == .verified(at: when))
    }

    /// **A refusal arrives on standard error with a non-zero status, and that
    /// is the whole reason this does not use `LocalProcessRunner`.** That
    /// runner discards standard error and answers nil for a non-zero exit,
    /// which is right for a sampler and exactly wrong here: it would turn
    /// "Not logged in" into silence, and silence parses as unverified — so a
    /// signed-out account would read as one nobody had asked about, and the
    /// machine would be offered as a destination.
    @Test
    func aRefusalOnStandardErrorSurvivesANonZeroExit() async throws {
        let agent = try FakeAgent(
            #"printf '%s\n' "Not logged in" >&2"# + "\nexit 1"
        )

        let state = await AgentAuthVerifier.verify(
            install: agent.installation,
            isLocal: true,
            host: "unused",
            identityFile: nil
        )

        #expect(state == .refused(reason: "Not signed in on this account."))
    }

    /// Silence is not a refusal. A nested agent launched from inside another
    /// agent's session is killed outright with no output and no message, and
    /// calling that "signed out" sends somebody to fix an account that is
    /// fine.
    @Test
    func anAgentThatSaysNothingIsUnverifiedRatherThanRefused() async throws {
        let agent = try FakeAgent("exit 0")

        let state = await AgentAuthVerifier.verify(
            install: agent.installation,
            isLocal: true,
            host: "unused",
            identityFile: nil
        )

        #expect(state == .unverified)
    }

    /// An agent whose path has gone is a path problem, not a sign-in one —
    /// the likeliest failure of all, because an agent's path carries its
    /// version and the runtime updates itself underneath. The message comes
    /// from the shell rather than from the agent, which is the point: nothing
    /// ran, and the parser still has to place it.
    @Test
    func aMissingAgentReadsAsAPathProblem() async throws {
        let install = AgentInstallation(
            provider: .claude,
            version: "test",
            path: NSTemporaryDirectory()
                .appending("little-herd-absent-\(UUID().uuidString)")
        )

        let state = await AgentAuthVerifier.verify(
            install: install,
            isLocal: true,
            host: "unused",
            identityFile: nil
        )

        #expect(
            state == .refused(
                reason: "The agent is no longer at that path — it has been updated."
            )
        )
    }

    /// **Standard input must be closed, not inherited.** Measured on this
    /// herd: the same `codex exec` that answers in thirty seconds from a shell
    /// ran into the ninety-second watchdog when launched from the app, because
    /// the app's own standard input never reaches EOF.
    ///
    /// **Two earlier versions of this test passed with the behaviour deleted.**
    /// The first drained stdin in the agent and asserted the call returned
    /// quickly — it does either way, because a test runner's stdin is already
    /// at EOF. The second asked the agent whether its stdin was the null
    /// device — it is either way, because `xcodebuild` hands the test process
    /// `/dev/null` as well, so inheriting it and setting it are the same
    /// descriptor. Neither could have failed.
    ///
    /// So the test makes the two distinguishable: it puts a pipe on this
    /// process's own descriptor 0 for the duration, which is the only state in
    /// which "inherited" and "closed" differ at all. The agent then answers
    /// only if it sees the null device. Verified by deleting
    /// `process.standardInput = FileHandle.nullDevice` and watching this go
    /// red — which the two versions before it did not.
    ///
    /// The swap is restored immediately and nothing else in the suite reads
    /// standard input, but it is process-wide while it lasts, which is why it
    /// is this narrow and why the test does nothing else.
    @Test
    func standardInputIsTheNullDeviceRatherThanInherited() async throws {
        let agent = try FakeAgent(
            """
            if [ -c /dev/fd/0 ] \
               && [ "$(stat -f %i /dev/fd/0)" = "$(stat -f %i /dev/null)" ]
            then
              printf '%s\\n' "AUTH_OK"
            else
              printf '%s\\n' "Not logged in" >&2
            fi
            """
        )
        let when = Date(timeIntervalSince1970: 2_000)

        let inherited = Pipe()
        let saved = dup(STDIN_FILENO)
        #expect(saved >= 0, "could not save this process's own stdin")
        dup2(inherited.fileHandleForReading.fileDescriptor, STDIN_FILENO)
        defer {
            dup2(saved, STDIN_FILENO)
            close(saved)
        }

        let state = await AgentAuthVerifier.verify(
            install: agent.installation,
            isLocal: true,
            host: "unused",
            identityFile: nil,
            now: when
        )

        #expect(
            state == .verified(at: when),
            "the agent saw this process's stdin rather than the null device"
        )
    }

    /// Both streams come back, whatever order they arrive in and whatever the
    /// exit status — one pipe carries them so they cannot deadlock against
    /// each other. The reply here is on standard error while noise is on
    /// standard out, which is the arrangement that catches a runner reading
    /// only one of them.
    @Test
    func bothStreamsAreReadWhicheverCarriesTheAnswer() async throws {
        let agent = try FakeAgent(
            #"printf '%s\n' "starting up""# + "\n"
                + #"printf '%s\n' "AUTH_OK" >&2"# + "\nexit 3"
        )
        let when = Date(timeIntervalSince1970: 3_000)

        let state = await AgentAuthVerifier.verify(
            install: agent.installation,
            isLocal: true,
            host: "unused",
            identityFile: nil,
            now: when
        )

        #expect(state == .verified(at: when))
    }

    // MARK: - The watchdog

    /// `readDataToEndOfFile` waits for the write end of the pipe to close, and
    /// a child that is simply slow never closes it. Terminating the process is
    /// what closes it — so without this the read blocks for ever, which is the
    /// ten-minute hang that put the watchdog here in the first place.
    @Test
    func aProcessThatStopsAnsweringIsKilledSoTheReadCanReturn() async throws {
        let probe = try SpawnedProbe(script: "sleep 30")
        let watchdog = ProbeWatchdog(process: probe.process, after: 0.3)

        let output = probe.readToEnd()
        probe.process.waitUntilExit()

        #expect(watchdog.finish(), "the watchdog should report that it fired")
        #expect(output.isEmpty)
        #expect(!probe.process.isRunning)
    }

    /// **A watchdog that can be ignored is decoration.** SIGTERM is sent first
    /// so an agent can close down tidily, and a process that traps it holds the
    /// pipe open — which is exactly the state the watchdog exists to end — so
    /// SIGKILL follows three seconds later. This is the half that is easy to
    /// leave out and impossible to notice missing.
    @Test
    func aProcessThatIgnoresSIGTERMIsKilledAnyway() async throws {
        let probe = try SpawnedProbe(script: "trap '' TERM\nsleep 30")
        let watchdog = ProbeWatchdog(process: probe.process, after: 0.3)
        let started = Date()

        let output = probe.readToEnd()
        probe.process.waitUntilExit()
        let elapsed = Date().timeIntervalSince(started)

        #expect(watchdog.finish())
        #expect(output.isEmpty)
        #expect(!probe.process.isRunning)
        // The escalation is at three seconds; anything under the ninety-second
        // timeout would be an improvement, but a run that came back before the
        // SIGTERM had been ignored would mean the trap never took and the test
        // is proving nothing.
        #expect(elapsed > 3, "SIGTERM should have been ignored first, took \(elapsed)s")
        #expect(elapsed < 30, "SIGKILL should not have waited for the sleep")
    }

    /// A probe that answers in time must not be reported as having timed out,
    /// and the pending watchdog must not go on to kill something else. The
    /// second half matters because the timer is already scheduled by the time
    /// the process exits — `finish()` is what disarms it.
    @Test
    func aProbeThatAnswersInTimeIsNotReportedAsTimedOut() async throws {
        let probe = try SpawnedProbe(script: #"printf '%s\n' "done""#)
        let watchdog = ProbeWatchdog(process: probe.process, after: 60)

        let output = probe.readToEnd()
        probe.process.waitUntilExit()

        #expect(!watchdog.finish(), "nothing should have fired")
        #expect(output.contains("done"))
    }

    /// Asked twice, it answers the same. `finish()` is called once by the
    /// runner today, and a second caller reading "no, it did not fire" off a
    /// watchdog that did would be the quietest possible bug.
    @Test
    func askingTheWatchdogTwiceGivesTheSameAnswer() async throws {
        let probe = try SpawnedProbe(script: "sleep 30")
        let watchdog = ProbeWatchdog(process: probe.process, after: 0.3)

        _ = probe.readToEnd()
        probe.process.waitUntilExit()

        let first = watchdog.finish()
        #expect(first)
        #expect(watchdog.finish() == first)
    }
}

// MARK: - The fakes

/// An executable standing in for an agent, which can be told to answer,
/// refuse, hang, or read its standard input first.
///
/// It is a real file on disk run by a real shell, because everything this
/// suite is here to check — descriptors, signals, exit statuses — exists only
/// in a real process. A stubbed runner would agree with whatever the code did.
private struct FakeAgent {
    let path: String

    /// - Parameter body: shell run when the agent is invoked. The probe's own
    ///   arguments arrive as `$@` and are ignored; what is being tested is the
    ///   plumbing around the command, not the prompt inside it.
    init(_ body: String) throws {
        path = NSTemporaryDirectory()
            .appending("little-herd-fake-agent-\(UUID().uuidString)")
        try ("#!/bin/sh\n" + body + "\n").write(
            toFile: path,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: path
        )
    }

    /// `.claude` rather than `.codex` only because its command form is the
    /// shorter of the two; the script ignores its arguments either way.
    var installation: AgentInstallation {
        AgentInstallation(provider: .claude, version: "test", path: path)
    }
}

/// A running child with one pipe carrying both its streams — the same shape
/// `runLocally` builds, so the watchdog is watching what it watches in
/// production rather than a bare `sleep`.
private struct SpawnedProbe {
    let process: Process
    private let pipe: Pipe

    init(script: String) throws {
        process = Process()
        pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        try process.run()
    }

    func readToEnd() -> String {
        String(
            decoding: pipe.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
    }
}
