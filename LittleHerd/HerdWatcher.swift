import Foundation
import Observation

/// Serving the herd while this Mac is its watcher.
///
/// **One switch, one job.** "This Mac watches the herd continuously" already
/// means "this is the Mac that stays awake and pays attention"; a phone that
/// wants to see the herd needs exactly that Mac. So turning the watcher on is
/// what starts the server, and turning it off stops it. There is no separate
/// "share with my phone" switch, because a second switch would be a second
/// thing to get wrong on each Mac, and item 18's whole open problem is that
/// there are already too many of those.
///
/// **A watcher samples with no window open.** Monitoring runs only while a
/// surface — the dashboard or the menu bar — is active, which is right for a
/// laptop and wrong for a Mac nobody is sitting at: a watcher with its window
/// closed was watching nothing. Reading the code for the server made that
/// plain, and the fix is that the server is a surface too. It was always the
/// case that a nominated watcher with no window open alerted on nothing;
/// this is the first build in which that is not so.
@MainActor
@Observable
final class HerdWatcher {
    private(set) var server: HerdServer?
    let watcherName: String
    @ObservationIgnored private let model: MonitorModel
    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?
    @ObservationIgnored private let defaults: UserDefaults

    var isServing: Bool { server?.isListening == true }
    var port: UInt16? { server?.port }
    var lastError: String? { server?.lastError }
    var advertisingError: String? { server?.advertisingError }
    var requestsAnswered: Int { server?.requestsAnswered ?? 0 }

    init(
        model: MonitorModel,
        watcherName: String = Host.current().localizedName ?? "Little Herd",
        defaults: UserDefaults = .standard
    ) {
        self.model = model
        self.watcherName = watcherName
        self.defaults = defaults
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reconcile() }
        }
        reconcile()
    }

    /// Whether the switch in Settings says this Mac is on duty.
    var shouldServe: Bool {
        defaults.bool(forKey: LittleHerdPreferences.watchesHerdKey)
    }

    /// Brings the server into line with the switch. Idempotent, and called on
    /// every defaults change because there is no cheaper way to hear one key.
    func reconcile() {
        if shouldServe, server == nil {
            let server = HerdServer(watcherName: watcherName) { [model, watcherName] in
                model.wireSnapshot(watcherName: watcherName)
            }
            self.server = server
            model.activate(.watcher)
            server.start(port: configuredPort)
        } else if !shouldServe, let server {
            server.stop()
            self.server = nil
            model.deactivate(.watcher)
        }
    }

    /// A port other than the default, if someone set one with
    /// `defaults write com.malpern.LittleHerd herdServerPort -int N`.
    private var configuredPort: UInt16 {
        let stored = defaults.integer(forKey: LittleHerdPreferences.herdServerPortKey)
        guard stored > 0, stored <= Int(UInt16.max) else { return HerdWire.defaultPort }
        return UInt16(stored)
    }
}

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
            machines: machines.map { $0.wireMachine(now: now) }
        )
    }
}

extension MachineMonitorModel {
    func wireMachine(now: Date) -> HerdWire.Machine {
        let diskMetric = metrics.first(where: { $0.kind == .disk })?.value
        return HerdWire.Machine(
            id: machine.rawValue,
            name: name,
            shortName: shortName,
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
            }
        )
    }

    private static func wireName(_ pressure: MemoryPressureLevel) -> String {
        switch pressure {
        case .normal: "normal"
        case .warning: "warning"
        case .critical: "critical"
        }
    }
}
