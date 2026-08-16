import Foundation
import SwiftUI
import Testing
@testable import LittleHerd

/// The rules the interface applies before it draws anything.
///
/// Every defect these cover was found by looking at the running app, because
/// the rules lived inside view bodies where nothing else could reach them. Two
/// of them are here as regressions rather than hypotheticals: the same machine
/// reported two different statuses depending on which surface you looked at,
/// and the memory bar knew to fall back to a usage figure in the overview but
/// not on the machine's own page.

@MainActor
struct MachineStatusPresentationTests {
    /// Red means it broke. A machine that has never answered has not broken —
    /// it has not been set up, and there may be nothing wrong with it at all.
    @Test
    func aMachineThatNeverAnsweredIsNotColouredAsAFault() {
        let machine = nas()
        machine.markOffline(.other("No shared folder is mounted."))

        #expect(machine.status == .notSetUp)
        #expect(machine.status.label == "Not set up yet")
    }

    /// Once it has worked, going quiet is a real fault again.
    @Test
    func aMachineThatWorkedAndStoppedIsAFault() {
        let machine = nas()
        machine.apply(
            SystemSnapshot(timestamp: .now, readings: [.disk: MetricReading(value: 40)])
        )
        machine.markOffline(.noAnswer)

        #expect(machine.status == .unreachable)
        #expect(machine.status.label == "Unreachable")
    }

    /// The regression. `MachineStatusLabel` drew a never-connected machine grey
    /// and called it "Not set up yet"; the two hover headers had their own
    /// copies of the same switch, never learned the rule, and drew it red and
    /// called it "Unreachable". One machine, three surfaces, two answers — and
    /// nothing to catch it but noticing.
    @Test
    func everySurfaceAgreesAboutOneMachine() {
        let neverConnected = nas()
        neverConnected.markOffline(.other("No shared folder is mounted."))

        // Whatever a surface asks, it asks this — there is no second switch to
        // disagree with.
        #expect(
            neverConnected.status
                == MachineStatus.resolve(state: .offline, hasNeverConnected: true)
        )
        #expect(
            MachineStatus.resolve(state: .offline, hasNeverConnected: true)
                != MachineStatus.resolve(state: .offline, hasNeverConnected: false)
        )
    }

    /// The surfaces that write the status out in words, rather than only
    /// speaking it to VoiceOver, were the last two holding their own vocabulary:
    /// the sidebar on a machine's own page said "Not connected" and
    /// "Unavailable" in grey, and the menu bar row said "Unavailable" in red
    /// whether or not the machine had ever answered. Both read `label` and
    /// `tint` now, so the words on screen are the words being spoken, and a
    /// machine that has never been set up is never coloured as a fault.
    @Test
    func theWrittenStatusesReadLikeTheSpokenOnes() {
        let neverConnected = nas()
        neverConnected.markOffline(.other("No shared folder is mounted."))

        #expect(neverConnected.status.label == "Not set up yet")
        #expect(neverConnected.status.tint != MachineStatus.unreachable.tint)

        let droppedOut = nas()
        droppedOut.apply(
            SystemSnapshot(timestamp: .now, readings: [.disk: MetricReading(value: 40)])
        )
        droppedOut.markOffline(.noAnswer)

        #expect(droppedOut.status.label == "Unreachable")
        // A machine that worked and stopped is a fault, and now says so
        // wherever it appears rather than only in the overview.
        #expect(droppedOut.status.tint == Color.red)
    }

    /// Two statuses sharing a sentence would put the drift back by another
    /// route: a surface could pick either word and still look consistent.
    @Test
    func noTwoStatusesShareASentence() {
        let labels = MachineStatus.allCases.map { String(localized: $0.label) }

        #expect(Set(labels).count == MachineStatus.allCases.count)
    }

    @Test
    func theRemainingStatesKeepTheirOwnWords() {
        #expect(
            MachineStatus.resolve(state: .connecting, hasNeverConnected: false)
                == .connecting
        )
        #expect(MachineStatus.resolve(state: .live, hasNeverConnected: false) == .live)
        #expect(
            MachineStatus.resolve(state: .stopped, hasNeverConnected: false) == .paused
        )
    }

    /// Paused and not-set-up share a colour but must not share a sentence: one
    /// is a choice you made, the other is a machine waiting for you.
    @Test
    func pausedAndNotSetUpReadDifferently() {
        #expect(MachineStatus.paused.label != MachineStatus.notSetUp.label)
    }
}

