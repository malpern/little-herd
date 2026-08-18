import Darwin
import Foundation
import IOKit

nonisolated enum MemoryPressureLevel: Int, Equatable, Sendable {
    case normal = 1
    case warning = 2
    case critical = 4

    init?(systemValue: Int) {
        self.init(rawValue: systemValue)
    }

    static func estimated(availableBytes: Double, totalBytes: Double) -> Self? {
        guard totalBytes > 0 else { return nil }
        let availableFraction = min(max(availableBytes / totalBytes, 0), 1)
        if availableFraction < 0.10 {
            return .critical
        }
        if availableFraction < 0.20 {
            return .warning
        }
        return .normal
    }

    var visualizationPercent: Double {
        switch self {
        case .normal: 30
        case .warning: 70
        case .critical: 100
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .normal: "Normal"
        case .warning: "Warning"
        case .critical: "Critical"
        }
    }
}

nonisolated struct MemoryConsumer: Identifiable, Equatable, Sendable {
    let name: String
    let residentBytes: Double
    let growthEvidence: MemoryGrowthEvidence?
    /// Path to the `.app` the process came from, when it came from one. Kept so
    /// the interface can show the real icon instead of a generic glyph; nil for
    /// command-line tools and for anything on a Linux machine.
    let bundlePath: String?

    init(
        name: String,
        residentBytes: Double,
        growthEvidence: MemoryGrowthEvidence? = nil,
        bundlePath: String? = nil
    ) {
        self.name = name
        self.residentBytes = residentBytes
        self.growthEvidence = growthEvidence
        self.bundlePath = bundlePath
    }

    var id: String { name }
}

nonisolated struct MemoryGrowthEvidence: Equatable, Sendable {
    let growthBytes: Double
    let duration: TimeInterval
    let sampleCount: Int
    let risingIntervalCount: Int
    let observedIntervalCount: Int
}

nonisolated struct ProcessMemorySample: Equatable, Sendable {
    let command: String
    let residentBytes: Double
}

nonisolated struct ProcessSample: Equatable, Sendable {
    let cpuPercent: Double
    let residentBytes: Double
    let processID: Int
    let command: String

    var activityLine: String {
        "\(cpuPercent) \(processID) \(command)"
    }

    var memorySample: ProcessMemorySample {
        ProcessMemorySample(command: command, residentBytes: residentBytes)
    }
}

nonisolated enum ProcessSampleParser {
    static func parse(_ output: String) -> [ProcessSample] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(maxSplits: 3, whereSeparator: \.isWhitespace)
            guard fields.count == 4,
                  let cpuPercent = Double(fields[0]),
                  let residentKilobytes = Double(fields[1]),
                  let processID = Int(fields[2])
            else {
                return nil
            }

            return ProcessSample(
                cpuPercent: cpuPercent,
                residentBytes: residentKilobytes * 1_024,
                processID: processID,
                command: String(fields[3])
            )
        }
    }
}

