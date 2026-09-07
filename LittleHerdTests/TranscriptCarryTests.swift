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
