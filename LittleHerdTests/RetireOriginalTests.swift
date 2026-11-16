import Foundation
import Testing

@testable import LittleHerd

/// A move ends the original once the copy on the destination is running.
/// See `TransferDriver.retireOriginal`.
@Suite("Retire the original", .serialized)
struct RetireOriginalTests {
    private static let session = "c64bf6a3-e3c4-4b59-95ff-110d1150befb"

    /// A home holding one registry entry, and a process for it to point at.
    private func fixture(
        processName: String,
        status: String
    ) throws -> (home: URL, process: Process) {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("retire-\(UUID().uuidString)")
        let sessions = home.appendingPathComponent(".claude/sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let binary = home.appendingPathComponent(processName)
        try FileManager.default.createSymbolicLink(atPath: binary.path, withDestinationPath: "/bin/sleep")
        let process = Process()
        process.executableURL = binary
        process.arguments = ["30"]
        try process.run()
        let entry: [String: Any] = [
            "pid": Int(process.processIdentifier), "sessionId": Self.session,
            "kind": "interactive", "status": status,
        ]
        try JSONSerialization.data(withJSONObject: entry)
            .write(to: sessions.appendingPathComponent("\(process.processIdentifier).json"))
        return (home, process)
    }

    private func runRetire(home: URL) throws -> String {
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", TransferDriver.retireCommand(sessionIdentifier: Self.session)]
        shell.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin"]
        let pipe = Pipe()
        shell.standardOutput = pipe
        try shell.run()
        shell.waitUntilExit()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    @Test
    func anIdleOriginalIsClosed() throws {
        let (home, process) = try fixture(processName: "claude", status: "idle")
        defer { process.terminate(); try? FileManager.default.removeItem(at: home) }
        #expect(TransferDriver.retiredAnswer(try runRetire(home: home)) == .retired)
        process.waitUntilExit()
        #expect(process.terminationReason == .uncaughtSignal)
    }

    /// Cutting off a turn loses more than a duplicate costs.
    @Test
    func aBusyOriginalIsLeftRunning() throws {
        let (home, process) = try fixture(processName: "claude", status: "busy")
        defer { process.terminate(); try? FileManager.default.removeItem(at: home) }
        #expect(TransferDriver.retiredAnswer(try runRetire(home: home)) == .leftRunning)
        #expect(process.isRunning)
    }

    /// A registry entry whose pid now belongs to something else is not
    /// signalled.
    @Test
    func aProcessThatIsNotClaudeIsNeverSignalled() throws {
        let (home, process) = try fixture(processName: "sleeper", status: "idle")
        defer { process.terminate(); try? FileManager.default.removeItem(at: home) }
        #expect(TransferDriver.retiredAnswer(try runRetire(home: home)) == .gone)
        #expect(process.isRunning)
    }

    @Test
    func onlyALiveLandingRetires() async {
        let oneShot = SuccessorOutcome(result: .landed, failingStep: nil, output: "")
        let failed = SuccessorOutcome(
            result: .agentFailed, failingStep: .agent, output: "", backgroundSession: "472f7442"
        )
        for outcome in [oneShot, failed] {
            let retired = await TransferDriver.retireOriginal(
                after: outcome, sessionIdentifier: Self.session,
                sourceCommand: { _ in Issue.record("must not run"); return ("", false) }
            )
            #expect(retired == nil)
        }
    }

    @Test
    func theLandingSaysWhatHappenedToTheOriginal() {
        var outcome = SuccessorOutcome(
            result: .landed, failingStep: nil, output: "", backgroundSession: "472f7442"
        )
        outcome.originalRetired = .retired
        #expect(outcome.liveLandingSentence.contains("the original was closed"))
        outcome.originalRetired = .leftRunning
        #expect(outcome.liveLandingSentence.contains("still open"))
    }

    /// The copy carried for the fork is removed only once the fork holds its
    /// last message, and only for a session that started.
    @Test
    func theCarriedCopyIsRemovedOnlyAfterTheForkHoldsIt() throws {
        let plan = try SuccessorLaunch.plan(
            briefPath: "Documentation/transfers/x.md",
            briefText: "",
            branch: "transfer/x",
            repository: "/home/malpern/local-code/sandpiper",
            scratchRoot: SuccessorLaunch.liveRoot(repository: "/home/malpern/local-code/sandpiper"),
            provider: .claude,
            reportedAgentPath: "/home/malpern/.local/share/mise/installs/claude/latest/claude",
            expectedCommit: String(repeating: "a", count: 40),
            carriedSession: Self.session,
            live: SuccessorLaunch.Live(name: "x")
        ).get()
        let removal = SuccessorRun.carriedCopyRemoval(plan: plan, marker: "'/m.live'")
        #expect(removal.contains("test -e '/m.live'"))
        #expect(removal.contains("grep -qF"))
        #expect(removal.contains("-home-malpern-local-code-sandpiper--claude-worktrees-transfer-x"))
        #expect(removal.contains("rm -f \"$HOME\"/.claude/projects/"))

        var unCarried = plan
        unCarried.carriedSession = nil
        #expect(SuccessorRun.carriedCopyRemoval(plan: unCarried, marker: "m").isEmpty)
    }

    /// The command itself, run against a home laid out the way linux's was.
    @Test
    func theCarriedCopyCommandRemovesTheCopyAndKeepsTheFork() throws {
        let plan = try SuccessorLaunch.plan(
            briefPath: "", briefText: "", branch: "transfer/x",
            repository: "/home/malpern/local-code/sandpiper",
            scratchRoot: SuccessorLaunch.liveRoot(repository: "/home/malpern/local-code/sandpiper"),
            provider: .claude,
            reportedAgentPath: "/home/malpern/.local/share/mise/installs/claude/latest/claude",
            expectedCommit: String(repeating: "a", count: 40),
            carriedSession: Self.session,
            live: SuccessorLaunch.Live(name: "x")
        ).get()
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("carry-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let folder = home.appendingPathComponent(
            ".claude/projects/" + TranscriptCarry.projectDirectoryName(for: plan.workingDirectory)
        )
        let sidecar = folder.appendingPathComponent(Self.session)
        try FileManager.default.createDirectory(at: sidecar, withIntermediateDirectories: true)
        let copy = folder.appendingPathComponent("\(Self.session).jsonl")
        let fork = folder.appendingPathComponent("7b637a40-46b5-455d-8d00-10532e498a8b.jsonl")
        try "{\"uuid\":\"a1\"}\n{\"uuid\":\"b2\"}\n".write(to: copy, atomically: true, encoding: .utf8)
        try "{\"uuid\":\"a1\"}\n{\"uuid\":\"b2\"}\n{\"uuid\":\"c3\"}\n"
            .write(to: fork, atomically: true, encoding: .utf8)
        let marker = home.appendingPathComponent("m.live")

        func run() throws {
            let shell = Process()
            shell.executableURL = URL(fileURLWithPath: "/bin/sh")
            shell.arguments = ["-c", "true" + SuccessorRun.carriedCopyRemoval(
                plan: plan, marker: RemoteShell.quoted(marker.path))]
            shell.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin"]
            try shell.run()
            shell.waitUntilExit()
            #expect(shell.terminationStatus == 0)
        }

        // A session that never started keeps everything.
        try run()
        #expect(FileManager.default.fileExists(atPath: copy.path))

        FileManager.default.createFile(atPath: marker.path, contents: nil)
        try run()
        #expect(!FileManager.default.fileExists(atPath: copy.path))
        #expect(!FileManager.default.fileExists(atPath: sidecar.path))
        #expect(FileManager.default.fileExists(atPath: fork.path))
    }
}
