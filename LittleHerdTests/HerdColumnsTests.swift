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

/// Which way the card over a token opens. Arithmetic over the herd, and the
/// last piece of arithmetic over the herd shipped with an off-by-one in it.
struct AgentCardSideTests {
    /// A machine on the left opens right, into the window rather than over the
    /// herd — and, at the left edge, rather than off the screen.
    @Test
    func theFirstHalfOpensRight() {
        #expect(AgentCardSide.side(forMachineAt: 0, inHerdOf: 4) == .trailing)
        #expect(AgentCardSide.side(forMachineAt: 1, inHerdOf: 4) == .trailing)
    }

    @Test
    func theSecondHalfOpensLeft() {
        #expect(AgentCardSide.side(forMachineAt: 2, inHerdOf: 4) == .leading)
        #expect(AgentCardSide.side(forMachineAt: 3, inHerdOf: 4) == .leading)
    }

    /// An odd herd has no halfway, so the middle machine goes with the left
    /// half. Rounding the other way would put three of five on the leading
    /// side, which reads as a mistake at exactly the width where a person can
    /// see both answers at once.
    @Test
    func theMiddleOfAnOddHerdOpensRight() {
        #expect(AgentCardSide.side(forMachineAt: 1, inHerdOf: 3) == .trailing)
        #expect(AgentCardSide.side(forMachineAt: 2, inHerdOf: 3) == .leading)
    }

    /// One machine is all left half.
    @Test
    func aHerdOfOneOpensRight() {
        #expect(AgentCardSide.side(forMachineAt: 0, inHerdOf: 1) == .trailing)
    }

    /// A machine this herd does not contain still has to answer, because the
    /// answer is a popover's edge and there is nowhere for it to be nothing.
    @Test
    func aMachineOutsideTheHerdStillAnswers() {
        #expect(AgentCardSide.side(forMachineAt: 0, inHerdOf: 0) == .trailing)
        #expect(AgentCardSide.side(forMachineAt: -1, inHerdOf: 4) == .trailing)
        #expect(AgentCardSide.side(forMachineAt: 9, inHerdOf: 4) == .trailing)
    }
}

/// Which column a point falls in, for a drag that carries an agent across the
/// herd rather than nudging a token sideways.
struct HerdColumnHitTests {
    private let columns = HerdColumns(
        ids: [MachineID("air"), MachineID("mini"), MachineID("linux"), MachineID("nas")],
        stride: 72
    )
    private let inset: CGFloat = 14

    /// The middle of each column answers with that column's machine.
    @Test
    func eachColumnAnswersForItsOwnMiddle() {
        for (index, id) in [MachineID("air"), MachineID("mini"),
                            MachineID("linux"), MachineID("nas")].enumerated() {
            let centre = inset + CGFloat(index) * 72 + 36
            #expect(columns.machine(atX: centre, leadingInset: inset) == id)
        }
    }

    /// The boundary belongs to the column it starts, so no point falls in two.
    @Test
    func theBoundaryBelongsToTheColumnItStarts() {
        #expect(columns.machine(atX: inset + 71.9, leadingInset: inset) == MachineID("air"))
        #expect(columns.machine(atX: inset + 72, leadingInset: inset) == MachineID("mini"))
    }

    /// Outside the herd is nobody, rather than the nearest machine — carrying
    /// an agent into the margin is not carrying it to the edge machine.
    @Test
    func outsideTheHerdIsNobody() {
        #expect(columns.machine(atX: inset - 1, leadingInset: inset) == nil)
        #expect(columns.machine(atX: inset + 4 * 72 + 1, leadingInset: inset) == nil)
    }
}
