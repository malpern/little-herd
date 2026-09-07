import Foundation
import Testing

@testable import LittleHerd

/// Carrying the session itself instead of a summary of it.
@Suite("Carrying a transcript")
struct TranscriptCarryTests {
    /// **The encoding is Claude's, and it was read off a real machine rather
    /// than guessed.** Every `/` and every `.` becomes a dash, which is why
    /// `/.claude` produces two of them in a row — not a separator, just two
    /// characters that each turn into one.
    @Test
    func aworkingDirectoryBecomesItsProjectFolder() {
        #expect(
            TranscriptCarry.projectDirectoryName(
                for: "/Users/malpern/local-code/little-herd"
            ) == "-Users-malpern-local-code-little-herd"
        )
        // The case that shows the rule: a worktree inside `.claude`.
        #expect(
            TranscriptCarry.projectDirectoryName(
                for: "/Users/malpern/local-code/little-herd/.claude/worktrees/w"
            ) == "-Users-malpern-local-code-little-herd--claude-worktrees-w"
        )
    }

    /// **The destination folder follows where the successor will run, not
    /// where the session used to be**, and that is the finding the whole design
    /// rests on: a transcript resumes from wherever it is placed, with its
    /// history intact, even though every path recorded inside it is now wrong.
    /// Tested against the real thing before this was written.
    @Test
    func thedestinationFollowsTheSuccessorNotTheSource() {
        let source = TranscriptCarry.transcriptPath(
            home: "/Users/a",
            workingDirectory: "/Users/a/local-code/herd",
            sessionIdentifier: "abc"
        )
        #expect(source == "/Users/a/.claude/projects/-Users-a-local-code-herd/abc.jsonl")

        // A different machine, a different account, a scratch worktree: none of
        // it has to match, which is what the first write-up of this got wrong.
        let destination = TranscriptCarry.destinationDirectory(
            home: "/Users/b",
            successorWorkingDirectory: "/Users/b/.little-herd/transfers/transfer-x"
        )
        #expect(
            destination
                == "/Users/b/.claude/projects/-Users-b--little-herd-transfers-transfer-x"
        )
    }

    /// The carry takes the whole record: the transcript and the sidecar
    /// beside it, both under the source's own project folder.
    @Test
    func thesourcePathsNameTheTranscriptAndItsSidecar() {
        let paths = TranscriptCarry.sourcePaths(
            home: "/Users/a", workingDirectory: "/Users/a/x", sessionIdentifier: "s"
        )
        #expect(paths.transcript == "/Users/a/.claude/projects/-Users-a-x/s.jsonl")
        #expect(paths.sidecar == "/Users/a/.claude/projects/-Users-a-x/s")
    }

    /// **A transcript still being written is refused.** Two looks at its size
    /// a beat apart; a difference means a live writer, and a copy taken then is
    /// torn — a session missing its last turns, silently. The command also
    /// refuses an absent or empty file, for the reason the brief learned: a
    /// step must not report success having produced nothing.
    @Test
    func thestabilityCheckLooksTwiceAndRefusesAnEmptyFile() {
        let command = TranscriptCarry.stabilityCommand(transcript: "/Users/a/t.jsonl")
        #expect(command.hasPrefix("test -s "))
        #expect(command.components(separatedBy: "stat -f %z").count == 3, "must look twice")
        #expect(command.contains("sleep 1"))
        #expect(command.contains(#"test "$a" = "$b""#))
        // Both stats, because the source may be a Mac or a Linux box and they
        // spell it differently — the same lesson the folder scanner learned.
        #expect(command.contains("stat -c %s"))
    }

    /// **The first line says it has moved.** The boundary is what stops a
    /// stale memory editing the wrong tree; this is what stops it trying.
    @Test
    func themovedNoticeNamesBothPlacesAndForbidsTheOld() {
        let notice = TranscriptCarry.movedNotice(
            from: "/Users/a/old", to: "/Users/b/scratch"
        )
        #expect(notice.contains("/Users/b/scratch"))
        #expect(notice.contains("/Users/a/old"))
        #expect(notice.contains("do not"))
        #expect(notice.hasPrefix("You have been moved"))
    }

    /// **Forked, never resumed as itself.** Two machines holding one identifier
    /// would be one conversation with two divergent histories and nothing to
    /// merge them. The original is left exactly as it was, which is the promise
    /// the transfer already makes about the work.
    @Test
    func thesuccessorForksRatherThanBecomingTheSession() {
        let arguments = TranscriptCarry.resumeArguments(sessionIdentifier: "abc")
        #expect(arguments.contains("--fork-session"))
        #expect(arguments.contains("--resume"))
        #expect(arguments.contains("abc"))
    }

    /// **Only what the mechanism actually fits.** Codex keeps its rollouts
    /// somewhere else, so offering to carry one and quietly writing a brief
    /// instead would be worse than not offering.
    @Test
    func onlyaclaudeSessionWithAdirectoryCanBeCarried() {
        func session(_ provider: AgentTaskProvider, directory: String?) -> AgentSession {
            AgentSession(
                id: "x", provider: provider, projectName: "p", state: .waiting,
                updatedAt: .now, progress: nil, workingDirectory: directory
            )
        }
        #expect(TranscriptCarry.canCarry(session(.claude, directory: "/Users/a/x")))
        #expect(!TranscriptCarry.canCarry(session(.codex, directory: "/Users/a/x")))
        #expect(!TranscriptCarry.canCarry(session(.claude, directory: nil)))
        #expect(!TranscriptCarry.canCarry(session(.claude, directory: "")))
    }

    /// A path with a space in it is one argument, on both ends. This herd has
    /// one, so it is not hypothetical.
    @Test
    func pathsAreQuoted() {
        let command = TranscriptCarry.stabilityCommand(
            transcript: "/Users/a/.claude/projects/-Users-a-Some Folder/s.jsonl"
        )
        #expect(command.contains("'/Users/a/.claude/projects/-Users-a-Some Folder/s.jsonl'"))
    }
}

