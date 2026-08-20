import Foundation
import Observation

nonisolated enum MonitorSurface: Hashable, Sendable {
    case dashboard
    case menuBar
}

@MainActor
@Observable
final class MonitorModel {
    private(set) var machines: [MachineMonitorModel] = []
    private(set) var diskMachines: [MachineMonitorModel] = []
    let aiUsageLimits = AIUsageLimitsModel()

    /// What each model has been seen to hold before compacting. Observed as
    /// samples arrive rather than by reading transcripts, and persisted so a
    /// limit learned once survives a restart.
    private(set) var compactionThresholds = AgentCompactionThresholds(
        observed: UserDefaults.standard.dictionary(
            forKey: LittleHerdPreferences.observedCompactionThresholdsKey
        ) as? [String: Int] ?? [:]
    )

    @ObservationIgnored
    private lazy var compactionLearner = AgentCompactionLearner(
        limits: compactionThresholds
    )

    @ObservationIgnored
    private var cpuTracker = AgentCPUTracker()

    /// What each session is costing, by session id, once two readings exist.
    private(set) var agentCPU: [String: Double] = [:]

    /// When each session last compacted, by session id.
    private(set) var agentCompactedAt: [String: Date] = [:]

    /// Reads thresholds out of transcripts already on disk, once.
    ///
    /// Without this the warning is dormant on a fresh install: nothing has a
    /// threshold until a session has been *watched* compacting, which on a
    /// model holding a million tokens is days away. Merged rather than
    /// assigned, and only upward, so a threshold already measured by watching
    /// is never lowered by a hand-run compaction found in an old transcript.
    func seedCompactionThresholdsIfNeeded() async {
        let defaults = UserDefaults.standard
        guard !defaults.bool(
            forKey: LittleHerdPreferences.hasSeededCompactionThresholdsKey
        ) else {
            return
        }

        let seeded = await CompactionThresholdSeeder.scan()
        defaults.set(
            true,
            forKey: LittleHerdPreferences.hasSeededCompactionThresholdsKey
        )
        guard !seeded.isEmpty else { return }

        var merged = compactionThresholds.observed
        for (model, threshold) in seeded {
            merged[model] = max(merged[model] ?? 0, threshold)
        }
        compactionThresholds = AgentCompactionThresholds(observed: merged)
        compactionLearner = AgentCompactionLearner(limits: compactionThresholds)
        defaults.set(
            merged,
            forKey: LittleHerdPreferences.observedCompactionThresholdsKey
        )
    }

    /// Feeds a machine's sessions to the learner and keeps what it works out.
    func observeContext(of sessions: [AgentSession]) {
        for session in cpuTracker.rating(sessions, now: .now) {
            guard let percent = session.resource?.cpuPercent else { continue }
            agentCPU[session.id] = percent
        }
        let learned = compactionLearner.observe(sessions)
        agentCompactedAt = compactionLearner.compactedAt
        guard learned else { return }
        compactionThresholds = compactionLearner.limits
        UserDefaults.standard.set(
            compactionThresholds.observed,
            forKey: LittleHerdPreferences.observedCompactionThresholdsKey
        )
    }
    let taskTransfers = TaskTransferMonitorModel()
    let alerts = MachineAlertCenter()
    /// What the herd has been doing, so the interface can say whether something
    /// is getting worse rather than only what it is now.
    let history = MetricHistoryStore.makeDefault()
    var selection: DashboardSelection = .overview
    var overviewMetric: OverviewMetric = .cpu

    private struct LocalMonitor {
        let machine: MachineMonitorModel
        let sampler: MetricsSampler
    }

    private struct RemoteMonitor {
        let machine: MachineMonitorModel
        let sampler: RemoteMetricsSampler
    }

    private struct StorageMonitor {
        let machine: MachineMonitorModel
        let sampler: SMBStorageSampler
    }

    /// Kept apart from `StorageMonitor` because DSM is ordinary HTTPS: it needs
    /// none of the macOS network-volume permission the SMB path is gated behind,
    /// so it runs with the remote machines instead.
    private struct DSMMonitor {
        let machine: MachineMonitorModel
        let sampler: SynologyMetricsSampler
        /// Consulted only when signing in fails, to tell "no password saved"
        /// apart from "saved and unreadable" — the same error, opposite causes.
        let credentials: @Sendable () -> KeychainAvailability
    }

