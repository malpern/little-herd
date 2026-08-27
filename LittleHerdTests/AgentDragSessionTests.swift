import Foundation
import Testing
@testable import LittleHerd

/// Every state a token drag can be in, decided outside the gesture handler so
/// it can be argued with.
@MainActor
struct AgentDragSessionTests {
    private let air = MachineID("air")
    private let mini = MachineID("mini")
    private let linux = MachineID("linux")

    private var carrying: AgentDragSession {
        AgentDragSession(
            origin: air,
            activity: MachineAgentActivity(
                provider: .claude,
                sessions: []
            ),
            over: nil
        )
    }

    private func accepts(_ machine: MachineID) -> Bool { machine != linux }

    /// The machine it came from never becomes a target. Its pad stays quiet so
    /// the token has somewhere obvious to fall back to, and so the herd does
    /// not light up as though every machine were a choice.
    @Test
    func theoriginIsNeverATarget() {
        var drag = carrying
        drag.over = air

        #expect(drag.padState(for: air, canAccept: accepts) == .idle)
    }

    /// Everything else that could take it says so before the pointer arrives —
    /// that is the whole point of showing pads during a drag.
    @Test
    func machinesThatCouldTakeItSaySoBeforeYouGetThere() {
        let drag = carrying

        #expect(drag.padState(for: mini, canAccept: accepts) == .available)
        #expect(drag.padState(for: linux, canAccept: accepts) == .refused)
    }

    /// And the one under the pointer is distinct from the ones merely willing.
    @Test
    func theonebeingPointedAtIsDistinctFromTheRest() {
        var drag = carrying
        drag.over = mini

        #expect(drag.padState(for: mini, canAccept: accepts) == .targeted)
        #expect(drag.padState(for: air, canAccept: accepts) == .idle)
    }

    /// A refusal does not become acceptance just because you are hovering it.
    @Test
    func hoveringAMachineThatRefusesDoesNotPersuadeIt() {
        var drag = carrying
        drag.over = linux

        #expect(drag.padState(for: linux, canAccept: accepts) == .refused)
        #expect(drag.outcome(canAccept: accepts) == .refused(linux))
    }

    /// Dropped back where it started is nothing happening, not a failure.
    /// Telling somebody off for changing their mind is a bad way to teach a
    /// gesture.
    @Test
    func droppingItBackHomeIsNotARefusal() {
        var drag = carrying
        drag.over = air

        #expect(drag.outcome(canAccept: accepts) == .cancelled)
    }

    /// Released over nothing at all is the same: cancelled.
    @Test
    func releasedOverNothingIsCancelled() {
        #expect(carrying.outcome(canAccept: accepts) == .cancelled)
    }

    /// And the one case that will eventually do something.
    @Test
    func droppedOnAwillingMachineIsAccepted() {
        var drag = carrying
        drag.over = mini

        #expect(drag.outcome(canAccept: accepts) == .accepted(mini))
    }
}
