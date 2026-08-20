import Foundation
import Testing
@testable import LittleHerd

/// Tying a session to the process running it, and turning a counter into a rate.
struct AgentResourceTests {
    private func session(
        id: String,
        directory: String?
    ) -> AgentSession {
        AgentSession(
            id: id,
            provider: .claude,
            projectName: "Little Herd",
            state: .active,
            updatedAt: .now,
            progress: nil,
            workingDirectory: directory
        )
    }

    private func process(
        pid: Int,
        directory: String,
        rss: Int = 300 * 1_024 * 1_024,
        cpuSeconds: Double = 100
    ) -> AgentProcessSample {
        AgentProcessSample(
            pid: pid,
            residentBytes: rss,
            cpuSeconds: cpuSeconds,
            workingDirectory: directory
        )
    }

    /// `ps` writes cumulative CPU two different ways, and an agent session runs
    /// long enough that the hour-plus form is the common one.
    @Test
    func cumulativeCPUIsReadInBothFormsPSUses() {
        #expect(AgentProcessOutputParser.cpuSeconds("9:09.29") == 549.29)
        #expect(AgentProcessOutputParser.cpuSeconds("1:02:03.50") == 3_723.5)
        #expect(AgentProcessOutputParser.cpuSeconds("0:01.00") == 1)
        #expect(AgentProcessOutputParser.cpuSeconds("nonsense") == nil)
    }

    @Test
    func aProcessLineIsReadIntoASample() throws {
        let directory = Data("/Users/x/local-code/little-herd".utf8)
            .base64EncodedString()
        let samples = AgentProcessOutputParser.parse(
            "agent_process=87873\t309440\t6:04.32\t\(directory)"
        )
        let sample = try #require(samples.first)
        #expect(sample.pid == 87_873)
        #expect(sample.residentBytes == 309_440 * 1_024)
        #expect(sample.cpuSeconds == 364.32)
        #expect(sample.workingDirectory == "/Users/x/local-code/little-herd")
    }

    @Test
    func aSessionIsMatchedToTheProcessInItsDirectory() throws {
        let joined = AgentResourceJoin.attach(
            processes: [process(pid: 1, directory: "/a"), process(pid: 2, directory: "/b")],
            to: [session(id: "one", directory: "/b")]
        )
        let resource = try #require(joined.first?.resource)
        #expect(resource.residentBytes == 300 * 1_024 * 1_024)
    }

    /// Two sessions in one directory cannot be told apart by directory, so
    /// neither gets a figure. Attributing one session's cost to both would read
    /// as "this is the expensive one" and could send someone to move the wrong
    /// work — a wrong number here is worse than none.
    @Test
    func ambiguousDirectoriesAreLeftUnattributed() {
        let joined = AgentResourceJoin.attach(
            processes: [process(pid: 1, directory: "/shared")],
            to: [
                session(id: "one", directory: "/shared"),
                session(id: "two", directory: "/shared"),
            ]
        )
        #expect(joined.allSatisfy { $0.resource == nil })
    }

    @Test
    func aSessionWithNoMatchingProcessIsLeftAlone() {
        let joined = AgentResourceJoin.attach(
            processes: [process(pid: 1, directory: "/a")],
            to: [session(id: "one", directory: "/elsewhere")]
        )
        #expect(joined.first?.resource == nil)
    }

    /// One reading cannot describe a rate, and the app must not invent one from
    /// a process's lifetime average — which is what `ps` would hand it.
    @Test
    func oneReadingProducesNoRate() {
        var tracker = AgentCPUTracker()
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let rated = tracker.rating(
            AgentResourceJoin.attach(
                processes: [process(pid: 1, directory: "/a", cpuSeconds: 500)],
                to: [session(id: "one", directory: "/a")]
            ),
            now: now
        )
        #expect(rated.first?.resource?.cpuPercent == nil)
    }

    /// Five seconds of CPU across ten seconds of wall clock is half a core.
    @Test
    func twoReadingsBecomeAShareOfACore() throws {
        var tracker = AgentCPUTracker()
        let start = Date(timeIntervalSinceReferenceDate: 2_000)
        func sample(_ cpu: Double) -> [AgentSession] {
            AgentResourceJoin.attach(
                processes: [process(pid: 1, directory: "/a", cpuSeconds: cpu)],
                to: [session(id: "one", directory: "/a")]
            )
        }
        _ = tracker.rating(sample(100), now: start)
        let rated = tracker.rating(sample(105), now: start.addingTimeInterval(10))
        #expect(try #require(rated.first?.resource?.cpuPercent) == 50)
    }

    /// A restarted process starts its counter again. That is not negative work.
    @Test
    func aCounterGoingBackwardsIsNotAMeasurement() {
        var tracker = AgentCPUTracker()
        let start = Date(timeIntervalSinceReferenceDate: 3_000)
        func sample(_ cpu: Double) -> [AgentSession] {
            AgentResourceJoin.attach(
                processes: [process(pid: 1, directory: "/a", cpuSeconds: cpu)],
                to: [session(id: "one", directory: "/a")]
            )
        }
        _ = tracker.rating(sample(900), now: start)
        let rated = tracker.rating(sample(3), now: start.addingTimeInterval(10))
        #expect(rated.first?.resource?.cpuPercent == nil)
    }
}
