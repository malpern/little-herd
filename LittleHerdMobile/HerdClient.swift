import Foundation
import Network
import Observation

/// Where a watcher is, as far as the phone knows.
nonisolated enum WatcherEndpoint: Hashable, Sendable {
    /// Announced on the local network. Resolved by Network.framework at
    /// connect time, so no address is ever seen or stored.
    case discovered(name: String, endpoint: NWEndpoint)
    /// Typed by a person — a Tailscale name, an IP — for a watcher that is
    /// not on this network.
    case typed(host: String, port: UInt16)

    var displayName: String {
        switch self {
        case let .discovered(name, _): name
        case let .typed(host, port):
            port == HerdWire.defaultPort ? host : "\(host):\(port)"
        }
    }

    var nwEndpoint: NWEndpoint {
        switch self {
        case let .discovered(_, endpoint): endpoint
        case let .typed(host, port):
            .hostPort(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port) ?? .any
            )
        }
    }

    /// `host`, `host:port`, or nothing usable.
    static func typed(from text: String) -> WatcherEndpoint? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // An IPv6 literal carries colons of its own; only a trailing `:NNNN`
        // after a closing bracket, or after a name with no other colon, is a
        // port.
        if let colon = trimmed.lastIndex(of: ":"),
           trimmed.filter({ $0 == ":" }).count == 1 || trimmed[..<colon].hasSuffix("]"),
           let port = UInt16(trimmed[trimmed.index(after: colon)...])
        {
            var host = String(trimmed[..<colon])
            if host.hasPrefix("["), host.hasSuffix("]") {
                host = String(host.dropFirst().dropLast())
            }
            return .typed(host: host, port: port)
        }
        return .typed(host: trimmed, port: HerdWire.defaultPort)
    }
}

/// The phone's side of the wire.
///
/// **One way to reach a watcher, whether found or typed.** A discovered
/// watcher is a Bonjour endpoint and a typed one is a host and port, and
/// `URLSession` can only take the second. Rather than resolve the first by
/// hand — a deprecated API, and one that hands back an address to keep in
/// step — the request is spoken over an `NWConnection`, which resolves either
/// kind itself. That costs writing `GET` by hand, which is the same forty
/// lines the Mac wrote for the other end.
@MainActor
@Observable
final class HerdClient {
    private(set) var snapshot: HerdWire.Snapshot?
    private(set) var lastFetched: Date?
    private(set) var lastError: String?
    private(set) var isFetching = false

    /// Watchers announced on this network, newest last.
    private(set) var discovered: [WatcherEndpoint] = []
    private(set) var isBrowsing = false

    /// The address a person typed, if any. Empty means "use what is found".
    var typedAddress: String {
        didSet {
            UserDefaults.standard.set(typedAddress, forKey: Self.typedAddressKey)
            snapshot = nil
            lastError = nil
        }
    }

    /// The discovered watcher a person picked, by its announced name, so the
    /// same Mac is chosen again next launch when more than one announces.
    var preferredName: String? {
        didSet { UserDefaults.standard.set(preferredName, forKey: Self.preferredNameKey) }
    }

    private static let typedAddressKey = "watcherAddress"
    private static let preferredNameKey = "watcherName"
    private var browser: NWBrowser?

    init() {
        typedAddress = UserDefaults.standard.string(forKey: Self.typedAddressKey) ?? ""
        preferredName = UserDefaults.standard.string(forKey: Self.preferredNameKey)
    }

    /// Which watcher to ask: a typed address wins, then the preferred
    /// discovered one, then whichever was found first.
    var current: WatcherEndpoint? {
        if let typed = WatcherEndpoint.typed(from: typedAddress) { return typed }
        if let name = preferredName,
           let match = discovered.first(where: { $0.displayName == name })
        {
            return match
        }
        return discovered.first
    }

    // MARK: - Finding a watcher

    func startBrowsing() {
        guard browser == nil else { return }
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let browser = NWBrowser(
            for: .bonjour(type: HerdWire.serviceType, domain: nil),
            using: parameters
        )
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                switch state {
                case .ready: self?.isBrowsing = true
                case let .failed(error):
                    self?.isBrowsing = false
                    self?.lastError = "Can’t look for a watcher: \(error.localizedDescription)"
                case .cancelled: self?.isBrowsing = false
                default: break
                }
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let found = results.compactMap { result -> WatcherEndpoint? in
                guard case let .service(name, _, _, _) = result.endpoint else { return nil }
                return .discovered(name: name, endpoint: result.endpoint)
            }
            Task { @MainActor [weak self] in
                self?.discovered = found.sorted { $0.displayName < $1.displayName }
            }
        }
        self.browser = browser
        browser.start(queue: .main)
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        isBrowsing = false
    }

    // MARK: - Reading the herd

    /// Fetches until cancelled, every few seconds — the cadence of the Mac's
    /// own sampling, so asking faster would only reread the same answer.
    func keepFresh() async {
        startBrowsing()
        defer { stopBrowsing() }
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(5))
        }
    }

    func refresh() async {
        guard let watcher = current, !isFetching else { return }
        isFetching = true
        defer { isFetching = false }
        do {
            let data = try await HerdFetcher.get(path: "/herd", from: watcher.nwEndpoint)
            snapshot = try HerdWire.decoder().decode(HerdWire.Snapshot.self, from: data)
            lastFetched = .now
            lastError = nil
        } catch {
            lastError = Self.describe(error, watcher: watcher)
        }
    }

    private static func describe(_ error: Error, watcher: WatcherEndpoint) -> String {
        if let fetch = error as? HerdFetcher.Failure {
            return fetch.description(watcher: watcher.displayName)
        }
        if error is DecodingError {
            return "“\(watcher.displayName)” answered, but not in a shape this "
                + "version understands. One of the two apps is out of date."
        }
        return "“\(watcher.displayName)”: \(error.localizedDescription)"
    }
}

