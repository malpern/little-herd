import Foundation
import Testing
@testable import LittleHerd

/// History is what turns "229 bad sectors" into "up 40 this week" — the
/// difference between a number and a decision.
struct MetricHistoryTests {
    private let machine = MachineID("synology")
    private let drive = HistorySeries.driveSectors(driveID: "sdb")

    private func store(
        retention: TimeInterval = MetricHistoryStore.defaultRetention
    ) -> MetricHistoryStore {
        // No file: these test the arithmetic, not the disk.
        MetricHistoryStore(fileURL: nil, retention: retention)
    }

    private var base: Date { Date(timeIntervalSince1970: 1_000_000_000) }

    @Test
    func samplesInOneBucketAverageIntoASinglePoint() async {
        let store = store()
        // Ten seconds apart, as the sampler runs: all inside one bucket.
        for (index, value) in [10.0, 20.0, 30.0].enumerated() {
            await store.record(
                machine: machine,
                series: .metric(.cpu),
                value: value,
                at: base.addingTimeInterval(Double(index) * 10)
            )
        }

        let points = await store.samples(machine: machine, series: .metric(.cpu))
        #expect(points.count == 1)
        #expect(points[0].value == 20)
    }

    /// A bucket still filling must still be visible, or the newest reading
    /// vanishes from a chart until its five minutes are up.
    @Test
    func theBucketInProgressIsIncluded() async {
        let store = store()
        await store.record(
            machine: machine, series: .metric(.cpu), value: 42, at: base
        )
        let points = await store.samples(machine: machine, series: .metric(.cpu))
        #expect(points.count == 1)
        #expect(points[0].value == 42)
    }

    @Test
    func separateBucketsBecomeSeparatePoints() async {
        let store = store()
        await store.record(
            machine: machine, series: .metric(.disk), value: 50, at: base
        )
        await store.record(
            machine: machine,
            series: .metric(.disk),
            value: 60,
            at: base.addingTimeInterval(MetricHistoryStore.bucketDuration * 2)
        )

        let points = await store.samples(machine: machine, series: .metric(.disk))
        #expect(points.count == 2)
        #expect(points.map(\.value) == [50, 60])
    }

    /// Series must not bleed into one another — two drives, two histories.
    @Test
    func seriesAndMachinesAreKeptApart() async {
        let store = store()
        await store.record(machine: machine, series: drive, value: 229, at: base)
        await store.record(
            machine: machine,
            series: .driveSectors(driveID: "sda"),
            value: 0,
            at: base
        )
        await store.record(
            machine: MachineID("mini"), series: drive, value: 7, at: base
        )

        #expect(await store.samples(machine: machine, series: drive)[0].value == 229)
        #expect(
            await store.samples(
                machine: machine, series: .driveSectors(driveID: "sda")
            )[0].value == 0
        )
        #expect(
            await store.samples(machine: MachineID("mini"), series: drive)[0].value == 7
        )
    }

    /// The question the whole feature exists to answer.
    @Test
    func aTrendReportsWhatChangedAndOverHowLong() async {
        let store = store()
        let week = 7 * 24 * 60 * 60.0
        await store.record(
            machine: machine, series: drive, value: 189,
            at: base
        )
        await store.record(
            machine: machine, series: drive, value: 210,
            at: base.addingTimeInterval(week / 2)
        )
        await store.record(
            machine: machine, series: drive, value: 229,
            at: base.addingTimeInterval(week)
        )

        let trend = await store.trend(
            machine: machine,
            series: drive,
            over: week * 2,
            now: base.addingTimeInterval(week)
        )
        let found = try? #require(trend)
        #expect(found?.change == 40)
        #expect(found?.sampleCount == 3)
        #expect(found?.isMeaningful == true)
    }

    /// Two points a minute apart is not a trend, however different they are.
    @Test
    func aChangeOverMinutesIsNotCalledATrend() async {
        let store = store()
        await store.record(machine: machine, series: drive, value: 0, at: base)
        await store.record(
            machine: machine, series: drive, value: 500,
            at: base.addingTimeInterval(MetricHistoryStore.bucketDuration)
        )

        let trend = await store.trend(
            machine: machine, series: drive, over: 3600,
            now: base.addingTimeInterval(MetricHistoryStore.bucketDuration)
        )
        #expect(trend?.isMeaningful == false)
    }

    @Test
    func aSingleReadingIsNoTrendAtAll() async {
        let store = store()
        await store.record(machine: machine, series: drive, value: 229, at: base)
        #expect(
            await store.trend(
                machine: machine, series: drive, over: 3600, now: base
            ) == nil
        )
    }

    /// Otherwise a monitor left running becomes an ever-growing file.
    @Test
    func pointsOlderThanTheRetentionWindowAreDropped() async {
        let store = store(retention: 3600)
        await store.record(machine: machine, series: drive, value: 1, at: base)
        await store.record(
            machine: machine, series: drive, value: 2,
            at: base.addingTimeInterval(1800)
        )
        // Two hours on: the first two points are now outside the window.
        await store.record(
            machine: machine, series: drive, value: 3,
            at: base.addingTimeInterval(7200)
        )

        let points = await store.samples(machine: machine, series: drive)
        #expect(points.allSatisfy { $0.timestamp >= base.addingTimeInterval(3600) })
    }

    @Test
    func historySurvivesARestart() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lh-history-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("history.json")

        // Recent timestamps, not the fixed fixture date: loading prunes
        // anything past the retention window against the real clock, and a
        // point from 2001 is correctly thrown away.
        let recent = Date.now.addingTimeInterval(-3600)

        let first = MetricHistoryStore(fileURL: file)
        await first.record(machine: machine, series: drive, value: 189, at: recent)
        // Closes the bucket so there is something finished to write.
        await first.record(
            machine: machine, series: drive, value: 229,
            at: recent.addingTimeInterval(MetricHistoryStore.bucketDuration)
        )
        await first.flush()

        let reopened = MetricHistoryStore(fileURL: file)
        let points = await reopened.samples(machine: machine, series: drive)
        #expect(points.contains { $0.value == 189 })
    }
}