    @ObservationIgnored
    private var localMonitors: [LocalMonitor] = []

    @ObservationIgnored
    private var remoteMonitors: [RemoteMonitor] = []

    @ObservationIgnored
    private var storageMonitors: [StorageMonitor] = []

    @ObservationIgnored
    private var dsmMonitors: [DSMMonitor] = []

    @ObservationIgnored
    private var monitoringTasks: [Task<Void, Never>] = []

    @ObservationIgnored
    private var historyFlushTask: Task<Void, Never>?

    @ObservationIgnored
    private var networkStorageMonitoringTasks: [Task<Void, Never>] = []

    @ObservationIgnored
    private var networkStorageMonitoringEnabled: Bool

    @ObservationIgnored
    private var activeSurfaces: Set<MonitorSurface> = []

    /// Opt-in, and off until asked for: a monitor that interrupts you without
    /// permission gets muted.
    @ObservationIgnored
    private var alertsEnabled: Bool {
        UserDefaults.standard.bool(forKey: LittleHerdPreferences.alertsEnabledKey)
    }

    /// Called the first time a NAS's TLS certificate is seen, so the owner of
    /// the configuration store can record it for pinning.
    @ObservationIgnored
    var onCertificateDiscovered: ((MachineID, String) -> Void)?

    @ObservationIgnored
    private var configurations: [MachineConfiguration] = []

    init(
        configurations: [MachineConfiguration] = [.local()],
        networkStorageMonitoringEnabled: Bool = false
    ) {
        self.networkStorageMonitoringEnabled = networkStorageMonitoringEnabled
        rebuildMonitors(from: configurations)
    }

    var selectedMachine: MachineMonitorModel? {
        guard let machineID = selection.machineID else { return nil }
        return machines.first { $0.machine == machineID }
    }

    var overviewMachines: [MachineMonitorModel] {
        overviewMetric == .disk ? diskMachines : machines
    }

    /// Names come from the saved configuration, never from the machine's
    /// identifier. A machine the user renamed has to read the same in the menu
    /// bar as it does on the dashboard; deriving a name from the id would show
    /// two different names for one machine.
    func name(for machineID: MachineID) -> String {
        configuredMachine(machineID)?.name ?? machineID.displayName
    }

    func shortName(for machineID: MachineID) -> String {
        configuredMachine(machineID)?.shortName ?? machineID.shortName
    }

    private func configuredMachine(
        _ machineID: MachineID
    ) -> MachineMonitorModel? {
        diskMachines.first { $0.machine == machineID }
    }

    func cycleOverviewMetric() {
        overviewMetric = overviewMetric.next
    }

    func showOverview(_ metric: OverviewMetric) {
        selection = .overview
        overviewMetric = metric
    }

    /// Used by the metric picker in the header, which stays visible while a
    /// single machine is in focus: changing metric there re-lenses the machine
    /// you are looking at rather than throwing you back to the overview.
    func selectOverviewMetric(_ metric: OverviewMetric) {
        overviewMetric = metric
        if !selection.isMetricFocus {
            selection = .overview
        }
    }

    func applyConfigurations(_ configurations: [MachineConfiguration]) {
        guard !configurations.isEmpty else { return }
        let shouldRestart = !activeSurfaces.isEmpty
        stop()
        alerts.reset()
        rebuildMonitors(from: configurations)
        if selection.machineID.map({ machineID in
            !machines.contains { $0.machine == machineID }
        }) == true {
            selection = .overview
        }
        if shouldRestart { start() }
    }

    func activate(_ surface: MonitorSurface) {
        let wasInserted = activeSurfaces.insert(surface).inserted
        guard wasInserted, activeSurfaces.count == 1 else { return }
        start()
    }

    func deactivate(_ surface: MonitorSurface) {
        guard activeSurfaces.remove(surface) != nil,
              activeSurfaces.isEmpty
        else {
            return
        }
        stop()
    }

