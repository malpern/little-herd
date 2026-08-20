import Foundation
import Testing
@testable import LittleHerd

/// Reading Codex's account limits out of its own rollouts.
struct CodexRolloutUsageTests {
    private func makeDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "codex-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

    private func entry(
        primary: String?,
        secondary: String? = nil,
        at timestamp: String
    ) -> String {
        let blocks = [
            primary.map { "\"primary\":\($0)" } ?? "\"primary\":null",
            secondary.map { "\"secondary\":\($0)" } ?? "\"secondary\":null",
        ].joined(separator: ",")
        return """
        {"timestamp":"\(timestamp)","type":"event_msg","payload":\
        {"type":"token_count","rate_limits":{\(blocks)}}}
        """
    }

    private func block(used: Double, minutes: Int, resets: Int) -> String {
        "{\"used_percent\":\(used),\"window_minutes\":\(minutes),\"resets_at\":\(resets)}"
    }

    /// The shape found in 216 rollouts on this Mac.
    @Test
    func aPopulatedBlockIsRead() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try entry(
            primary: block(used: 100, minutes: 10_080, resets: 1_786_388_138),
            at: "2026-08-19T12:00:00Z"
        ).write(
            to: directory.appending(path: "a.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let reading = try #require(await CodexRolloutUsage.latest(directory: directory))
        let window = try #require(reading.blocking)
        #expect(window.usedPercent == 100)
        #expect(window.windowMinutes == 10_080)
        #expect(window.resetsAt == Date(timeIntervalSince1970: 1_786_388_138))
    }

    /// Null blocks are the common case — most turns carry the key with nothing
    /// in it, and a reading must not be invented from those.
    @Test
    func nullBlocksAreNotAReading() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try entry(primary: nil, at: "2026-08-19T12:00:00Z").write(
            to: directory.appending(path: "a.jsonl"),
            atomically: true,
            encoding: .utf8
        )
        #expect(await CodexRolloutUsage.latest(directory: directory) == nil)
    }

    /// Later lines describe now; earlier ones describe a window that has since
    /// moved. The last populated block in a file wins.
    @Test
    func theLastReadingInAFileWins() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let lines = [
            entry(
                primary: block(used: 10, minutes: 300, resets: 1),
                at: "2026-08-19T10:00:00Z"
            ),
            entry(
                primary: block(used: 64, minutes: 300, resets: 2),
                at: "2026-08-19T11:00:00Z"
            ),
        ].joined(separator: "\n")
        try lines.write(
            to: directory.appending(path: "a.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let reading = try #require(await CodexRolloutUsage.latest(directory: directory))
        #expect(reading.blocking?.usedPercent == 64)
    }

    /// The window that stops you first, with the tie-break taken from the
    /// CodexBar path rather than reasoned out again.
    ///
    /// This test is the reason the two agree: written to assert the opposite,
    /// it failed, and the disagreement it exposed would have shown one
    /// provider reading differently depending on which file the number came
    /// from — a bug nobody could reproduce.
    @Test
    func theBlockingWindowMatchesTheOtherSourcesRule() {
        let short = CodexRolloutUsage.Window(
            usedPercent: 90,
            windowMinutes: 300,
            resetsAt: nil
        )
        let weekly = CodexRolloutUsage.Window(
            usedPercent: 90,
            windowMinutes: 10_080,
            resetsAt: nil
        )
        let fuller = CodexRolloutUsage.Window(
            usedPercent: 96,
            windowMinutes: 300,
            resetsAt: nil
        )
        // Equal percentages: the shorter window, as the other source does.
        #expect(
            CodexRolloutUsage.Reading(windows: [short, weekly], observedAt: .now)
                .blocking == short
        )
        #expect(
            CodexRolloutUsage.Reading(windows: [weekly, fuller], observedAt: .now)
                .blocking == fuller
        )
    }

    /// Nothing there is not a failure — this runs on machines that have never
    /// had Codex installed.
    @Test
    func anAbsentDirectoryIsNotAFailure() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(
            await CodexRolloutUsage.latest(
                directory: directory.appending(path: "absent")
            ) == nil
        )
    }
}

