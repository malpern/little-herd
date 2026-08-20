import Foundation
import Testing
@testable import LittleHerd

/// The join between what the machines are doing and what the agents are doing.
///
/// The rules under test are mostly about *silence*: this sentence is only worth
/// showing when it says something true and useful, and every case below that
/// returns nothing is a case where a plausible-looking sentence would have been
/// a guess.
struct HerdWorkloadTests {
    private func input(
        _ machine: MachineID,
        name: String,
        live: Bool = true,
        cpu: Double?,
        sessions: Int = 0
    ) -> HerdWorkloadInput {
        HerdWorkloadInput(
            machine: machine,
            name: name,
            isLive: live,
            sustainedCPUPercent: cpu,
            activeSessionCount: sessions
        )
    }

    @Test
    func aSaturatedMachineCarryingTheSessionsIsSaidOnce() throws {
        let finding = try #require(
            HerdWorkloadReader.finding(for: [
                input(.macBookAir, name: "Air", cpu: 94, sessions: 3),
                input(.macMini, name: "Mini", cpu: 8),
            ])
        )
        #expect(finding.busyMachine == .macBookAir)
        #expect(finding.idleMachine == .macMini)
        #expect(finding.sessionCount == 3)
        #expect(finding.sentence.contains("3 sessions on Air"))
        #expect(finding.sentence.contains("94%"))
        #expect(finding.sentence.contains("8%"))
    }

    /// The sentence must not read as advice. Little Herd cannot know whether
    /// the idle machine could take the work — that is the eligibility probe,
    /// which does not exist — and the README promises the app does not move
    /// anything.
    @Test
    func theSentenceObservesRatherThanRecommends() throws {
        let finding = try #require(
            HerdWorkloadReader.finding(for: [
                input(.macBookAir, name: "Air", cpu: 94, sessions: 3),
                input(.macMini, name: "Mini", cpu: 8),
            ])
        )
        for word in ["move", "should", "instead", "try"] {
            #expect(
                !finding.sentence.lowercased().contains(word),
                "the finding must not read as advice, but says: \(finding.sentence)"
            )
        }
    }

    /// A machine with no history yet is unmeasured, not idle. Saying it is idle
    /// would be a guess wearing the costume of a reading — the same rule
    /// `SustainedLoad` already applies to the menu bar.
    @Test
    func aMachineWithNoSustainedAverageIsNotCalledIdle() {
        #expect(
            HerdWorkloadReader.finding(for: [
                input(.macBookAir, name: "Air", cpu: 94, sessions: 3),
                input(.macMini, name: "Mini", cpu: nil),
            ]) == nil
        )
    }

    /// An unmeasured machine must be set aside, not ranked as if it read zero.
    ///
    /// This test exists because the obvious version of it did not work: with
    /// only two machines, dropping the filter still returned nothing, because
    /// unwrapping the average failed a line later and the result looked the
    /// same. It takes a third machine to tell the two implementations apart —
    /// and what goes wrong is a *false negative*, a true and useful sentence
    /// silently withheld because an unmeasured machine sorted below a real one.
    @Test
    func anUnmeasuredMachineDoesNotCrowdOutARealIdleOne() throws {
        let finding = try #require(
            HerdWorkloadReader.finding(for: [
                input(.macBookAir, name: "Air", cpu: 94, sessions: 3),
                input(.macMini, name: "Mini", cpu: nil),
                input(.linux, name: "Linux", cpu: 5),
            ])
        )
        #expect(finding.idleMachine == .linux)
    }

    /// A machine that is offline is not an idle machine.
    @Test
    func anOfflineMachineIsNeverTheIdleOne() {
        #expect(
            HerdWorkloadReader.finding(for: [
                input(.macBookAir, name: "Air", cpu: 94, sessions: 3),
                input(.macMini, name: "Mini", live: false, cpu: 2),
            ]) == nil
        )
    }

    /// Without a session on it, a busy machine is just a busy machine — which
    /// the menu bar already says. The join only earns a line when agent work is
    /// what is landing there.
    @Test
    func loadWithNoAgentSessionBehindItSaysNothingHere() {
        #expect(
            HerdWorkloadReader.finding(for: [
                input(.macBookAir, name: "Air", cpu: 94),
                input(.macMini, name: "Mini", cpu: 8),
            ]) == nil
        )
    }

    /// A herd where everything is busy has no idle machine to name.
    @Test
    func aUniformlyBusyHerdSaysNothing() {
        #expect(
            HerdWorkloadReader.finding(for: [
                input(.macBookAir, name: "Air", cpu: 92, sessions: 2),
                input(.macMini, name: "Mini", cpu: 88, sessions: 1),
            ]) == nil
        )
    }

    /// One machine cannot be compared with anything.
    @Test
    func aHerdOfOneSaysNothing() {
        #expect(
            HerdWorkloadReader.finding(for: [
                input(.macBookAir, name: "Air", cpu: 99, sessions: 4),
            ]) == nil
        )
    }

    /// Waiting sessions are blocked on a person and consume nothing, so they
    /// must not be counted as the cause of load.
    @Test
    func theBusyMachineIsJudgedOnWorkThatIsActuallyRunning() {
        // Three waiting sessions and none active: nothing here is causing the
        // load, so there is nothing to attribute.
        #expect(
            HerdWorkloadReader.finding(for: [
                input(.macBookAir, name: "Air", cpu: 94, sessions: 0),
                input(.macMini, name: "Mini", cpu: 5),
            ]) == nil
        )
    }

    @Test
    func oneSessionIsNotPluralised() throws {
        let finding = try #require(
            HerdWorkloadReader.finding(for: [
                input(.macBookAir, name: "Air", cpu: 96, sessions: 1),
                input(.macMini, name: "Mini", cpu: 3),
            ])
        )
        #expect(finding.sentence.hasPrefix("1 session on Air"))
    }
}
