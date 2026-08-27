import CoreGraphics

/// The size of each dashboard screen, in one place.
///
/// The overview divided a hard-coded width into columns while the window
/// carried its own copy of that number in another file. Nothing enforced that
/// the two agreed, and when the window grew to make room for the agent pads
/// the overview went on carving up the old width — which shows as a right
/// margin twice the left and as nothing at all in a build log.
nonisolated enum DashboardMetrics {
    /// The height of every screen here, as the window must be told it.
    ///
    /// **The content and the window are not the same height.** The sizes below
    /// are what the view needs; the window has to be that plus the band macOS
    /// keeps for the traffic lights, and getting this wrong clips the bottom
    /// of whatever is last on the screen.
    static func windowHeight(for content: CGSize) -> CGFloat {
        content.height + titlebarInset
    }

    /// What macOS keeps for the traffic lights.
    ///
    /// **The window draws under its own titlebar, and SwiftUI still insets the
    /// content by this much.** The two facts together are why every size here
    /// is written as content plus the inset: `fullSizeContentView` makes the
    /// frame height equal the content height, so nothing in the window code
    /// adds a titlebar — but the view inside is pushed down by 32 points all
    /// the same, and whatever does not fit is cut off the bottom.
    ///
    /// This has now clipped the dashboard twice: once taking the machine names
    /// off the overview, and once taking the metric tabs off. The second time
    /// the height was measured from a render, and `ImageRenderer` has no safe
    /// area — so the picture fitted perfectly and the window did not.
    static let titlebarInset: CGFloat = 32

    /// The overview: four columns of thermometers, with the metric tabs under
    /// them.
    static let overviewContent = CGSize(width: 324, height: 296)
    /// The metric row along the bottom of every dashboard screen.
    /// What the metric tabs cost the two machine screens, over and above what
    /// they already had.
    ///
    /// Almost nothing, and that is the surprising part. Those two heights were
    /// set while the window was being sized to the content *without* the
    /// titlebar band, so the screens had been laying out in thirty-two points
    /// less than their numbers claimed. Fixing that handed back very nearly a
    /// tab row. This is the difference, plus a little air under the last row.
    static let metricTabsHeight: CGFloat = 16

    /// One machine through the current metric's lens.
    ///
    /// This and the one below keep the heights they were given by looking at
    /// the running window, so the titlebar band is already inside them — but
    /// those numbers predate the tab row, which is why both shipped with the
    /// tabs cut off. The earlier reasoning that they needed no adjustment was
    /// right about the band and wrong about the tabs.
    static let metricFocusContent = CGSize(
        width: 400,
        height: 330 + metricTabsHeight
    )
    /// Everything about one machine.
    static let machineContent = CGSize(
        width: 420,
        height: 340 + metricTabsHeight
    )
}
