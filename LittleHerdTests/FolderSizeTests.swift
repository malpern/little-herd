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

/// Finder's columns, and Finder's habits about them.
struct FolderSortTests {
    private func entry(_ name: String, size: Double, daysAgo: Double) -> FolderEntry {
        FolderEntry(
            name: name, path: "/V/\(name)", sizeBytes: size, isDirectory: true,
            modifiedAt: Date().addingTimeInterval(-daysAgo * 86_400)
        )
    }

    private var sample: [FolderEntry] {
        [
            entry("beta", size: 900, daysAgo: 30),
            entry("Alpha", size: 10, daysAgo: 1),
            entry("gamma", size: 100, daysAgo: 90),
        ]
    }

    /// Each column has an order that is obviously the useful one: biggest and
    /// newest first, but names A to Z.
    @Test
    func eachColumnStartsTheWayYouWouldWantIt() {
        #expect(!FolderSortField.size.defaultAscending)
        #expect(!FolderSortField.dateModified.defaultAscending)
        #expect(FolderSortField.name.defaultAscending)
    }

    @Test
    func sizeSortsLargestFirst() {
        let sorted = FolderSort(field: .size, ascending: false).sorted(sample)
        #expect(sorted.map(\.name) == ["beta", "gamma", "Alpha"])
    }

    @Test
    func dateSortsNewestFirst() {
        let sorted = FolderSort(field: .dateModified, ascending: false).sorted(sample)
        #expect(sorted.map(\.name) == ["Alpha", "beta", "gamma"])
    }

    /// Names compare the way a person reads them — case-insensitively, and with
    /// numbers in numeric order — which is what localizedStandardCompare is for.
    @Test
    func namesSortLikeTheFinderSortsThem() {
        let sorted = FolderSort(field: .name, ascending: true).sorted(sample)
        #expect(sorted.map(\.name) == ["Alpha", "beta", "gamma"])

        let numbered = [
            FolderEntry(name: "item10", path: "/V/item10", sizeBytes: 1, isDirectory: true, modifiedAt: nil),
            FolderEntry(name: "item2", path: "/V/item2", sizeBytes: 1, isDirectory: true, modifiedAt: nil),
        ]
        #expect(
            FolderSort(field: .name, ascending: true).sorted(numbered).map(\.name)
                == ["item2", "item10"]
        )
    }

    /// A folder the machine could not stat sinks rather than jumping to the top
    /// of a date sort, where it would look like the most recent thing.
    @Test
    func anUndatedFolderSortsAsOldest() {
        let undated = FolderEntry(
            name: "mystery", path: "/V/mystery", sizeBytes: 50,
            isDirectory: true, modifiedAt: nil
        )
        let sorted = FolderSort(field: .dateModified, ascending: false)
            .sorted(sample + [undated])

        #expect(sorted.last?.name == "mystery")
    }

    /// Clicking the same column reverses it; clicking a different one starts
    /// from that column's own sensible direction rather than inheriting.
    @Test
    func clickingAColumnBehavesLikeAColumnHeading() {
        var sort = FolderSort(field: .size, ascending: false)

        sort.toggle(.size)
        #expect(sort == FolderSort(field: .size, ascending: true))

        sort.toggle(.dateModified)
        #expect(sort == FolderSort(field: .dateModified, ascending: false))

        sort.toggle(.name)
        #expect(sort == FolderSort(field: .name, ascending: true))
    }
}

struct FolderDateFormatterTests {
    /// "Today at 2:30 PM" reads at a glance; a timestamp has to be decoded, and
    /// decoded against today's date to mean anything at all.
    @Test
    func recentDaysAreNamedRatherThanNumbered() {
        let now = Date()
        let calendar = Calendar.current

        let today = FolderDateFormatter.string(for: now, now: now, calendar: calendar)
        #expect(today.hasPrefix("Today "))

        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        #expect(
            FolderDateFormatter.string(for: yesterday, now: now, calendar: calendar)
                .hasPrefix("Yesterday ")
        )
    }

    /// Anything older gets a date, because "17 days ago" is not something
    /// anyone can act on.
    @Test
    func olderThingsGetADate() {
        let now = Date()
        let old = Calendar.current.date(byAdding: .day, value: -17, to: now)!
        let text = FolderDateFormatter.string(for: old, now: now)

        #expect(!text.hasPrefix("Today"))
        #expect(!text.hasPrefix("Yesterday"))
        #expect(!text.isEmpty)
    }
}


/// A scan costs tens of seconds, so it is paid for once.
@MainActor
struct FolderSizeStoreTests {
    private func store() -> (FolderSizeStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("folder-sizes-\(UUID().uuidString).json")
        return (FolderSizeStore(fileURL: url), url)
    }

    private func entries() -> [FolderEntry] {
        [FolderEntry(
            name: "CrabBox", path: "/Volumes/V/CrabBox",
            sizeBytes: 213_233_680 * 1_024, isDirectory: true, modifiedAt: Date()
        )]
    }

    @Test
    func areadingSurvivesARestart() throws {
        let (first, url) = store()
        first.record(entries(), machine: MachineID("mini"), path: "/Volumes/V")

        let reopened = FolderSizeStore(fileURL: url)
        let restored = try #require(reopened.scan(machine: MachineID("mini"), path: "/Volumes/V"))

        #expect(restored.entries.map(\.name) == ["CrabBox"])
        try? FileManager.default.removeItem(at: url)
    }

