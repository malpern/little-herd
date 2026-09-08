import Foundation
import Testing

@testable import LittleHerd

/// A session's CPU, measured as a rate rather than differenced from a lifetime counter.
@Suite("A session's CPU is a rate")
struct AgentCPURateTests {
    /// The probe's five-field line, with the rate it measured.
    @Test
    func themeasuredRateIsParsed() throws {
        let cwd = Data("/Users/a/x".utf8).base64EncodedString()
        let s = try #require(
            AgentProcessOutputParser.parse("agent_process=42\t131072\t1:05.00\t184.50\t\(cwd)").first
        )
        #expect(s.pid == 42)
        #expect(s.cpuSeconds == 65)
        #expect(s.measuredCPUPercent == 184.5)
        #expect(s.workingDirectory == "/Users/a/x")
    }

    /// **An empty rate is "not measured", not "measured nothing".** The probe leaves it
    /// blank when a process appeared inside its window or when the tree shrank, and
    /// reading that as 0% would put an idle badge on a session that is working.
    @Test
    func anemptyRateIsNilRatherThanZero() throws {
        let cwd = Data("/Users/a/x".utf8).base64EncodedString()
        let s = try #require(
            AgentProcessOutputParser.parse("agent_process=42\t131072\t1:05.00\t\t\(cwd)").first
        )
        #expect(s.measuredCPUPercent == nil)
        #expect(s.cpuSeconds == 65)
    }

    /// The older four-field shape still parses, so a machine mid-upgrade is read rather
    /// than dropped.
    @Test
    func thefourFieldShapeStillParses() throws {
        let cwd = Data("/Users/a/x".utf8).base64EncodedString()
        let s = try #require(
            AgentProcessOutputParser.parse("agent_process=42\t131072\t1:05.00\t\(cwd)").first
        )
        #expect(s.measuredCPUPercent == nil)
        #expect(s.workingDirectory == "/Users/a/x")
    }

    // MARK: - The tracker

    private func session(cpuSeconds: Double, measured: Double?) -> AgentSession {
        AgentSession(
            id: "s", provider: .claude, projectName: "p", state: .active,
            updatedAt: .now, progress: nil, workingDirectory: "/x"
        ).consuming(AgentResourceUsage(
            residentBytes: 1024, cpuSeconds: cpuSeconds, measuredCPUPercent: measured
        ))
    }

    /// **A measured rate needs no second reading.** Differencing needs two probe runs —
    /// a minute of showing nothing — where the probe already watched for two seconds.
    @Test
    func afirstSampleWithAmeasurementReportsImmediately() {
        var tracker = AgentCPUTracker()
        let rated = tracker.rating([session(cpuSeconds: 65, measured: 184.5)], now: .now)
        #expect(rated.first?.resource?.cpuPercent == 184.5)
    }

    /// **The case the old path threw away.** A child finishing makes the tree's total
    /// fall, so the difference is negative and `burned >= 0` discarded the whole
    /// reading — a session that ran a build to completion measured nothing. The probe's
    /// own figure survives that, because it is not a difference of totals.
    @Test
    func afallingCounterNoLongerLosesTheReading() {
        var tracker = AgentCPUTracker()
        let now = Date()
        _ = tracker.rating([session(cpuSeconds: 500, measured: nil)], now: now)
        // The tree shrank: 500 -> 120. Differencing gives -380 and no reading.
        let differenced = tracker.rating(
            [session(cpuSeconds: 120, measured: nil)], now: now.addingTimeInterval(30))
        #expect(differenced.first?.resource?.cpuPercent == nil, "the old path still declines")
        // With the probe's own measurement, the same fall still reports.
        var measuring = AgentCPUTracker()
        _ = measuring.rating([session(cpuSeconds: 500, measured: nil)], now: now)
        let measured = measuring.rating(
            [session(cpuSeconds: 120, measured: 76.0)], now: now.addingTimeInterval(30))
        #expect(measured.first?.resource?.cpuPercent == 76.0)
    }

    /// Without a measurement it still differences, so nothing regressed for a machine
    /// that has not been updated.
    @Test
    func differencingStillWorksWhenNothingWasMeasured() {
        var tracker = AgentCPUTracker()
        let now = Date()
        _ = tracker.rating([session(cpuSeconds: 100, measured: nil)], now: now)
        let rated = tracker.rating(
            [session(cpuSeconds: 130, measured: nil)], now: now.addingTimeInterval(30))
        // 30 CPU seconds in 30 wall seconds is one core.
        #expect(rated.first?.resource?.cpuPercent == 100)
    }
}