    func setNetworkStorageMonitoringEnabled(_ isEnabled: Bool) {
        guard networkStorageMonitoringEnabled != isEnabled else { return }
        networkStorageMonitoringEnabled = isEnabled

        if isEnabled {
            startNetworkStorageMonitoringIfNeeded()
        } else {
            for task in networkStorageMonitoringTasks {
                task.cancel()
            }
            networkStorageMonitoringTasks.removeAll()
            for monitor in storageMonitors {
                monitor.machine.markStopped()
            }
        }
    }

    func requestNetworkStorageAccess() async {
        for monitor in storageMonitors {
            monitor.machine.markConnecting()
            do {
                do {
                    let snapshot = try await monitor.sampler.sample()
                    monitor.machine.apply(snapshot)
                    observeContext(of: snapshot.agentSessions)
                }
            } catch {
                monitor.machine.markOffline()
            }
        }
    }

    private func rebuildMonitors(from configurations: [MachineConfiguration]) {
        self.configurations = configurations
        let models = configurations.map(MachineMonitorModel.init)
        // A machine is kept out of the CPU, memory, and AI overviews only when
        // capacity is genuinely all it can report. A NAS reached through DSM
        // reports load and memory too, so it belongs with the rest of the herd.
        machines = zip(configurations, models).compactMap { configuration, model in
            configuration.reportsFullMetrics ? model : nil
        }
        diskMachines = models
        localMonitors = []
        remoteMonitors = []
        storageMonitors = []
        dsmMonitors = []

        for (configuration, model) in zip(configurations, models) {
            switch configuration.connection {
            case .local:
                localMonitors.append(
                    LocalMonitor(machine: model, sampler: MetricsSampler())
                )
            case .ssh:
                guard let platform = configuration.remotePlatform else {
                    model.markOffline()
                    continue
                }
                remoteMonitors.append(
                    RemoteMonitor(
                        machine: model,
                        sampler: RemoteMetricsSampler(
                            host: configuration.hostname,
                            platform: platform,
                            identityFile: configuration.identityFile
                        )
                    )
                )
            case .smb:
                let names = configuration.serverNames.isEmpty
                    ? [configuration.hostname]
                    : configuration.serverNames
                storageMonitors.append(
                    StorageMonitor(
                        machine: model,
                        sampler: SMBStorageSampler(serverNames: names)
                    )
                )
            case .dsm:
                guard let endpoint = configuration.dsmEndpoint else {
                    model.markOffline(
                        .other("No DSM account set for this NAS yet.")
                    )
                    continue
                }
                let keychainAccount = KeychainSecret.account(for: endpoint)
                let machineID = configuration.id
                dsmMonitors.append(
                    DSMMonitor(
                        machine: model,
                        sampler: SynologyMetricsSampler(
                            endpoint: endpoint,
                            pinnedCertificate:
                                configuration.dsmCertificateFingerprint,
                            // Falls back to whatever the Finder has mounted, so
                            // a NAS keeps reporting capacity while DSM access is
                            // being sorted out.
                            fallbackServerNames: configuration.serverNames,
                            passwordProvider: {
                                KeychainSecret.read(account: keychainAccount)
                            },
                            onCertificateObserved: { [weak self] fingerprint in
                                Task { @MainActor in
                                    self?.recordCertificate(
                                        fingerprint,
                                        for: machineID
                                    )
                                }
                            }
                        ),
                        credentials: {
                            KeychainSecret.availability(account: keychainAccount)
                        }
                    )
                )
            }
        }
    }

