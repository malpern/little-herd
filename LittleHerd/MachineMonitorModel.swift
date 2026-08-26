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
    /// Enough to reach this machine the same way its metrics are reached, so a
    /// folder scan cannot drift from how the machine is otherwise contacted.
    let identityFile: String?
    let remotePlatform: RemotePlatform?
    let cpu: MetricModel
    let memory: MetricModel
    let metrics: [MetricModel]
    private(set) var state: MonitorConnectionState = .connecting
    private(set) var lastUpdated: Date?
    private(set) var activities: [MachineActivity] = []
    private(set) var agentSessions: [AgentSession] = []
    private(set) var storageVolumes: [StorageVolume] = []
    /// What this account last said it can run and which repositories it has.
    /// Nil until the probe has answered, which is why it is not an empty
    /// report: never asked and asked-and-empty read the same otherwise.
    private(set) var destinationReport: DestinationReport?
    /// Whether a session may be moved onto this account. A choice, kept here
    /// so the interface can set it against what the account can actually do.
    private(set) var mayHostSessions: Bool
    /// How the failing drive's sector count has moved, when there is enough
    /// history to say. The number that turns "229 bad sectors" into a decision:
    /// 229 accumulated over years is a different situation from 229 since
    /// Tuesday, and the count alone cannot tell them apart.
    private(set) var driveSectorTrend: HistoryTrend?

    func applyDriveSectorTrend(_ trend: HistoryTrend?) {
        driveSectorTrend = trend
    }

    /// Physical drives, for machines that can report them. A NAS is the only one
    /// that does, and a failing drive there is the most consequential thing
    /// Little Herd can notice.
    private(set) var drives: [SynologyDrive] = []
    private(set) var memoryPressure: MemoryPressureLevel?
    /// Logical cores, once the machine has said. Used to express a process's
    /// share of one core as a share of the whole machine.
    private(set) var coreCount: Int?
    private(set) var memoryConsumers: [MemoryConsumer] = []
    /// What kind of machine this is. Kept because a pressure verdict means a
    /// different thing on each: a Mac's comes from the kernel, everything
    /// else's is estimated here from how much memory is free.
    let platform: MachinePlatform
    /// What this account's agent last said when asked to prove it can sign
    /// in. Not sampled — see `AgentAuthVerifier` for why a monitor must not
    /// spend the budget it is reporting on.
    private(set) var agentAuth: AgentAuthState = .unverified
    private(set) var isVerifyingAgent = false
    private(set) var swap: SwapUsage?
    /// Swap written across the watched window, when enough of one exists.
    private(set) var swapGrowth: SwapGrowth?
    /// Why the machine is unreachable, when it is. Kept beside `state` so the
    /// interface can say more than "Unavailable".
    private(set) var unavailability: RemoteUnavailability?
    /// Consecutive samples that have failed.
    ///
    /// One failure is not an outage. This Mac is a laptop: it sleeps, wakes,
    /// and changes networks, and the first sample after waking can easily fail
    /// before the network is up. Reporting that as a machine going down —
    /// with a notification, and another when it "came back" a few seconds
    /// later — is the monitor crying wolf about its own laptop.
    private(set) var consecutiveFailures = 0

    @ObservationIgnored
    private var memoryGrowthDetector = MemoryGrowthDetector()
    private var swapTrend = SwapTrend()

    var id: MachineID { machine }

    init(configuration: MachineConfiguration) {
        let cpu = MetricModel(kind: .cpu)
        let memory = MetricModel(kind: .memory)
        machine = configuration.id
        name = configuration.name
        shortName = configuration.shortName
        hostname = configuration.hostname
        platform = configuration.platform
        symbolName = configuration.platform.symbolName
        avatar = configuration.avatar
        supportsGPU = configuration.supportsGPU
        isStorage = configuration.isStorage
        isLocal = configuration.connection == .local
        mayHostSessions = configuration.mayHostSessions
        identityFile = configuration.identityFile
        remotePlatform = configuration.remotePlatform
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
        // Kept across samples: the probe runs every thirty seconds and the
        // metrics every few, so most samples carry nothing here and blanking
        // it would make the destination flicker between measured and unknown.
        destinationReport = snapshot.destination ?? destinationReport
        drives = snapshot.drives
        memoryPressure = snapshot.memoryPressure
        // Kept across samples: a machine's core count does not change, and a
        // sample that omits it should not blank the figure.
        coreCount = snapshot.coreCount ?? coreCount
        memoryConsumers = memoryGrowthDetector.annotate(
            consumers: snapshot.memoryConsumers,
            at: snapshot.timestamp
        )
        swap = snapshot.swap
        swapGrowth = swapTrend.record(snapshot.swap, at: snapshot.timestamp)
        lastUpdated = snapshot.timestamp
        state = .live
        unavailability = nil
        // One good answer settles it. Coming back needs no confirming: the
        // machine is demonstrably there.
        consecutiveFailures = 0
    }

    /// How to measure folder sizes here, and why it cannot be done when it
    /// cannot. A remote machine's commands run under sshd, which already has
    /// the access; this Mac has to be granted it, and a NAS cannot answer at
    /// all.
    var folderScanning: FolderScanAvailability {
        if isLocal {
            return FullDiskAccess.isGranted
                ? .available(FolderSizeScanner(location: .local))
                : .needsFullDiskAccess
        }
        guard let remotePlatform, !isStorage else { return .unsupported }
        return .available(
            FolderSizeScanner(
                location: .ssh(
                    host: hostname,
                    identityFile: identityFile,
                    platform: remotePlatform
                )
            )
        )
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
        consecutiveFailures += 1
        state = .offline
        unavailability = reason
        agentSessions = agentSessions.map { $0.waitingIfActive() }
    }

    /// Changes only the choice, leaving every measurement in place.
    ///
    /// A preference is not a reason to tear the herd's monitors down and put
    /// them back up: doing that on a toggle would blank the dashboard and
    /// throw away the readings the toggle is meant to be judged against.
    func setMayHostSessions(_ mayHost: Bool) {
        mayHostSessions = mayHost
    }

    /// Whether this account could take a session, and if not, which of the
    /// three unrelated reasons applies.
    ///
    /// - Parameter repository: the slug of the repository the work is in, when
    ///   the question is about particular work. Nil asks about the account
    ///   alone, which is what Settings can answer.
    func destinationEligibility(
        forRepository repository: String? = nil
    ) -> DestinationEligibility {
        DestinationEligibility.resolve(
            report: destinationReport,
            repository: repository,
            isAllowed: mayHostSessions
        )
    }

    /// This account as the destination question sees it: a name, a choice, and
    /// what it last reported about itself.
    var destinationAccount: DestinationAccount {
        DestinationAccount(
            machine: machine,
            name: shortName,
            symbolName: symbolName,
            report: destinationReport,
            mayHostSessions: mayHostSessions,
            auth: agentAuth,
            isVerifying: isVerifyingAgent
        )
    }

    /// Ask this account's agent to answer, and remember what it said.
    ///
    /// Deliberately only ever called from a press. It costs a model call, and
    /// the answer decays — an account that answered an hour ago may not now,
    /// which was measured on the linux box in the space of that hour.
    func verifyAgentAuthentication() async {
        guard !isVerifyingAgent,
              let install = destinationReport?.bestInstallation
        else { return }

        isVerifyingAgent = true
        defer { isVerifyingAgent = false }

        agentAuth = await AgentAuthVerifier.verify(
            install: install,
            isLocal: isLocal,
            host: hostname,
            identityFile: identityFile
        )
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

    /// The same sentence with what the count has done recently, when history
    /// has enough to say so.
    func summary(trend: HistoryTrend?) -> String {
        guard let trend, trend.isMeaningful, trend.change > 0 else {
            return summary
        }
        let days = max(Int((trend.duration / 86_400).rounded()), 1)
        let window = days == 1 ? "today" : "in \(days) days"
        return "\(summary), up \(Int(trend.change)) \(window)"
    }
}

