import Foundation
import Testing
@testable import LittleHerd

/// Reading thresholds out of transcripts that already exist.
///
/// The watching path is exact and slow — days, on a model holding a million
/// tokens — so a fresh install shows no proportion and never blinks. Every
/// compaction that already happened is written down, and reading them once
/// gives day one what watching gives a fortnight.
struct CompactionSeedTests {
    private func transcript(
        _ lines: [String],
        in directory: URL,
        named name: String
    ) throws {
        try lines.joined(separator: "\n")
            .write(
                to: directory.appending(path: name),
                atomically: true,
                encoding: .utf8
            )
    }

    private func assistant(model: String, tokens: Int) -> String {
        """
        {"type":"assistant","message":{"model":"\(model)","usage":\
        {"input_tokens":2,"cache_read_input_tokens":\(tokens - 2),\
        "cache_creation_input_tokens":0}}}
        """
    }

    private var compaction: String {
        #"{"type":"user","isCompactSummary":true,"message":{"content":"..."}}"#
    }

    private func makeDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "seed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

    /// The shape this exists for: context climbs, then a compaction, and the
    /// peak just before it is the threshold.
    @Test
    func thePeakBeforeACompactionIsTheThreshold() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try transcript(
            [
                assistant(model: "claude-opus-5", tokens: 400_000),
                assistant(model: "claude-opus-5", tokens: 996_407),
                compaction,
                assistant(model: "claude-opus-5", tokens: 40_000),
            ],
            in: directory,
            named: "a.jsonl"
        )

        let seeded = await CompactionThresholdSeeder.scan(directory: directory)
        #expect(seeded["claude-opus-5"] == 996_407)
    }

    /// A hand-run /compact fires below the real threshold and never above it,
    /// so the largest observation is the one that is not a manual one. This is
    /// opus-4-8's real shape: four compactions near 995,000 and two far below.
    @Test
    func aHandCompactionDoesNotLowerTheThreshold() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try transcript(
            [
                assistant(model: "claude-opus-4-8", tokens: 354_689),
                compaction,
                assistant(model: "claude-opus-4-8", tokens: 997_232),
                compaction,
            ],
            in: directory,
            named: "b.jsonl"
        )

        let seeded = await CompactionThresholdSeeder.scan(directory: directory)
        #expect(seeded["claude-opus-4-8"] == 997_232)
    }

    /// Models are measured apart, which is the whole reason a single table was
    /// wrong: sonnet compacts near 165,000 and opus near a million.
    @Test
    func modelsAreSeededSeparatelyAcrossFiles() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try transcript(
            [assistant(model: "claude-opus-5", tokens: 998_120), compaction],
            in: directory,
            named: "c.jsonl"
        )
        try transcript(
            [assistant(model: "claude-sonnet-4-6", tokens: 166_702), compaction],
            in: directory,
            named: "d.jsonl"
        )

        let seeded = await CompactionThresholdSeeder.scan(directory: directory)
        #expect(seeded["claude-opus-5"] == 998_120)
        #expect(seeded["claude-sonnet-4-6"] == 166_702)
    }

    /// A session that has never compacted teaches nothing. Its peak is where it
    /// happens to have got to, not where the model gives out — seeding from it
    /// would invent a threshold far below the truth and make every later
    /// session read as nearly full.
    @Test
    func aTranscriptThatNeverCompactedTeachesNothing() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try transcript(
            [
                assistant(model: "claude-opus-5", tokens: 120_000),
                assistant(model: "claude-opus-5", tokens: 300_000),
            ],
            in: directory,
            named: "e.jsonl"
        )

        let seeded = await CompactionThresholdSeeder.scan(directory: directory)
        #expect(seeded.isEmpty)
    }

    /// A directory with nothing in it, and one that is not there at all, both
    /// mean "no thresholds" rather than a crash — this runs at launch.
    @Test
    func nothingToReadIsNotAFailure() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(await CompactionThresholdSeeder.scan(directory: directory).isEmpty)
        #expect(
            await CompactionThresholdSeeder.scan(
                directory: directory.appending(path: "absent")
            ).isEmpty
        )
    }

    /// Lines that are not JSON at all sit in real transcripts, and a scan that
    /// gave up on one would lose every threshold behind it in the file.
    @Test
    func unreadableLinesDoNotStopTheScan() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try transcript(
            [
                "{not json at all",
                assistant(model: "claude-opus-5", tokens: 996_878),
                "",
                compaction,
            ],
            in: directory,
            named: "f.jsonl"
        )

        let seeded = await CompactionThresholdSeeder.scan(directory: directory)
        #expect(seeded["claude-opus-5"] == 996_878)
    }
}