@MainActor
struct MetricValueDisplayTests {
    /// A tick on every healthy Mac is a badge that is always lit, and one of
    /// those says nothing at all. A machine that is fine reads like every other
    /// row: a number.
    @Test
    func aHealthyMachineShowsItsFigureRatherThanATick() {
        #expect(
            MetricValueDisplay.resolve(kind: .memory, value: 82, memoryPressure: .normal)
                == .percent(82)
        )
    }

    /// Trouble takes the column back. This is the one moment memory is worth
    /// interrupting for, and a shape carries further than a colour.
    @Test
    func troubleTakesTheColumn() {
        #expect(
            MetricValueDisplay.resolve(kind: .memory, value: 91, memoryPressure: .warning)
                == .pressure(.warning)
        )
        #expect(
            MetricValueDisplay.resolve(kind: .memory, value: 97, memoryPressure: .critical)
                == .pressure(.critical)
        )
    }

    /// A NAS has no notion of pressure but does know what it is using. It used
    /// to draw a dash beside a figure it had in hand.
    @Test
    func aMachineWithNoPressureSignalDoesNotGetADash() {
        #expect(
            MetricValueDisplay.resolve(kind: .memory, value: 77, memoryPressure: nil)
                == .percent(77)
        )
    }

    /// The tick survives in the one case it still earns: a verdict arrived and
    /// no figure did.
    @Test
    func averdictWithNoFigureIsStillBetterThanADash() {
        #expect(
            MetricValueDisplay.resolve(kind: .memory, value: nil, memoryPressure: .normal)
                == .pressure(.normal)
        )
    }

    /// No pressure and no figure either is the one case that has nothing to say.
    @Test
    func nothingKnownAboutMemoryIsADash() {
        #expect(
            MetricValueDisplay.resolve(kind: .memory, value: nil, memoryPressure: nil)
                == .unavailable
        )
    }

    @Test
    func theOtherMetricsReadAsPercentagesOrRates() {
        for kind in [MetricKind.cpu, .gpu, .disk] {
            #expect(
                MetricValueDisplay.resolve(kind: kind, value: 41, memoryPressure: nil)
                    == .percent(41)
            )
        }
        #expect(
            MetricValueDisplay.resolve(kind: .network, value: 2_048, memoryPressure: nil)
                == .bytesPerSecond(2_048)
        )
    }

    /// Pressure belongs to memory alone — a disk reading one would be nonsense,
    /// and the argument is there for every row.
    @Test
    func pressureIsIgnoredForEverythingButMemory() {
        #expect(
            MetricValueDisplay.resolve(kind: .disk, value: 55, memoryPressure: .critical)
                == .percent(55)
        )
    }

    @Test
    func aMetricWithNoReadingIsADash() {
        #expect(
            MetricValueDisplay.resolve(kind: .cpu, value: nil, memoryPressure: nil)
                == .unavailable
        )
    }

    /// The overview's RAM column showed the pressure symbol and nothing else, so
    /// the Synology — which has no pressure to report — sat under a dash beside
    /// a filled bar. It was the one machine missing from its own overview.
    @Test
    func theOverviewsRAMColumnShowsANASItsFigure() {
        #expect(
            MetricValueDisplay.resolve(metric: .memory, value: 77, memoryPressure: nil)
                == .percent(77)
        )
    }

    /// The overview and the metric rows are the same question asked twice, so
    /// they must not answer differently.
    @Test
    func theOverviewAgreesWithTheRows() {
        let cases: [(Double?, MemoryPressureLevel?)] = [
            (82, .normal), (91, .warning), (97, .critical),
            (77, nil), (nil, .normal), (nil, nil),
        ]
        for (value, pressure) in cases {
            #expect(
                MetricValueDisplay.resolve(
                    metric: .memory, value: value, memoryPressure: pressure
                ) == MetricValueDisplay.resolve(
                    kind: .memory, value: value, memoryPressure: pressure
                )
            )
        }
    }

    /// The agent column counts sessions rather than reading a gauge.
    @Test
    func theAgentColumnHasNoReading() {
        #expect(
            MetricValueDisplay.resolve(metric: .ai, value: 5, memoryPressure: nil)
                == .unavailable
        )
    }
}

