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

/// The inline thermometer's arithmetic, which is presentation and therefore
/// testable without drawing anything.
@MainActor
struct InlineThermometerTests {
    private func filled(_ value: Double?, blocks: Int = 5) -> Int {
        guard let value else { return 0 }
        return min(max(Int(ceil(value / (100 / Double(blocks)))), 0), blocks)
    }

    /// Any work at all lights a block, so a session doing something never looks
    /// the same as one doing nothing — the rule the column thermometer follows.
    @Test
    func anyWorkLightsTheFirstBlock() {
        #expect(filled(0.4) == 1)
        #expect(filled(nil) == 0)
        #expect(filled(0) == 0)
    }

    @Test
    func aFullCoreFillsEveryBlock() {
        #expect(filled(100) == 5)
        // More than one core's worth is still a full bar rather than an
        // overflowing one.
        #expect(filled(340) == 5)
    }

    @Test
    func theScaleIsProportional() {
        #expect(filled(20) == 1)
        #expect(filled(21) == 2)
        #expect(filled(60) == 3)
        #expect(filled(96) == 5)
    }

    /// Five blocks across a row read the same colours as ten down a column: a
    /// session at 95% must be the red a machine at 95% is, or the shared
    /// vocabulary is a lie.
    @Test
    func aRowUsesTheSameBandsAsAColumn() {
        func band(position: Int, blocks: Int) -> ThermometerBand {
            ThermometerScale.band(
                forLevel: Int((Double(position) + 0.5) / Double(blocks) * 10)
            )
        }
        #expect(band(position: 0, blocks: 5) == .calm)
        #expect(band(position: 4, blocks: 5) == .critical)
        #expect(band(position: 9, blocks: 10) == .critical)
        #expect(band(position: 0, blocks: 10) == .calm)
    }
}

/// What a session's checkout says about moving the work.
struct AgentRepoStateTests {
    private func session(id: String, directory: String?) -> AgentSession {
        AgentSession(
            id: id,
            provider: .claude,
            projectName: "Little Herd",
            state: .waiting,
            updatedAt: .now,
            progress: nil,
            workingDirectory: directory
        )
    }

    /// The exact line the probe produced against this repository.
    @Test
    func aProbeLineIsRead() throws {
        let directory = Data("/Users/x/local-code/little-herd".utf8)
            .base64EncodedString()
        let branch = Data("claude/roadmap-3-4-6".utf8).base64EncodedString()
        let states = AgentRepoStateOutputParser.parse(
            "repo_state=\(directory)\t\(branch)\t0\t0"
        )
        let state = try #require(states["/Users/x/local-code/little-herd"])
        #expect(state.branch == "claude/roadmap-3-4-6")
        #expect(state.isPushedSomewhereElse)
        #expect(!state.carriesUnsharedWork)
    }

    /// Uncommitted work is what a summary forgets and a transfer has to carry.
    @Test
    func uncommittedWorkIsUnshared() {
        let state = AgentRepoState(
            branch: "main",
            uncommittedFileCount: 3,
            unpushedCommitCount: 0
        )
        #expect(state.carriesUnsharedWork)
        #expect(!state.isPushedSomewhereElse)
    }

    /// Committed is not the same as reachable. A target machine can fetch a
    /// branch and cannot fetch what was never pushed.
    @Test
    func committedButUnpushedIsAlsoUnshared() {
        let state = AgentRepoState(
            branch: "main",
            uncommittedFileCount: 0,
            unpushedCommitCount: 2
        )
        #expect(state.carriesUnsharedWork)
    }

    /// No upstream is a stronger statement than nothing to push: the branch
    /// exists on this machine and nowhere else at all.
    @Test
    func aBranchWithNoUpstreamIsNotMistakenForAPushedOne() {
        let state = AgentRepoState(
            branch: "scratch",
            uncommittedFileCount: 0,
            unpushedCommitCount: -1
        )
        #expect(!state.hasUpstream)
        #expect(state.carriesUnsharedWork)
        #expect(!state.isPushedSomewhereElse)
    }

    /// Two sessions in one directory share its repository state truthfully —
    /// unlike a process, it is a fact about the directory rather than about
    /// either session, so both are told.
    @Test
    func sessionsSharingADirectoryBothLearnItsState() {
        let states = [
            "/shared": AgentRepoState(
                branch: "main",
                uncommittedFileCount: 1,
                unpushedCommitCount: 0
            ),
        ]
        let joined = AgentResourceJoin.attach(
            repoStates: states,
            to: [
                session(id: "one", directory: "/shared"),
                session(id: "two", directory: "/shared"),
            ]
        )
        #expect(joined.allSatisfy { $0.repo?.branch == "main" })
        #expect(joined.allSatisfy { $0.repo?.carriesUnsharedWork == true })
    }

    @Test
    func aSessionOutsideAnyCheckoutLearnsNothing() {
        let joined = AgentResourceJoin.attach(
            repoStates: ["/elsewhere": AgentRepoState(
                branch: "main",
                uncommittedFileCount: 0,
                unpushedCommitCount: 0
            )],
            to: [session(id: "one", directory: "/Users/x/Documents")]
        )
        #expect(joined.first?.repo == nil)
    }
}
