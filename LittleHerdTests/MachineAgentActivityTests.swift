import Foundation
import Testing
@testable import LittleHerd

/// What earns a machine a badge on the CPU screen.
@MainActor
struct MachineAgentActivityTests {
    private func session(
        _ id: String,
        _ provider: AgentTaskProvider,
        _ title: String,
        _ state: AgentSessionState,
        minutesAgo: Double = 0
    ) -> AgentSession {
        AgentSession(
            id: id,
            provider: provider,
            projectName: "little-herd",
            state: state,
            updatedAt: Date().addingTimeInterval(-minutesAgo * 60),
            progress: nil,
            title: title,
            activity: nil,
            model: "claude-opus-5"
        )
    }

    /// The case the first design would have got wrong. A session running a
    /// long tool call is nearly idle as a process while the work underneath it
    /// saturates a core, and its CPU reading needs two samples so it may not
    /// have arrived at all. Gating the badge on CPU would hide exactly the
    /// work it exists to surface.
    @Test
    func aliveSessionWithNoCPUReadingStillEarnsABadge() {
        let activity = MachineAgentActivityReader.activity(
            for: [session("a", .claude, "Running the suite", .active)],
            cpuBySession: [:]
        )

        #expect(activity?.count == 1)
        #expect(activity?.provider == .claude)
    }

    /// Nor does a nearly-idle reading disqualify one.
    @Test
    func aquietButRunningSessionStillEarnsABadge() {
        let activity = MachineAgentActivityReader.activity(
            for: [session("a", .claude, "Thinking", .active)],
            cpuBySession: ["a": 0.2]
        )

        #expect(activity?.count == 1)
    }

    /// Anything not running earns nothing. The badge says work is happening
    /// now, and a mark left over from an hour ago would say the opposite of
    /// what it means.
    @Test
    func nothingRunningEarnsNoBadge() {
        let activity = MachineAgentActivityReader.activity(
            for: [
                session("a", .claude, "Waiting on you", .waiting),
                session("b", .codex, "Finished", .completed),
                session("c", .claude, "Stopped part-way", .stalled),
            ],
            cpuBySession: ["a": 90, "b": 90, "c": 90]
        )

        #expect(activity == nil)
    }

    /// The mark is the busiest session's provider, and the popover reads in
    /// that same order — so the first line is the one that earned it.
    @Test
    func thebusiestSessionDecidesTheMarkAndTheOrder() {
        let activity = MachineAgentActivityReader.activity(
            for: [
                session("quiet", .claude, "Quiet one", .active),
                session("busy", .codex, "Busy one", .active),
            ],
            cpuBySession: ["quiet": 3, "busy": 61]
        )

        #expect(activity?.provider == .codex)
        #expect(activity?.sessions.first?.displayTitle == "Busy one")
        #expect(activity?.count == 2)
    }

    /// A count on a single session would be a "1" on every working machine,
    /// which is a number people stop reading.
    @Test
    func acountAppearsOnlyWhenThereIsMoreThanOne() {
        let one = MachineAgentActivityReader.activity(
            for: [session("a", .claude, "One", .active)],
            cpuBySession: [:]
        )
        let two = MachineAgentActivityReader.activity(
            for: [
                session("a", .claude, "One", .active),
                session("b", .claude, "Two", .active),
            ],
            cpuBySession: [:]
        )

        #expect(one?.showsCount == false)
        #expect(two?.showsCount == true)
    }
}
