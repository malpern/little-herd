import Testing
@testable import LittleHerd

/// When a tab earns its red dot.
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

    /// The dot follows the bar. Ninety-one fills the tenth block, which the
    /// scale paints red; ninety fills nine and is orange.
    @Test
    func theDotAgreesWithWhatTheThermometerPaints() {
        #expect(MetricAlarm.isInTheRed(reading(91)))
        #expect(!MetricAlarm.isInTheRed(reading(90)))
        #expect(!MetricAlarm.isInTheRed(reading(63)))
    }

    /// Critical memory pressure is trouble whatever the percentage says — it
    /// is why that column shows a symbol rather than a figure.
    @Test
    func criticalMemoryPressureIsInTheRedAtAnyPercentage() {
        #expect(MetricAlarm.isInTheRed(reading(40, pressure: .critical)))
        #expect(!MetricAlarm.isInTheRed(reading(40, pressure: .warning)))
    }

    /// A machine that is not answering is not a machine in trouble. It has no
    /// reading at all, and a dot would send you to look at nothing.
    @Test
    func aMachineWithNoReadingRaisesNothing() {
        #expect(!MetricAlarm.isInTheRed(reading(nil)))
        #expect(!MetricAlarm.isInTheRed(.nothingToShow))
    }

    /// One machine in the red is enough for the herd.
    @Test
    func oneMachineIsEnough() {
        #expect(
            MetricAlarm.isInTheRed(across: [reading(10), reading(20), reading(97)])
        )
        #expect(!MetricAlarm.isInTheRed(across: [reading(10), reading(20)]))
        #expect(!MetricAlarm.isInTheRed(across: []))
    }
}
