import Foundation
import Testing

@testable import LittleHerd

@Suite("Successor over SSH")
struct SuccessorSSHTests {
    /// Asserts the *relationships*, not the numbers. A test that repeats the
    /// constant back proves only that somebody typed it twice; what matters is
    /// that the agent gets longer than the suite it will run, and that the
    /// bookkeeping around both stays short enough to fail fast.
    @Test
    func eachKindOfStepIsTimedForWhatItActuallyDoes() {
        let agent = SuccessorSSH.timeout(for: .agent)
        let check = SuccessorSSH.timeout(for: .verification)
        let push = SuccessorSSH.timeout(for: .delivery)
        let worktree = SuccessorSSH.timeout(for: .worktree)

        #expect(agent > check)
        #expect(check > push)
        #expect(push > worktree)
        // Bookkeeping either works at once or is wedged.
        #expect(worktree <= 60)
        // And an agent working through a real brief is allowed a real amount
        // of time, or every useful transfer is killed part-way.
        #expect(agent >= 20 * 60)
    }

    /// A host that could be read as a flag never reaches `ssh`. `SSHHostName`
    /// covers this, and the successor path is new enough to be worth checking
    /// it is actually going through it.
    @Test
    func ahostileHostNameIsRefusedRatherThanRun() async {
        let result = await SSHCommandRunner.runReportingStatus(
            host: "-oProxyCommand=touch /tmp/little-herd-should-not-exist",
            command: "true",
            timeout: 5
        )
        #expect(!result.succeeded)
        #expect(
            !FileManager.default.fileExists(
                atPath: "/tmp/little-herd-should-not-exist"
            )
        )
    }
}
