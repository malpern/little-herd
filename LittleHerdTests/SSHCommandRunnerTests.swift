import Foundation
import Testing

@testable import LittleHerd

/// `SSHCommandRunner.runCapturingAll`, driven by a stub instead of a machine.
///
/// **The half item 13 has called untested since 25 August.** Roughly a hundred
/// and ninety lines of process and concurrency plumbing in which *four bugs
/// were found by running it and none by the suite*: stdin inherited rather than
/// closed, no watchdog at all, silence read as a refusal, and a cancelled probe
/// that did not stop the work it started.
///
/// The objection recorded there was that testing it needs a live host and that
/// pointing it at `localhost` would test this Mac's sshd rather than the
/// runner. Both true, and both answered by not using ssh: the executable is a
/// parameter now, so a script standing in for it exercises exactly the
/// plumbing that had the bugs — combined streams, a closed stdin, the watchdog
/// — without a network or a second machine.
///
/// Each of these was checked by breaking what it covers. The notes say how.
@Suite("The SSH runner's plumbing")
struct SSHCommandRunnerTests {
    /// A script standing in for `ssh`, which ignores the arguments it is given
    /// the way a fake would and does whatever the test needs.
    private func stub(_ body: String) throws -> String {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ssh-stub-\(UUID().uuidString).sh")
        try ("#!/bin/sh\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: url.path
        )
        return url.path
    }

    /// **Both streams, because a refusal arrives on either.** Every refusal
    /// measured on this herd came back on standard error with a non-zero
    /// status, so a runner that kept only stdout would report silence and the
    /// probe would call a signed-out machine "unverified".
    ///
    /// Breaks if `standardError` stops pointing at the same pipe: the
    /// assertion on "refused" fails.
    @Test
    func itKeepsStandardErrorAsWellAsStandardOutput() async throws {
        let path = try stub("echo out; echo refused >&2; exit 1")
        let result = await SSHCommandRunner.runCapturingAll(
            host: "example", command: "x", timeout: 20, executable: path
        )
        #expect(result.output.contains("out"))
        #expect(result.output.contains("refused"))
        #expect(!result.timedOut)
    }

    /// **A non-zero exit is an answer, not a failure.** The whole reason this
    /// function exists beside `run`: the refusal *is* the result.
    @Test
    func aFailingCommandStillReportsWhatItSaid() async throws {
        let path = try stub("echo 'Invalid API key'; exit 3")
        let result = await SSHCommandRunner.runCapturingAll(
            host: "example", command: "x", timeout: 20, executable: path
        )
        #expect(result.output.contains("Invalid API key"))
    }

    /// **Stdin is closed, not inherited**, and this is the bug that shipped:
    /// an agent that finds an open standard input waits on it, and the app's
    /// own never reaches EOF. The stub blocks reading stdin, so if it were
    /// inherited this would hit the timeout instead of answering at once.
    ///
    /// Breaks if `standardInput = FileHandle.nullDevice` is removed: the read
    /// blocks and `timedOut` comes back true.
    @Test
    func standardInputIsClosedSoNothingWaitsOnIt() async throws {
        let path = try stub("cat > /dev/null; echo drained")
        let result = await SSHCommandRunner.runCapturingAll(
            host: "example", command: "x", timeout: 15, executable: path
        )
        #expect(result.output.contains("drained"))
        #expect(!result.timedOut, "an inherited stdin would have hung until the watchdog")
    }

    /// **The watchdog, which did not exist once.** Without it a wedged
    /// destination holds the read for ever: ssh keeps the pipe open as long as
    /// the remote command lives. Measured before it existed — a probe to the
    /// mini held a test for the ten minutes it took to kill it.
    ///
    /// Breaks if the watchdog is removed: this never returns.
    @Test
    func aCommandThatNeverFinishesIsKilledAndSaysSo() async throws {
        let path = try stub("sleep 120")
        let started = Date()
        let result = await SSHCommandRunner.runCapturingAll(
            host: "example", command: "x", timeout: 2, executable: path
        )
        let took = Date().timeIntervalSince(started)
        #expect(result.timedOut, "the watchdog did not fire")
        #expect(took < 30, "it waited for the command rather than the timeout")
    }

