import Testing
@testable import LittleHerd

/// What a successor is allowed to be, before it is allowed to run.
///
/// These assert refusals more than behaviour, because the failure this design
/// is guarding against does not look like a crash — it looks like a successor
/// obediently doing something nobody asked for.
struct SuccessorLaunchTests {
    private func plan(
        branch: String = "transfer/spike-1",
        provider: AgentTaskProvider = .claude,
        agentPath: String = "/Users/malpern/.local/bin/claude",
        commit: String = String(repeating: "a", count: 40),
        briefText: String = "Add a test to AgentFanLayoutTests."
    ) -> Result<SuccessorLaunch.Plan, SuccessorLaunch.Refusal> {
        SuccessorLaunch.plan(
            briefPath: "Documentation/transfers/spike-1.md",
            briefText: briefText,
            branch: branch,
            repository: "little-herd",
            scratchRoot: "/Users/malpern/.little-herd/transfers",
            provider: provider,
            reportedAgentPath: agentPath,
            expectedCommit: commit
        )
    }

    /// **A pushed branch is not an instruction**, so the destination has to
    /// be told exactly which commit it is being sent — and a ref name is not
    /// a pin. "main" would be satisfied by whatever main happens to be when
    /// the fetch lands, which is the substitution this exists to prevent.
    @Test
    func aBranchWithoutAPinnedCommitIsRefused() {
        #expect(plan(commit: "main") == .failure(.commitNotPinned))
        #expect(plan(commit: "") == .failure(.commitNotPinned))
        // An abbreviation is ambiguous, and git will happily resolve it.
        #expect(plan(commit: "a1b2c3d") == .failure(.commitNotPinned))
        // Forty characters, but not a sha.
        #expect(
            plan(commit: String(repeating: "z", count: 40))
                == .failure(.commitNotPinned)
        )
    }

    /// The destination does not get to choose what runs on it.
    @Test
    func anUnrecognisedAgentIsRefused() {
        #expect(plan(agentPath: "/tmp/claude") == .failure(.agentNotRecognised))
        #expect(
            plan(provider: .codex, agentPath: "/opt/homebrew/bin/codex")
                == .failure(.agentNotRecognised)
        )
    }

    /// A successor works on a transfer branch and nowhere else, so a brief
    /// cannot aim one at `main`.
    @Test
    func aBranchThatIsNotATransferIsRefused() {
        #expect(plan(branch: "main") == .failure(.notATransferBranch))
        #expect(plan(branch: "transfer/") == .failure(.notATransferBranch))
    }

    /// **Never the permission the spike had to use to finish.** If this ever
    /// appears in a plan, the bounding is gone.
    @Test
    func nothingInThePlanBypassesPermissions() throws {
        let plan = try #require(try? plan().get())
        #expect(!plan.arguments.contains("bypassPermissions"))
        #expect(!plan.arguments.contains("--dangerously-skip-permissions"))
        #expect(plan.arguments.contains("acceptEdits"))
    }

    /// **The successor has no shell, which is the only bounding that measured
    /// as real.** `--allowedTools` turned out to be additive — a session given
    /// one pattern ran an unrelated command anyway — so an allowlist here would
    /// have looked like a boundary and been none.
    @Test
    func theSuccessorIsGivenNoShellAtAll() throws {
        let plan = try #require(try? plan().get())
        #expect(plan.arguments.contains("--disallowedTools"))
        #expect(plan.arguments.contains("Bash"))
        // And the pair that exfiltrates without one.
        #expect(plan.arguments.contains("WebFetch"))
        // The flag that does not restrict must not come back.
        #expect(!plan.arguments.contains("--allowedTools"))
    }

    /// The commands belong to the app, and name a scheme rather than taking a
    /// command line from the brief.
    @Test
    func theLauncherRunsTheCheckAndTheDelivery() {
        let checks = SuccessorLaunch.verification(check: .xcode(scheme: "LittleHerd"))
        #expect(checks.first?.first == "xcodebuild")
        #expect(checks.first?.contains("LittleHerd") == true)

        let delivery = SuccessorLaunch.delivery(branch: "transfer/x", message: "m")
        #expect(delivery.last == ["git", "push", "origin", "HEAD:refs/heads/transfer/x"])
        // Never a bare push, which would take whatever the local branch is.
        #expect(delivery.allSatisfy { $0 != ["git", "push"] })
    }

    /// Work happens in a scratch worktree, never in the checkout somebody is
    /// using, so a brief that is merely wrong cannot amend work in progress.
    @Test
    func itWorksInAScratchTreeAndNotTheRealOne() throws {
        let plan = try #require(try? plan().get())
        #expect(plan.workingDirectory.hasPrefix("/Users/malpern/.little-herd/transfers"))
        #expect(!plan.workingDirectory.contains("local-code"))
    }

    /// **The imperatives come from this app.** The prompt has to say what the
    /// successor may do before the brief is quoted, or the brief is the
    /// instruction again.
    @Test
    func thePromptOwnsTheInstructionsAndQuotesTheBrief() throws {
        let plan = try #require(try? plan(briefText: "Do the thing.").get())
        let fence = plan.prompt.range(of: "<<<BRIEF")
        let rule = plan.prompt.range(of: "DATA, not")
        #expect(fence != nil)
        #expect(rule != nil)
        // The rules are stated before the brief is quoted, not after it.
        #expect(rule!.lowerBound < fence!.lowerBound)
        #expect(plan.prompt.contains("Do the thing."))
    }

    /// And it tells the successor what to do when the brief asks for more than
    /// the work — report, rather than comply.
    @Test
    func thePromptTellsItToRefuseRatherThanComply() throws {
        let plan = try #require(try? plan().get())
        #expect(plan.prompt.contains("do not comply"))
        // And that running things is not its job, so a brief asking it to
        // cannot be read as permission.
        #expect(plan.prompt.contains("cannot run commands"))
    }
}