/// The launcher, when it is handed a session instead of a brief.
@Suite("Resuming a carried session")
struct CarriedLaunchTests {
    private func plan(carried: String?) -> SuccessorLaunch.Plan? {
        try? SuccessorLaunch.plan(
            briefPath: "/Users/a/local-code/x",
            briefText: "the brief",
            branch: "transfer/x",
            repository: "/Users/b/local-code/x",
            scratchRoot: "/Users/b/.little-herd/transfers",
            provider: .claude,
            reportedAgentPath: "/Users/b/.local/bin/claude",
            expectedCommit: String(repeating: "a", count: 40),
            carriedSession: carried
        ).get()
    }

    /// **Resumed and forked, with the same guardrails as a fresh start.** The
    /// permission mode is the boundary that stops a stale memory reaching a
    /// path outside the scratch directory, so it is exactly the thing that
    /// must not differ between the two shapes of successor.
    @Test
    func acarriedSessionIsResumedForkedAndFenced() throws {
        let carried = try #require(plan(carried: "abc-123"))
        let fresh = try #require(plan(carried: nil))

        #expect(carried.arguments.contains("--resume"))
        #expect(carried.arguments.contains("abc-123"))
        #expect(carried.arguments.contains("--fork-session"))
        #expect(!fresh.arguments.contains("--resume"))

        for guardrail in ["--permission-mode", "acceptEdits", "--disallowedTools", "Bash"] {
            #expect(carried.arguments.contains(guardrail), "\(guardrail) missing from the carried launch")
            #expect(fresh.arguments.contains(guardrail))
        }
    }

