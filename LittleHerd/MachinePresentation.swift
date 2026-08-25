import SwiftUI

/// What the interface decides to show, separated from the drawing of it.
///
/// These rules used to live inside view bodies, where nothing could reach them
/// but the eye. Every one of them had drifted: the same machine read "Not set
/// up yet" in the overview and "Unreachable" on hover, and the memory bar knew
/// to fall back to a usage figure in one place and not the other. A rule with
/// one home cannot disagree with itself, and a rule outside a `body` can be
/// tested.
///
/// The precedent is `MachineAlerts.swift` — the alert conditions were pulled
/// out for the same reason and have not drifted since.

/// The five things a machine's status dot can mean.
///
/// Offline is deliberately two of them. A machine that answered and stopped is
/// a fault worth colouring red; one that has never answered has not been set up
/// yet, and red says the hardware is broken when nothing is.
nonisolated enum MachineStatus: Equatable, CaseIterable, Sendable {
    case notSetUp
    case connecting
    case live
    case unreachable
    case paused

    static func resolve(
        state: MonitorConnectionState,
        hasNeverConnected: Bool
    ) -> MachineStatus {
        if hasNeverConnected { return .notSetUp }
        switch state {
        case .connecting: return .connecting
        case .live: return .live
        case .offline: return .unreachable
        case .stopped: return .paused
        }
    }

    var label: LocalizedStringResource {
        switch self {
        case .notSetUp: "Not set up yet"
        case .connecting: "Connecting"
        case .live: "Live"
        case .unreachable: "Unreachable"
        case .paused: "Paused"
        }
    }

    var tint: Color {
        switch self {
        case .notSetUp: .secondary
        case .connecting: .orange
        case .live: .green
        case .unreachable: .red
        case .paused: .secondary
        }
    }
}

/// What belongs in a metric value column.
///
/// Memory is the awkward one. The operating system's pressure verdict is a
/// better answer than a percentage — cache it is deliberately holding is not a
/// problem — but a green tick on every healthy Mac is a badge that is always
/// lit, and one of those says nothing at all. So the verdict appears when it is
/// news, and the plain figure the rest of the rows show appears the rest of the
/// time. A NAS has no notion of pressure at all and now reads like anything
/// else, instead of the dash it used to draw beside a figure it had in hand.
nonisolated enum MetricValueDisplay: Equatable, Sendable {
    case pressure(MemoryPressureLevel)
    case percent(Double)
    case bytesPerSecond(Double)
    /// A dash. There is no reading at all.
    case unavailable

    static func resolve(
        kind: MetricKind,
        value: Double?,
        memoryPressure: MemoryPressureLevel?
    ) -> MetricValueDisplay {
        if kind == .memory {
            // Trouble takes the column: a shape carries further than a colour,
            // and this is the one moment memory is worth interrupting for.
            if let memoryPressure, memoryPressure != .normal {
                return .pressure(memoryPressure)
            }
            if let value { return .percent(value) }
            // A verdict with no figure behind it is still better than a dash.
            if let memoryPressure { return .pressure(memoryPressure) }
            return .unavailable
        }
        guard let value else { return .unavailable }
        switch kind {
        case .cpu, .gpu, .disk: return .percent(value)
        case .network: return .bytesPerSecond(value)
        case .memory: return .unavailable
        }
    }

    /// The overview's columns ask the same question in its own vocabulary.
    static func resolve(
        metric: OverviewMetric,
        value: Double?,
        memoryPressure: MemoryPressureLevel?
    ) -> MetricValueDisplay {
        switch metric {
        case .cpu:
            resolve(kind: .cpu, value: value, memoryPressure: nil)
        case .memory:
            resolve(kind: .memory, value: value, memoryPressure: memoryPressure)
        case .disk:
            resolve(kind: .disk, value: value, memoryPressure: nil)
        // The agent column counts sessions, which is not a reading.
        case .ai:
            .unavailable
        }
    }
}

