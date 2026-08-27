import CoreGraphics

/// The size of each dashboard screen, in one place.
///
/// The overview divided a hard-coded width into columns while the window
/// carried its own copy of that number in another file. Nothing enforced that
/// the two agreed, and when the window grew to make room for the agent pads
/// the overview went on carving up the old width — which shows as a right
/// margin twice the left and as nothing at all in a build log.
nonisolated enum DashboardMetrics {
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
    static let overviewContent = CGSize(
        width: 324,
        height: 296 + titlebarInset
    )
    /// One machine through the current metric's lens.
    ///
    /// This and the one below are literals, and deliberately not written as
    /// content plus the inset: they were arrived at by looking at the running
    /// window, so whatever the titlebar takes is already inside them. Adding
    /// the inset here would make both screens thirty-two points too tall.
    static let metricFocusContent = CGSize(width: 400, height: 330)
    /// Everything about one machine.
    static let machineContent = CGSize(width: 420, height: 340)
}