    /// Records the certificate seen on a first successful connection, so every
    /// later one can be checked against it. Only ever fires when nothing is
    /// recorded yet — a change to an existing pin is refused in the trust
    /// evaluator, never quietly accepted here.
    /// Records the readings worth remembering. Called wherever a snapshot is
    /// applied, so every machine gets history regardless of how it is sampled.
    private func recordHistory(
        for machine: MachineMonitorModel,
        from snapshot: SystemSnapshot
    ) {
        let machineID = machine.machine
        let history = history
        let machine = machine
        let readings = snapshot.readings
        let drives = snapshot.drives
        let volumes = snapshot.storageVolumes
        let timestamp = snapshot.timestamp

        Task {
            for (kind, reading) in readings {
                guard let value = reading.value else { continue }
                await history.record(
                    machine: machineID,
                    series: .metric(kind),
                    value: value,
                    at: timestamp
                )
            }
            // The number that says whether a failing drive is failing faster.
            var worstTrend: HistoryTrend?
            for drive in drives where drive.uncorrectableSectors > 0 {
                await history.record(
                    machine: machineID,
                    series: .driveSectors(driveID: drive.id),
                    value: Double(drive.uncorrectableSectors),
                    at: timestamp
                )
                // A fortnight: long enough to see a slow bleed, short enough
                // that a drive which settled months ago stops being news.
                let trend = await history.trend(
                    machine: machineID,
                    series: .driveSectors(driveID: drive.id),
                    over: 14 * 24 * 60 * 60,
                    now: timestamp
                )
                if let trend, trend.change > (worstTrend?.change ?? 0) {
                    worstTrend = trend
                }
            }
            let resolved = worstTrend
            await MainActor.run { machine.applyDriveSectorTrend(resolved) }
            for volume in volumes {
                await history.record(
                    machine: machineID,
                    series: .volumeUsedPercent(volumeID: volume.id),
                    value: volume.usedPercent,
                    at: timestamp
                )
            }
        }
    }

    private func recordCertificate(
        _ fingerprint: String,
        for machineID: MachineID
    ) {
        guard configurations.first(where: { $0.id == machineID })?
            .dsmCertificateFingerprint == nil
        else {
            return
        }
        onCertificateDiscovered?(machineID, fingerprint)
    }

    private func start() {
        guard monitoringTasks.isEmpty else { return }

        for machine in machines {
            machine.markConnecting()
        }
        for monitor in storageMonitors {
            if networkStorageMonitoringEnabled {
                monitor.machine.markConnecting()
            } else {
                monitor.machine.markStopped()
            }
        }
        monitoringTasks = localMonitors.map {
            monitorLocalMachine($0.machine, with: $0.sampler)
        } + remoteMonitors.map {
            monitorRemoteMachine($0.machine, with: $0.sampler)
        } + dsmMonitors.map {
            monitorDSMMachine(
                $0.machine,
                with: $0.sampler,
                credentials: $0.credentials
            )
        }
        startNetworkStorageMonitoringIfNeeded()
        aiUsageLimits.start()
        taskTransfers.start()
        startHistoryFlushing()
    }