@MainActor
struct OverviewMetricPresentationTests {
    /// The regression. The overview learned to draw the bar from plain usage
    /// when a machine reports no pressure; the machine's own page kept the
    /// original `memoryPressure?.visualizationPercent` and nothing else, so
    /// opening the NAS showed an empty bar beside a memory figure it had in
    /// hand. Both surfaces now ask the same question.
    @Test
    func aNASWithNoPressureSignalStillFillsItsMemoryBar() {
        let machine = nas()
        machine.apply(
            SystemSnapshot(
                timestamp: .now,
                readings: [.memory: MetricReading(value: 77)],
                memoryPressure: nil
            )
        )

        let presentation = machine.metricPresentation(for: .memory, isReporting: true)

        #expect(presentation.value == 77)
        #expect(presentation.thermometerValue == 77)
        #expect(presentation.memoryPressure == nil)
    }

    /// Where there is a verdict it drives the bar, so the bar and the symbol
    /// beside it cannot tell different stories.
    @Test
    func pressureDrivesTheBarWhenTheMachineReportsIt() {
        let machine = mac()
        machine.apply(
            SystemSnapshot(
                timestamp: .now,
                readings: [.memory: MetricReading(value: 40)],
                memoryPressure: .warning
            )
        )

        let presentation = machine.metricPresentation(for: .memory, isReporting: true)

        #expect(presentation.memoryPressure == .warning)
        #expect(
            presentation.thermometerValue == MemoryPressureLevel.warning.visualizationPercent
        )
        // The figure underneath is still the real usage, not the bar's stand-in.
        #expect(presentation.value == 40)
    }

    /// A remembered verdict would be a claim about a machine that is not
    /// answering, so pressure stops at the moment the machine does.
    @Test
    func pressureIsNotRememberedPastGoingOffline() {
        let machine = mac()
        machine.apply(
            SystemSnapshot(
                timestamp: .now,
                readings: [.memory: MetricReading(value: 40)],
                memoryPressure: .critical
            )
        )
        machine.markOffline(.noAnswer)

        let presentation = machine.metricPresentation(for: .memory, isReporting: true)

        #expect(presentation.memoryPressure == nil)
        // The usage figure survives, so the bar still has something to draw.
        #expect(presentation.thermometerValue == 40)
    }

    /// "How full is this machine" means the volume that runs out first, not the
    /// first one that happens to be listed.
    @Test
    func diskFollowsTheFullestVolume() {
        let machine = nas()
        machine.apply(
            SystemSnapshot(
                timestamp: .now,
                readings: [.disk: MetricReading(value: 12)],
                storageVolumes: [
                    volume("volume1", used: 20),
                    volume("volume2", used: 91),
                    volume("volume3", used: 64),
                ]
            )
        )

        let presentation = machine.metricPresentation(for: .disk, isReporting: true)

        #expect(presentation.value == 91)
        #expect(presentation.thermometerValue == 91)
    }

    /// A surface that has decided not to show a machine's numbers shows none of
    /// them — no half-lit column with a stale figure and an empty bar.
    @Test
    func aSurfaceThatIsNotReportingShowsNothingAtAll() {
        let machine = mac()
        machine.apply(
            SystemSnapshot(
                timestamp: .now,
                readings: [.cpu: MetricReading(value: 63)],
                memoryPressure: .normal
            )
        )

        let presentation = machine.metricPresentation(for: .cpu, isReporting: false)

        #expect(presentation == .nothingToShow)
    }

    /// AI is a column of its own with no number behind it yet.
    @Test
    func theAgentColumnHasNoNumber() {
        let machine = mac()
        let presentation = machine.metricPresentation(for: .ai, isReporting: true)

        #expect(presentation.value == nil)
        #expect(presentation.thermometerValue == nil)
    }
}

