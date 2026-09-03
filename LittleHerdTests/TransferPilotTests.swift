import Foundation
import Testing

@testable import LittleHerd

/// A flag a `@Sendable` closure may set.
nonisolated private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func raise() {
        lock.lock()
        value = true
        lock.unlock()
    }

    var isRaised: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

@Suite("Transfer pilot")
struct TransferPilotTests {
    nonisolated private static let sha = "4f2c1a9e8b7d6c5a4f3e2d1c0b9a8f7e6d5c4b3a"

    private func departureSteps() -> [TransferDeparture.Step] {
        TransferDeparture.steps(
            repository: "/repo",
            branch: "transfer/fan",
            sessionIdentifier: "abc",
            provider: .claude,
            agentExecutable: "/Users/malpern/.local/bin/claude",
            briefPath: "Documentation/transfers/x.md",
            prompt: "brief",
            message: "m"
        )
    }

    /// **`git push` narrates, and the narration contains things that look like
    /// answers.** The sha is read from the end, and only a full one counts.
    @Test
    func theShaIsReadPastEverythingPushSays() {
        let output = """
            Enumerating objects: 12, done.
            remote: Resolving deltas: 100% (3/3)
            To github.com:malpern/little-herd.git
             * [new branch]      transfer/fan -> transfer/fan
            \(Self.sha)
            """
        #expect(TransferPilot.commit(inPushOutput: output) == Self.sha)
    }

    /// A push that said nothing usable is a failure, not a guess.
    @Test
    func aPushThatReportsNoShaIsAFailure() async {
        let outcome = await TransferPilot.depart(steps: departureSteps()) { _ in
            .init(text: "Everything up-to-date", succeeded: true)
        }
        #expect(outcome == .failure(.noCommitReported))
    }

    /// And an abbreviation is not a sha. Accepting one here would defeat the
    /// pin on the far side, which exists precisely because a short or
    /// ambiguous ref can resolve to something else.
    @Test
    func anAbbreviatedShaIsNotAccepted() {
        #expect(TransferPilot.commit(inPushOutput: "4f2c1a9") == nil)
        #expect(TransferPilot.commit(inPushOutput: "transfer/fan") == nil)
    }

    /// The happy path, end to end and without a machine: the source reports a
    /// commit, and the destination's steps are pinned to that exact commit.
    @Test
    func theCommitTheSourcePushedIsWhatTheDestinationIsPinnedTo() async throws {
        let departed = await TransferPilot.depart(steps: departureSteps()) {
            step in
            .init(
                text: step.purpose == .push ? "To origin\n\(Self.sha)" : "",
                succeeded: true
            )
        }
        let commit = try departed.get()
        #expect(commit == Self.sha)

        let steps = try TransferPilot.arrival(
            commit: commit,
            briefPath: "Documentation/transfers/fan.md",
            briefText: "brief",
            branch: "transfer/fan",
            repository: "/repo",
            scratchRoot: "/tmp/herd",
            provider: .claude,
            reportedAgentPath: "/Users/malpern/.local/bin/claude",
            check: .xcode(scheme: "LittleHerd"),
            commitMessage: "m"
        ).get()

        let worktree = try #require(steps.first { $0.purpose == .worktree })
        #expect(worktree.command.contains(Self.sha))
    }

    /// A failed departure never reaches the destination, and still tidies up.
    @Test
    func afailedDepartureSaysWhichStepAndStillCleansUp() async {
        let cleaned = Flag()
        let outcome = await TransferPilot.depart(steps: departureSteps()) {
            step in
            if step.purpose == .cleanup { cleaned.raise() }
            return .init(
                text: step.purpose == .capture ? "nothing to commit" : "",
                succeeded: step.purpose != .capture
            )
        }

        #expect(outcome == .failure(.departure(.capture, "nothing to commit")))
        #expect(cleaned.isRaised)
    }

    /// A refusal on the destination side is carried through rather than
    /// flattened into a generic failure.
    @Test
    func adestinationRefusalSurvivesTheJoin() {
        let result = TransferPilot.arrival(
            commit: Self.sha,
            briefPath: "b.md",
            briefText: "b",
            branch: "main",
            repository: "/repo",
            scratchRoot: "/tmp",
            provider: .claude,
            reportedAgentPath: "/Users/malpern/.local/bin/claude",
            check: .xcode(scheme: "LittleHerd"),
            commitMessage: "m"
        )
        #expect(result == .failure(.refused(.notATransferBranch)))
    }
}