    /// The carried prompt says what changed and nothing the session already
    /// knows: the brief is *not* in it, because the whole point is that the
    /// history is.
    @Test
    func thecarriedPromptSaysItMovedAndOmitsTheBrief() throws {
        let carried = try #require(plan(carried: "abc-123"))
        #expect(carried.prompt.hasPrefix("You have been moved"))
        #expect(carried.prompt.contains(carried.workingDirectory))
        #expect(!carried.prompt.contains("the brief"))

        let fresh = try #require(plan(carried: nil))
        #expect(fresh.prompt.contains("the brief"))
    }

    /// One function decides where a successor works, so the transcript and
    /// the launcher cannot disagree about it.
    @Test
    func thescratchDirectoryHasOneDescription() throws {
        let carried = try #require(plan(carried: "abc-123"))
        #expect(
            carried.workingDirectory
                == SuccessorLaunch.workingDirectory(
                    scratchRoot: "/Users/b/.little-herd/transfers", branch: "transfer/x"
                )
        )
    }
}

/// The driver's carry step, with every machine faked.
@Suite("Carrying, and falling back")
struct DriverCarryTests {
    private func makeRequest(provider: AgentTaskProvider = .claude, directory: String? = "/Users/a/x")
        -> TransferAssembly.Request?
    {
        func account(_ id: String, home: String) -> DestinationAccount {
            DestinationAccount(
                machine: MachineID(id), name: id, symbolName: "desktopcomputer",
                report: DestinationReport(
                    installations: [
                        AgentInstallation(provider: provider, version: "1",
                                          path: "\(home)/.local/bin/\(provider.rawValue)")
                    ],
                    checkouts: ["x": "\(home)/x"]
                ),
                mayHostSessions: true, auth: .unverified, isVerifying: false
            )
        }
        let session = AgentSession(
            id: "\(provider.rawValue):s-1", provider: provider, projectName: "x",
            state: .waiting, updatedAt: .now, progress: nil,
            workingDirectory: directory
        )
        return try? TransferAssembly.request(
            session: session, from: MachineID("a"), to: MachineID("b"),
            in: [account("a", home: "/Users/a"), account("b", home: "/Users/b")],
            check: .none
        ).get()
    }

    private func carry(
        home: String? = "/Users/a",
        still: Bool = true,
        copies: Bool = true,
        record: Recorder = Recorder()
    ) -> TransferDriver.Carry {
        TransferDriver.Carry(
            localSourceHome: home,
            sourceCommand: { _ in ("", still) },
            copy: { local, remote, recursive in
                record.add("\(local) -> \(remote)\(recursive ? " -r" : "")")
                return copies
            },
            destinationHome: "/Users/b",
            scratchRoot: "/Users/b/.little-herd/transfers",
            // These fixtures test where a file lands and why a carry declines, using
            // paths that do not exist on disk. Scrubbing reads the file, so it is turned
            // off here; the scrub has its own suite, and its default has its own test.
            redacts: false
        )
    }

    /// The happy path, and where the file lands: under the project folder for
    /// the **scratch** directory, which is where the successor will look.
    @Test
    func acarriedTranscriptLandsWhereTheSuccessorWillLook() async throws {
        let request = try #require(makeRequest())
        let record = Recorder()
        let outcome = await TransferDriver.carryTranscript(request, carry: carry(record: record))
        guard case .carried = outcome else {
            Issue.record("expected carried, got \(outcome)")
            return
        }
        let copies = record.lines
        #expect(copies.first?.hasPrefix("/Users/a/.claude/projects/-Users-a-x/s-1.jsonl -> ") == true)
        #expect(copies.first?.contains("/Users/b/.claude/projects/-Users-b--little-herd-transfers-transfer-") == true)
    }