struct ThermometerScaleTests {
    /// A machine that is barely working still has to look different from one
    /// that is not answering, so any reading at all lights a block.
    @Test
    func anyReadingLightsAtLeastOneBlock() {
        #expect(ThermometerScale.filledBlockCount(for: 0.4) == 1)
        #expect(ThermometerScale.filledBlockCount(for: 0) == 0)
        #expect(ThermometerScale.filledBlockCount(for: nil) == 0)
    }

    @Test
    func afullBarNeedsAFullReading() {
        #expect(ThermometerScale.filledBlockCount(for: 100) == ThermometerScale.blockCount)
        #expect(ThermometerScale.filledBlockCount(for: 91) == ThermometerScale.blockCount)
        #expect(ThermometerScale.filledBlockCount(for: 90) == 9)
    }

    /// Readings arrive from machines, not from this process, so a figure outside
    /// 0–100 must clamp rather than draw a bar with negative or extra blocks.
    @Test
    func readingsOutsideTheScaleAreClamped() {
        #expect(ThermometerScale.filledBlockCount(for: 140) == ThermometerScale.blockCount)
        #expect(ThermometerScale.filledBlockCount(for: -8) == 0)
    }

    /// The bar has to change colour as it climbs, or it says nothing that its
    /// height did not already say.
    @Test
    func theBarWarmsAsItClimbs() {
        #expect(ThermometerScale.band(forLevel: 0) == .calm)
        #expect(ThermometerScale.band(forLevel: 3) == .calm)
        #expect(ThermometerScale.band(forLevel: 4) == .moderate)
        #expect(ThermometerScale.band(forLevel: 6) == .moderate)
        #expect(ThermometerScale.band(forLevel: 7) == .high)
        #expect(ThermometerScale.band(forLevel: 8) == .high)
        #expect(ThermometerScale.band(forLevel: 9) == .critical)
    }

    /// Every block in a full bar gets a band, and the top one is the alarming
    /// one — an off-by-one here would light the last block green.
    @Test
    func everyBlockInAFullBarIsAccountedFor() {
        let bands = (0 ..< ThermometerScale.blockCount)
            .map(ThermometerScale.band(forLevel:))

        #expect(bands.count == ThermometerScale.blockCount)
        #expect(bands.last == .critical)
        #expect(Set(bands) == Set(ThermometerBand.allCases))
    }
}

/// Reordering without a mouse.
///
/// Dragging was the only way to reorder the herd, which quietly excluded anyone
/// driving the app from the keyboard. The arithmetic behind "move down" is the
/// part worth pinning: `move(fromOffsets:toOffset:)` counts the gaps between
/// rows rather than the rows, so down needs a correction that up does not.
struct ListPositionTests {
    @Test
    func theEndsOfTheListKnowTheyAreTheEnds() {
        let first = ListPosition(index: 0, count: 4)
        #expect(!first.canMoveUp)
        #expect(first.canMoveDown)

        let last = ListPosition(index: 3, count: 4)
        #expect(last.canMoveUp)
        #expect(!last.canMoveDown)
    }

    @Test
    func aloneInTheListMeansNowhereToGo() {
        let only = ListPosition(index: 0, count: 1)
        #expect(!only.canMoveUp)
        #expect(!only.canMoveDown)
        #expect(only.destination(movingBy: 1) == nil)
        #expect(only.destination(movingBy: -1) == nil)
    }

