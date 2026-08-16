import Foundation
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
