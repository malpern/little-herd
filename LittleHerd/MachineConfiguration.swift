import Foundation
import Observation

nonisolated enum MachineConnection: String, Codable, Equatable, Sendable {
    case local
    case ssh
    case smb
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

    var isStorage: Bool {
        connection == .smb || platform == .storage
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