    /// Walking off either end moves nothing rather than trapping or wrapping.
    @Test
    func aRowCannotBeMovedOffTheList() {
        #expect(ListPosition(index: 0, count: 4).destination(movingBy: -1) == nil)
        #expect(ListPosition(index: 3, count: 4).destination(movingBy: 1) == nil)
    }

    /// The asymmetry, stated: down clears the row it displaces, up does not.
    @Test
    func movingDownClearsTheRowItDisplaces() {
        #expect(ListPosition(index: 1, count: 4).destination(movingBy: 1) == 3)
        #expect(ListPosition(index: 1, count: 4).destination(movingBy: -1) == 0)
    }

    /// Said against the real thing rather than against a belief about it: the
    /// arithmetic above is only correct if `move(fromOffsets:toOffset:)` agrees,
    /// so this runs it through the store and reads the order back out.
    @Test
    func theArithmeticMatchesWhatTheStoreActuallyDoes() {
        let storage = InMemoryConfigurationStorage()
        let store = MachineConfigurationStore(storage: storage)
        store.add([herdMember("alpha"), herdMember("beta"), herdMember("gamma")])
        #expect(store.machines.map(\.id.rawValue) == ["local", "alpha", "beta", "gamma"])

        // "alpha" (index 1) moves down one. It should end up after "beta".
        let down = try! #require(
            ListPosition(index: 1, count: 4).destination(movingBy: 1)
        )
        store.move(fromOffsets: IndexSet(integer: 1), toOffset: down)
        #expect(store.machines.map(\.id.rawValue) == ["local", "beta", "alpha", "gamma"])

        // And back up again, returning the herd to where it started.
        let up = try! #require(
            ListPosition(index: 2, count: 4).destination(movingBy: -1)
        )
        store.move(fromOffsets: IndexSet(integer: 2), toOffset: up)
        #expect(store.machines.map(\.id.rawValue) == ["local", "alpha", "beta", "gamma"])
    }

    /// The order the rows are read out in, which is the only thing telling a
    /// VoiceOver user that this list has an order at all.
    @Test
    func aRowSaysWhereItSits() {
        #expect(ListPosition(index: 0, count: 4).description == "1 of 4")
        #expect(ListPosition(index: 3, count: 4).description == "4 of 4")
    }
}

private func herdMember(_ id: String) -> MachineConfiguration {
    MachineConfiguration(
        id: MachineID(id),
        name: id.capitalized,
        shortName: id.capitalized,
        hostname: id,
        hardwareSummary: "Test",
        platform: .linux,
        connection: .ssh,
        avatar: .oxGPU,
        identityFile: nil,
        serverNames: [],
        supportsGPU: false
    )
}

/// The graph above each pane's list.
///
/// A list says what is using the machine right now; the graph says whether that
/// is new. Two cores held means one thing on a flat line and another on a
/// climbing one, and the list alone cannot tell them apart.
@MainActor
struct MetricSeriesTests {
    @Test
    func aSeriesCarriesTheMetricItDraws() {
        let machine = mac()
        machine.apply(
            SystemSnapshot(timestamp: .now, readings: [.cpu: MetricReading(value: 40)])
        )

        #expect(machine.series(for: .cpu).kind == .cpu)
        #expect(machine.series(for: .memory).kind == .memory)
    }

    /// The agent column counts sessions rather than measuring a quantity, so
    /// there is no series to draw above it.
    @Test
    func theAgentPaneHasNoGraph() {
        #expect(mac().series(showing: .ai) == nil)
    }

    @Test
    func theOverviewMetricsMapToTheirOwnSeries() {
        let machine = mac()

        #expect(machine.series(showing: .cpu)?.kind == .cpu)
        #expect(machine.series(showing: .memory)?.kind == .memory)
        #expect(machine.series(showing: .disk)?.kind == .disk)
    }

