import Foundation
import Testing

@testable import LittleHerd

@Suite("Transfer strip")
struct TransferStripTests {
    private func finished(_ result: SuccessorOutcome.Result) -> TransferPhase {
        .finished(
            SuccessorOutcome(result: result, failingStep: nil, output: "")
        )
    }

    /// **A running transfer offers to stop; a finished one offers to go away.**
    /// Stopping work on another machine and clearing a row you have read are
    /// different enough that one control must not do both.
    @Test
    func theControlMatchesWhatIsPossible() {
        #expect(TransferPhase.preparing.control == .stop)
        #expect(TransferPhase.running(.agent).control == .stop)
        #expect(finished(.landed).control == .dismiss)
        #expect(finished(.cancelled).control == .dismiss)
    }

    /// A red check is not an error to be cleared away — it is work waiting on
    /// a branch — so it reads as something to look at rather than something
    /// that went wrong.
    @Test
    func aRedCheckAsksToBeRead() {
        #expect(finished(.checkFailed).tint == .wantsReading)
        #expect(finished(.agentFailed).tint == .wantsReading)
        #expect(finished(.couldNotStart).tint == .wantsReading)
        #expect(finished(.landed).tint == .landed)
    }

    /// **Cancelling is not failing.** The person who stopped it already knows,
    /// so it is neither coloured like a problem nor asks for attention.
    @Test
    func cancellingIsNotAFailure() {
        #expect(finished(.cancelled).tint == .quiet)
        #expect(!finished(.cancelled).wantsAttention)
        #expect(finished(.checkFailed).wantsAttention)
    }

    /// **The strip's line fits and the detail says what became of the work.**
    /// The two exist separately because the useful half of a one-line summary
    /// is the half that gets truncated in a 324-point window.
    @Test
    func theShortLineFitsAndTheLongOneExplains() {
        let red = finished(.checkFailed)
        #expect(red.summary.count <= 16)
        #expect(red.detail.contains("still on the branch"))
        #expect(finished(.couldNotStart).detail.contains("nothing was changed"))
        #expect(TransferPhase.running(.agent).detail.contains("working"))
    }

    /// Every phase says something a person would recognise, and none of them
    /// says the step's own name.
    @Test
    func everyPhaseHasWordsForIt() {
        let phases: [TransferPhase] = [
            .preparing,
            .running(.worktree), .running(.prompt), .running(.agent),
            .running(.verification), .running(.delivery), .running(.cleanup),
            finished(.landed), finished(.checkFailed), finished(.agentFailed),
            finished(.couldNotStart), finished(.cancelled),
        ]
        for phase in phases {
            #expect(!phase.summary.isEmpty)
            #expect(!phase.summary.contains("("))
        }
    }
}

/// A flag a `@Sendable` closure may set.
nonisolated final class TouchFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func raise() { lock.lock(); value = true; lock.unlock() }
    var isRaised: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

@MainActor
@Suite("Rehearsal")
struct TransferRehearsalTests {
    private let transfer = Transfer(
        origin: MachineID("local"),
        destination: MachineID("mini"),
        branch: "transfer/x",
        title: "Fan layout"
    )

    /// **A rehearsal must not be able to reach a machine.** The coordinator is
    /// given a runner that fails the test outright if it is ever called, so a
    /// rehearsal that quietly started doing something real would not pass.
    @Test
    func aRehearsalRunsNothing() async {
        let touched = TouchFlag()
        let coordinator = TransferCoordinator { _ in
            { _ in
                touched.raise()
                return .init(text: "", succeeded: true)
            }
        }
        coordinator.rehearse(transfer)
        // Long enough to be well into the scripted phases.
        try? await Task.sleep(for: .milliseconds(1500))
        #expect(!touched.isRaised)
        #expect(coordinator.phase(for: transfer)?.isCancellable == true)
        coordinator.cancel(transfer)
    }

    /// It still reports phases, or there would be nothing to look at.
    @Test
    func aRehearsalReportsProgress() async {
        let coordinator = TransferCoordinator { _ in
            { _ in .init(text: "", succeeded: true) }
        }
        coordinator.rehearse(transfer)
        try? await Task.sleep(for: .milliseconds(1400))
        #expect(coordinator.phase(for: transfer) == .running(.prompt))
        coordinator.cancel(transfer)
    }
}

@MainActor
@Suite("Clearing finished rows")
struct TransferClearingTests {
    private let transfer = Transfer(
        origin: MachineID("local"),
        destination: MachineID("mini"),
        branch: "transfer/y",
        title: "Fan layout"
    )

    private func coordinator(
        _ succeed: Bool
    ) -> TransferCoordinator {
        TransferCoordinator { _ in
            { step in
                .init(
                    text: "",
                    succeeded: succeed || step.purpose != .verification
                )
            }
        }
    }

    /// **A transfer that worked takes its own row away.** The card already
    /// said so — a tick, a chime, and the card standing on the machine it
    /// moved to — and a line of text repeating it only asks to be dismissed.
    @Test
    func aSuccessClearsItself() async {
        let one = coordinator(true)
        one.begin(transfer, steps: [])
        try? await Task.sleep(for: .milliseconds(1900))
        #expect(one.phase(for: transfer) == nil)
    }

    /// **A failure stays.** The card coming home says it did not work; only
    /// the row says why, and that difference decides what you do next.
    @Test
    func aFailureWaitsToBeRead() async {
        let one = coordinator(false)
        one.begin(
            transfer,
            steps: [
                .init(purpose: .verification, command: "x", isFatal: true)
            ]
        )
        try? await Task.sleep(for: .milliseconds(1900))
        #expect(one.phase(for: transfer) != nil)
        #expect(one.needingAttention == [transfer])
    }
}
