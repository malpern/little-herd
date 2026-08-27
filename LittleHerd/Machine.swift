import Foundation

nonisolated enum OverviewMetric: String, CaseIterable, Equatable, Identifiable, Sendable {
    case cpu
    case memory
    case disk
    case ai

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .disk: "Disk"
        case .ai: "AI"
        }
    }

    var symbolName: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .ai: "sparkles"
        }
    }

    var next: OverviewMetric {
        switch self {
        case .cpu: .memory
        case .memory: .disk
        case .disk: .ai
        case .ai: .cpu
        }
    }

    var previous: OverviewMetric {
        switch self {
        case .cpu: .ai
        case .memory: .cpu
        case .disk: .memory
        case .ai: .disk
        }
    }

    var cycleHint: LocalizedStringResource {
        switch self {
        case .cpu: "Show memory usage across machines"
        case .memory: "Show storage usage across machines"
        case .disk: "Show AI agents across machines"
        case .ai: "Show CPU usage across machines"
        }
    }
}

nonisolated enum DashboardSelection: Equatable, Sendable {
    case overview
    /// Everything about one machine — reached by clicking its icon.
    case machine(MachineID)
    /// One machine through the lens of the current overview metric — reached
    /// by clicking its thermometer.
    case machineMetric(MachineID)

    var machineID: MachineID? {
        switch self {
        case .overview: nil
        case let .machine(machineID), let .machineMetric(machineID): machineID
        }
    }

    var isMetricFocus: Bool {
        if case .machineMetric = self { return true }
        return false
    }
}