    /// Writes history to disk once a minute rather than on every sample.
    ///
    /// The file is rewritten whole, so this should not run six times a minute —
    /// but it cannot be left to shutdown either: quitting does not reliably
    /// reach this object, and a fire-and-forget write loses the race with
    /// process exit. A minute bounds what a crash or a force-quit can cost.
    private func startHistoryFlushing() {
        guard historyFlushTask == nil else { return }
        historyFlushTask = Task { [history] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if Task.isCancelled { return }
                await history.flush()
            }
        }
    }

    private func stop() {
        historyFlushTask?.cancel()
        historyFlushTask = nil
        Task { [history] in await history.flush() }
        for task in monitoringTasks {
            task.cancel()
        }
        monitoringTasks.removeAll()
        for task in networkStorageMonitoringTasks {
            task.cancel()
        }
        networkStorageMonitoringTasks.removeAll()
        aiUsageLimits.stop()
        taskTransfers.stop()
        for machine in diskMachines {
            machine.markStopped()
        }
    }

    private func startNetworkStorageMonitoringIfNeeded() {
        guard networkStorageMonitoringEnabled,
              !activeSurfaces.isEmpty,
              networkStorageMonitoringTasks.isEmpty
        else {
            return
        }

        for monitor in storageMonitors {
            monitor.machine.markConnecting()
        }
        networkStorageMonitoringTasks = storageMonitors.map {
            monitorSMBStorage($0.machine, with: $0.sampler)
        }
    }

    private func monitorLocalMachine(
        _ machine: MachineMonitorModel,
        with sampler: MetricsSampler
    ) -> Task<Void, Never> {
        Task { [machine, sampler] in
            await sampler.prime()

            do {
                try await Task.sleep(for: .milliseconds(450))
            } catch {
                return
            }

            while !Task.isCancelled {
                let snapshot = await sampler.sample()
                machine.apply(snapshot)
                observeContext(of: snapshot.agentSessions)
                recordHistory(for: machine, from: snapshot)
                alerts.evaluate(machine, isEnabled: alertsEnabled)

                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    return
                }
            }
        }
    }

    private func monitorRemoteMachine(
        _ machine: MachineMonitorModel,
        with sampler: RemoteMetricsSampler
    ) -> Task<Void, Never> {
        Task { [machine, sampler] in
            let clock = ContinuousClock()
            var isStarting = true

            while !Task.isCancelled {
                let startedAt = clock.now
                do {
                    let snapshot = try await sampler.sample()
                    machine.apply(snapshot)
                    observeContext(of: snapshot.agentSessions)
                observeContext(of: snapshot.agentSessions)
                    recordHistory(for: machine, from: snapshot)
                } catch {
                    machine.markOffline(RemoteUnavailability.classify(error))
                }
                alerts.evaluate(machine, isEnabled: alertsEnabled)

                // Wait out whatever is left of the interval rather than a fixed
                // amount on top of it, because how long a sample takes now
                // depends on the machine. A remote Mac has no CPU counter a
                // shell can read, so it measures by watching for the whole
                // interval and has already spent it by the time it answers;
                // Linux differences two counter readings and returns at once.
                // Pacing on elapsed time serves both, and a machine that has
                // stopped answering waits out the remainder instead of being
                // retried as fast as it can fail.
                //
                // Linux CPU and all remote network rates need two readings, so
                // the first interval is short and those rows fill in quickly.
                let target = isStarting
                    ? .seconds(1)
                    : RemoteMetricsSampler.samplingInterval
                isStarting = false

                let remaining = target - startedAt.duration(to: clock.now)
                guard remaining > .zero else { continue }
                do {
                    try await Task.sleep(for: remaining)
                } catch {
                    return
                }
            }
        }
    }

    /// Unlike the SMB loop, this evaluates alerts: a NAS filling up or losing a
    /// drive is exactly the kind of thing worth interrupting someone for, and it
    /// was the one machine that could never raise one.
    private func monitorDSMMachine(
        _ machine: MachineMonitorModel,
        with sampler: SynologyMetricsSampler,
        credentials: @escaping @Sendable () -> KeychainAvailability
    ) -> Task<Void, Never> {
        Task { [machine, sampler] in
            while !Task.isCancelled {
                do {
                    let snapshot = try await sampler.sample()
                    machine.apply(snapshot)
                    observeContext(of: snapshot.agentSessions)
                observeContext(of: snapshot.agentSessions)
                    recordHistory(for: machine, from: snapshot)
                } catch let error as SynologyDSMError {
                    // Asked only on the way to reporting a failure, so the
                    // keychain is not touched while everything is working.
                    machine.markOffline(
                        .classify(dsm: error, credentials: credentials())
                    )
                } catch {
                    machine.markOffline()
                }
                // Evaluated whether or not alerts are enabled: the center tracks
                // transitions, so skipping the call while muted would make the
                // next unmuted sample look like a fresh alert.
                alerts.evaluate(machine, isEnabled: alertsEnabled)

                do {
                    try await Task.sleep(for: .seconds(10))
                } catch {
                    return
                }
            }
        }
    }

    private func monitorSMBStorage(
        _ machine: MachineMonitorModel,
        with sampler: SMBStorageSampler
    ) -> Task<Void, Never> {
        Task { [machine, sampler] in
            while !Task.isCancelled {
                do {
                    let snapshot = try await sampler.sample()
                    machine.apply(snapshot)
                    observeContext(of: snapshot.agentSessions)
                observeContext(of: snapshot.agentSessions)
                    recordHistory(for: machine, from: snapshot)
                } catch SMBStorageMonitorError.noMountedShares {
                    // "Unavailable" on its own reads as a broken NAS. Nothing
                    // being mounted is a different situation with a different
                    // fix, and the machine may be perfectly healthy.
                    machine.markOffline(
                        .other(
                            "No shared folder from this server is mounted. Open it in the Finder, or connect to DSM to read it without a mount."
                        )
                    )
                } catch {
                    machine.markOffline()
                }

                do {
                    try await Task.sleep(for: .seconds(10))
                } catch {
                    return
                }
            }
        }
    }
}

