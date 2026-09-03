import Foundation
import Testing

@testable import LittleHerd

/// The runner that lets this Mac take part in a transfer.
///
/// It exists because both halves of a transfer refused `isLocal`, which made
/// the machine somebody is sitting at the only one in the herd that could
/// neither send work nor receive it — and "I am working here, hand this to the
/// mini" is the ordinary case rather than the exotic one.
///
/// These run real subprocesses. The whole value of this type is that it behaves
/// exactly like `SuccessorSSH` from the executor's side, and the ways those two
/// can differ — a status swallowed, standard error dropped, a wedged step that
/// never returns — are all things only a real process shows.
struct SuccessorLocalTests {
    /// The ordinary case: it ran, it worked, and what it said comes back.
    @Test
    func aStepThatWorksReportsWhatItSaid() async {
        let result = await SuccessorLocal.runReportingStatus(
            command: #"printf '%s\n' "on the branch""#,
            timeout: 30
        )

        #expect(result.succeeded)
        #expect(result.output.contains("on the branch"))
    }

    /// **A failed step must report its own output, not swallow it.**
    /// `LocalProcessRunner` — the obvious thing to have reached for — returns
    /// `nil` for a non-zero exit and discards standard error, which is right
    /// for a sampler and exactly wrong here: the whole point of a red step is
    /// the message it printed on the way down.
    @Test
    func aFailedStepStillCarriesItsMessage() async {
        let result = await SuccessorLocal.runReportingStatus(
            command: #"printf '%s\n' "fatal: not a git repository" >&2"# + "\nexit 128",
            timeout: 30
        )

        #expect(!result.succeeded)
        #expect(result.output.contains("not a git repository"))
    }

    /// Both streams, through one pipe, in the order they were written — the
    /// same arrangement the SSH path uses, and for the same reason: two pipes
    /// would have to be drained concurrently to avoid the 64 KiB deadlock.
    @Test
    func bothStreamsComeBackTogether() async {
        let result = await SuccessorLocal.runReportingStatus(
            command: #"printf '%s\n' "compiling"; printf '%s\n' "warning: unused" >&2"#,
            timeout: 30
        )

        #expect(result.succeeded)
        #expect(result.output.contains("compiling"))
        #expect(result.output.contains("warning: unused"))
    }

    /// A step that will not finish is a failed step, not a hung transfer. The
    /// watchdog is shared with the SSH path and with the auth probe; this
    /// checks it is actually wired in here.
    @Test
    func aStepThatOutlivesItsTimeoutFails() async {
        let started = Date()
        let result = await SuccessorLocal.runReportingStatus(
            command: "sleep 30",
            timeout: 0.4
        )
        let elapsed = Date().timeIntervalSince(started)

        #expect(!result.succeeded)
        #expect(elapsed < 20, "the watchdog should have ended this, took \(elapsed)s")
    }

    /// A command that cannot be launched at all is a failure rather than a
    /// crash — `/bin/sh` reports it, so this also confirms the shell is really
    /// in the path rather than the command being exec'd directly.
    @Test
    func anImpossibleCommandFailsQuietly() async {
        let result = await SuccessorLocal.runReportingStatus(
            command: "definitely-not-a-command-\(UUID().uuidString)",
            timeout: 30
        )

        #expect(!result.succeeded)
        #expect(result.output.contains("not found"))
    }

    /// **Cancelling reaches the work, and here that is free.**
    ///
    /// On the SSH side it is not: a remote command survives SIGTERM to the
    /// local `ssh` unless the connection forced a terminal, which is why `-tt`
    /// is load-bearing there and why calling off a transfer would otherwise
    /// leave an agent working on somebody else's Mac. Measured here rather than
    /// assumed, in both shapes a step can take — one the shell `exec`s, and one
    /// where it forks a child and waits — because they are not obviously the
    /// same and the compound form is what every real step looks like.
    @Test
    func cancellingAStepStopsTheWork() async throws {
        // A duration nothing else on this machine would be running.
        let marker = "9931"
        let task = Task {
            await SuccessorLocal.runReportingStatus(
                command: "cd /tmp && sleep \(marker)",
                timeout: 120
            )
        }

        // Let it actually start, then confirm it did — a cancellation test
        // that never started the work would pass proving nothing.
        try await Task.sleep(for: .milliseconds(700))
        #expect(Self.running(marker) > 0, "the work never started")

        task.cancel()
        _ = await task.value
        try await Task.sleep(for: .milliseconds(700))

        #expect(Self.running(marker) == 0, "the work outlived its cancellation")
    }

    /// How many processes are sleeping for that many seconds. The bracket
    /// keeps `grep` from matching its own command line.
    private static func running(_ marker: String) -> Int {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "ps -Ao command | grep -c '[s]leep \(marker)'"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return -1 }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Int(
            String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        ) ?? 0
    }
}
