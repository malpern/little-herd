import CoreGraphics
import Testing
@testable import LittleHerd

/// Where the icons land when a deck fans out.
struct AgentFanLayoutTests {
    private let window: CGFloat = 324
    private let tile: CGFloat = 37
    private let gap: CGFloat = 9

    private func lay(_ count: Int, centre: CGFloat) -> AgentFanLayout {
        AgentFanLayout.lay(
            out: count, centredOn: centre, inWindowOfWidth: window, tile: tile, gap: gap
        )
    }

    /// A fan that fits is centred on the animal it came from.
    @Test
    func aFanThatFitsIsCentredOnItsAnimal() {
        let fan = lay(3, centre: 162)
        #expect(fan.icons.count == 3)
        let span = fan.icons[0].minX ... fan.icons[2].maxX
        #expect(abs((span.lowerBound + span.upperBound) / 2 - 162) < 0.5)
    }

    /// Clear space between them, never touching.
    @Test
    func thereIsAlwaysSpaceBetweenThem() {
        let fan = lay(4, centre: 162)
        for (left, right) in zip(fan.icons, fan.icons.dropFirst()) {
            #expect(abs(right.minX - left.maxX - gap) < 0.001)
        }
    }

    /// Clamping recomputes the positions from the edge, not the centre; the gap
    /// has to survive that second origin just as it does the first.
    @Test
    func theGapSurvivesBeingClampedToAnEdge() {
        let fan = lay(4, centre: 40)
        #expect(fan.icons.first?.minX == 10)
        for (left, right) in zip(fan.icons, fan.icons.dropFirst()) {
            #expect(abs(right.minX - left.maxX - gap) < 0.001)
        }
    }

    /// Centring on the leftmost machine would push it off the window, so the
    /// margin stops it instead.
    @Test
    func theEdgeStopsItCentring() {
        let fan = lay(4, centre: 40)
        #expect(fan.icons.first?.minX == 10)
        #expect(fan.icons.last!.maxX <= window - 10)
    }

    /// And the same on the right.
    @Test
    func theOtherEdgeStopsItToo() {
        let fan = lay(4, centre: window - 40)
        #expect(fan.icons.last!.maxX <= window - 10 + 0.001)
        #expect(fan.icons.first!.minX >= 10)
    }

    /// **The whole fan stays inside the window, whatever it is given.** This is
    /// the property the clamping exists for, and the one worth asserting over
    /// every arrangement rather than at two chosen points.
    @Test
    func nothingEverLeavesTheWindow() {
        for count in 1 ... 12 {
            for centre in stride(from: 0.0, through: Double(window), by: 20) {
                let fan = lay(count, centre: CGFloat(centre))
                let all = fan.icons + (fan.overflow.map { [$0.rect] } ?? [])
                #expect(all.allSatisfy { $0.minX >= 10 - 0.001 })
                #expect(all.allSatisfy { $0.maxX <= window - 10 + 0.001 })
            }
        }
    }

    /// More than the window holds: the last place becomes the remainder, and
    /// the arithmetic adds up.
    @Test
    func whatDoesNotFitBecomesOneCard() {
        let fan = lay(9, centre: 162)
        let shown = fan.icons.count
        let overflow = try? #require(fan.overflow)
        #expect(overflow != nil)
        #expect(shown + (overflow?.count ?? 0) == 9)
        // The remainder sits at the end of the row, one gap along.
        #expect(
            abs((overflow?.rect.minX ?? 0) - (fan.icons.last!.maxX + gap)) < 0.001
        )
    }

    /// Exactly as many as fit needs no remainder card.
    @Test
    func aFanThatExactlyFitsHasNoRemainder() {
        let fitting = Int((324 - 20 + gap) / (tile + gap))
        let fan = lay(fitting, centre: 162)
        #expect(fan.icons.count == fitting)
        #expect(fan.overflow == nil)
    }

    /// Nothing running lays out nothing, rather than one card of zero.
    @Test
    func noAgentsLaysOutNothing() {
        #expect(lay(0, centre: 162).icons.isEmpty)
        #expect(lay(0, centre: 162).overflow == nil)
    }
}
