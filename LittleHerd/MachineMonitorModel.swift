import Foundation
import Observation

@MainActor
@Observable
final class MachineMonitorModel: Identifiable {
    let machine: MachineID
    let name: String
    let shortName: String
    let hostname: String
    let symbolName: String
    let avatar: HerdwareAvatar
    let supportsGPU: Bool
    let isStorage: Bool
    /// This Mac. Actions that touch the filesystem only apply here.
    let isLocal: Bool
    let cpu: MetricModel
    let memory: MetricModel
    let metrics: [MetricModel]
    private(set) var state: MonitorConnectionState = .connecting
    private(set) var lastUpdated: Date?
    private(set) var activities: [MachineActivity] = []
    private(set) var agentSessions: [AgentSession] = []
    private(set) var storageVolumes: [StorageVolume] = []
    /// Physical drives, for machines that can report them. A NAS is the only one
    /// that does, and a failing drive there is the most consequential thing
    /// Little Herd can notice.
    private(set) var drives: [SynologyDrive] = []
    private(set) var memoryPressure: MemoryPressureLevel?
    private(set) var memoryConsumers: [MemoryConsumer] = []
    /// Why the machine is unreachable, when it is. Kept beside `state` so the
    /// interface can say more than "Unavailable".
    private(set) var unavailability: RemoteUnavailability?

    @ObservationIgnored
    private var memoryGrowthDetector = MemoryGrowthDetector()

    var id: MachineID { machine }

    init(configuration: MachineConfiguration) {
        let cpu = MetricModel(kind: .cpu)
        let memory = MetricModel(kind: .memory)
        machine = configuration.id
        name = configuration.name
        shortName = configuration.shortName
        hostname = configuration.hostname
        symbolName = configuration.platform.symbolName
        avatar = configuration.avatar
        supportsGPU = configuration.supportsGPU
        isStorage = configuration.isStorage
        isLocal = configuration.connection == .local
        self.cpu = cpu
        self.memory = memory
        metrics = [
            cpu,
            MetricModel(kind: .gpu),
            memory,
            MetricModel(kind: .network),
            MetricModel(kind: .disk),
        ]
    }

    func apply(_ snapshot: SystemSnapshot) {
        for metric in metrics {
            guard let reading = snapshot.readings[metric.kind] else { continue }
            metric.update(with: reading, at: snapshot.timestamp)
        }
        activities = snapshot.activities
        agentSessions = snapshot.agentSessions
        storageVolumes = snapshot.storageVolumes
        drives = snapshot.drives
        memoryPressure = snapshot.memoryPressure
        memoryConsumers = memoryGrowthDetector.annotate(
            consumers: snapshot.memoryConsumers,
            at: snapshot.timestamp
        )
        lastUpdated = snapshot.timestamp
        state = .live
        unavailability = nil
    }

    /// The worst thing this machine's storage reports, when it is worth saying
    /// out loud. One definition, so the overview badge, the machine's own page,
    /// and the menu bar cannot disagree about whether a drive is in trouble.
    ///
    /// Healthy and unreported storage produce nothing: a badge that is always
    /// lit says nothing at all.
    var storageConcern: StorageConcern? {
        let worstDrive = drives.max { $0.health.severity < $1.health.severity }
        let worstVolume = storageVolumes
            .compactMap { volume -> (SynologyHealth, String)? in
                volume.health.map { ($0, volume.name) }
            }
            .max { $0.0.severity < $1.0.severity }

        // A named drive beats a volume: it is the thing you would physically
        // replace, and the volume is usually just reporting the same fault.
        if let worstDrive, worstDrive.health == .warning
            || worstDrive.health == .critical {
            return StorageConcern(
                health: worstDrive.health,
                subject: worstDrive.name,
                detail: worstDrive.uncorrectableSectors > 0
                    ? "\(worstDrive.uncorrectableSectors) bad sectors"
                    : nil
            )
        }
        if let worstVolume, worstVolume.0 == .warning || worstVolume.0 == .critical {
            return StorageConcern(
                health: worstVolume.0,
                subject: worstVolume.1,
                detail: nil
            )
        }
        return nil
    }

    /// Offline covers two situations that deserve different treatment. A
    /// machine that answered and then stopped is a problem worth a red dot. One
    /// that has never answered at all has not been set up yet — colouring that
    /// red says the hardware is broken when nothing is wrong with it.
    ///
    /// The alert center already draws this line; the interface should too.
    var hasNeverConnected: Bool {
        state == .offline && lastUpdated == nil
    }