nonisolated struct MachineID: RawRepresentable, Codable, Hashable, Identifiable,
    Sendable
{
    let rawValue: String

    var id: Self { self }

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static let macBookAir = Self("macBookAir")
    static let macMini = Self("macMini")
    static let linux = Self("linux")
    static let synology = Self("synology")

    var shortName: String {
        switch self {
        case .macBookAir: "Air"
        case .macMini: "Mini"
        case .linux: "Linux"
        case .synology: "Synology"
        default: fallbackName
        }
    }

    var displayName: String {
        switch self {
        case .macBookAir: Host.current().localizedName ?? "MacBook Air"
        case .macMini: "Mac mini"
        case .linux: "Linux"
        case .synology: "Synology"
        default: fallbackName
        }
    }

    var symbolName: String {
        switch self {
        case .macBookAir: "laptopcomputer"
        case .macMini: "macmini"
        case .linux: "server.rack"
        case .synology: "externaldrive.connected.to.line.below"
        default: "desktopcomputer"
        }
    }

    private var fallbackName: String {
        let component = rawValue.split(separator: ".").first.map(String.init)
            ?? rawValue
        return component
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

nonisolated enum MonitorConnectionState: Equatable, Sendable {
    case connecting
    case live
    case offline
    case stopped
}

nonisolated struct MenuBarMachineSnapshot: Equatable, Identifiable, Sendable {
    let machine: MachineID
    let state: MonitorConnectionState
    let cpuPercent: Double?
    let memoryPressure: MemoryPressureLevel?
    let diskUsedPercent: Double?
    /// The worst condition any of this machine's drives or volumes reports,
    /// when it reports one at all.
    var storageHealth: SynologyHealth?
    /// What the CPU has averaged recently, when there is enough history to say.
    /// `cpuPercent` is the current reading and is what the menu bar shows while
    /// nothing is wrong; this is what decides whether something is.
    var sustainedCPUPercent: Double?

    var id: MachineID { machine }
}

/// Whether a machine is busy, as opposed to momentarily peaking.
///
/// A single reading is a poor basis for interrupting someone. Every machine
/// here touches 95% several times an hour — opening an app does it — and a menu
/// bar that flips into an alarm and back out again on a ten-second sample is
/// noise wearing the costume of information.
///
/// So the question asked is not "is it busy now" but "has it been busy", which
/// needs the readings to cover a window before it can be answered at all. That
/// means nothing is flagged for the first few minutes after launch. The menu
/// bar still shows the busiest machine and its current figure throughout; what
/// it withholds is the claim that something is wrong, which genuinely cannot be
/// made yet.
nonisolated enum SustainedLoad {
    /// Long enough that a build starting, an app launching, or a page rendering
    /// has passed; short enough to still be news.
    static let window: TimeInterval = 300

    /// The mean reading across the window, or nothing if the readings do not
    /// reach back far enough to cover it.
    static func average(
        of points: [HistoryPoint],
        endingAt now: Date,
        window: TimeInterval = window
    ) -> Double? {
        let start = now.addingTimeInterval(-window)
        // The oldest reading has to predate the window, otherwise the average
        // describes a shorter stretch than it claims to.
        guard let oldest = points.first?.timestamp, oldest <= start else {
            return nil
        }
        let inWindow = points.filter { $0.timestamp >= start }
        guard !inWindow.isEmpty else { return nil }
        return inWindow.reduce(0) { $0 + $1.value } / Double(inWindow.count)
    }
}

nonisolated enum MenuBarHeadline: Equatable, Sendable {
    case connecting(live: Int, total: Int)
    case normal(machine: MachineID?, cpuPercent: Int?, live: Int, total: Int)
    case unavailable(live: Int, total: Int)
    case highCPU(machine: MachineID, percent: Int, critical: Bool)
    case memoryPressure(machine: MachineID, critical: Bool)
    case lowDisk(machine: MachineID, usedPercent: Int, critical: Bool)
    case storageUnhealthy(machine: MachineID, critical: Bool)
}

nonisolated enum MenuBarStatusSelector {
    static func headline(for snapshots: [MenuBarMachineSnapshot]) -> MenuBarHeadline {
        let liveSnapshots = snapshots.filter { $0.state == .live }
        let liveCount = liveSnapshots.count

        // Above everything else: a full disk or a busy CPU is recoverable, and
        // a drive that is going takes the data with it.
        if let failing = liveSnapshots.first(where: {
            $0.storageHealth == .critical
        }) {
            return .storageUnhealthy(machine: failing.machine, critical: true)
        }
        if let degrading = liveSnapshots.first(where: {
            $0.storageHealth == .warning
        }) {
            return .storageUnhealthy(machine: degrading.machine, critical: false)
        }

        if let criticalMemory = liveSnapshots.first(where: {
            $0.memoryPressure == .critical
        }) {
            return .memoryPressure(machine: criticalMemory.machine, critical: true)
        }

        // Sustained, not instantaneous: see `SustainedLoad`. The figure reported
        // is the same one the threshold was applied to, so the headline and the
        // reason it appeared cannot disagree.
        if let criticalCPU = liveSnapshots
            .filter({ ($0.sustainedCPUPercent ?? 0) >= 95 })
            .max(by: {
                ($0.sustainedCPUPercent ?? 0) < ($1.sustainedCPUPercent ?? 0)
            })
        {
            return .highCPU(
                machine: criticalCPU.machine,
                percent: roundedPercent(criticalCPU.sustainedCPUPercent) ?? 0,
                critical: true
            )
        }

        if let criticalDisk = liveSnapshots
            .filter({ ($0.diskUsedPercent ?? 0) >= 95 })
            .max(by: { ($0.diskUsedPercent ?? 0) < ($1.diskUsedPercent ?? 0) })
        {
            return .lowDisk(
                machine: criticalDisk.machine,
                usedPercent: roundedPercent(criticalDisk.diskUsedPercent) ?? 0,
                critical: true
            )
        }

        if let warningMemory = liveSnapshots.first(where: {
            $0.memoryPressure == .warning
        }) {
            return .memoryPressure(machine: warningMemory.machine, critical: false)
        }

        if let highCPU = liveSnapshots
            .filter({ ($0.sustainedCPUPercent ?? 0) >= 80 })
            .max(by: {
                ($0.sustainedCPUPercent ?? 0) < ($1.sustainedCPUPercent ?? 0)
            })
        {
            return .highCPU(
                machine: highCPU.machine,
                percent: roundedPercent(highCPU.sustainedCPUPercent) ?? 0,
                critical: false
            )
        }

        if let lowDisk = liveSnapshots
            .filter({ ($0.diskUsedPercent ?? 0) >= 90 })
            .max(by: { ($0.diskUsedPercent ?? 0) < ($1.diskUsedPercent ?? 0) })
        {
            return .lowDisk(
                machine: lowDisk.machine,
                usedPercent: roundedPercent(lowDisk.diskUsedPercent) ?? 0,
                critical: false
            )
        }

        let unavailableCount = snapshots.count {
            $0.state == .offline || $0.state == .stopped
        }
        if unavailableCount > 0 {
            return .unavailable(live: liveCount, total: snapshots.count)
        }

        if liveCount == 0 {
            return .connecting(live: 0, total: snapshots.count)
        }

        let busiest = liveSnapshots
            .filter { $0.cpuPercent != nil }
            .max(by: { ($0.cpuPercent ?? 0) < ($1.cpuPercent ?? 0) })
        return .normal(
            machine: busiest?.machine,
            cpuPercent: roundedPercent(busiest?.cpuPercent),
            live: liveCount,
            total: snapshots.count
        )
    }

    private static func roundedPercent(_ value: Double?) -> Int? {
        guard let value else { return nil }
        return min(max(Int(value.rounded()), 0), 100)
    }
}