    /// One reading is a dot, not a shape. A line drawn through it invites a
    /// conclusion about a trend that a single sample cannot support.
    @Test
    func asingleReadingIsNotYetAGraph() {
        let machine = mac()
        #expect(!machine.series(for: .cpu).isWorthDrawing)

        machine.apply(
            SystemSnapshot(timestamp: .now, readings: [.cpu: MetricReading(value: 40)])
        )
        #expect(!machine.series(for: .cpu).isWorthDrawing)

        machine.apply(
            SystemSnapshot(
                timestamp: Date().addingTimeInterval(10),
                readings: [.cpu: MetricReading(value: 55)]
            )
        )
        #expect(machine.series(for: .cpu).isWorthDrawing)
    }
}

/// When a busy machine is worth saying something about.
///
/// The thresholds used to read the latest sample, so a ten-second spike — which
/// every machine here produces several times an hour, opening an app does it —
/// flipped the menu bar into an alarm and back out again. A monitor that cries
/// wolf gets muted, and a muted monitor is worse than none.
struct SustainedLoadTests {
    private func readings(
        _ values: [Double],
        every interval: TimeInterval = 10,
        endingAt end: Date
    ) -> [HistoryPoint] {
        values.enumerated().map { index, value in
            HistoryPoint(
                timestamp: end.addingTimeInterval(
                    -Double(values.count - 1 - index) * interval
                ),
                value: value
            )
        }
    }

    /// Nothing can be claimed about a stretch of time the readings do not cover.
    @Test
    func aMachineJustStartedSaysNothingYet() {
        let now = Date()
        let justLaunched = readings([99, 99, 99], endingAt: now)

        #expect(SustainedLoad.average(of: justLaunched, endingAt: now) == nil)
    }

    @Test
    func aWindowfulOfReadingsAverages() {
        let now = Date()
        // Six minutes of readings, so the five-minute window is covered.
        let pegged = readings(Array(repeating: 96, count: 37), endingAt: now)

        #expect(SustainedLoad.average(of: pegged, endingAt: now) == 96)
    }

    /// The point of the window: a burst inside an otherwise quiet stretch does
    /// not average out to trouble.
    @Test
    func aBurstDoesNotAverageToTrouble() throws {
        let now = Date()
        var values = Array(repeating: 4.0, count: 31)
        // The last minute pegged — a build starting, or an app launching.
        for index in 25 ..< 31 { values[index] = 100 }

        let average = try #require(
            SustainedLoad.average(of: readings(values, endingAt: now), endingAt: now)
        )
        #expect(average < 80)
    }

    /// Readings from before the window are history, not evidence about now.
    @Test
    func readingsOlderThanTheWindowAreNotCounted() throws {
        let now = Date()
        // Twenty minutes: the first half pegged, the recent half idle.
        var values = Array(repeating: 100.0, count: 121)
        for index in 61 ..< 121 { values[index] = 2 }

        let average = try #require(
            SustainedLoad.average(of: readings(values, endingAt: now), endingAt: now)
        )
        #expect(average < 10)
    }

    /// The whole point, stated end to end: a spike is not a headline, and a
    /// machine that has genuinely been pegged is.
    @Test
    func aSpikeIsNotAHeadlineButSustainedLoadIs() {
        let spiking = MenuBarMachineSnapshot(
            machine: MachineID("air"),
            state: .live,
            cpuPercent: 99,
            memoryPressure: .normal,
            diskUsedPercent: 40,
            sustainedCPUPercent: 12
        )
        guard case .normal = MenuBarStatusSelector.headline(for: [spiking]) else {
            Issue.record("a momentary spike should not raise an alarm")
            return
        }

        let pegged = MenuBarMachineSnapshot(
            machine: MachineID("mini"),
            state: .live,
            cpuPercent: 40,
            memoryPressure: .normal,
            diskUsedPercent: 40,
            sustainedCPUPercent: 96
        )
        // Reported as what it was judged on. A headline saying 40% because the
        // machine happened to dip at the moment it was drawn would leave no way
        // to tell why it appeared.
        #expect(
            MenuBarStatusSelector.headline(for: [pegged])
                == .highCPU(machine: MachineID("mini"), percent: 96, critical: true)
        )
    }
}