    /// "/" means something different on every machine, so one machine's answer
    /// must never be shown as another's.
    @Test
    func machinesDoNotShareAnswers() {
        let (store, url) = store()
        store.record(entries(), machine: MachineID("mini"), path: "/")

        #expect(store.scan(machine: MachineID("mini"), path: "/") != nil)
        #expect(store.scan(machine: MachineID("linux"), path: "/") == nil)
        try? FileManager.default.removeItem(at: url)
    }

    /// Past the retention window it describes what *was* on the disk, and
    /// re-measuring is the better answer than restoring it.
    @Test
    func astaleReadingIsNotRestored() {
        let (store, url) = store()
        store.record(
            entries(), machine: MachineID("mini"), path: "/old",
            measuredAt: Date().addingTimeInterval(-FolderSizeStore.retention - 60)
        )

        #expect(store.scan(machine: MachineID("mini"), path: "/old") == nil)
        try? FileManager.default.removeItem(at: url)
    }

    @Test
    func amachineLeavingTheHerdTakesItsReadingsWithIt() {
        let (store, url) = store()
        store.record(entries(), machine: MachineID("mini"), path: "/a")
        store.record(entries(), machine: MachineID("linux"), path: "/a")

        store.forget(machine: MachineID("mini"))

        #expect(store.scan(machine: MachineID("mini"), path: "/a") == nil)
        #expect(store.scan(machine: MachineID("linux"), path: "/a") != nil)
        try? FileManager.default.removeItem(at: url)
    }
}

/// What the folder view is showing, without drawing it.
@MainActor
struct FolderBrowserModelTests {
    private func model(_ availability: FolderScanAvailability = .unsupported) -> FolderBrowserModel {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("browser-\(UUID().uuidString).json")
        return FolderBrowserModel(
            machine: MachineID("mini"),
            availability: availability,
            store: FolderSizeStore(fileURL: url)
        )
    }

    /// A machine that cannot answer says so rather than offering a control that
    /// does nothing — the NAS, whose DirSize API denies its own tasks exist.
    @Test
    func amachineThatCannotMeasureSaysSo() {
        let browser = model(.unsupported)

        #expect(!browser.canMeasure)
        guard case .unsupported = browser.scanAvailability else {
            Issue.record("expected unsupported")
            return
        }
    }

    /// This Mac without permission is a different answer from a NAS that can
    /// never answer, and the interface has a different thing to say about each.
    @Test
    func amacWithoutPermissionIsItsOwnAnswer() {
        let browser = model(.needsFullDiskAccess)

        #expect(!browser.canMeasure)
        guard case .needsFullDiskAccess = browser.scanAvailability else {
            Issue.record("expected needsFullDiskAccess")
            return
        }
    }

    /// Closing a folder closes what was open inside it, so reopening does not
    /// reveal a tree someone left three levels deep an hour ago.
    @Test
    func closingAFolderClosesWhatWasInsideIt() {
        let browser = model(.available(FolderSizeScanner(location: .local)))
        browser.toggle("/Volumes/V", isRoot: true)
        browser.toggle("/Volumes/V/inner")
        browser.toggle("/Volumes/V/inner/deeper")

        #expect(browser.isExpanded("/Volumes/V/inner/deeper"))

        browser.toggle("/Volumes/V")

        #expect(!browser.isExpanded("/Volumes/V"))
        #expect(!browser.isExpanded("/Volumes/V/inner"))
        #expect(!browser.isExpanded("/Volumes/V/inner/deeper"))
    }

    /// Sorting is a property of the list, not of one folder: changing it
    /// reorders every level that is open.
    @Test
    func changingTheSortRebuildsTheWholeList() {
        let browser = model(.available(FolderSizeScanner(location: .local)))
        browser.sort.toggle(.name)

        #expect(browser.sort.field == .name)
        #expect(browser.sort.ascending)
    }
}

/// Output arriving a line at a time, which is what makes a slow scan readable.
struct StreamingProcessRunnerTests {
    @Test
    func linesArriveSeparatelyRatherThanAllAtOnce() async throws {
        var received: [String] = []
        for try await line in StreamingProcessRunner.lines(
            executablePath: "/bin/sh",
            arguments: ["-c", "printf 'one\\ntwo\\nthree\\n'"]
        ) {
            received.append(line)
        }

        #expect(received == ["one", "two", "three"])
    }

    /// A line split across two reads must not be reported as a truncated path.
    @Test
    func apartialLineWaitsForTheRestOfItself() async throws {
        var received: [String] = []
        for try await line in StreamingProcessRunner.lines(
            executablePath: "/bin/sh",
            arguments: ["-c", "printf 'begin'; sleep 0.2; printf 'ning\\nsecond\\n'"]
        ) {
            received.append(line)
        }

        #expect(received == ["beginning", "second"])
    }

    /// Output with no trailing newline is still reported rather than dropped.
    @Test
    func alastLineWithoutANewlineIsNotLost() async throws {
        var received: [String] = []
        for try await line in StreamingProcessRunner.lines(
            executablePath: "/bin/sh",
            arguments: ["-c", "printf 'no trailing newline'"]
        ) {
            received.append(line)
        }

        #expect(received == ["no trailing newline"])
    }

}
