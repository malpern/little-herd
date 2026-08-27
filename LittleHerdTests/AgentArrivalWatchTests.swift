import Foundation
import Testing
@testable import LittleHerd

/// When the herd should say something started, and when it should keep quiet.
struct AgentArrivalWatchTests {
    private let air = MachineID("air")
    private let mini = MachineID("mini")
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func session(
        _ id: String,
        _ state: AgentSessionState = .active
    ) -> AgentSession {
        AgentSession(
            id: id,
            provider: .claude,
            projectName: "little-herd",
            state: state,
            updatedAt: .now,
            progress: nil,
            title: id,
            activity: nil,
            model: "claude-opus-5"
        )
    }

    private func herd(
        air airSessions: [AgentSession] = [],
        mini miniSessions: [AgentSession] = []
    ) -> [(machine: MachineID, sessions: [AgentSession])] {
        [(air, airSessions), (mini, miniSessions)]
    }

    /// Opening Little Herd is not four things starting at once.
    @Test
    func theFirstLookAnnouncesNothing() {
        var watch = AgentArrivalWatch()
        #expect(
            watch.arrival(in: herd(air: [session("a"), session("b")]), at: start)
                == nil
        )
    }

    /// A session that appears afterwards is announced, and named.
    @Test
    func aSessionThatStartsAfterwardsIsAnnounced() {
        var watch = AgentArrivalWatch()
        _ = watch.arrival(in: herd(air: [session("a")]), at: start)

        #expect(
            watch.arrival(in: herd(air: [session("a"), session("b")]), at: start)
                == AgentArrival(machine: air, session: "b")
        )
    }

    /// **The noise this exists to prevent.** A session that drops out of one
    /// sample and returns in the next has not started — the probe blinked.
    @Test
    func aSessionThatBlinksOutAndBackIsNotANewSession() {
        var watch = AgentArrivalWatch()
        _ = watch.arrival(in: herd(air: [session("a")]), at: start)
        _ = watch.arrival(in: herd(air: []), at: start.addingTimeInterval(10))

        #expect(
            watch.arrival(in: herd(air: [session("a")]), at: start.addingTimeInterval(20))
                == nil
        )
    }

    /// Only one at a time, and the rest are dropped rather than queued — an
    /// announcement about something that started half a minute ago would be
    /// claiming it just happened.
    @Test
    func severalStartingTogetherAnnounceOnce() {
        var watch = AgentArrivalWatch()
        _ = watch.arrival(in: herd(), at: start)

        #expect(
            watch.arrival(
                in: herd(air: [session("a"), session("b")], mini: [session("c")]),
                at: start.addingTimeInterval(1)
            ) == AgentArrival(machine: air, session: "a")
        )
        // The ones passed over are marked seen, so they do not surface later
        // as though they had only just started.
        #expect(
            watch.arrival(
                in: herd(air: [session("a"), session("b")], mini: [session("c")]),
                at: start.addingTimeInterval(600)
            ) == nil
        )
    }

    /// Inside the quiet period, nothing is said.
    @Test
    func aSecondArrivalWithinTheQuietPeriodIsSilent() {
        var watch = AgentArrivalWatch()
        _ = watch.arrival(in: herd(), at: start)
        _ = watch.arrival(in: herd(air: [session("a")]), at: start.addingTimeInterval(1))

        #expect(
            watch.arrival(
                in: herd(air: [session("a")], mini: [session("b")]),
                at: start.addingTimeInterval(4)
            ) == nil
        )
    }

    /// And after it, the herd speaks again.
    @Test
    func afterTheQuietPeriodItSpeaksAgain() {
        var watch = AgentArrivalWatch()
        _ = watch.arrival(in: herd(), at: start)
        _ = watch.arrival(in: herd(air: [session("a")]), at: start.addingTimeInterval(1))

        #expect(
            watch.arrival(
                in: herd(air: [session("a")], mini: [session("b")]),
                at: start.addingTimeInterval(30)
            ) == AgentArrival(machine: mini, session: "b")
        )
    }

    /// A session that arrives already waiting has not started work, and the
    /// card would have nothing to report about it.
    @Test
    func aWaitingSessionIsNotAnArrival() {
        var watch = AgentArrivalWatch()
        _ = watch.arrival(in: herd(), at: start)

        #expect(
            watch.arrival(
                in: herd(air: [session("a", .waiting)]),
                at: start.addingTimeInterval(10)
            ) == nil
        )
    }
}
