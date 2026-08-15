import Foundation

@MainActor
final class BonjourMachineDiscovery: NSObject {
    var onMachineResolved: ((DiscoveredMachine) -> Void)?
    var onMachineRemoved: ((DiscoveredMachine.ID) -> Void)?
    var onSearchingChanged: ((Bool) -> Void)?

    private var browsers: [NetServiceBrowser] = []
    private var services: [String: NetService] = [:]
    private var searchingBrowserCount = 0
    private let canAccessNetworkStorage: () -> Bool

    init(
        canAccessNetworkStorage: @escaping () -> Bool = {
            UserDefaults.standard.bool(
                forKey: LittleHerdPreferences
                    .networkVolumeAccessOnboardingCompletedKey
            )
        }
    ) {
        self.canAccessNetworkStorage = canAccessNetworkStorage
        super.init()
    }

    func start() {
        stop()
        for type in ["_ssh._tcp.", "_smb._tcp."] {
            let browser = NetServiceBrowser()
            browser.delegate = self
            browsers.append(browser)
            browser.searchForServices(ofType: type, inDomain: "local.")
        }
    }

    func stop() {
        for browser in browsers {
            browser.stop()
            browser.delegate = nil
        }
        for service in services.values {
            service.stop()
            service.delegate = nil
        }
        browsers.removeAll()
        services.removeAll()
        searchingBrowserCount = 0
        onSearchingChanged?(false)
    }

    private func resolve(_ service: NetService) {
        let key = serviceKey(service)
        guard services[key] == nil else { return }
        services[key] = service
        service.delegate = self
        service.resolve(withTimeout: 5)
    }

    private func serviceKey(_ service: NetService) -> String {
        "\(service.type)|\(service.domain)|\(service.name)"
    }

    private func discoveredMachine(from service: NetService) -> DiscoveredMachine {
        let fallbackHostname = service.name
            .replacingOccurrences(of: " ", with: "-") + ".local"
        let hostname = (service.hostName ?? fallbackHostname)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let isStorage = service.type == "_smb._tcp."
        let platform: MachinePlatform
        if isStorage {
            platform = .storage
        } else {
            let normalized = "\(service.name) \(hostname)".lowercased()
            platform = normalized.contains("linux")
                || normalized.contains("gpu")
                || normalized.contains("ubuntu")
                ? .linux
                : .macOS
        }
        let avatar = MachineConfiguration.inferredAvatar(
            name: service.name,
            platform: platform
        )
        return DiscoveredMachine(
            id: service.name.lowercased(),
            name: service.name,
            hostname: hostname,
            hardwareSummary: isStorage
                ? "Network storage"
                : (platform == .linux ? "Linux · SSH available" : "Mac · SSH available"),
            platform: platform,
            connection: isStorage ? .smb : .ssh,
            avatar: avatar,
            readiness: isStorage && !canAccessNetworkStorage()
                ? .permissionNeeded
                : .ready
        )
    }
}

extension BonjourMachineDiscovery: @preconcurrency NetServiceBrowserDelegate {
    func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {
        searchingBrowserCount += 1
        onSearchingChanged?(true)
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        searchingBrowserCount = max(searchingBrowserCount - 1, 0)
        onSearchingChanged?(searchingBrowserCount > 0)
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didNotSearch errorDict: [String: NSNumber]
    ) {
        searchingBrowserCount = max(searchingBrowserCount - 1, 0)
        onSearchingChanged?(searchingBrowserCount > 0)
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didFind service: NetService,
        moreComing: Bool
    ) {
        onMachineResolved?(discoveredMachine(from: service))
        resolve(service)
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didRemove service: NetService,
        moreComing: Bool
    ) {
        services.removeValue(forKey: serviceKey(service))
        let stillAvailable = services.values.contains {
            $0.name.caseInsensitiveCompare(service.name) == .orderedSame
        }
        if !stillAvailable {
            onMachineRemoved?(service.name.lowercased())
        }
    }
}

extension BonjourMachineDiscovery: @preconcurrency NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        onMachineResolved?(discoveredMachine(from: sender))
    }
}
