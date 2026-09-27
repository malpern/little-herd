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

    /// The code a phone has to be told, as a person reads it: `XXXX-XXXX`.
    ///
    /// Made once and kept in defaults, not the Keychain — this is a "were you
    /// told" check on a private network, not a credential, and a Keychain read
    /// is a prompt this menu-bar app has been careful never to raise. Kept in
    /// the same domain as the switch that starts the server, so nominating a
    /// different Mac gives a different code by construction.
    var pairingCode: String {
        HerdWire.Pairing.display(storedPairingCode())
    }

    /// A new code. The phone will ask for it again, which is the point.
    func regeneratePairingCode() {
        let code = HerdWire.Pairing.generate()
        defaults.set(code, forKey: LittleHerdPreferences.herdPairingCodeKey)
        server?.pairingCode = code
        // The code salts every paired phone's key, so none of them could sign
        // after this anyway; forgetting them says so rather than leaving
        // entries that can never work.
        devices.removeAll()
    }

    /// Phones that may move sessions, and send pushes to.
    @ObservationIgnored let devices: HerdDeviceStore
    @ObservationIgnored private let gate = HerdWriteGate()
    @ObservationIgnored let push: HerdPushRelay

    var pairedDeviceNames: [String] { devices.devices.map(\.name) }

    private func storedPairingCode() -> String {
        if let stored = defaults.string(forKey: LittleHerdPreferences.herdPairingCodeKey),
           !HerdWire.Pairing.normalize(stored).isEmpty
        {
            return stored
        }
        let code = HerdWire.Pairing.generate()
        defaults.set(code, forKey: LittleHerdPreferences.herdPairingCodeKey)
        return code
    }

    init(
        model: MonitorModel,
        watcherName: String = Host.current().localizedName ?? "Little Herd",
        defaults: UserDefaults = .standard
    ) {
        self.model = model
        self.watcherName = watcherName
        self.defaults = defaults
        devices = HerdDeviceStore(defaults: defaults)
        push = HerdPushRelay(devices: devices, defaults: defaults)
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
            let server = HerdServer(
                watcherName: watcherName,
                pairingCode: storedPairingCode()
            ) { [model, watcherName] in
                model.wireSnapshot(watcherName: watcherName, acceptsWrites: true)
            }
            server.writes = HerdWrites(
                pair: { [devices, weak server] request in
                    try devices.pair(request, pairingCode: server?.pairingCode ?? "")
                },
                verify: { [gate, devices] request in
                    gate.verify(request, keys: devices.key(for:))
                },
                move: { [model] request in model.remoteMove(request) },
                registerPush: { [devices] registration, deviceID in
                    devices.setPush(registration, for: deviceID)
                }
            )
            self.server = server
            HerdPushRelay.shared = push
            // A watcher may never have its dashboard opened, and the
            // dashboard is what switches network storage on. Serving is
            // reason enough, once the person has been through the
            // one-time volume permission.
            if defaults.bool(forKey: LittleHerdPreferences.networkVolumeAccessOnboardingCompletedKey) {
                model.setNetworkStorageMonitoringEnabled(true)
            }
            model.activate(.watcher)
            server.start(port: configuredPort)
        } else if !shouldServe, let server {
            server.stop()
            self.server = nil
            HerdPushRelay.shared = nil
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
    func wireSnapshot(
        watcherName: String,
        now: Date = .now,
        acceptsWrites: Bool = false
    ) -> HerdWire.Snapshot {
        let herd = machines.map(\.destinationAccount)
        // A machine that is not answering cannot take work, whatever its
        // checkouts say. Offering it lets a phone start a move that can only
        // fail once it runs.
        let reachable = Set(machines.filter { $0.state == .live }.map(\.machine))
        let requiresApproval = UserDefaults.standard
            .bool(forKey: LittleHerdPreferences.requiresDestinationApprovalKey)
        return HerdWire.Snapshot(
            watcher: watcherName,
            generatedAt: now,
            // `diskMachines` is the whole herd; `machines` leaves out storage
            // that reports only capacity. The phone draws a NAS on the Disk
            // lens, so it needs the whole herd and filters for itself.
            machines: diskMachines.map {
                $0.wireMachine(
                    now: now,
                    herd: acceptsWrites ? herd : nil,
                    reachable: reachable,
                    requiresApproval: requiresApproval
                )
            },
            transfers: wireTransfers,
            alerts: diskMachines.flatMap { machine in
                MachineAlert.active(for: machine)
                    .sorted { $0.rawValue < $1.rawValue }
                    .map { alert in
                        HerdWire.Alert(
                            id: "\(machine.machine.rawValue):\(alert.rawValue)",
                            machine: machine.machine.rawValue,
                            kind: alert.rawValue,
                            title: alert.title(machine: machine.name),
                            body: MachineAlertCenter.body(for: alert, machine)
                        )
                    }
            },
            acceptsWrites: acceptsWrites
        )
    }

    /// Transfers the dashboard's strip would show, newest first.
    private var wireTransfers: [HerdWire.Transfer] {
        transfers.order.reversed().compactMap { transfer in
            guard let phase = transfers.phase(for: transfer) else { return nil }
            let (name, detail): (String, String?) = switch phase {
            case .fixing(let machine): ("fixing", "Setting up \(machine)")
            case .preparing: ("preparing", "Writing down where it got to")
            case .running(let purpose): ("running", Self.wireDetail(purpose))
            case .finished(let outcome):
                outcome.result == .landed
                    ? ("landed", nil)
                    : ("failed", outcome.output.isEmpty ? nil : outcome.output)
            }
            return HerdWire.Transfer(
                id: transfer.branch,
                title: transfer.title,
                origin: transfer.origin.rawValue,
                destination: transfer.destination.rawValue,
                phase: name,
                progress: phase.progress,
                detail: detail
            )
        }
    }

    private static func wireDetail(_ purpose: SuccessorRun.Step.Purpose) -> String {
        switch purpose {
        case .worktree: "Making a worktree"
        case .prompt: "Handing over the brief"
        case .agent: "The agent is working"
        case .verification: "Running the checks"
        case .delivery: "Pushing the result"
        case .cleanup: "Tidying up"
        }
    }
}

