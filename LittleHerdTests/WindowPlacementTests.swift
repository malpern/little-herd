import AppKit
import Testing
@testable import LittleHerd

/// Keeping the window somewhere a person can see it.
struct WindowPlacementTests {
    /// A 1470×924 display with the menu bar and Dock taken off it.
    private let visible = NSRect(x: 0, y: 25, width: 1470, height: 874)

    /// **The case that prompted this.** The saved dashboard frame on this Mac
    /// sat 32 points below the bottom of the screen. The splash centres itself
    /// on that frame and is 450×355 against the dashboard's 300×328, so it
    /// launched starting 45 points below the bottom edge with its lower band
    /// cut off.
    @Test
    func asplashCentredOnAFrameBelowTheScreenIsBroughtBack() {
        let savedDashboard = NSRect(x: 962, y: -32, width: 300, height: 328)
        let centre = NSPoint(x: savedDashboard.midX, y: savedDashboard.midY)
        let splash = NSRect(
            x: centre.x - 225,
            y: centre.y - 177.5,
            width: 450,
            height: 355
        )
        #expect(splash.minY < visible.minY, "the fixture must reproduce the bug")

        let placed = WindowPlacement.onScreen(splash, within: visible)
        #expect(placed.minY - visible.minY == WindowPlacement.edgeMargin)
        #expect(placed.maxY <= visible.maxY)
        // Moved the least distance needed: it was never off horizontally.
        #expect(placed.minX == splash.minX)
        #expect(placed.size == splash.size)
    }

    /// **What was actually reported.** The splash, 450 wide, was launching at
    /// x=1112 on a 1470-point display — 92 points beyond the right edge.
    /// Measured on the installed build before this existed.
    @Test
    func thesplashHangingOffTheRightIsBroughtBackWithRoomToSpare() {
        let splash = NSRect(x: 1112, y: 572, width: 450, height: 359)
        #expect(splash.maxX > visible.maxX, "the fixture must reproduce the bug")

        let placed = WindowPlacement.onScreen(splash, within: visible)
        #expect(placed.maxX <= visible.maxX)
        // Not merely rescued: rescued with a gap, because flush against the
        // edge still reads as cut off.
        #expect(visible.maxX - placed.maxX == WindowPlacement.edgeMargin)
        #expect(placed.size == splash.size)
    }

    /// **The second report, from the first fix.** Rescuing the right edge left
    /// the splash sitting exactly on the bottom of the visible area — on
    /// screen by the arithmetic and still reading as cut off. A window resting
    /// on an edge gets the margin too, not only one hanging over it.
    @Test
    func awindowRestingOnAnEdgeIsNudgedOffIt() {
        let onTheEdge = NSRect(
            x: 700,
            y: visible.minY,
            width: 450,
            height: 359
        )
        let placed = WindowPlacement.onScreen(onTheEdge, within: visible)
        #expect(placed.minY - visible.minY == WindowPlacement.edgeMargin)
    }

    /// A margin that cannot be honoured must not shove the window off the far
    /// side to make room for it.
    @Test
    func amarginTooLargeForTheWindowIsAbandonedRatherThanForced() {
        let wide = NSRect(x: -40, y: 300, width: 1470, height: 359)
        let placed = WindowPlacement.onScreen(wide, within: visible)
        #expect(placed.minX == visible.minX)
        #expect(placed.maxX == visible.maxX)
    }

    /// A window with room on every side is left exactly where it is. Only the
    /// edges are enforced; nothing is centred or tidied.
    @Test
    func aframeWellInsideTheScreenIsNotMoved() {
        let frame = NSRect(x: 400, y: 300, width: 450, height: 355)
        #expect(WindowPlacement.onScreen(frame, within: visible) == frame)
    }

    @Test
    func everyEdgeIsBroughtBack() {
        let size = NSSize(width: 450, height: 355)
        func placed(_ x: CGFloat, _ y: CGFloat) -> NSRect {
            WindowPlacement.onScreen(
                NSRect(origin: NSPoint(x: x, y: y), size: size),
                within: visible
            )
        }
        let margin = WindowPlacement.edgeMargin
        #expect(placed(-200, 300).minX - visible.minX == margin)
        #expect(visible.maxX - placed(1400, 300).maxX == margin)
        #expect(placed(400, -200).minY - visible.minY == margin)
        #expect(visible.maxY - placed(400, 900).maxY == margin)
    }

    /// A window taller than the screen cannot be contained, and losing its
    /// bottom beats losing its top — the title and the first row of content
    /// are up there.
    @Test
    func awindowLargerThanTheScreenKeepsItsTopLeft() {
        let huge = NSRect(x: -50, y: -50, width: 2000, height: 1200)
        let placed = WindowPlacement.onScreen(huge, within: visible)
        #expect(placed.minX == visible.minX)
        #expect(placed.maxY == visible.maxY)
    }
}