/// Which mounted things count as a machine's storage.
///
/// A Time Machine sparsebundle kept on the NAS mounts on the Mac that backs up
/// to it, and was listed as that Mac's storage: 16 TB, 95% full. Both figures
/// were wrong. The 16 TB is the image's ceiling rather than storage that
/// exists — 2.3 TB was written with 817 GB free — and the bytes are the NAS's,
/// counted a second time on a machine that merely has them mounted.
struct ImageVolumeExclusionTests {
    private func storageLine(
        name: String,
        mount: String,
        total: Double,
        available: Double,
        group: String
    ) -> String {
        let encode = { (value: String) in Data(value.utf8).base64EncodedString() }
        return [
            "storage=\(encode(name))",
            encode(mount),
            String(format: "%.0f", total),
            String(format: "%.0f", available),
            encode(group),
        ].joined(separator: "\t")
    }

    private func imageLine(_ mount: String) -> String {
        "imagevolume=\(Data(mount.utf8).base64EncodedString())"
    }

    @Test
    func aBackupImageMountedFromTheNASIsNotThisMachinesStorage() {
        let output = [
            storageLine(
                name: "Macintosh HD", mount: "/",
                total: 994_662_584_320, available: 49_653_043_200, group: "disk3"
            ),
            storageLine(
                name: "Backups of Micah's M1",
                mount: "/Volumes/Backups of Micah's M1",
                total: 16_000_000_000_000, available: 817_189_216_256, group: "disk7"
            ),
            imageLine("/Volumes/Backups of Micah's M1"),
        ].joined(separator: "\n")

        let volumes = RemoteOutputParser.parseStorageVolumes(output)

        #expect(volumes.map(\.name) == ["Macintosh HD"])
    }

    /// Hardware stays. The exclusion is about images, not about anything that
    /// happens to be mounted under /Volumes.
    @Test
    func realVolumesAreUntouched() {
        let output = [
            storageLine(
                name: "Foot Locker", mount: "/Volumes/Foot Locker",
                total: 4_000_577_273_856, available: 1_225_835_945_984, group: "disk5"
            ),
            imageLine("/Volumes/Cursor Installer"),
        ].joined(separator: "\n")

        #expect(RemoteOutputParser.parseStorageVolumes(output).count == 1)
    }

    @Test
    func aMachineReportingNoImagesLosesNothing() {
        let output = storageLine(
            name: "Macintosh HD", mount: "/",
            total: 994_662_584_320, available: 49_653_043_200, group: "disk3"
        )

        #expect(RemoteOutputParser.parseImageVolumeMounts(output).isEmpty)
        #expect(RemoteOutputParser.parseStorageVolumes(output).count == 1)
    }

    /// The startup row is one volume of a container whose siblings are not
    /// listed, so what it reports using describes the sealed system alone. The
    /// total less what is free counts the siblings too, and is what makes a
    /// mini with 46 GB left read as nearly full rather than a quarter used.
    @Test
    func aContainersUsageCountsSiblingsThatAreNotListed() {
        let startup = StorageVolume(
            id: "disk3",
            name: "Macintosh HD",
            mountPath: "/",
            availableBytes: 49_653_043_200,
            totalBytes: 994_662_584_320
        )

        #expect(Int(startup.usedPercent.rounded()) == 95)
    }
}

/// Losing the password has to make a sound.
///
/// The keychain read is declined rather than answered, so when a saved password
/// stops being readable nothing is raised: DSM sign-in fails, the NAS drops to
/// offline, and monitoring stops — including drive health, on the one machine
/// whose drive is actually failing. It was reported as "stopped responding",
/// which blames a machine that is answering perfectly well and sends you to
/// check a network that is fine.
@MainActor
struct SignInLostTests {
    private func nasThatWasWorking() -> MachineMonitorModel {
        let machine = nas()
        machine.apply(
            SystemSnapshot(timestamp: .now, readings: [.disk: MetricReading(value: 67)])
        )
        return machine
    }

