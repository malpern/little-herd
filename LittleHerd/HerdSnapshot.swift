import Foundation

extension MonitorModel {
    /// The herd as the dashboard would draw it, flattened for a phone.
    ///
    /// Every figure here is the one the menu bar already computes for the same
    /// machine — `menuBarSnapshot` is the precedent — so the phone cannot say
    /// something the Mac would not.
    func wireSnapshot(watcherName: String, now: Date = .now) -> HerdWire.Snapshot {
        HerdWire.Snapshot(
            watcher: watcherName,
            generatedAt: now,
            // `diskMachines` is the whole herd; `machines` leaves out storage
            // that reports only capacity. The phone draws a NAS on the Disk
            // lens, so it needs the whole herd and filters for itself.
            machines: diskMachines.map { $0.wireMachine(now: now) },
            // This watcher delivers alerts itself. Omitting the polling alerts
            // keeps an open iPhone from posting a second local notification.
            acceptsWrites: true
        )
    }
}

extension MachineMonitorModel {
    func wireMachine(now: Date) -> HerdWire.Machine {
        let diskMetric = metrics.first(where: { $0.kind == .disk })?.value
        return HerdWire.Machine(
            id: machine.rawValue,
            name: name,
            // `MachineConfiguration.local()` calls this Mac "This Mac", which
            // is true on this Mac and false on every phone reading it. The
            // phone gets the name instead.
            shortName: isLocal && shortName == "This Mac" ? name : shortName,
            avatar: avatar.rawValue,
            platform: platform.rawValue,
            isStorage: isStorage,
            isWatcher: isLocal,
            state: String(describing: state),
            lastUpdated: lastUpdated,
            unavailability: unavailability.map {
                String(localized: $0.detail(host: hostname))
            },
            cpuPercent: cpu.value,
            sustainedCPUPercent: SustainedLoad.average(
                of: cpu.history,
                endingAt: lastUpdated ?? now
            ),
            memoryPressure: memoryPressure.map(Self.wireName),
            memoryUsedBytes: memory.auxiliaryValue,
            memoryTotalBytes: memory.capacity,
            diskUsedPercent: storageVolumes.map(\.usedPercent).max() ?? diskMetric,
            volumes: storageVolumes.map { volume in
                HerdWire.Volume(
                    id: volume.id,
                    name: volume.name,
                    usedBytes: volume.usedBytes,
                    totalBytes: volume.totalBytes,
                    health: volume.health?.rawValue
                )
            },
            sessions: agentSessions.map { session in
                HerdWire.Session(
                    id: session.id,
                    short: HerdCommand.shortIdentifier(session.id),
                    provider: session.provider.rawValue,
                    state: session.state.rawValue,
                    title: session.title ?? session.projectName,
                    updatedAt: session.updatedAt,
                    activity: session.activity?.phrase,
                    workingDirectory: session.workingDirectory,
                    contextTokens: session.contextTokens,
                    model: session.model
                )
            },
            cpuHistory: Self.thinned(series(for: .cpu).points),
            memoryHistory: Self.thinned(series(for: .memory).points),
            processes: state == .live
                ? activities
                    .filter { $0.cpuCores >= 0.05 }
                    .prefix(12)
                    .map { activity in
                        HerdWire.Process(
                            name: String(localized: activity.shortLabel),
                            pid: activity.processID,
                            percent: ProcessShare.percent(
                                ofOneCore: activity.cpuPercent,
                                coreCount: coreCount
                            ),
                            cores: activity.cpuCores,
                            agent: activity.agentTask.map { _ in activity.processName }
                        )
                    }
                : nil,
            memoryConsumers: state == .live
                ? memoryConsumers.prefix(12).map {
                    HerdWire.Consumer(
                        name: $0.name,
                        bytes: $0.residentBytes,
                        growingBytes: $0.growthEvidence?.growthBytes
                    )
                }
                : nil
        )
    }

    /// A few dozen points is a sparkline; the full history is a payload.
    private static func thinned(_ points: [HistoryPoint], keeping limit: Int = 48) -> [HerdWire.Point]? {
        guard !points.isEmpty else { return nil }
        let stride = max(1, Int((Double(points.count) / Double(limit)).rounded(.up)))
        var kept = Swift.stride(from: points.count - 1, through: 0, by: -stride).map { points[$0] }
        kept.reverse()
        return kept.map { HerdWire.Point(t: $0.timestamp, v: $0.value) }
    }

    private static func wireName(_ pressure: MemoryPressureLevel) -> String {
        switch pressure {
        case .normal: "normal"
        case .warning: "warning"
        case .critical: "critical"
        }
    }
}