/// What the pressure symbol says when you point at it.
///
/// The symbol used to carry `.help(Text(level.title))` — the single word
/// "Warning" — while the column around it carried a longer text listing the
/// heaviest apps. The short one won. The innermost `.help` owns its own
/// region, so the fuller sentence was unreachable at exactly the place a
/// person aims: the symbol. Explaining it once, here, is what stops the two
/// from disagreeing again.
///
/// Three beats, because a verdict on its own cannot be acted on: what the
/// system said, what that means for the machine, and the one thing worth
/// doing about it. The last is named rather than generic — "close some apps"
/// is advice anyone could give without measuring, and this app has measured.
nonisolated enum MemoryPressureExplanation {
    static func text(
        level: MemoryPressureLevel,
        platform: MachinePlatform,
        consumers: [MemoryConsumer],
        swap: SwapUsage? = nil,
        swapGrowth: SwapGrowth? = nil
    ) -> String {
        [
            String(localized: "\(String(localized: level.title)) memory pressure"),
            body(level: level, platform: platform, swap: swap, swapGrowth: swapGrowth),
            advice(for: level, consumers: consumers),
        ]
        .compactMap(\.self)
        // A blank line under the headline, so it reads as a title rather than
        // as the first sentence of a paragraph. It did read as one.
        .joined(separator: "\n\n")
    }

    private static func body(
        level: MemoryPressureLevel,
        platform: MachinePlatform,
        swap: SwapUsage?,
        swapGrowth: SwapGrowth?
    ) -> String? {
        let sentences = [
            situation(
                level: level,
                platform: platform,
                swapped: swapped(swapGrowth),
                hasSwap: swap?.isConfigured
            ),
            noSwapNote(level: level, platform: platform, swap: swap),
        ]
        .compactMap(\.self)
        .joined(separator: " ")
        return sentences.isEmpty ? nil : sentences
    }

    /// Only the direction of travel earns a mention. The level is a high-water
    /// mark of every busy hour the machine has had — see `SwapGrowth` — so
    /// printing it would put a large, permanent, unactionable number in front
    /// of anyone whose Mac was ever busy.
    ///
    /// A fragment rather than a sentence, because it reads better written into
    /// the situation than bolted on after it. "macOS has swapped 1.4 GB in the
    /// last 3 minutes to keep everything running" is one fact; the same thing
    /// appended as its own sentence was three sentences of throat-clearing.
    private static func swapped(_ growth: SwapGrowth?) -> String? {
        guard let growth else { return nil }
        let written = Int64(growth.bytes).formatted(.byteCount(style: .memory))
        let minutes = max(1, Int((growth.duration / 60).rounded()))
        return String(localized: "\(written) in the last \(minutes) minutes")
    }

    /// Warning and critical are different situations, not one sentence with a
    /// word swapped. Warning is the system working as designed; critical is
    /// the system about to take the decision out of your hands.
    ///
    /// A Mac is quoted because a Mac's verdict is the kernel's own. Everything
    /// else is `MemoryPressureLevel.estimated`, computed here from how much
    /// memory is free — so it is described as the observation it is, rather
    /// than put in a kernel's mouth. (A remote Mac whose pressure sysctl fails
    /// falls back to the estimate too, and is flattered slightly here. It has
    /// not been seen to happen.)
    private static func situation(
        level: MemoryPressureLevel,
        platform: MachinePlatform,
        swapped: String?,
        hasSwap: Bool?
    ) -> String? {
        switch (level, platform) {
        case (.normal, _):
            String(localized: "There is room to spare.")

        case (.warning, .macOS):
            if let swapped {
                String(localized: """
                    macOS has swapped \(swapped) to keep everything running. \
                    Nothing has failed, but apps may feel slower.
                    """)
            } else {
                String(localized: """
                    macOS is compressing and swapping to keep everything \
                    running. Nothing has failed, but apps may feel slower.
                    """)
            }

        case (.critical, .macOS):
            if let swapped {
                String(localized: """
                    macOS has swapped \(swapped) and may start force-quitting \
                    apps.
                    """)
            } else {
                String(localized:
                    "macOS is out of room and may start force-quitting apps.")
            }

        case (.warning, _):
            if let swapped {
                String(localized: """
                    Under a fifth of memory is available, and \(swapped) has \
                    been swapped. Apps may feel slower.
                    """)
            } else {
                String(localized: """
                    Under a fifth of memory is available. Nothing has failed, \
                    but apps may feel slower.
                    """)
            }

        // The note below explains what a machine with no swap does instead,
        // so this must not say it as well. Said twice, it stops being read.
        case (.critical, _) where hasSwap == false:
            String(localized: "Under a tenth of memory is available.")

        case (.critical, _):
            if let swapped {
                String(localized: """
                    Under a tenth of memory is available, and \(swapped) has \
                    been swapped. The kernel may start killing processes.
                    """)
            } else {
                String(localized: """
                    Under a tenth of memory is available, and the kernel may \
                    start killing processes.
                    """)
            }
        }
    }

    /// Worth saying only where paging out was an option at all. A Linux box
    /// with no swap does not get slower under pressure; it kills something.
    private static func noSwapNote(
        level: MemoryPressureLevel,
        platform: MachinePlatform,
        swap: SwapUsage?
    ) -> String? {
        guard level != .normal, platform != .macOS else { return nil }
        guard let swap, !swap.isConfigured else { return nil }
        return String(localized: """
            No swap is configured, so a process is killed rather than paged \
            out.
            """)
    }

    /// Nothing to suggest when the machine is fine — a tooltip that proposes a
    /// fix for a healthy machine reads as a complaint — and nothing to suggest
    /// when no process list came back, which is every machine that reports
    /// pressure without one.
    ///
    /// One app, not the whole list. The list already exists on the machine's
    /// memory page with real icons beside it, and a hover that repeats it is a
    /// hover people stop reading.
    private static func advice(
        for level: MemoryPressureLevel,
        consumers: [MemoryConsumer]
    ) -> String? {
        guard level != .normal else { return nil }
        guard let largest = consumers.max(by: {
            $0.residentBytes < $1.residentBytes
        }) else { return nil }

        let size = Int64(largest.residentBytes)
            .formatted(.byteCount(style: .memory))

        // A process that is still climbing gets a different promise. Quitting
        // it frees the memory either way, but saying so without the caveat
        // invites the conclusion that the problem is now solved.
        guard let evidence = largest.growthEvidence else {
            return String(localized:
                "Quitting \(largest.name) would free the most (\(size)).")
        }

        let growth = Int64(evidence.growthBytes)
            .formatted(.byteCount(style: .memory))
        let minutes = max(1, Int((evidence.duration / 60).rounded()))
        return String(localized: """
            \(largest.name) is the largest at \(size), and has grown \
            \(growth) over \(minutes) minutes. Quitting it should help, \
            though it may climb again.
            """)
    }
}