    /// Output written before a hang still comes back, so a timed-out probe can
    /// report what it did hear rather than nothing at all.
    @Test
    func whatWasSaidBeforeTheHangSurvivesIt() async throws {
        let path = try stub("echo 'partial answer'; sleep 120")
        let result = await SSHCommandRunner.runCapturingAll(
            host: "example", command: "x", timeout: 2, executable: path
        )
        #expect(result.timedOut)
        #expect(result.output.contains("partial answer"))
    }

    /// **A host that is not a host never reaches a process.** The guard is a
    /// boundary: the host reaches an argument list, and a value shaped like a
    /// flag would be read as one.
    @Test
    func animpossibleHostIsRefusedWithoutRunningAnything() async throws {
        // The stub would say "ran" if it were reached, so this asserts the
        // guard by what is absent.
        let path = try stub("echo ran")
        for host in ["-oProxyCommand=x", "", "a host with spaces"] {
            let result = await SSHCommandRunner.runCapturingAll(
                host: host, command: "x", timeout: 10, executable: path
            )
            #expect(result.output.isEmpty, "“\(host)” reached a process")
            #expect(!result.timedOut)
        }
    }

    /// An executable that is not there is a failure to report, not a crash or
    /// a hang — `process.run()` throws and the runner answers empty.
    @Test
    func amissingExecutableAnswersRatherThanThrowing() async {
        let result = await SSHCommandRunner.runCapturingAll(
            host: "example", command: "x", timeout: 5,
            executable: "/nonexistent/ssh"
        )
        #expect(result.output.isEmpty)
        #expect(!result.timedOut)
    }
}

/// `SSHCommandRunner.copy`, the transport a transcript actually fits through.
@Suite("Copying a file to a machine")
struct SSHCopyTests {
    private func stub(_ body: String) throws -> String {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("scp-stub-\(UUID().uuidString).sh")
        try ("#!/bin/sh\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }

    /// **The arguments are what scp is given, in the order it needs them**, and
    /// the stub simply echoes them back so the test can read the invocation.
    @Test
    func theInvocationIsShapedForScp() async throws {
        let path = try stub(#"printf '%s\n' "$@""#)
        let result = await SSHCommandRunner.copy(
            "/tmp/a.jsonl", to: "malpern@mini", remotePath: "/Users/m/x/a.jsonl",
            identityFile: "/Users/m/.ssh/id", recursive: true, executable: path
        )
        #expect(result.succeeded)
        let lines = result.output.split(separator: "\n").map(String.init)
        #expect(lines.contains("-r"))
        #expect(lines.contains("BatchMode=yes"))
        #expect(lines.contains("IdentitiesOnly=yes"))
        #expect(lines.contains("/Users/m/.ssh/id"))
        // "--" before the paths, and the remote written host:path.
        let dash = try #require(lines.firstIndex(of: "--"))
        #expect(lines[dash + 1] == "/tmp/a.jsonl")
        #expect(lines[dash + 2] == "malpern@mini:/Users/m/x/a.jsonl")
    }

    /// A failing copy is a failure with its words kept, so a full disk or a
    /// refused key reaches the person rather than a bare false.
    @Test
    func afailedCopyKeepsWhatScpSaid() async throws {
        let path = try stub("echo 'scp: No space left on device' >&2; exit 1")
        let result = await SSHCommandRunner.copy(
            "/tmp/a", to: "example", remotePath: "/x", executable: path
        )
        #expect(!result.succeeded)
        #expect(result.output.contains("No space left"))
    }

    /// The host guard is the same boundary the other runners keep: a value
    /// shaped like a flag never reaches an argument list.
    @Test
    func animpossibleHostNeverRunsScp() async throws {
        let path = try stub("echo ran")
        let result = await SSHCommandRunner.copy(
            "/tmp/a", to: "-oProxyCommand=x", remotePath: "/x", executable: path
        )
        #expect(!result.succeeded)
        #expect(result.output.isEmpty)
    }

    /// And the watchdog, because a stalled network holds scp open for ever.
    @Test
    func acopyThatHangsIsKilled() async throws {
        let path = try stub("sleep 120")
        let started = Date()
        let result = await SSHCommandRunner.copy(
            "/tmp/a", to: "example", remotePath: "/x", timeout: 2, executable: path
        )
        #expect(!result.succeeded)
        #expect(Date().timeIntervalSince(started) < 30)
    }
}
