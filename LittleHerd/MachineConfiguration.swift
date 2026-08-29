import Foundation
import Observation

nonisolated enum MachineConnection: String, Codable, Equatable, Sendable {
    case local
    case ssh
    case smb
    /// A Synology measured through DSM's Web API. Unlike `smb`, this does not
    /// depend on the Finder having a share mounted, and it can report drive
    /// health as well as capacity.
    case dsm
}

nonisolated enum MachinePlatform: String, Codable, Equatable, Sendable {
    case macOS
    case linux
    case storage

    var symbolName: String {
        switch self {
        case .macOS: "macmini"
        case .linux: "server.rack"
        case .storage: "externaldrive.connected.to.line.below"
        }
    }
}

nonisolated struct MachineConfiguration: Codable, Equatable, Identifiable,
    Sendable
{
    let id: MachineID
    var name: String
    var shortName: String
    var hostname: String
    var hardwareSummary: String
    var platform: MachinePlatform
    var connection: MachineConnection
    var avatar: HerdwareAvatar
    var identityFile: String?

    /// The account on that host, when it is not the one `ssh` would pick.
    ///
    /// **A machine is an account on a host, not a host.** The mini has two
    /// that matter — one runs the scheduled jobs, the other is the console
    /// login — and they have different checkouts, different agents and
    /// different credentials. Treating the host as the unit made a repository
    /// that plainly exists on the mini invisible, because Little Herd was
    /// looking at the other account: a drag onto it was refused for want of a
    /// checkout that was sitting there the whole time.
    ///
    /// Kept apart from `hostname` rather than folded into it so the two can be
    /// shown separately, and so an existing configuration — which has no
    /// account recorded — keeps meaning exactly what it meant.
    var sshUser: String?
    var serverNames: [String]
    var supportsGPU: Bool
    /// DSM account name. The password lives in the keychain, never here — this
    /// struct is written to `~/Library/Preferences` in the clear.
    var dsmUsername: String?
    var dsmPort: Int?
    /// SHA-256 of the public key in the certificate DSM presented the first time
    /// Little Herd connected, recorded only when the system does not already
    /// trust that certificate. See `SynologyTrustEvaluator`.
    var dsmCertificateFingerprint: String?

    /// Whether a session may be moved onto this account.
    ///
    /// Stored as an optional so that a machine saved before this setting
    /// existed still decodes. The store reads the herd entry by entry and
    /// keeps out whatever it cannot decode, so a new non-optional key would
    /// have emptied everyone's saved herd on the first launch after an update.
    /// Measured rather than assumed: a non-optional `Bool` with a default
    /// value in its declaration *still* throws on a missing key, because
    /// Swift's synthesised decoder never consults the default.
    ///
    /// Read through `mayHostSessions`, which is the question the rest of the
    /// app asks.
    var mayHostSessionsPreference: Bool?

    /// The host the permission above was granted for.
    ///
    /// **A permission is about a machine, and `id` is not one.** The id is
    /// minted at discovery and never changes, while `hostname` is an ordinary
    /// editable field — so a herd entry can be re-pointed at a different box
    /// while carrying an approval somebody gave to the old one. Nothing about
    /// that is exotic: renaming a machine, or repurposing an entry after
    /// replacing hardware, is enough.
    ///
    /// Recording what the grant was for turns that from a silent inheritance
    /// into an expired permission, which is the safe direction: the worst case
    /// is being asked again.
    ///
    /// Optional for the same reason as the preference above — a new
    /// non-optional key empties everyone's saved herd on first launch.
    var mayHostSessionsGrantedFor: String?

    /// Intent, and only intent.
    ///
    /// Off until someone says otherwise, because the consequence of a wrong
    /// answer is not symmetric: a machine wrongly offered as a destination
    /// invites work to be moved somewhere it will fail, and a machine wrongly
    /// withheld costs one toggle. Whether the machine *could* host anything is
    /// a separate, measured question — see `DestinationEligibility`.
    ///
    /// **Reads false once the host it was granted for has changed**, and
    /// setting it records the host it is being granted for. A grant made
    /// before this existed has no host recorded and is honoured as it stands:
    /// invalidating every existing permission on upgrade would be a worse
    /// answer than trusting one the user gave.
    var mayHostSessions: Bool {
        get {
            guard mayHostSessionsPreference == true else { return false }
            guard let grantedFor = mayHostSessionsGrantedFor else { return true }
            return grantedFor == hostname
        }
        set {
            mayHostSessionsPreference = newValue
            mayHostSessionsGrantedFor = newValue ? hostname : nil
        }
    }

    var isStorage: Bool {
        connection == .smb || connection == .dsm || platform == .storage
    }

    /// Whether this machine can report more than capacity. DSM answers with CPU
    /// and memory too, so a NAS reached that way is no longer disk-only.
    var reportsFullMetrics: Bool {
        connection != .smb
    }

    var dsmEndpoint: SynologyDSMEndpoint? {
        guard connection == .dsm, let dsmUsername, !dsmUsername.isEmpty else {
            return nil
        }
        return SynologyDSMEndpoint(
            host: hostname,
            port: dsmPort ?? SynologyDSM.defaultPort,
            username: dsmUsername
        )
    }

    var remotePlatform: RemotePlatform? {
        switch platform {
        case .macOS: .macOS
        case .linux: .linux
        case .storage: nil
        }
    }

    /// What `ssh` should be given: the account and the host together, or just
    /// the host when no account is recorded.
    ///
    /// Composed here rather than at each call site, because there are several
    /// and one of them forgetting is a machine that is sampled as the wrong
    /// account without saying so.
    var sshDestination: String {
        guard let user = sshUser?.trimmingCharacters(in: .whitespaces),
              !user.isEmpty
        else { return hostname }
        return "\(user)@\(hostname)"
    }

    static func local(
        computerName: String = Host.current().localizedName ?? "This Mac"
    ) -> Self {
        Self(
            id: MachineID("local"),
            name: computerName,
            shortName: "This Mac",
            hostname: "localhost",
            hardwareSummary: "This Mac",
            platform: .macOS,
            connection: .local,
            avatar: inferredAvatar(name: computerName, platform: .macOS),
            identityFile: nil,
            serverNames: [],
            supportsGPU: true
        )
    }

    static func inferredAvatar(
        name: String,
        platform: MachinePlatform
    ) -> HerdwareAvatar {
        let normalized = name.lowercased()
        if platform == .storage { return .pigletNAS }
        if platform == .linux {
            return normalized.contains("gpu") ? .oxGPU : .rabbitNUC
        }
        if normalized.contains("macbook") || normalized.contains("laptop") {
            return .chickLaptop
        }
        if normalized.contains("studio") { return .lambStudio }
        if normalized.contains("mini") { return .calfMini }
        if normalized.contains("imac") { return .duckAllInOne }
        return .roosterCoordinator
    }
}

