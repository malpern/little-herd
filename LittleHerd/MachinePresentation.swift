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