extension MachineMonitorModel {
    /// - Parameter herd: every machine's destination account, when the watcher
    ///   accepts moves; nil leaves `move` off every session.
    func wireMachine(
        now: Date,
        herd: [DestinationAccount]? = nil,
        reachable: Set<MachineID> = [],
        requiresApproval: Bool = false
    ) -> HerdWire.Machine {
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
                    model: session.model,
                    move: herd.map {
                        wireMove(for: session, in: $0, reachable: reachable, requiresApproval: requiresApproval)
                    }
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

    /// The verdict the dashboard would reach for a drag of this session.
    private func wireMove(
        for session: AgentSession,
        in herd: [DestinationAccount],
        reachable: Set<MachineID>,
        requiresApproval: Bool
    ) -> HerdWire.Move {
        let verdict = TransferEligibility.verdict(
            for: session,
            hasRepository: session.workingDirectory != nil
        )
        let carrying = MachineAgentActivity(provider: session.provider, sessions: [session])
        let destinations: [HerdWire.Destination] = herd.compactMap { account in
            guard account.machine != machine, reachable.contains(account.machine) else { return nil }
            switch AgentDropEligibility.disposition(
                of: account.machine,
                carrying: carrying,
                from: machine,
                in: herd,
                requiresApproval: requiresApproval
            ) {
            case .ready: return HerdWire.Destination(machine: account.machine.rawValue, disposition: "ready")
            case .fixable: return HerdWire.Destination(machine: account.machine.rawValue, disposition: "fixable")
            case .refuse: return nil
            }
        }
        switch verdict {
        case .ready:
            return HerdWire.Move(verdict: "ready", reason: nil, destinations: destinations)
        case .afterItFinishes:
            return HerdWire.Move(verdict: "afterItFinishes", reason: nil, destinations: destinations)
        case .refused(let refusal):
            return HerdWire.Move(
                verdict: "refused",
                reason: TransferEligibility.explanation(for: refusal),
                destinations: []
            )
        }
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