    @Test
    func anUnreadablePasswordIsToldApartFromNoPasswordAtAll() {
        #expect(
            RemoteUnavailability.classify(
                dsm: .notAuthenticated, credentials: .unreadable
            ) == .signInLost
        )
        #expect(
            RemoteUnavailability.classify(
                dsm: .notAuthenticated, credentials: .absent
            ) != .signInLost
        )
    }

    /// The keychain says which by refusing rather than by coming up empty.
    @Test
    func theKeychainDistinguishesRefusedFromEmpty() {
        #expect(KeychainAvailability(status: errSecSuccess) == .available)
        #expect(KeychainAvailability(status: errSecItemNotFound) == .absent)
        #expect(KeychainAvailability(status: errSecAuthFailed) == .unreadable)
        #expect(
            KeychainAvailability(status: errSecInteractionNotAllowed) == .unreadable
        )
    }

    /// The alert, which is the whole point: it now happens, and says the right
    /// thing about the right culprit.
    @Test
    func aLostSignInRaisesItsOwnAlertRatherThanBlamingTheMachine() {
        let machine = nasThatWasWorking()
        machine.markOffline(.signInLost)

        let alerts = MachineAlert.active(for: machine)

        #expect(alerts.contains(.signInLost))
        #expect(!alerts.contains(.unreachable))
        #expect(
            MachineAlert.signInLost.title(machine: "Synology")
                == "Little Herd can’t sign in to Synology"
        )
    }

    /// A NAS that genuinely stopped answering still reads as unreachable, so
    /// the new condition has not swallowed the old one.
    @Test
    func aMachineThatReallyStoppedAnsweringIsStillUnreachable() {
        let machine = nasThatWasWorking()
        machine.markOffline(.noAnswer)

        let alerts = MachineAlert.active(for: machine)

        #expect(alerts.contains(.unreachable))
        #expect(!alerts.contains(.signInLost))
    }

    /// A NAS that has never been signed in to is not a fault. The same rule the
    /// rest of the alerts already follow: nothing to recover from.
    @Test
    func aNASThatWasNeverSignedInRaisesNothing() {
        let machine = nas()
        machine.markOffline(.signInLost)

        #expect(MachineAlert.active(for: machine).isEmpty)
    }

    /// Every condition needs its own words in both directions, or a recovery
    /// notification describes the wrong thing.
    @Test
    func theNewConditionHasItsOwnWording() {
        let titles = MachineAlert.allCases.map { $0.title(machine: "X") }
        let recoveries = MachineAlert.allCases.map { $0.recoveryTitle(machine: "X") }

        #expect(Set(titles).count == MachineAlert.allCases.count)
        #expect(Set(recoveries).count == MachineAlert.allCases.count)
    }
}

// MARK: - Machines to look at

@MainActor
private func nas() -> MachineMonitorModel {
    MachineMonitorModel(
        configuration: MachineConfiguration(
            id: MachineID("synology"),
            name: "Synology",
            shortName: "Synology",
            hostname: "AlpernServer.local",
            hardwareSummary: "Network storage",
            platform: .storage,
            connection: .dsm,
            avatar: .pigletNAS,
            identityFile: nil,
            serverNames: [],
            supportsGPU: false,
            dsmUsername: "malpern"
        )
    )
}

@MainActor
private func mac() -> MachineMonitorModel {
    MachineMonitorModel(
        configuration: MachineConfiguration(
            id: MachineID("studio"),
            name: "Mac Studio",
            shortName: "Studio",
            hostname: "studio.local",
            hardwareSummary: "Mac Studio",
            platform: .macOS,
            connection: .ssh,
            avatar: .lambStudio,
            identityFile: nil,
            serverNames: [],
            supportsGPU: true
        )
    )
}

private func volume(_ name: String, used: Double) -> StorageVolume {
    let total = 1_000_000_000_000.0
    return StorageVolume(
        id: name,
        name: name,
        mountPath: "/volume/\(name)",
        availableBytes: total * (1 - used / 100),
        totalBytes: total
    )
}