/// Where the saved herd lives.
///
/// `UserDefaults` in the app. Tests substitute memory, so a test run leaves
/// nothing behind in the user's real preferences — several hundred stray
/// suites had accumulated there before this existed, and no amount of care in
/// the cleanup could beat cfprefsd writing the domain back out at process exit.
@MainActor
protocol MachineConfigurationStorage: AnyObject {
    func loadConfigurationData() -> Data?
    func saveConfigurationData(_ data: Data)
}

extension UserDefaults: MachineConfigurationStorage {
    public func loadConfigurationData() -> Data? {
        data(forKey: LittleHerdPreferences.machineConfigurationsKey)
    }

    public func saveConfigurationData(_ data: Data) {
        set(data, forKey: LittleHerdPreferences.machineConfigurationsKey)
    }
}

@MainActor
@Observable
final class MachineConfigurationStore {
    private(set) var machines: [MachineConfiguration]

    @ObservationIgnored
    private let storage: MachineConfigurationStorage

    /// Saved entries this build could not decode — a machine written by a newer
    /// version, most likely. Carried through untouched so that running an older
    /// build, or one that predates a connection kind, does not quietly discard
    /// machines it happens not to understand.
    @ObservationIgnored
    private var unreadableEntries: [Any] = []

    convenience init(defaults: UserDefaults = .standard) {
        self.init(storage: defaults)
    }

    /// - Parameter localMachine: the Mac this is running on, used to seed an
    ///   empty store.
    ///
    ///   **Injectable because its default reads the computer's own name, and
    ///   that leaked into the tests.** `add` treats a same-named machine as a
    ///   duplicate, so on a Mac actually called "Mac mini" the fixture named
    ///   "Mac mini" was silently deduped against the seeded local machine and
    ///   two tests failed — on that machine only. They passed on a laptop
    ///   called "air" and would have passed anywhere else, which is the worst
    ///   version of the bug: green everywhere it was run, red on the one
    ///   machine it was about to matter on. Found by running the suite on the
    ///   mini during the first real transfer.
    init(
        storage: MachineConfigurationStorage,
        localMachine: MachineConfiguration = .local()
    ) {
        self.storage = storage

        guard let data = storage.loadConfigurationData() else {
            // Genuinely nothing saved: a first launch, so seed the local Mac.
            machines = [localMachine]
            persist()
            return
        }

        let (decoded, unreadable) = Self.decode(data)
        unreadableEntries = unreadable
        // The app still has to run, so fall back to the local Mac — but do not
        // write that over what is already there. Saved machines are the one
        // thing the user cannot get back by pointing Little Herd at the network
        // again: a machine reached over a VPN advertises no Bonjour service, so
        // nothing will ever rediscover it. A read that failed is not a reason to
        // destroy the thing that failed to read.
        machines = decoded.isEmpty ? [localMachine] : decoded
    }