extension MachineMonitorModel {
    /// This machine's pressure verdict, explained — or nothing when there is
    /// no live verdict to explain.
    ///
    /// Gated on `.live` for the same reason `metricPresentation` gates the
    /// verdict itself: a remembered pressure level is a guess about a machine
    /// that is not answering, and advice built on one names an app that may
    /// have quit hours ago.
    var memoryPressureExplanation: String? {
        guard state == .live, let memoryPressure else { return nil }
        return MemoryPressureExplanation.text(
            level: memoryPressure,
            platform: platform,
            consumers: memoryConsumers,
            swap: swap,
            swapGrowth: swapGrowth
        )
    }
}

/// The numbers behind one machine's column: the figure, the bar, and the
/// pressure verdict when there is one.
nonisolated struct OverviewMetricPresentation: Equatable, Sendable {
    let value: Double?
    let thermometerValue: Double?
    let memoryPressure: MemoryPressureLevel?

    static let nothingToShow = OverviewMetricPresentation(
        value: nil,
        thermometerValue: nil,
        memoryPressure: nil
    )
}

extension MachineMonitorModel {
    var status: MachineStatus {
        MachineStatus.resolve(
            state: state,
            hasNeverConnected: hasNeverConnected
        )
    }

    /// The volume that will run out first — what "how full is this machine"
    /// means when a machine has several.
    var fullestVolume: StorageVolume? {
        storageVolumes.max { $0.usedPercent < $1.usedPercent }
    }

    /// - Parameter isReporting: whether this surface is willing to show the
    ///   machine's numbers at all. The overview and a machine's own page answer
    ///   this differently on purpose — a disconnected NAS keeps its column in
    ///   the overview but is offered a sign-in page of its own — so the gate
    ///   stays with the caller and only the selection is shared.
    func metricPresentation(
        for metric: OverviewMetric,
        isReporting: Bool
    ) -> OverviewMetricPresentation {
        guard isReporting else { return .nothingToShow }

        let value: Double? = switch metric {
        case .cpu: cpu.value
        case .memory: memory.value
        case .disk: fullestVolume?.usedPercent
        case .ai: nil
        }

        // Pressure is a live reading; a remembered one would be a guess about a
        // machine that is not answering.
        let pressure = metric == .memory && state == .live
            ? memoryPressure
            : nil

        let thermometerValue: Double? = switch metric {
        case .cpu, .disk:
            value
        case .memory:
            // Pressure where the machine reports it, plain usage where it does
            // not. A NAS was drawing an empty bar beside a memory figure it had
            // in hand.
            pressure?.visualizationPercent ?? value
        case .ai:
            nil
        }

        return OverviewMetricPresentation(
            value: value,
            thermometerValue: thermometerValue,
            memoryPressure: pressure
        )
    }
}

