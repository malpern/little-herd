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

/// What belongs in a metric row's value column.
///
/// Memory is the awkward one. Where the operating system offers a pressure
/// verdict that is the honest answer, since cache it is deliberately holding is
/// not a problem. A NAS has no such notion, but it does know how much it is
/// using — and the row already spells that out underneath, so the column stays
/// empty rather than printing a dash beside "1.5 GB of 1.94 GB".
nonisolated enum MetricValueDisplay: Equatable, Sendable {
    case pressure(MemoryPressureLevel)
    case percent(Double)
    case bytesPerSecond(Double)
    /// Nothing here: the figure is already written out below the row.
    case spelledOutBelow
    /// A dash. There is no reading at all.
    case unavailable

    static func resolve(
        kind: MetricKind,
        value: Double?,
        memoryPressure: MemoryPressureLevel?
    ) -> MetricValueDisplay {
        if kind == .memory, let memoryPressure {
            return .pressure(memoryPressure)
        }
        guard let value else { return .unavailable }
        switch kind {
        case .cpu, .gpu, .disk: return .percent(value)
        case .network: return .bytesPerSecond(value)
        case .memory: return .spelledOutBelow
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
