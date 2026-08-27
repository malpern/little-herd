import SwiftUI

/// Whether a metric has a machine worth looking at, and how badly.
///
/// **Defined as what the thermometer paints, not as what raises an alert.**
/// The two thresholds differ on purpose — a notification fires when a volume is
/// 95% full, the bar turns red above 90 — because they answer different
/// questions: one interrupts you, the other is already on screen. A mark on a
/// tab is a promise about what you will find when you open it, so it agrees
/// with the picture.
nonisolated enum MetricAlarm {
    /// Ordered worst-last, so a herd's mark is `max` of its machines'.
    enum Severity: Comparable, Sendable {
        case warning
        case critical

        /// Borrowed from the thermometer's own bands rather than named again
        /// here, so the mark on a tab and the block on a bar cannot drift to
        /// two different reds.
        ///
        /// The only part of this type that touches SwiftUI, and so the only
        /// part that is isolated: the decision above is a plain value that
        /// tests can reach without a main actor.
        @MainActor var tint: Color {
            switch self {
            case .warning: ThermometerBand.high.color
            case .critical: ThermometerBand.critical.color
            }
        }
    }

    /// **Memory is the one metric whose percentage is not the signal.** A Mac
    /// can be calm at seventy per cent of its RAM and swapping hard at sixty,
    /// so the verdict is the only reading that means anything — which is why
    /// that column stops showing a figure the moment pressure leaves normal.
    /// The tab follows the column: if it was worth taking over the column for,
    /// it is worth a mark.
    ///
    /// **A bar merely in its orange band raises nothing.** A disk at eighty per
    /// cent is a fact about a disk, not a machine in trouble, and a mark that
    /// is lit most of the time is a mark nobody reads. That asymmetry between
    /// memory and the rest is the point rather than an oversight.
    static func severity(_ presentation: OverviewMetricPresentation) -> Severity? {
        let fromBar = barSeverity(presentation.thermometerValue)
        let fromPressure: Severity? = switch presentation.memoryPressure {
        case .critical: .critical
        case .warning: .warning
        default: nil
        }
        return [fromBar, fromPressure].compactMap(\.self).max()
    }

    /// One machine is enough, and the worst of them decides the colour: a herd
    /// where three are calm and one is full is a herd you need to look at.
    static func severity(across presentations: [OverviewMetricPresentation]) -> Severity? {
        presentations.compactMap(severity).max()
    }

    /// Asked of the scale rather than of a number, so moving the band moves
    /// the mark with it.
    private static func barSeverity(_ value: Double?) -> Severity? {
        let filled = ThermometerScale.filledBlockCount(for: value)
        guard filled > 0,
              ThermometerScale.band(forLevel: filled - 1) == .critical
        else { return nil }
        return .critical
    }
}