nonisolated enum MemoryConsumerAggregator {
    static func consumers(
        from samples: [ProcessMemorySample],
        limit: Int = 3
    ) -> [MemoryConsumer] {
        var totals: [String: Double] = [:]
        var bundlePaths: [String: String] = [:]

        for sample in samples where sample.residentBytes > 0 {
            guard let application = application(for: sample.command) else {
                continue
            }
            totals[application.name, default: 0] += sample.residentBytes
            if let bundlePath = application.bundlePath {
                bundlePaths[application.name] = bundlePath
            }
        }

        return totals
            .map {
                MemoryConsumer(
                    name: $0.key,
                    residentBytes: $0.value,
                    bundlePath: bundlePaths[$0.key]
                )
            }
            .sorted {
                if $0.residentBytes == $1.residentBytes {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.residentBytes > $1.residentBytes
            }
            .prefix(max(limit, 0))
            .map { $0 }
    }

    private static func application(
        for command: String
    ) -> (name: String, bundlePath: String?)? {
        if command.contains("/Library/Application Support/Claude/claude-code/") {
            return ("Claude Code", nil)
        }

        // "/Applications/Dia.app/Contents/MacOS/Dia" gives both the name and
        // the bundle the icon can be read from.
        if command.hasPrefix("/"), let appRange = command.range(of: ".app") {
            let bundlePath = String(command[..<appRange.upperBound])
            let name = (bundlePath as NSString)
                .lastPathComponent
                .replacingOccurrences(of: ".app", with: "")
            if !name.isEmpty {
                return (name, bundlePath)
            }
        }

        let components = command.split(separator: "/")
        if let applicationComponent = components.first(where: { $0.hasSuffix(".app") }) {
            let name = applicationComponent.dropLast(".app".count)
            return name.isEmpty ? nil : (String(name), nil)
        }

        let executable = components.last.map(String.init) ?? command
        let fallback: String? = switch executable.lowercased() {
        case "codex": "Codex"
        case "claude": "Claude Code"
        case "chromium": "Chromium"
        case "chrome", "google chrome": "Chrome"
        case "firefox": "Firefox"
        case "node": "Node"
        case "python", "python3": "Python"
        case "java": "Java"
        case "zellij": "Zellij"
        case "ninja": "Ninja"
        case "clang", "clang++", "swift-frontend", "swiftc": "Compiler"
        case "rustc", "cargo": "Rust"
        default: nil
        }
        return fallback.map { ($0, nil) }
    }
}

nonisolated struct MetricReading: Equatable, Sendable {
    let value: Double?
    let auxiliaryValue: Double?
    let capacity: Double?

    init(value: Double?, auxiliaryValue: Double? = nil, capacity: Double? = nil) {
        self.value = value
        self.auxiliaryValue = auxiliaryValue
        self.capacity = capacity
    }
}

nonisolated struct SystemSnapshot: Equatable, Sendable {
    let timestamp: Date
    let readings: [MetricKind: MetricReading]
    let activities: [MachineActivity]
    let agentSessions: [AgentSession]
    let storageVolumes: [StorageVolume]
    let memoryPressure: MemoryPressureLevel?
    let memoryConsumers: [MemoryConsumer]
    /// Physical drives, when the machine can report them. Only a NAS reached
    /// through DSM does today; a Mac reports volumes but not the health of the
    /// hardware underneath them.
    let drives: [SynologyDrive]
    /// Logical cores, so a process's share of one core can be expressed as a
    /// share of the whole machine. Nil where the machine does not say.
    let coreCount: Int?

    init(
        timestamp: Date,
        readings: [MetricKind: MetricReading],
        activities: [MachineActivity] = [],
        agentSessions: [AgentSession] = [],
        storageVolumes: [StorageVolume] = [],
        memoryPressure: MemoryPressureLevel? = nil,
        memoryConsumers: [MemoryConsumer] = [],
        drives: [SynologyDrive] = [],
        coreCount: Int? = nil
    ) {
        self.timestamp = timestamp
        self.readings = readings
        self.activities = activities
        self.agentSessions = agentSessions
        self.storageVolumes = storageVolumes
        self.memoryPressure = memoryPressure
        self.memoryConsumers = memoryConsumers
        self.drives = drives
        self.coreCount = coreCount
    }
}

actor MetricsSampler {
    private struct ProcessHighlights: Sendable {
        let activities: [MachineActivity]
        let memoryConsumers: [MemoryConsumer]
        let agentSessions: [AgentSession]
    }

    private struct CPUCounters: Sendable {
        let active: UInt64
        let total: UInt64
    }

    private struct NetworkCounters: Sendable {
        let received: UInt64
        let sent: UInt64
    }

    private var previousCPU: CPUCounters?
    private var previousNetwork: NetworkCounters?
    private var previousNetworkTimestamp: ContinuousClock.Instant?
    private var cachedActivities: [MachineActivity] = []
    private var cachedMemoryConsumers: [MemoryConsumer] = []
    private var previousActivityTimestamp: ContinuousClock.Instant?
    private var cachedAgentTasks: [AgentTaskProvider: AgentTaskSummary] = [:]
    private var cachedAgentSessions: [AgentSession] = []
    private var previousAgentTaskTimestamp: ContinuousClock.Instant?
    private let clock = ContinuousClock()

    func prime() {
        previousCPU = readCPUCounters()
        previousNetwork = readNetworkCounters()
        previousNetworkTimestamp = clock.now
    }

    func sample() async -> SystemSnapshot {
        let timestamp = Date()
        let cpu = cpuUtilization()
        let gpu = gpuUtilization()
        let memory = memoryUsage()
        let memoryPressure = memoryPressureLevel()
        let network = networkThroughput()
        let storageVolumes = storageVolumes()
        let disk = storageVolumes.first(where: { $0.mountPath == "/" })
        let processHighlights = await processHighlights()

        return SystemSnapshot(
            timestamp: timestamp,
            readings: [
                .cpu: MetricReading(value: cpu),
                .gpu: MetricReading(value: gpu),
                .memory: MetricReading(
                    value: memoryPressure?.visualizationPercent,
                    auxiliaryValue: memory.map { Double($0.used) },
                    capacity: memory.map { Double($0.total) }
                ),
                .network: MetricReading(
                    value: network.map { $0.receivedPerSecond + $0.sentPerSecond },
                    auxiliaryValue: network?.receivedPerSecond,
                    capacity: network?.sentPerSecond
                ),
                .disk: MetricReading(
                    value: disk?.usedPercent,
                    auxiliaryValue: disk?.availableBytes,
                    capacity: disk?.totalBytes
                ),
            ],
            activities: processHighlights.activities,
            agentSessions: processHighlights.agentSessions,
            storageVolumes: storageVolumes,
            memoryPressure: memoryPressure,
            memoryConsumers: processHighlights.memoryConsumers,
            coreCount: ProcessInfo.processInfo.activeProcessorCount
        )
    }

    private func processHighlights() async -> ProcessHighlights {
        let now = clock.now
        let cachedHighlights = ProcessHighlights(
            activities: cachedActivities,
            memoryConsumers: cachedMemoryConsumers,
            agentSessions: cachedAgentSessions
        )

        if let previousActivityTimestamp,
           previousActivityTimestamp.duration(to: now) < .seconds(15)
        {
            return cachedHighlights
        }

        previousActivityTimestamp = now

        guard let output = await LocalProcessRunner.run(
            executablePath: "/bin/ps",
            arguments: ["-Ao", "pcpu=,rss=,pid=,comm="]
        ) else {
            return cachedHighlights
        }

        let shouldRefreshAgentTasks: Bool
        if let previousAgentTaskTimestamp {
            shouldRefreshAgentTasks = previousAgentTaskTimestamp.duration(to: now)
                >= AgentTaskProbe.refreshInterval
        } else {
            shouldRefreshAgentTasks = true
        }

        if shouldRefreshAgentTasks {
            let agentSnapshot = await AgentTaskProbe.readLocalSnapshot()
            cachedAgentTasks = agentSnapshot.tasksByProvider
            cachedAgentSessions = agentSnapshot.sessions
            previousAgentTaskTimestamp = now
        }

        let samples = ProcessSampleParser.parse(output)
        let activityOutput = samples.map(\.activityLine).joined(separator: "\n")
        var candidateActivities: [MachineActivity] = []
        for activity in MachineActivityParser.highlights(
            from: activityOutput,
            limit: 20,
            minimumCPUPercent: 0
        ) {
            candidateActivities.append(
                await addWorkingDirectoryContext(to: activity)
            )
        }
        cachedActivities = MachineActivityPrioritizer.select(
            from: candidateActivities,
            agentTasks: cachedAgentTasks,
            limit: MachineActivityParser.detailHighlights
        )
        cachedMemoryConsumers = MemoryConsumerAggregator.consumers(
            from: samples.map(\.memorySample)
        )
        return ProcessHighlights(
            activities: cachedActivities,
            memoryConsumers: cachedMemoryConsumers,
            agentSessions: cachedAgentSessions
        )
    }

    private func addWorkingDirectoryContext(
        to activity: MachineActivity
    ) async -> MachineActivity {
        guard activity.kind == .compiling || activity.kind == .building,
              let processID = activity.processID,
              let workingDirectory = await workingDirectory(
                  forProcessID: processID
              )
        else {
            return activity
        }

        return activity.addingContext(
            MachineActivityContext.projectName(fromWorkingDirectory: workingDirectory)
        )
    }

    private func workingDirectory(forProcessID processID: Int) async -> String? {
        await LocalProcessRunner.run(
            executablePath: "/usr/sbin/lsof",
            arguments: ["-a", "-p", String(processID), "-d", "cwd", "-Fn"]
        )?
            .split(whereSeparator: \.isNewline)
            .first { $0.first == "n" }
            .map { String($0.dropFirst()) }
    }

    private func cpuUtilization() -> Double? {
        guard let current = readCPUCounters() else { return nil }
        defer { previousCPU = current }
        guard let previousCPU,
              current.total >= previousCPU.total,
              current.active >= previousCPU.active
        else {
            return nil
        }

        let totalDelta = current.total - previousCPU.total
        let activeDelta = current.active - previousCPU.active
        guard totalDelta > 0 else { return 0 }
        return min(max(Double(activeDelta) / Double(totalDelta) * 100, 0), 100)
    }

    private func readCPUCounters() -> CPUCounters? {
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0
        var cpuCount: natural_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &cpuInfo,
            &cpuInfoCount
        )

        guard result == KERN_SUCCESS, let cpuInfo else { return nil }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: cpuInfo),
                vm_size_t(cpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            )
        }

        let buffer = UnsafeBufferPointer(start: cpuInfo, count: Int(cpuInfoCount))
        var active: UInt64 = 0
        var total: UInt64 = 0

        for cpu in 0 ..< Int(cpuCount) {
            let offset = cpu * Int(CPU_STATE_MAX)
            let user = UInt64(UInt32(bitPattern: buffer[offset + Int(CPU_STATE_USER)]))
            let system = UInt64(UInt32(bitPattern: buffer[offset + Int(CPU_STATE_SYSTEM)]))
            let nice = UInt64(UInt32(bitPattern: buffer[offset + Int(CPU_STATE_NICE)]))
            let idle = UInt64(UInt32(bitPattern: buffer[offset + Int(CPU_STATE_IDLE)]))

            active += user + system + nice
            total += user + system + nice + idle
        }

        return CPUCounters(active: active, total: total)
    }

    private func gpuUtilization() -> Double? {
        guard let matching = IOServiceMatching("IOAccelerator") else { return nil }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var highestUtilization: Double?
        var service = IOIteratorNext(iterator)

        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            guard let rawStatistics = IORegistryEntryCreateCFProperty(
                service,
                "PerformanceStatistics" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue(),
                let statistics = rawStatistics as? [String: Any]
            else {
                continue
            }

            for key in ["Device Utilization %", "Renderer Utilization %"] {
                guard let number = statistics[key] as? NSNumber else { continue }
                highestUtilization = max(highestUtilization ?? 0, number.doubleValue)
            }
        }

        return highestUtilization.map { min(max($0, 0), 100) }
    }

    private func memoryUsage() -> (used: UInt64, total: UInt64)? {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )

        let result = withUnsafeMutablePointer(to: &statistics) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return nil }

        var hostPageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &hostPageSize) == KERN_SUCCESS else {
            return nil
        }
        let pageSize = UInt64(hostPageSize)
        let total = ProcessInfo.processInfo.physicalMemory
        let free = UInt64(statistics.free_count) * pageSize
        let speculative = UInt64(statistics.speculative_count) * pageSize
        let immediatelyAvailable = min(free + speculative, total)
        let used = total - immediatelyAvailable

        return (used, total)
    }

    private func memoryPressureLevel() -> MemoryPressureLevel? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname(
            "kern.memorystatus_vm_pressure_level",
            &value,
            &size,
            nil,
            0
        )
        guard result == 0 else { return nil }
        return MemoryPressureLevel(systemValue: Int(value))
    }

    private func networkThroughput() -> (receivedPerSecond: Double, sentPerSecond: Double)? {
        guard let current = readNetworkCounters() else { return nil }
        let now = clock.now
        defer {
            previousNetwork = current
            previousNetworkTimestamp = now
        }

        guard let previousNetwork, let previousNetworkTimestamp else { return nil }
        let elapsed = previousNetworkTimestamp.duration(to: now)
        let seconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000
        guard seconds > 0 else { return nil }

        let receivedDelta = current.received >= previousNetwork.received
            ? current.received - previousNetwork.received
            : 0
        let sentDelta = current.sent >= previousNetwork.sent
            ? current.sent - previousNetwork.sent
            : 0

        return (
            receivedPerSecond: Double(receivedDelta) / seconds,
            sentPerSecond: Double(sentDelta) / seconds
        )
    }

    private func readNetworkCounters() -> NetworkCounters? {
        var addressList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressList) == 0, let firstAddress = addressList else {
            return nil
        }
        defer { freeifaddrs(firstAddress) }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddress

        while let interface = cursor?.pointee {
            defer { cursor = interface.ifa_next }

            let flags = Int32(interface.ifa_flags)
            let isUp = flags & IFF_UP != 0
            let isLoopback = flags & IFF_LOOPBACK != 0
            guard isUp, !isLoopback,
                  interface.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
                  let dataPointer = interface.ifa_data
            else {
                continue
            }

            let name = String(cString: interface.ifa_name)
            guard name.hasPrefix("en") else { continue }

            let data = dataPointer.assumingMemoryBound(to: if_data.self).pointee
            received += UInt64(data.ifi_ibytes)
            sent += UInt64(data.ifi_obytes)
        }

        return NetworkCounters(received: received, sent: sent)
    }

    /// The startup disk only.
    ///
    /// Enumerating every mounted volume can trigger macOS's network-volume
    /// privacy prompt even when network entries are filtered out afterwards, so
    /// routine local sampling stays scoped to `/` and broader discovery stays
    /// gated behind SMBStorageSampler.
    private func storageVolumes() -> [StorageVolume] {
        let root = URL(fileURLWithPath: "/", isDirectory: true)
        // Plain available capacity, not "for important usage".
        //
        // The important-usage figure credits purgeable space — caches and local
        // snapshots macOS would evict under pressure — and on this Mac that is
        // a 39 GB difference. Remote Macs are measured with df, which does not
        // credit it, so using the generous number here made the local machine
        // look emptier than an identical remote one. This is the conservative
        // reading: space you can use right now, and the one diskutil agrees
        // with.
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
        ]

        guard let values = try? root.resourceValues(forKeys: keys),
              let totalValue = values.volumeTotalCapacity,
              let availableValue = values.volumeAvailableCapacity,
              totalValue > 0
        else {
            return []
        }

        let total = Double(totalValue)
        let trimmedName = values.volumeName?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return [
            StorageVolume(
                id: root.path,
                name: trimmedName.flatMap { $0.isEmpty ? nil : $0 } ?? "Internal",
                mountPath: root.path,
                availableBytes: min(max(Double(availableValue), 0), total),
                totalBytes: total
            ),
        ]
    }
}