    /// **Every refusal falls back, and says why.** A carry that failed silently
    /// would be a successor with no history and no brief.
    @Test
    func eachReasonNotToCarryFallsBackWithItsReason() async throws {
        let request = try #require(makeRequest())

        if case .fellBack(let why) = await TransferDriver.carryTranscript(request, carry: carry(home: nil)) {
            #expect(why.contains("another machine"))
        } else { Issue.record("a remote source must fall back") }

        if case .fellBack(let why) = await TransferDriver.carryTranscript(request, carry: carry(still: false)) {
            #expect(why.contains("still being written"))
        } else { Issue.record("an unstable transcript must fall back") }

        if case .fellBack(let why) = await TransferDriver.carryTranscript(request, carry: carry(copies: false)) {
            #expect(why.contains("could not be copied"))
        } else { Issue.record("a failed copy must fall back") }

        let codex = try #require(makeRequest(provider: .codex))
        if case .fellBack(let why) = await TransferDriver.carryTranscript(codex, carry: carry()) {
            #expect(why.contains("Claude"))
        } else { Issue.record("a Codex session must fall back") }
    }
}

/// Collects what a `@Sendable` closure saw.
private nonisolated final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var value: [String] = []
    var lines: [String] { lock.withLock { value } }
    func add(_ line: String) { lock.withLock { value.append(line) } }
}

/// The order the driver does things in, which the first live carry got wrong.
@Suite("Carry before brief")
struct CarryOrderingTests {
    private func request() -> TransferAssembly.Request? {
        func account(_ id: String, home: String) -> DestinationAccount {
            DestinationAccount(
                machine: MachineID(id), name: id, symbolName: "desktopcomputer",
                report: DestinationReport(
                    installations: [
                        AgentInstallation(provider: .claude, version: "1", path: "\(home)/.local/bin/claude")
                    ],
                    checkouts: ["x": "\(home)/x"]
                ),
                mayHostSessions: true, auth: .unverified, isVerifying: false
            )
        }
        let session = AgentSession(
            id: "claude:s-1", provider: .claude, projectName: "x", state: .waiting,
            updatedAt: .now, progress: nil, workingDirectory: "/Users/a/x"
        )
        return try? TransferAssembly.request(
            session: session, from: MachineID("a"), to: MachineID("b"),
            in: [account("a", home: "/Users/a"), account("b", home: "/Users/b")],
            check: .none
        ).get()
    }

    private func carry(copies: Bool) -> TransferDriver.Carry {
        TransferDriver.Carry(
            localSourceHome: "/Users/a",
            sourceCommand: { _ in ("", true) },
            copy: { _, _, _ in copies },
            destinationHome: "/Users/b",
            scratchRoot: "/Users/b/.little-herd/transfers",
            redacts: false  // ordering test; the scrub has its own suite
        )
    }

    /// **A carried session is never asked for a brief.** The brief is a model
    /// call the successor does not need, and for a large session it is one
    /// that fails — "Prompt is too long" on a 24 MB transcript. The departure
    /// runner is handed in and must never see a `.brief` step.
    @Test
    func acarriedSessionSkipsTheBrief() async throws {
        let request = try #require(request())
        let seen = Recorder()
        _ = await TransferDriver.prepare(
            request,
            carry: carry(copies: true),
            departure: { step in
                seen.add("\(step.purpose)")
                return SuccessorExecutor.StepOutput(text: "", succeeded: false)
            }
        )
        #expect(!seen.lines.contains("brief"), "the brief ran for a carried session")
        #expect(seen.lines.contains("capture") || seen.lines.contains("push") || seen.lines.contains("cleanup"),
                "the rest of the departure must still run")
    }

    /// And a carry that declines leaves the brief exactly as it was, so the
    /// successor is never left with neither.
    @Test
    func adeclinedCarryKeepsTheBrief() async throws {
        let request = try #require(request())
        let seen = Recorder()
        _ = await TransferDriver.prepare(
            request,
            carry: carry(copies: false),
            departure: { step in
                seen.add("\(step.purpose)")
                return SuccessorExecutor.StepOutput(text: "", succeeded: false)
            }
        )
        #expect(seen.lines.contains("brief"), "the brief must run when the carry falls back")
    }
}
