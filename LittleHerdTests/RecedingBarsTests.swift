import Foundation
import Testing

@testable import LittleHerd

/// The thermometers falling back while a fan is raised.
///
/// An experiment behind `LittleHerdPreferences.recedesBarsUnderFanKey`, off by
/// default. What can be tested without a pointer is the rule, not the feel:
/// which machines step back, which do not, and that the default changes
/// nothing. **The feel has to be watched** — the render harness cannot draw a
/// hover state at all, which is why the fan's own constants were settled by
/// looking rather than by rendering.
@Suite("Receding bars")
struct RecedingBarsTests {
    /// **Off unless asked for.** The herd already had a hover dim and it was
    /// removed for being a large gesture in answer to a small question; a
    /// second attempt at that idea does not get to arrive switched on.
    @Test
    func theExperimentIsOffByDefault() {
        let defaults = UserDefaults(suiteName: "receding-bars-\(UUID().uuidString)")!
        #expect(!defaults.bool(forKey: LittleHerdPreferences.recedesBarsUnderFanKey))
    }

    /// **A machine in the red never recedes.** Everything else is backdrop
    /// while you read a fan; a reading that says something is wrong is not
    /// backdrop, and it is the one number that has to survive a change of
    /// focus.
    @Test
    func aShoutingMachineKeepsItsPlace() {
        // **The scale is a percentage, not a fraction.** `filledBlockCount`
        // is `ceil(value / 10)`, so critical starts above 90 — a first version
        // of this test used 0.99 and asserted it was critical, which is one
        // block off the bottom of the bar.
        let critical = OverviewMetricPresentation(
            value: 95,
            thermometerValue: 95,
            memoryPressure: nil
        )
        #expect(MetricAlarm.severity(critical) != nil, "95% should be critical")

        let calm = OverviewMetricPresentation(
            value: 10,
            thermometerValue: 10,
            memoryPressure: nil
        )
        #expect(MetricAlarm.severity(calm) == nil, "10% should be calm")
    }

    /// **Memory pressure counts too**, which is why this asks `MetricAlarm`
    /// rather than the bar's number. A machine can be under pressure with an
    /// unremarkable bar, and that is precisely one you would not want quietly
    /// stepping back.
    @Test
    func pressureAloneIsEnoughToStayForward() {
        let pressured = OverviewMetricPresentation(
            value: 20,
            thermometerValue: 20,
            memoryPressure: .critical
        )
        #expect(MetricAlarm.severity(pressured) != nil)
    }
}