nonisolated enum SMBStorageMonitorError: Error, Sendable {
    case noMountedShares
}

actor SMBStorageSampler {
    private struct MountedShare: Sendable {
        let name: String
        let mountPath: String
        let totalBytes: Double
        let availableBytes: Double
        let volumeIdentifier: String?
    }

    private let serverNames: Set<String>
    private static let resourceKeys: Set<URLResourceKey> = [
        .volumeNameKey,
        .volumeTotalCapacityKey,
        .volumeAvailableCapacityKey,
        .volumeURLForRemountingKey,
        .volumeUUIDStringKey,
    ]

    init(serverNames: [String]) {
        self.serverNames = Set(serverNames.map { $0.lowercased() })
    }

    func sample() async throws -> SystemSnapshot {
        // Enumerating mounted volumes, and reading their capacities, blocks for
        // the full SMB timeout when a share is unreachable. Keep that off the
        // cooperative pool so one stalled mount cannot starve the whole app.
        let serverNames = serverNames
        let shares = await Task.detached(priority: .utility) {
            Self.mountedShares(matching: serverNames)
        }.value

        guard !shares.isEmpty else {
            throw SMBStorageMonitorError.noMountedShares
        }

        let groups = Dictionary(grouping: shares) { share in
            share.volumeIdentifier ?? "capacity:\(Int64(share.totalBytes))"
        }
        let storageVolumes = groups.sorted { $0.key < $1.key }.compactMap {
            groupKey, group -> StorageVolume? in
            guard let first = group.first else { return nil }
            let totalBytes = group.map(\.totalBytes).max() ?? first.totalBytes
            let availableBytes = group.map(\.availableBytes).min()
                ?? first.availableBytes
            let name = group.count > 1 ? "Synology" : first.name
            return StorageVolume(
                id: "smb:\(groupKey)",
                name: name,
                mountPath: group.map(\.mountPath).sorted().joined(separator: ", "),
                availableBytes: availableBytes,
                totalBytes: totalBytes,
                volumeCount: group.count
            )
        }

        let totalBytes = storageVolumes.reduce(0) { $0 + $1.totalBytes }
        let availableBytes = storageVolumes.reduce(0) { $0 + $1.availableBytes }
        let usedPercent = totalBytes > 0
            ? (totalBytes - availableBytes) / totalBytes * 100
            : 0

        return SystemSnapshot(
            timestamp: .now,
            readings: [
                .disk: MetricReading(
                    value: min(max(usedPercent, 0), 100),
                    auxiliaryValue: availableBytes,
                    capacity: totalBytes
                ),
            ],
            storageVolumes: storageVolumes
        )
    }

    private static func mountedShares(
        matching serverNames: Set<String>
    ) -> [MountedShare] {
        let mountedURLs = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(resourceKeys),
            options: [.skipHiddenVolumes]
        ) ?? []

        return mountedURLs.compactMap {
            mountedShare(at: $0, matching: serverNames)
        }
    }

    private static func mountedShare(
        at mountedURL: URL,
        matching serverNames: Set<String>
    ) -> MountedShare? {
        guard let values = try? mountedURL.resourceValues(forKeys: resourceKeys),
              let remountURL = values.volumeURLForRemounting,
              remountURL.scheme?.lowercased() == "smb",
              let host = remountURL.host?.lowercased(),
              serverNames.contains(host),
              let totalCapacity = values.volumeTotalCapacity,
              let availableCapacity = values.volumeAvailableCapacity,
              totalCapacity > 0
        else {
            return nil
        }

        return MountedShare(
            name: values.volumeName ?? remountURL.lastPathComponent,
            mountPath: mountedURL.path,
            totalBytes: Double(totalCapacity),
            availableBytes: Double(min(availableCapacity, totalCapacity)),
            volumeIdentifier: values.volumeUUIDString
        )
    }
}