/// Watches swap the way `MemoryGrowthDetector` watches a process: for the
/// direction, not the level.
///
/// The level is nearly useless on its own here — macOS never reclaims swap
/// eagerly, so the figure is a high-water mark of every busy hour the machine
/// has ever had. Growth across a window is what says the machine is paying for
/// memory pressure *now*.
///
/// Reports nothing far more often than it reports something, and that is
/// correct: most of the time a machine is not actively swapping, and a line
/// that is always present is a line nobody reads.
nonisolated struct SwapTrend: Sendable {
    private struct Sample: Sendable {
        let date: Date
        let usedBytes: Double
    }

    private var samples: [Sample] = []

    /// Long enough that one sample landing mid-write is not a trend.
    private let minimumDuration: TimeInterval = 60
    private let maximumDuration: TimeInterval = 5 * 60
    /// Below this the machine is trickling rather than thrashing, and saying
    /// so would put a number in front of someone for no decision.
    private let minimumGrowth = 64 * 1_024 * 1_024.0

    mutating func record(_ usage: SwapUsage?, at timestamp: Date) -> SwapGrowth? {
        guard let usage, usage.isConfigured else {
            samples.removeAll()
            return nil
        }

        samples.removeAll {
            $0.date < timestamp.addingTimeInterval(-maximumDuration)
        }
        samples.append(Sample(date: timestamp, usedBytes: usage.usedBytes))

        guard let oldest = samples.first, let newest = samples.last else {
            return nil
        }
        let duration = oldest.date.distance(to: newest.date)
        guard duration >= minimumDuration else { return nil }

        let growth = newest.usedBytes - oldest.usedBytes
        guard growth >= minimumGrowth else { return nil }
        return SwapGrowth(bytes: growth, duration: duration)
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
