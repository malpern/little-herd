import Testing
@testable import LittleHerd

/// When a tab earns a mark, and which colour.
struct MetricAlarmTests {
    private func reading(
        _ value: Double?,
        pressure: MemoryPressureLevel? = nil
    ) -> OverviewMetricPresentation {
        OverviewMetricPresentation(
            value: value,
            thermometerValue: value,
            memoryPressure: pressure
        )
    }

    /// The mark follows the bar. Ninety-one fills the tenth block, which the
    /// scale paints red; ninety fills nine and is orange.
    @Test
    func aBarInTheRedIsCritical() {
        #expect(MetricAlarm.severity(reading(91)) == .critical)
        #expect(MetricAlarm.severity(reading(90)) == nil)
    }

    /// **A bar in its orange band raises nothing.** A disk at eighty per cent
    /// is a fact about a disk; a mark lit most of the time is a mark nobody
    /// reads.
    @Test
    func aBarMerelyInItsOrangeBandRaisesNothing() {
        #expect(MetricAlarm.severity(reading(80)) == nil)
        #expect(MetricAlarm.severity(reading(63)) == nil)
    }

    /// Memory is the exception, and deliberately: its percentage is not the
    /// signal, which is why elevated pressure takes over that column.
    @Test
    func elevatedMemoryPressureRaisesAMarkAtAnyPercentage() {
        #expect(MetricAlarm.severity(reading(30, pressure: .warning)) == .warning)
        #expect(MetricAlarm.severity(reading(30, pressure: .critical)) == .critical)
        #expect(MetricAlarm.severity(reading(30, pressure: .normal)) == nil)
    }

    /// A full disk on a machine under mere memory warning is still critical:
    /// the worse of the two decides.
    @Test
    func theWorseOfTheTwoReadingsDecides() {
        #expect(MetricAlarm.severity(reading(97, pressure: .warning)) == .critical)
    }

    /// A machine that is not answering has no reading, and a mark would send
    /// you to look at nothing.
    @Test
    func aMachineWithNoReadingRaisesNothing() {
        #expect(MetricAlarm.severity(reading(nil)) == nil)
        #expect(MetricAlarm.severity(.nothingToShow) == nil)
    }

    /// Across a herd: one machine is enough, and the worst decides the colour.
    @Test
    func theHerdTakesItsMarkFromItsWorstMachine() {
        #expect(
            MetricAlarm.severity(across: [
                reading(10), reading(30, pressure: .warning),
            ]) == .warning
        )
        #expect(
            MetricAlarm.severity(across: [
                reading(30, pressure: .warning), reading(97),
            ]) == .critical
        )
        #expect(MetricAlarm.severity(across: [reading(10), reading(20)]) == nil)
        #expect(MetricAlarm.severity(across: []) == nil)
    }
}
