import Foundation
import Testing

@testable import LittleHerd

@MainActor
@Suite("Transfer coordinator")
struct TransferCoordinatorTests {
    private func transfer(title: String = "Fan layout") -> Transfer {
        Transfer(
            origin: MachineID(rawValue: "air"),
            destination: MachineID(rawValue: "mini"),
            branch: "transfer/fan",
            title: title,
            repository: "/repo"
        )
    }

    private func steps() -> [SuccessorRun.Step] {
        SuccessorRun.steps(
            plan: SuccessorLaunch.Plan(
                expectedCommit: String(repeating: "a", count: 40),
                workingDirectory: "/tmp/w",
                executable: "/Users/malpern/.local/bin/claude",
                arguments: ["-p"],
                prompt: "p"
            ),
            repository: "/repo",
            branch: "transfer/fan",
            promptFile: "/tmp/p",
            check: .xcode(scheme: "LittleHerd"),
            commitMessage: "m"
        )
    }

    /// A transfer that ended while nobody was looking is still there when
    /// somebody looks. The whole point of the panel is that work on another
    /// machine does not happen invisibly.
    @Test
    func afinishedTransferSurvivesUntilItIsDismissed() async {
        let coordinator = TransferCoordinator { _ in
            { _ in .init(text: "", succeeded: true) }
        }
        let one = transfer()
        coordinator.begin(one, steps: steps())

        while coordinator.phase(for: one)?.isCancellable != false {
            await Task.yield()
        }

        #expect(coordinator.phase(for: one) == .finished(
            SuccessorOutcome(result: .landed, failingStep: nil, output: "")
        ))
        #expect(coordinator.needingAttention == [one])

        coordinator.dismiss(one)
        #expect(coordinator.phase(for: one) == nil)
        #expect(coordinator.needingAttention.isEmpty)
    }

    /// **A running transfer cannot be dismissed out from under itself.** The
    /// row is not a notification to be swept away; until it is over there is
    /// something on another machine that it is the only record of.
    @Test
    func arunningTransferCannotBeDismissed() {
        let coordinator = TransferCoordinator { _ in
            { _ in
                try? await Task.sleep(for: .seconds(30))
                return .init(text: "", succeeded: true)
            }
        }
        let one = transfer()
        coordinator.begin(one, steps: steps())

        coordinator.dismiss(one)
        #expect(coordinator.phase(for: one) != nil)
        coordinator.cancel(one)
    }

    /// Dragging the same thing twice does not start it twice.
    @Test
    func beginningOneTwiceStartsOneTransfer() {
        let coordinator = TransferCoordinator { _ in
            { _ in
                try? await Task.sleep(for: .seconds(30))
                return .init(text: "", succeeded: true)
            }
        }
        let one = transfer()
        coordinator.begin(one, steps: steps())
        coordinator.begin(one, steps: steps())

        #expect(coordinator.order == [one])
        coordinator.cancel(one)
    }

    /// A cancelled transfer is not something to be chased up: the person who
    /// cancelled it already knows.
    @Test
    func acancelledTransferDoesNotAskForAttention() async {
        let coordinator = TransferCoordinator { _ in
            { _ in .init(text: "", succeeded: true) }
        }
        let one = transfer()
        coordinator.begin(one, steps: steps())
        coordinator.cancel(one)

        while coordinator.phase(for: one)?.isCancellable != false {
            await Task.yield()
        }
        #expect(coordinator.needingAttention.isEmpty)
    }

    /// A red suite is news worth showing, and says so in the words a person
    /// would use — the edits are still on the branch.
    @Test
    func aredRunSaysTheWorkIsStillThere() {
        let phase = TransferPhase.finished(
            SuccessorOutcome(
                result: .checkFailed,
                failingStep: .verification,
                output: "2 failed"
            )
        )
        #expect(phase.wantsAttention)
        // The strip's line is short by necessity; what became of the work is
        // said where there is room for it.
        #expect(phase.summary == "Tests failed")
        #expect(phase.detail.contains("still on the branch"))
        #expect(!phase.isCancellable)
    }
}