/// The sentence the whole feature exists to produce.
@MainActor
struct DriveTrendWordingTests {
    private func concern(sectors: Int) -> StorageConcern {
        StorageConcern(
            health: .critical,
            subject: "Drive 2",
            detail: "\(sectors) bad sectors"
        )
    }

    private func trend(change: Double, days: Double, points: Int) -> HistoryTrend {
        let start = Date.now.addingTimeInterval(-days * 86_400)
        return HistoryTrend(
            first: HistorySample(timestamp: start, value: 229 - change),
            last: HistorySample(timestamp: Date.now, value: 229),
            sampleCount: points
        )
    }

    @Test
    func aGrowingCountSaysHowMuchAndOverHowLong() {
        let text = concern(sectors: 229)
            .summary(trend: trend(change: 40, days: 7, points: 50))
        #expect(text.contains("Drive 2 failing"))
        #expect(text.contains("229 bad sectors"))
        #expect(text.contains("up 40 in 7 days"))
    }

    /// A count that has not moved is the good case, and saying "up 0" about it
    /// would be alarming noise.
    @Test
    func acountThatHasNotMovedSaysNothingExtra() {
        let text = concern(sectors: 229)
            .summary(trend: trend(change: 0, days: 7, points: 50))
        #expect(text == concern(sectors: 229).summary)
    }

    /// Two readings minutes apart cannot support a claim about a fortnight.
    @Test
    func tooLittleHistoryMakesNoClaim() {
        let text = concern(sectors: 229)
            .summary(trend: trend(change: 40, days: 0.01, points: 2))
        #expect(!text.contains("up"))
    }

    @Test
    func noHistoryAtAllReadsAsBefore() {
        #expect(
            concern(sectors: 229).summary(trend: nil)
                == concern(sectors: 229).summary
        )
    }
}

/// A session shorter than one bucket must still leave something behind.
struct HistoryFlushTests {
    @Test
    func abucketStillFillingIsPersisted() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lh-flush-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("history.json")

        let store = MetricHistoryStore(fileURL: file)
        // One reading, well inside a bucket that never closes — the shape of a
        // short session, which is most of them.
        await store.record(
            machine: MachineID("synology"),
            series: .driveSectors(driveID: "sdb"),
            value: 229,
            at: Date.now
        )
        await store.flush()

        #expect(FileManager.default.fileExists(atPath: file.path))
        let reopened = MetricHistoryStore(fileURL: file)
        let points = await reopened.samples(
            machine: MachineID("synology"),
            series: .driveSectors(driveID: "sdb")
        )
        #expect(points.contains { $0.value == 229 })
    }
}
