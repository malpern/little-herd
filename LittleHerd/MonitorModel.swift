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
    let taskTransfers = TaskTransferMonitorModel()
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

    @ObservationIgnored
    private var localMonitors: [LocalMonitor] = []

    @ObservationIgnored
    private var remoteMonitors: [RemoteMonitor] = []

    @ObservationIgnored
    private var storageMonitors: [StorageMonitor] = []

    @ObservationIgnored
    private var monitoringTasks: [Task<Void, Never>] = []

    @ObservationIgnored
    private var networkStorageMonitoringTasks: [Task<Void, Never>] = []

    @ObservationIgnored
    private var networkStorageMonitoringEnabled: Bool

    @ObservationIgnored
    private var activeSurfaces: Set<MonitorSurface> = []

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

    func cycleOverviewMetric() {
        overviewMetric = overviewMetric.next
    }

    func showOverview(_ metric: OverviewMetric) {
        selection = .overview
        overviewMetric = metric
    }

    func applyConfigurations(_ configurations: [MachineConfiguration]) {
        guard !configurations.isEmpty else { return }
        let shouldRestart = !activeSurfaces.isEmpty
        stop()
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
                monitor.machine.apply(try await monitor.sampler.sample())
            } catch {
                monitor.machine.markOffline()
            }
        }
    }

    private func rebuildMonitors(from configurations: [MachineConfiguration]) {
        let models = configurations.map(MachineMonitorModel.init)
        machines = zip(configurations, models).compactMap { configuration, model in
            configuration.isStorage ? nil : model
        }
        diskMachines = models
        localMonitors = []
        remoteMonitors = []
        storageMonitors = []

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
            }
        }
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
        }
        startNetworkStorageMonitoringIfNeeded()
        aiUsageLimits.start()
        taskTransfers.start()
    }

    private func stop() {
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
            var isStarting = true

            while !Task.isCancelled {
                do {
                    let snapshot = try await sampler.sample()
                    machine.apply(snapshot)
                } catch {
                    machine.markOffline()
                }

                do {
                    // Linux CPU and all remote network rates need two counter
                    // readings. Take one extra startup sample so those rows fill
                    // in quickly, then settle into the low-overhead cadence.
                    try await Task.sleep(for: .seconds(isStarting ? 1 : 10))
                    isStarting = false
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
                    machine.apply(try await sampler.sample())
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
                totalBytes: totalBytes
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
