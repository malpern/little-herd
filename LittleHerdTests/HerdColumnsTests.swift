import CoreGraphics
import Testing
@testable import LittleHerd

/// Where a carried token thinks it is.
struct HerdColumnsTests {
    private let columns = HerdColumns(
        ids: [MachineID("air"), MachineID("mini"), MachineID("linux"), MachineID("nas")],
        stride: 72
    )

    /// Held still, a token is over the machine it came from. The bug this
    /// replaces failed exactly here: it read a coordinate rather than a
    /// distance, so a motionless token was already over its neighbour.
    @Test
    func aTokenThatHasNotMovedIsStillHome() {
        #expect(columns.machine(draggedFrom: MachineID("air"), displacedBy: 0) == MachineID("air"))
    }

    /// A column is claimed from halfway, not from full overlap.
    @Test
    func aColumnIsClaimedFromHalfway() {
        let air = MachineID("air")
        #expect(columns.machine(draggedFrom: air, displacedBy: 35) == air)
        #expect(columns.machine(draggedFrom: air, displacedBy: 37) == MachineID("mini"))
    }

    /// It counts from wherever it was picked up, not from the left edge.
    @Test
    func itCountsFromWhereItWasPickedUp() {
        #expect(
            columns.machine(draggedFrom: MachineID("linux"), displacedBy: -72)
                == MachineID("mini")
        )
    }

    /// Carried off the end of the herd is over nothing, not over the last one.
    /// Clamping would make the edge machine a magnet that accepts every
    /// overshoot.
    @Test
    func carriedOffTheEndIsOverNothing() {
        #expect(columns.machine(draggedFrom: MachineID("nas"), displacedBy: 200) == nil)
        #expect(columns.machine(draggedFrom: MachineID("air"), displacedBy: -200) == nil)
    }

    /// A machine that is not in the herd cannot be the origin of anything.
    @Test
    func anUnknownOriginIsOverNothing() {
        #expect(columns.machine(draggedFrom: MachineID("ghost"), displacedBy: 0) == nil)
    }
}
