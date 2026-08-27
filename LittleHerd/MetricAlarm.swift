import Foundation

/// Whether a metric has a machine in trouble, for the mark on its tab.
///
/// **Defined as what the thermometer paints red, not as what raises an
/// alert.** The two thresholds are different — an alert fires when a volume is
/// 95% full, while the bar turns red above 90 — and they should be, because
/// they answer different questions: one interrupts you, the other is already
/// on screen. A dot on a tab is a promise about what you will find when you
/// open it, so it has to agree with the picture rather than with the
/// notification.
nonisolated enum MetricAlarm {
    /// A reading is in the red when it fills a block the thermometer draws in
    /// the critical band. Asked of the scale rather than of a number, so the
    /// dot and the bar cannot drift apart: move the band and both move.
    static func isInTheRed(_ presentation: OverviewMetricPresentation) -> Bool {
        // Memory says so in words before it says so in height: a machine under
        // critical pressure is in trouble whatever percentage of its RAM is
        // technically in use, which is the whole reason that column shows a
        // symbol instead of a figure.
        if presentation.memoryPressure == .critical { return true }

        let filled = ThermometerScale.filledBlockCount(
            for: presentation.thermometerValue
        )
        guard filled > 0 else { return false }
        return ThermometerScale.band(forLevel: filled - 1) == .critical
    }

    /// One machine is enough. The tab is answering "is there anything here",
    /// and a herd where three machines are calm and one is full is a herd you
    /// need to look at.
    static func isInTheRed(across presentations: [OverviewMetricPresentation]) -> Bool {
        presentations.contains(where: isInTheRed)
    }
}