    func markOffline(_ reason: RemoteUnavailability? = nil) {
        state = .offline
        unavailability = reason
        agentSessions = agentSessions.map { $0.waitingIfActive() }
    }

    func markConnecting() {
        state = .connecting
    }

    func markStopped() {
        state = .stopped
    }
}

/// What is wrong with a machine's storage, said in the fewest words that still
/// identify the part to replace.
nonisolated struct StorageConcern: Equatable, Sendable {
    let health: SynologyHealth
    /// The drive or volume at fault, by the name the machine calls it.
    let subject: String
    let detail: String?

    var summary: String {
        let condition = health == .critical ? "failing" : "needs attention"
        guard let detail else { return "\(subject) \(condition)" }
        return "\(subject) \(condition) — \(detail)"
    }
}

nonisolated struct MemoryGrowthDetector: Sendable {
    private struct Sample: Equatable, Sendable {
        let timestamp: Date
        let residentBytes: Double
    }

    private var histories: [String: [Sample]] = [:]

    private let minimumDuration: TimeInterval = 90
    private let minimumSampleCount = 7
    private let maximumDuration: TimeInterval = 5 * 60
    private let minimumAbsoluteGrowth = 128 * 1_024 * 1_024.0
    private let minimumRelativeGrowth = 0.06
    private let meaningfulRise = 8 * 1_024 * 1_024.0
    private let absoluteDropTolerance = 32 * 1_024 * 1_024.0

    mutating func annotate(
        consumers: [MemoryConsumer],
        at timestamp: Date
    ) -> [MemoryConsumer] {
        let visibleNames = Set(consumers.map(\.name))
        histories = histories.filter { visibleNames.contains($0.key) }

        return consumers.map { consumer in
            record(consumer: consumer, at: timestamp)
            return MemoryConsumer(
                name: consumer.name,
                residentBytes: consumer.residentBytes,
                growthEvidence: evidence(for: consumer.name),
                bundlePath: consumer.bundlePath
            )
        }
    }

    private mutating func record(consumer: MemoryConsumer, at timestamp: Date) {
        var samples = histories[consumer.name, default: []]
        let oldestAllowedDate = timestamp.addingTimeInterval(-maximumDuration)
        samples.removeAll { $0.timestamp < oldestAllowedDate }

        if let last = samples.last,
           abs(last.residentBytes - consumer.residentBytes) < 1
        {
            histories[consumer.name] = samples
            return
        }

        samples.append(
            Sample(timestamp: timestamp, residentBytes: consumer.residentBytes)
        )
        histories[consumer.name] = samples
    }

    private func evidence(for name: String) -> MemoryGrowthEvidence? {
        guard let samples = histories[name],
              samples.count >= minimumSampleCount,
              let first = samples.first,
              let last = samples.last
        else {
            return nil
        }

        let duration = last.timestamp.timeIntervalSince(first.timestamp)
        let growth = last.residentBytes - first.residentBytes
        let requiredGrowth = max(
            minimumAbsoluteGrowth,
            first.residentBytes * minimumRelativeGrowth
        )
        guard duration >= minimumDuration, growth >= requiredGrowth else {
            return nil
        }

        let deltas = zip(samples, samples.dropFirst()).map {
            $1.residentBytes - $0.residentBytes
        }
        let dropTolerance = max(
            absoluteDropTolerance,
            first.residentBytes * 0.02
        )
        let risingIntervalCount = deltas.count { $0 >= meaningfulRise }
        let nonFallingIntervalCount = deltas.count { $0 >= -dropTolerance }
        let minimumRisingIntervals = max(4, Int(ceil(Double(deltas.count) / 3)))
        let minimumNonFallingIntervals = Int(ceil(Double(deltas.count) * 0.8))
        let peak = samples.map(\.residentBytes).max() ?? last.residentBytes

        guard risingIntervalCount >= minimumRisingIntervals,
              nonFallingIntervalCount >= minimumNonFallingIntervals,
              last.residentBytes >= peak - dropTolerance
        else {
            return nil
        }

        return MemoryGrowthEvidence(
            growthBytes: growth,
            duration: duration,
            sampleCount: samples.count,
            risingIntervalCount: risingIntervalCount,
            observedIntervalCount: deltas.count
        )
    }
}