/// Choosing between two sources that are each better when the other is not.
struct CodexUsageSourceTests {
    private func limit(
        usedPercent: Double,
        updatedAt: Date
    ) -> AIUsageLimit {
        AIUsageLimit(
            provider: .codex,
            remainingPercent: 100 - usedPercent,
            windowMinutes: 10_080,
            resetsAt: nil,
            updatedAt: updatedAt
        )
    }

    /// The rule that a check against real files disproved: preferring the
    /// first-party file would have shown a reading five days old saying 30%
    /// over one a day old saying 100%. Later wins, whichever wrote it.
    @Test
    func theLaterReadingWinsWhicheverSourceWroteIt() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000)
        let stale = limit(
            usedPercent: 30,
            updatedAt: now.addingTimeInterval(-5 * 86_400)
        )
        let recent = limit(
            usedPercent: 100,
            updatedAt: now.addingTimeInterval(-86_400)
        )

        func later(_ a: AIUsageLimit?, _ b: AIUsageLimit?) -> AIUsageLimit? {
            guard let a else { return b }
            guard let b else { return a }
            return a.updatedAt > b.updatedAt ? a : b
        }

        #expect(later(stale, recent)?.remainingPercent == 0)
        #expect(later(recent, stale)?.remainingPercent == 0)
        #expect(later(nil, stale)?.remainingPercent == 70)
        #expect(later(stale, nil)?.remainingPercent == 70)
        #expect(later(nil, nil) == nil)
    }

    /// A rollout reading is a file written when a session ran, not a poll, so
    /// it is subject to the same freshness test as anything else. Five days
    /// old is five days old whoever wrote it.
    @Test
    func aFirstPartyReadingIsStillSubjectToFreshness() {
        let now = Date(timeIntervalSinceReferenceDate: 900_000)
        let old = limit(
            usedPercent: 30,
            updatedAt: now.addingTimeInterval(-5 * 86_400)
        )
        let availability = AIUsageAvailability.resolve(
            limit: old,
            sourceInstalled: true,
            now: now,
            freshnessInterval: 15 * 60
        )
        guard case .stale = availability else {
            Issue.record("expected stale, got \(availability)")
            return
        }
    }
}

/// The reading as it arrives from a probe, which is how a remote machine's copy
/// gets here — it runs a shell script over ssh and cannot run the reader.
struct AgentUsageOutputParserTests {
    /// The exact line the mini produced over ssh, which is 16 hours newer than
    /// the one this Mac could produce: the same account, seen at two ages.
    @Test
    func theLineTheMiniProducedIsRead() throws {
        let limit = try #require(
            AgentUsageOutputParser.parse(
                "agent_usage=codex\t2026-08-15T01:34:15.613Z\t42.0\t10080\t1787197401\t-1\t0\t0"
            )
        )
        #expect(limit.provider == .codex)
        #expect(limit.remainingPercent == 58)
        #expect(limit.windowMinutes == 10_080)
        #expect(limit.resetsAt == Date(timeIntervalSince1970: 1_787_197_401))
    }

    /// -1 means the API reported no such window. An absent limit and a limit at
    /// zero percent are different things, and a blank field could not tell them
    /// apart — which is why the probe writes a number that cannot be mistaken
    /// for a reading.
    @Test
    func anAbsentWindowIsNotReadAsEmpty() {
        #expect(
            AgentUsageOutputParser.parse(
                "agent_usage=codex\t2026-08-15T01:34:15.613Z\t-1\t0\t0\t-1\t0\t0"
            ) == nil
        )
    }

    /// Both windows populated: the fuller one, by the rule both sources share.
    @Test
    func bothWindowsAreConsidered() throws {
        let limit = try #require(
            AgentUsageOutputParser.parse(
                "agent_usage=codex\t2026-08-15T01:34:15Z\t20.0\t300\t0\t88.0\t10080\t0"
            )
        )
        #expect(limit.remainingPercent == 12)
        #expect(limit.windowMinutes == 10_080)
    }

    /// Anything else on the probe's output is not this line.
    @Test
    func otherProbeOutputIsIgnored() {
        #expect(AgentUsageOutputParser.parse("agent_session=codex\tx\ty") == nil)
        #expect(AgentUsageOutputParser.parse("") == nil)
    }
}
