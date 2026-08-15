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
        case .memory: "RAM"
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
    case machine(MachineID)

    static let cpuOverview = Self.overview
    static let macBookAir = Self.machine(.macBookAir)
    static let macMini = Self.machine(.macMini)
    static let linux = Self.machine(.linux)

    var machineID: MachineID? {
        guard case let .machine(machineID) = self else { return nil }
        return machineID
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

    var supportsGPU: Bool {
        self == .macBookAir
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

    var id: MachineID { machine }
}

nonisolated enum MenuBarHeadline: Equatable, Sendable {
    case connecting(live: Int, total: Int)
    case normal(machine: MachineID?, cpuPercent: Int?, live: Int, total: Int)
    case unavailable(live: Int, total: Int)
    case highCPU(machine: MachineID, percent: Int, critical: Bool)
    case memoryPressure(machine: MachineID, critical: Bool)
    case lowDisk(machine: MachineID, usedPercent: Int, critical: Bool)
}

nonisolated enum MenuBarStatusSelector {
    static func headline(for snapshots: [MenuBarMachineSnapshot]) -> MenuBarHeadline {
        let liveSnapshots = snapshots.filter { $0.state == .live }
        let liveCount = liveSnapshots.count

        if let criticalMemory = liveSnapshots.first(where: {
            $0.memoryPressure == .critical
        }) {
            return .memoryPressure(machine: criticalMemory.machine, critical: true)
        }

        if let criticalCPU = liveSnapshots
            .filter({ ($0.cpuPercent ?? 0) >= 95 })
            .max(by: { ($0.cpuPercent ?? 0) < ($1.cpuPercent ?? 0) })
        {
            return .highCPU(
                machine: criticalCPU.machine,
                percent: roundedPercent(criticalCPU.cpuPercent) ?? 0,
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
            .filter({ ($0.cpuPercent ?? 0) >= 80 })
            .max(by: { ($0.cpuPercent ?? 0) < ($1.cpuPercent ?? 0) })
        {
            return .highCPU(
                machine: highCPU.machine,
                percent: roundedPercent(highCPU.cpuPercent) ?? 0,
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
