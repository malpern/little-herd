import Foundation
import Testing

@testable import LittleHerd

@Suite("Transfer departure")
struct TransferDepartureTests {
    private static let brief = "Where I got to'; rm -rf ~; echo '"

    private func steps() -> [TransferDeparture.Step] {
        TransferDeparture.steps(
            repository: "/Users/malpern/local-code/little-herd",
            branch: "transfer/fan",
            sessionIdentifier: "abc123",
            provider: .claude,
            agentExecutable: "/Users/malpern/.local/bin/claude",
            promptFile: "/tmp/herd/prompt",
            indexFile: "/tmp/herd/index",
            prompt: Self.brief,
            message: "Carry the work"
        )
    }

    /// **Nothing may touch the working copy, the index, or HEAD.** Measured
    /// against real git: the scratch-index version leaves `git status`
    /// byte-identical, while a plain `add -A` flattens a staged/unstaged split
    /// into one staged blob — somebody's real work, destroyed as a side effect
    /// of dragging an icon.
    @Test
    func theUsersCheckoutIsNeverTouched() {
        for step in steps() {
            #expect(!step.command.contains("git checkout"))
            #expect(!step.command.contains("git switch"))
            #expect(!step.command.contains("stash"))
            #expect(!step.command.contains("git reset"))
            // Any staging at all happens in a scratch index, never the real
            // one. This is the line that does the work.
            if step.command.contains("add -A") {
                #expect(step.command.contains("GIT_INDEX_FILE="))
            }
        }
    }

    /// The same rule as the successor's prompt, for the same reason: the brief
    /// is the one string here this app did not write.
    @Test
    func thepromptIsOnlyEverSentEncoded() throws {
        let commands = steps().map(\.command)
        for command in commands {
            #expect(!command.contains("rm -rf ~"))
        }
        let staged = try #require(commands.first { $0.contains("base64 -d") })
        let payload = try #require(
            staged.split(separator: "'").first { $0.count > 20 }
        )
        let decoded = try #require(Data(base64Encoded: String(payload)))
        #expect(
            String(decoding: decoded, as: UTF8.self).contains("rm -rf ~")
        )
    }

    /// It is the session's own account of itself, which is what `--resume`
    /// buys — a summary assembled from outside would be a different document
    /// wearing its voice.
    @Test
    func thesessionIsAskedRatherThanSummarised() throws {
        let brief = try #require(
            steps().last { $0.purpose == .brief }
        )
        #expect(brief.command.contains("--resume"))
        #expect(brief.command.contains("abc123"))
        // And it writes one file; it gets no shell either.
        #expect(brief.command.contains("--disallowedTools"))
        #expect(brief.command.contains("Bash"))
        // And the prompt is piped, never trailing — see SuccessorRun.
        #expect(brief.command.contains("cat '/tmp/herd/prompt' |"))
        #expect(!brief.command.contains("$(cat"))
    }

    /// The sha is what the destination is pinned to, so it has to come back.
    @Test
    func thepushReportsTheCommitItPushed() throws {
        let push = try #require(steps().first { $0.purpose == .push })
        #expect(push.command.contains("rev-parse"))
        #expect(push.command.contains("refs/heads/transfer/fan"))
    }

    /// The scratch index is removed whatever happened, like the successor's
    /// worktree.
    @Test
    func thescratchIndexIsAlwaysTidiedAway() throws {
        let last = try #require(steps().last)
        #expect(last.purpose == .cleanup)
        #expect(!last.isFatal)
        #expect(last.command.contains("/tmp/herd/index"))
    }
}