/// `GET` over an `NWConnection`, and nothing more.
nonisolated enum HerdFetcher {
    enum Failure: Error {
        case unreachable(String)
        case badResponse
        case status(Int)

        func description(watcher: String) -> String {
            switch self {
            case let .unreachable(reason):
                "Can’t reach “\(watcher)”. \(reason)"
            case .badResponse:
                "“\(watcher)” answered with something that is not HTTP."
            case let .status(code):
                "“\(watcher)” answered \(code)."
            }
        }
    }

    static func get(path: String, from endpoint: NWEndpoint) async throws -> Data {
        let connection = NWConnection(to: endpoint, using: .tcp)
        let received = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Data, Error>) in
            let box = Box(continuation: continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let request = "GET \(path) HTTP/1.1\r\nHost: herd\r\n"
                        + "Connection: close\r\n\r\n"
                    connection.send(
                        content: Data(request.utf8),
                        completion: .contentProcessed { error in
                            if let error {
                                box.finish(.failure(Failure.unreachable(error.localizedDescription)))
                                connection.cancel()
                            }
                        }
                    )
                    readAll(from: connection, into: box)
                case let .failed(error):
                    box.finish(.failure(Failure.unreachable(Self.plain(error))))
                    connection.cancel()
                case let .waiting(error):
                    // Waiting is Network.framework hoping the path improves.
                    // A phone user is not going to wait with it.
                    box.finish(.failure(Failure.unreachable(Self.plain(error))))
                    connection.cancel()
                case .cancelled:
                    box.finish(.failure(Failure.unreachable("The connection was closed.")))
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
        return try parse(received)
    }

    private static func readAll(from connection: NWConnection, into box: Box) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) {
            data, _, isComplete, error in
            if let data { box.append(data) }
            if let error {
                box.finish(.failure(Failure.unreachable(Self.plain(error))))
                connection.cancel()
            } else if isComplete {
                box.finish(.success(box.buffer))
                connection.cancel()
            } else {
                readAll(from: connection, into: box)
            }
        }
    }

    /// The body, once the status line says it is worth reading.
    static func parse(_ response: Data) throws -> Data {
        guard let headerEnd = response.range(of: Data("\r\n\r\n".utf8)) else {
            throw Failure.badResponse
        }
        let head = String(decoding: response[..<headerEnd.lowerBound], as: UTF8.self)
        let statusLine = head.split(separator: "\r\n", maxSplits: 1).first ?? ""
        let parts = statusLine.split(separator: " ")
        guard parts.count >= 2, parts[0].hasPrefix("HTTP/"), let code = Int(parts[1]) else {
            throw Failure.badResponse
        }
        guard code == 200 else { throw Failure.status(code) }
        return Data(response[headerEnd.upperBound...])
    }

    private static func plain(_ error: NWError) -> String {
        switch error {
        case .dns: "The name didn’t resolve. Check Tailscale, or the spelling."
        case let .posix(code) where code == .ECONNREFUSED:
            "Nothing is listening there. Is Little Herd running on that Mac, "
                + "with “watches the herd” turned on?"
        case let .posix(code) where code == .ETIMEDOUT || code == .EHOSTUNREACH:
            "It didn’t answer. Likely asleep, or on another network."
        default: error.localizedDescription
        }
    }

    /// One continuation, resumed exactly once, and the bytes so far.
    private final class Box: @unchecked Sendable {
        private var continuation: CheckedContinuation<Data, Error>?
        private let lock = NSLock()
        private var bytes = Data()

        init(continuation: CheckedContinuation<Data, Error>) {
            self.continuation = continuation
        }

        var buffer: Data {
            lock.lock(); defer { lock.unlock() }
            return bytes
        }

        func append(_ data: Data) {
            lock.lock(); defer { lock.unlock() }
            bytes.append(data)
        }

        func finish(_ result: Result<Data, Error>) {
            lock.lock()
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume(with: result)
        }
    }
}
