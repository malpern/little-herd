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

@MainActor
@Observable
final class MachineConfigurationStore {
    private(set) var machines: [MachineConfiguration]

    @ObservationIgnored
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(
            forKey: LittleHerdPreferences.machineConfigurationsKey
        ),
            let decoded = try? JSONDecoder().decode(
                [MachineConfiguration].self,
                from: data
            ),
            !decoded.isEmpty
        {
            machines = decoded
        } else {
            machines = [.local()]
            persist()
        }
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
        guard let data = try? JSONEncoder().encode(machines) else { return }
        defaults.set(
            data,
            forKey: LittleHerdPreferences.machineConfigurationsKey
        )
    }

    private static func normalizedHostname(_ hostname: String) -> String {
        hostname
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
    }
}
