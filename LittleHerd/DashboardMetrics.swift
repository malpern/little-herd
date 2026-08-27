import CoreGraphics

/// The size of each dashboard screen, in one place.
///
/// The overview divided a hard-coded width into columns while the window
/// carried its own copy of that number in another file. Nothing enforced that
/// the two agreed, and when the window grew to make room for the agent pads
/// the overview went on carving up the old width — which shows as a right
/// margin twice the left and as nothing at all in a build log.
nonisolated enum DashboardMetrics {
    /// The overview: four columns of thermometers with a pad under each.
    static let overviewContent = CGSize(width: 324, height: 312)
    /// One machine through the current metric's lens.
    static let metricFocusContent = CGSize(width: 400, height: 330)
    /// Everything about one machine.
    static let machineContent = CGSize(width: 420, height: 340)
}