    /// Decodes machine by machine rather than all at once.
    ///
    /// A `Codable` array fails entirely when a single element throws, so one
    /// entry written by a newer build would otherwise cost the user every
    /// machine they have configured.
    private static func decode(
        _ data: Data
    ) -> (machines: [MachineConfiguration], unreadable: [Any]) {
        guard let elements = (try? JSONSerialization.jsonObject(with: data))
            as? [Any]
        else {
            return ([], [])
        }

        let decoder = JSONDecoder()
        var machines: [MachineConfiguration] = []
        var unreadable: [Any] = []

        for element in elements {
            guard let elementData = try? JSONSerialization.data(
                withJSONObject: element
            ),
                let machine = try? decoder.decode(
                    MachineConfiguration.self,
                    from: elementData
                )
            else {
                unreadable.append(element)
                continue
            }
            machines.append(machine)
        }
        return (machines, unreadable)
    }

    func add(_ additions: [MachineConfiguration]) {
        guard !additions.isEmpty else { return }
        var updated = machines
        for addition in additions {
            if let index = updated.firstIndex(where: { $0.id == addition.id }) {
                updated[index] = addition
            } else if updated.contains(where: {
                // **The pair, not the host.** One machine is one account on
                // one host, so the mini's scheduled-jobs account and its
                // console login are two entries and must both be allowed in.
                // Matching on hostname alone kept the second one out, which
                // made the account field below unusable by anybody who tried
                // to add the machine it exists for.
                (Self.normalizedHostname($0.hostname)
                    == Self.normalizedHostname(addition.hostname)
                    && $0.sshUser == addition.sshUser)
                    || $0.name.caseInsensitiveCompare(addition.name) == .orderedSame
            }) {
                continue
            } else {
                updated.append(addition)
            }
        }
        replace(with: updated)
    }

    /// Whether a machine can be taken out of the herd. The local Mac always
    /// stays: it needs no configuration to reach, and an empty store would just
    /// be re-seeded with it on the next launch.
    func canRemove(_ machineID: MachineID) -> Bool {
        guard let machine = machines.first(where: { $0.id == machineID }) else {
            return false
        }
        return machine.connection != .local
    }

    func remove(_ machineID: MachineID) {
        guard canRemove(machineID) else { return }
        replace(with: machines.filter { $0.id != machineID })
    }

    /// Reorders the herd.
    ///
    /// The saved order is the order everywhere: the overview, the machine
    /// pages, and the menu bar all read this list in sequence, so arranging
    /// machines in Settings arranges them everywhere they appear.
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var updated = machines
        updated.move(fromOffsets: source, toOffset: destination)
        replace(with: updated)
    }

    /// Replaces one machine in place, leaving the rest of the herd untouched.
    func update(_ configuration: MachineConfiguration) {
        guard let index = machines.firstIndex(where: {
            $0.id == configuration.id
        }), machines[index] != configuration else {
            return
        }
        var updated = machines
        updated[index] = configuration
        replace(with: updated)
    }

    /// Records whether a machine may take work moved to it, and saves it.
    ///
    /// Here rather than in the view that draws the control, because the view
    /// that drew it first reached for `MachineMonitorModel.setMayHostSessions`
    /// — which changes memory and nothing else, since persistence used to flow
    /// the other way from the Settings checkbox that edited this store. The
    /// toggle worked and the answer was gone by the next launch. A permission
    /// a relaunch forgets is worse than no permission, so the write lives with
    /// the thing that can actually save it.
    ///
    /// - Returns: whether anything changed, so a caller can skip pushing an
    ///   unchanged herd back through the monitors.
    @discardableResult
    func setMayHostSessions(_ mayHost: Bool, on machine: MachineID) -> Bool {
        guard var configuration = machines.first(where: { $0.id == machine }),
              configuration.mayHostSessions != mayHost
        else { return false }
        configuration.mayHostSessions = mayHost
        update(configuration)
        return true
    }

    func replace(with configurations: [MachineConfiguration]) {
        guard !configurations.isEmpty, configurations != machines else { return }
        machines = configurations
        persist()
    }

    func contains(hostname: String) -> Bool {
        let normalized = Self.normalizedHostname(hostname)
        return machines.contains {
            Self.normalizedHostname($0.hostname) == normalized
                || $0.serverNames.contains {
                    Self.normalizedHostname($0) == normalized
                }
        }
    }

    func contains(name: String) -> Bool {
        let normalized = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return machines.contains {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() == normalized
        }
    }

    private func persist() {
        guard let encoded = try? JSONEncoder().encode(machines) else { return }

        // Anything this build could not read goes back exactly as it came, so a
        // newer version still finds its machines after an older one has written
        // here.
        guard !unreadableEntries.isEmpty else {
            storage.saveConfigurationData(encoded)
            return
        }

        guard var elements = (try? JSONSerialization.jsonObject(with: encoded))
            as? [Any] else { return }
        elements.append(contentsOf: unreadableEntries)
        guard let data = try? JSONSerialization.data(withJSONObject: elements)
        else {
            return
        }
        storage.saveConfigurationData(data)
    }

    private static func normalizedHostname(_ hostname: String) -> String {
        hostname
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
    }
}
