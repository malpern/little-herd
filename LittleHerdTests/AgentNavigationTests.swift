import Testing
@testable import LittleHerd

/// Where an agent token on the overview takes you.
@MainActor
struct AgentNavigationTests {
    /// Two changes, not one. The machine screens are lensed through whichever
    /// overview metric is current, so selecting the machine alone lands on a
    /// page about CPU — which is exactly what the token is *not* pointing at.
    @Test
    func aTokenOpensTheMachinesAIPageAndNotTheCurrentMetric() {
        let model = MonitorModel()
        model.overviewMetric = .cpu

        model.showAgents(on: MachineID("mini"))

        #expect(model.overviewMetric == .ai)
        #expect(model.selection == .machineMetric(MachineID("mini")))
    }

    /// And it works from a page about another machine, which is the case that
    /// would break if this only ever nudged the metric.
    @Test
    func itWorksFromAnotherMachinesPage() {
        let model = MonitorModel()
        model.overviewMetric = .disk
        model.selection = .machineMetric(MachineID("air"))

        model.showAgents(on: MachineID("linux"))

        #expect(model.overviewMetric == .ai)
        #expect(model.selection == .machineMetric(MachineID("linux")))
    }
}
