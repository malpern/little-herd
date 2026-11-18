import Foundation

/// Anything the remote-monitor loop can ask for a snapshot.
nonisolated protocol RemoteSnapshotSampling: Actor {
    func sample() async throws -> SystemSnapshot
}

extension RemoteMetricsSampler: RemoteSnapshotSampling {}

/// A machine Little Herd does not log in to, read from the report it pushes.
///
/// **Why this exists.** The Sandpiper Pi is production: SSH there needs a key
/// *and* a password unless dev mode is on, and every successful login pages
/// its owner. Sampling it over SSH every ten seconds would either fail all the
/// time or page all the time. So the Pi reports outbound instead, to a small
/// receiver on the mini (`herd-relay-receiver` in dotfiles), which keeps the
/// latest report at `~/.local/state/herd-relay/<name>.txt`. This sampler reads
/// that file over the SSH connection Little Herd already makes to the relay
/// host. Nothing logs in to the Pi.
///
/// The report is the Linux sampler's own `key=numbers` format, minus
/// everything that is not a number: no processes, no paths, no agents. So a
/// relayed machine shows load, memory, disk and network, and nothing that
/// would need a login to act on.
///
/// **Rates are computed from the Pi's clock, not ours.** The file only changes
/// when a new report lands, so reading it twice in one interval must not be
/// read as "no CPU used": a counter pair only counts when `reported_at` moved,
/// and the elapsed time is the difference between the two reports.
actor RelayMetricsSampler: RemoteSnapshotSampling {
    /// A report older than this means the machine has stopped reporting.
    static let staleAfter: TimeInterval = 60

    private let relayHost: String
    private let reportName: String
    private let identityFile: String?
    private let now: @Sendable () -> Date
    private let read: @Sendable (String, String, String?) async throws -> String

    private var previous: (reportedAt: Double, cpu: [Double], network: [Double])?
    private var lastReadings: (cpu: Double?, network: (Double, Double)?)

    init(
        relayHost: String,
        reportName: String,
        identityFile: String? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        read: @escaping @Sendable (String, String, String?) async throws -> String = {
            try await SSHCommandRunner.run(host: $0, command: $1, identityFile: $2)
        }
    ) {
        self.relayHost = relayHost
        self.reportName = reportName
        self.identityFile = identityFile
        self.now = now
        self.read = read
    }

    /// Only names the receiver itself would write, so a hand-edited preference
    /// can never turn into a different command on the relay host.
    static func isValidReportName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 32
            && name.allSatisfy { ("a" ... "z").contains($0) || ("0" ... "9").contains($0) || $0 == "-" }
    }

    static func command(reportName: String) -> String {
        "/bin/cat \"$HOME/.local/state/herd-relay/\(reportName).txt\""
    }

    func sample() async throws -> SystemSnapshot {
        guard Self.isValidReportName(reportName) else {
            throw RemoteMonitorError.commandFailed("“\(reportName)” is not a valid relay report name.")
        }
        let output = try await read(relayHost, Self.command(reportName: reportName), identityFile)
        let raw = RemoteOutputParser.parse(output)

        guard let receivedAt = raw["received_at"]?.first,
              let reportedAt = raw["reported_at"]?.first,
              let memory = raw["mem"], memory.count == 2,
              let disk = raw["disk"], disk.count == 2,
              let network = raw["network"], network.count == 2,
              let cpu = raw["cpu"], cpu.count >= 8
        else {
            throw RemoteMonitorError.invalidOutput
        }

        let age = now().timeIntervalSince1970 - receivedAt
        if age > Self.staleAfter {
            let minutes = max(Int(age / 60), 1)
            throw RemoteMonitorError.commandFailed(
                "No report from \(reportName) for \(minutes) min."
            )
        }

        if let previous, reportedAt > previous.reportedAt {
            let elapsed = reportedAt - previous.reportedAt
            lastReadings.cpu = Self.cpuPercent(from: previous.cpu, to: cpu)
            lastReadings.network = (
                max(network[0] - previous.network[0], 0) / elapsed,
                max(network[1] - previous.network[1], 0) / elapsed
            )
        }
        if previous == nil || reportedAt > previous!.reportedAt {
            previous = (reportedAt, cpu, network)
        }

        let memoryTotal = memory[0]
        let memoryAvailable = min(memory[1], memoryTotal)
        let memoryUsed = max(memoryTotal - memoryAvailable, 0)
        let memoryPressure = MemoryPressureLevel.estimated(
            availableBytes: memoryAvailable,
            totalBytes: memoryTotal
        )
        let diskTotal = disk[0]
        let diskAvailable = min(disk[1], diskTotal)
        let swap = raw["swap"].flatMap { values -> SwapUsage? in
            guard values.count == 2 else { return nil }
            return SwapUsage(usedBytes: max(values[1], 0), totalBytes: max(values[0], 0))
        }

        var readings: [MetricKind: MetricReading] = [
            .memory: MetricReading(
                value: memoryPressure?.visualizationPercent,
                auxiliaryValue: memoryUsed,
                capacity: memoryTotal
            ),
            .disk: MetricReading(
                value: diskTotal > 0 ? min(max((diskTotal - diskAvailable) / diskTotal * 100, 0), 100) : nil,
                auxiliaryValue: diskAvailable,
                capacity: diskTotal
            ),
        ]
        if let value = lastReadings.cpu {
            readings[.cpu] = MetricReading(value: value)
        }
        if let (received, sent) = lastReadings.network {
            readings[.network] = MetricReading(
                value: received + sent,
                auxiliaryValue: received,
                capacity: sent
            )
        }

        return SystemSnapshot(
            timestamp: Date(timeIntervalSince1970: reportedAt),
            readings: readings,
            storageVolumes: [
                StorageVolume(
                    id: "/",
                    name: "Root",
                    mountPath: "/",
                    availableBytes: diskAvailable,
                    totalBytes: diskTotal
                ),
            ],
            memoryPressure: memoryPressure,
            swap: swap,
            coreCount: raw["cores"]?.first.map { Int($0) }
        )
    }

    static func cpuPercent(from old: [Double], to new: [Double]) -> Double? {
        func split(_ fields: [Double]) -> (active: Double, total: Double) {
            let total = fields.reduce(0, +)
            return (total - fields[3] - fields[4], total)
        }
        let before = split(old), after = split(new)
        guard after.total > before.total, after.active >= before.active else { return nil }
        return min(max((after.active - before.active) / (after.total - before.total) * 100, 0), 100)
    }
}