/// One metric's recent history, ready to draw.
///
/// The kind travels with the points because it is what says how to draw them —
/// the colour the rest of the app already uses for this metric, and whether the
/// scale is pinned to 0–100 or follows the data.
nonisolated struct MetricSeries: Equatable, Sendable {
    let kind: MetricKind
    let points: [HistoryPoint]

    /// A single reading is a dot, not a shape, and a flat line drawn from one
    /// point invites a conclusion the data cannot support.
    var isWorthDrawing: Bool { points.count > 1 }
}

extension OverviewMetric {
    /// The measured quantity behind this column, when there is one. The agent
    /// column counts sessions rather than measuring anything, so it has none.
    ///
    /// Deliberately a mapping rather than a second `series(for:)` overload.
    /// Both enums have a `.cpu`, so `series(for: .cpu)` inside such an overload
    /// resolves to the overload itself — infinite recursion that compiles
    /// cleanly and crashes on the first detail pane opened.
    var metricKind: MetricKind? {
        switch self {
        case .cpu: .cpu
        case .memory: .memory
        case .disk: .disk
        case .ai: nil
        }
    }
}

extension MachineMonitorModel {
    func series(for kind: MetricKind) -> MetricSeries {
        MetricSeries(
            kind: kind,
            points: metrics.first { $0.kind == kind }?.history ?? []
        )
    }

    /// The series a given overview column should draw, if any.
    func series(showing metric: OverviewMetric) -> MetricSeries? {
        metric.metricKind.map { series(for: $0) }
    }
}

/// Where a row sits in a reorderable list, so it knows which way it can go.
nonisolated struct ListPosition: Equatable, Sendable {
    let index: Int
    let count: Int

    var canMoveUp: Bool { index > 0 }
    var canMoveDown: Bool { index < count - 1 }

    /// Said out loud for VoiceOver, which otherwise gives no sense of order in a
    /// list whose entire point is the order.
    var description: String { "\(index + 1) of \(count)" }

    /// The insertion point that moves this row by `offset`, or nothing if that
    /// would take it off either end.
    ///
    /// `move(fromOffsets:toOffset:)` counts the gaps between rows rather than
    /// the rows themselves, so moving down has to clear the row it displaces —
    /// `toOffset: index + 1` is where a row already is, and asking for it moves
    /// nothing at all. Moving up needs no such correction, which is exactly the
    /// asymmetry that makes this easy to get wrong and worth pinning down.
    func destination(movingBy offset: Int) -> Int? {
        let target = index + offset
        guard target >= 0, target < count else { return nil }
        return offset > 0 ? target + 1 : target
    }
}

/// How a ten-block bar fills and colours.
nonisolated enum ThermometerScale {
    static let blockCount = 10

    /// Any reading at all lights the first block, so a machine that is barely
    /// working still looks different from one that is not answering.
    static func filledBlockCount(for value: Double?) -> Int {
        guard let value else { return 0 }
        return min(max(Int(ceil(value / 10)), 0), blockCount)
    }

    static func band(forLevel level: Int) -> ThermometerBand {
        switch level {
        case ...3: .calm
        case 4 ... 6: .moderate
        case 7 ... 8: .high
        default: .critical
        }
    }
}

nonisolated enum ThermometerBand: Equatable, CaseIterable, Sendable {
    case calm
    case moderate
    case high
    case critical

    /// Isolated only because the brand palette is: the band itself is a plain
    /// value, so a test can reason about it without a main actor.
    @MainActor
    var color: Color {
        switch self {
        case .calm: LittleHerdTheme.loadGreen
        case .moderate: .yellow
        case .high: .orange
        case .critical: .red
        }
    }
}

/// What share of a whole machine a single process is using.
///
/// `ps` reports CPU as a percentage of one core, so a process can legitimately
/// read 380% — which is why this used to be shown as "3.8c". Cores are honest
/// but not comparable: 3.8 of the mini's 14 is a different situation from 3.8
/// of this Mac's 10, and neither can be set against the machine figure directly
/// above it.
///
/// Against the whole machine the rows land on the same scale as everything else
/// and visibly sum toward the machine's own reading.
nonisolated enum ProcessShare {
    /// - Parameter coreCount: how many logical cores the machine has. Without
    ///   it there is no machine to be a share *of*, so the caller keeps showing
    ///   cores rather than inventing a denominator.
    static func percent(ofOneCore cpuPercent: Double, coreCount: Int?) -> Double? {
        guard let coreCount, coreCount > 0 else { return nil }
        return min(max(cpuPercent / Double(coreCount), 0), 100)
    }

    /// What a process is holding, as a share of the machine's memory.
    static func percent(residentBytes: Double, totalBytes: Double?) -> Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return min(max(residentBytes / totalBytes * 100, 0), 100)
    }
}
