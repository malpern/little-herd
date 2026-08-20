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

    /// Intent, and only intent.
    ///
    /// Off until someone says otherwise, because the consequence of a wrong
    /// answer is not symmetric: a machine wrongly offered as a destination
    /// invites work to be moved somewhere it will fail, and a machine wrongly
    /// withheld costs one toggle. Whether the machine *could* host anything is
    /// a separate, measured question — see `DestinationEligibility`.
    var mayHostSessions: Bool {
        get { mayHostSessionsPreference ?? false }
        set { mayHostSessionsPreference = newValue }
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

    init(storage: MachineConfigurationStorage) {
        self.storage = storage

        guard let data = storage.loadConfigurationData() else {
            // Genuinely nothing saved: a first launch, so seed the local Mac.
            machines = [.local()]
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
        machines = decoded.isEmpty ? [.local()] : decoded
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
                Self.normalizedHostname($0.hostname)
                    == Self.normalizedHostname(addition.hostname)
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
