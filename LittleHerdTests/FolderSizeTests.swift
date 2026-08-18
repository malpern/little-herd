import Foundation
import Testing
@testable import LittleHerd

/// Measuring a volume takes tens of seconds, so the interface has to say how
/// far along it is and roughly how much longer — and has to be honest when it
/// does not yet know.
struct FolderScanProgressTests {
    @Test
    func nothingIsEstimatedFromASingleMeasurement() {
        let first = FolderScanProgress(measured: 1, total: 12, elapsed: 4)

        #expect(first.estimatedRemaining == nil)
        #expect(first.fraction > 0)
    }

    /// Once there is a rate, the projection is simply that rate applied to
    /// what is left.
    @Test
    func theEstimateFollowsTheRateSoFar() throws {
        // Four of twelve done in 40s: ten seconds each, eight to go.
        let progress = FolderScanProgress(measured: 4, total: 12, elapsed: 40)
        let remaining = try #require(progress.estimatedRemaining)

        #expect(Int(remaining.rounded()) == 80)
        #expect(abs(progress.fraction - 1.0 / 3.0) < 0.001)
    }

    @Test
    func afinishedScanHasNothingLeftToPredict() {
        let done = FolderScanProgress(measured: 12, total: 12, elapsed: 120)

        #expect(done.isComplete)
        #expect(done.estimatedRemaining == nil)
        #expect(done.fraction == 1)
    }

    @Test
    func anEmptyFolderDoesNotDivideByZero() {
        let empty = FolderScanProgress(measured: 0, total: 0, elapsed: 0)

        #expect(empty.fraction == 0)
        #expect(empty.estimatedRemaining == nil)
    }
}

struct DiskUsageParserTests {
    /// `du` reports the folder it was asked about alongside its children, and
    /// keeping it would list the folder inside itself.
    @Test
    func theFolderBeingListedIsNotOneOfItsOwnChildren() {
        let output = """
        298780800\t/Volumes/ChromiumWork/chromium-build-lane
        8\t/Volumes/ChromiumWork/.Spotlight-V100
        298780824\t/Volumes/ChromiumWork
        """

        let entries = DiskUsageParser.entries(from: output, parent: "/Volumes/ChromiumWork")

        #expect(entries.count == 2)
        #expect(!entries.contains { $0.path == "/Volumes/ChromiumWork" })
    }

    /// `du -k` counts kilobytes; everything else in the app speaks bytes.
    @Test
    func kilobytesBecomeBytes() throws {
        let entries = DiskUsageParser.entries(
            from: "298780800\t/Volumes/ChromiumWork/chromium-build-lane",
            parent: "/Volumes/ChromiumWork"
        )
        let entry = try #require(entries.first)

        #expect(entry.sizeBytes == 298_780_800 * 1_024)
        #expect(entry.name == "chromium-build-lane")
    }

    /// Paths with spaces are ordinary on a Mac — "KeyPath Lab" is one of these
    /// machines' volumes — so splitting on whitespace would lose them.
    @Test
    func apathWithSpacesSurvives() throws {
        let entries = DiskUsageParser.entries(
            from: "466000\t/Volumes/KeyPath Lab/Some Folder Name",
            parent: "/Volumes/KeyPath Lab"
        )
        let entry = try #require(entries.first)

        #expect(entry.name == "Some Folder Name")
        #expect(entry.path == "/Volumes/KeyPath Lab/Some Folder Name")
    }

    @Test
    func unreadableLinesAreSkippedRatherThanGuessedAt() {
        let entries = DiskUsageParser.entries(
            from: "du: /x: Permission denied\nnot a size\n1024\t/Volumes/V/real",
            parent: "/Volumes/V"
        )

        #expect(entries.map(\.name) == ["real"])
    }
}

struct FolderScanTests {
    private func scan(_ sizes: [(String, Double)], state: FolderScanState) -> FolderScan {
        FolderScan(
            path: "/Volumes/V",
            entries: sizes.map {
                FolderEntry(
                    name: $0.0, path: "/Volumes/V/\($0.0)",
                    sizeBytes: $0.1, isDirectory: true
                )
            },
            state: state
        )
    }

    /// The question is always "what is eating this", so the answer leads.
    @Test
    func thebiggestThingComesFirst() {
        let s = scan([("small", 10), ("huge", 900), ("middling", 100)], state: .idle)

        #expect(s.rankedEntries.map(\.name) == ["huge", "middling", "small"])
    }

    /// Partial results are still useful: the biggest folder is usually visible
    /// long before the last one has been walked.
    @Test
    func apartialScanStillRanksWhatItHas() {
        let s = scan(
            [("a", 5), ("b", 50)],
            state: .measuring(FolderScanProgress(measured: 2, total: 12, elapsed: 20))
        )

        #expect(s.rankedEntries.first?.name == "b")
        #expect(s.state.isRunning)
        #expect(s.totalMeasuredBytes == 55)
    }

    /// A reading from this morning describes this morning, so it offers a
    /// refresh rather than quietly passing itself off as current.
    @Test
    func anOldReadingKnowsItIsOld() {
        let now = Date()
        let fresh = scan([], state: .done(measuredAt: now.addingTimeInterval(-60)))
        let old = scan([], state: .done(measuredAt: now.addingTimeInterval(-7_200)))

        #expect(!fresh.isStale(now: now))
        #expect(old.isStale(now: now))
        // A scan still running is not stale — it is simply not finished.
        #expect(!scan([], state: .listing).isStale(now: now))
    }
}
