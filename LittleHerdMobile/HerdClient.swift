import CryptoKit
import Foundation
import Network
import Observation
import Security
import UIKit

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

    /// The code the watcher shows in its Settings. Sent with every read;
    /// without it the Mac answers 401 and says where to find it.
    var pairingCode: String {
        didSet {
            UserDefaults.standard.set(pairingCode, forKey: Self.pairingCodeKey)
            lastError = nil
        }
    }

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
    private static let pairingCodeKey = "watcherPairingCode"
    private var browser: NWBrowser?

    /// A herd from a file instead of a Mac, for looking at states the real
    /// herd does not happen to be in — a NAS, a stalled session, a volume
    /// the machine says is failing. Set by a test harness, never by a person.
    private let fixture: HerdWire.Snapshot?

    init() {
        typedAddress = UserDefaults.standard.string(forKey: Self.typedAddressKey) ?? ""
        preferredName = UserDefaults.standard.string(forKey: Self.preferredNameKey)
        pairingCode = UserDefaults.standard.string(forKey: Self.pairingCodeKey) ?? ""
        fixture = ProcessInfo.processInfo.environment["LITTLE_HERD_FIXTURE"] == "1"
            ? Self.loadFixture() : nil
    }

    private static func loadFixture() -> HerdWire.Snapshot? {
        guard let url = Bundle.main.url(forResource: "fixture-herd", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? HerdWire.decoder().decode(HerdWire.Snapshot.self, from: data)
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
        if let fixture {
            snapshot = fixture
            lastFetched = .now
            return
        }
        guard let watcher = current, !isFetching else { return }
        isFetching = true
        defer { isFetching = false }
        do {
            let data = try await HerdFetcher.get(
                path: "/herd",
                from: watcher.nwEndpoint,
                pairingCode: pairingCode
            )
            snapshot = try HerdWire.decoder().decode(HerdWire.Snapshot.self, from: data)
            lastFetched = .now
            lastError = nil
        } catch {
            lastError = Self.describe(error, watcher: watcher)
        }
    }

    // MARK: - Writes

    /// Whether the current watcher takes moves at all. An older watcher, or
    /// one read from the fixture, does not, and the phone hides moving.
    var canWrite: Bool { snapshot?.acceptsWrites == true }

    /// Asks the watcher what a move would do, or does it. Pairs for writes
    /// first if this phone has not, and once more if the watcher has
    /// forgotten it — a new code on the Mac retires every earlier pairing.
    func move(
        session: HerdWire.Session,
        from origin: String,
        to destination: String,
        dryRun: Bool
    ) async throws -> HerdWire.MoveResponse {
        if fixture != nil {
            // The harness has no watcher to ask; it answers the way a real
            // one would, so the confirm sheet can be judged by looking at it.
            try await Task.sleep(for: .milliseconds(400))
            let name = { (id: String) in self.snapshot?.machines.first { $0.id == id }?.shortName ?? id }
            return HerdWire.MoveResponse(
                applied: !dryRun,
                title: session.title,
                fromName: name(origin),
                toName: name(destination),
                refusal: nil,
                fixesFirst: false,
                steps: [
                    "Ask it to write down where it got to, and push that as a branch",
                    "Start the agent on \(name(destination)) from that branch",
                    "Run the checks and push the result",
                ]
            )
        }
        let request = HerdWire.MoveRequest(session: session.id, from: origin, to: destination, dryRun: dryRun)
        let data = try await signedPost("/move", body: HerdWire.encoder().encode(request))
        let response = try HerdWire.decoder().decode(HerdWire.MoveResponse.self, from: data)
        if response.applied { Task { await refresh() } }
        return response
    }

    /// Hands the watcher this phone's push token. Quietly does nothing
    /// without a watcher that takes writes.
    func registerPush(token: String, environment: String) async {
        guard canWrite else { return }
        let registration = HerdWire.PushRegistration(token: token, environment: environment)
        do {
            _ = try await signedPost("/push", body: HerdWire.encoder().encode(registration))
            pushRegisteredWith = current?.displayName
        } catch {
            lastError = current.map { Self.describe(error, watcher: $0) }
        }
    }

    /// Which watcher last took this phone's push token.
    private(set) var pushRegisteredWith: String?

    private func signedPost(_ path: String, body: Data, retried: Bool = false) async throws -> Data {
        guard let watcher = current else { throw HerdFetcher.Failure.unreachable("No watcher chosen.") }
        let credential = try await writeCredential(for: watcher)
        let time = String(Int(Date.now.timeIntervalSince1970))
        let nonce = UUID().uuidString
        let canonical = HerdWire.Signing.canonical(method: "POST", path: path, time: time, nonce: nonce, body: body)
        do {
            return try await HerdFetcher.send(
                method: "POST",
                path: path,
                to: watcher.nwEndpoint,
                headers: [
                    HerdWire.Signing.deviceHeader: credential.deviceID,
                    HerdWire.Signing.timeHeader: time,
                    HerdWire.Signing.nonceHeader: nonce,
                    HerdWire.Signing.signatureHeader: HerdWire.Signing.signature(key: credential.key, canonical: canonical),
                ],
                body: body
            )
        } catch HerdFetcher.Failure.refused(let reason) where !retried && reason.contains("pair") {
            WriteCredential.forget(watcher: watcher.displayName)
            return try await signedPost(path, body: body, retried: true)
        }
    }

    private func writeCredential(for watcher: WatcherEndpoint) async throws -> WriteCredential {
        if let stored = WriteCredential.load(watcher: watcher.displayName, code: pairingCode) {
            return stored
        }
        let mine = P256.KeyAgreement.PrivateKey()
        let request = HerdWire.PairRequest(
            deviceName: UIDevice.current.name,
            publicKey: mine.publicKey.rawRepresentation
        )
        let data = try await HerdFetcher.send(
            method: "POST",
            path: "/pair",
            to: watcher.nwEndpoint,
            pairingCode: pairingCode,
            body: HerdWire.encoder().encode(request)
        )
        let answer = try HerdWire.decoder().decode(HerdWire.PairResponse.self, from: data)
        let key = try HerdWire.Signing.sharedKey(
            privateKey: mine,
            peerPublicKey: answer.watcherPublicKey,
            pairingCode: pairingCode
        )
        let credential = WriteCredential(deviceID: answer.deviceID, key: key)
        credential.save(watcher: watcher.displayName, code: pairingCode)
        return credential
    }

    static func describe(_ error: Error, watcher: WatcherEndpoint) -> String {
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
    enum Failure: Error, Equatable {
        case unreachable(String)
        case badResponse
        /// The watcher answered and wants the pairing code. Told apart from
        /// any other status because it needs a different thing from a person:
        /// not a better address, a trip to the Mac's Settings.
        case needsPairingCode
        case status(Int)
        /// A signed write the watcher would not accept, and its reason.
        case refused(String)

        func description(watcher: String) -> String {
            switch self {
            case let .unreachable(reason):
                "Can’t reach “\(watcher)”. \(reason)"
            case .badResponse:
                "“\(watcher)” answered with something that is not HTTP."
            case .needsPairingCode:
                "“\(watcher)” wants its pairing code. It is in Little Herd’s "
                    + "settings on that Mac, under the watcher switch — enter "
                    + "it under Watcher here."
            case let .status(code):
                "“\(watcher)” answered \(code)."
            case let .refused(reason):
                "“\(watcher)” refused: \(reason)."
            }
        }
    }

    static func get(
        path: String,
        from endpoint: NWEndpoint,
        pairingCode: String = ""
    ) async throws -> Data {
        try await send(method: "GET", path: path, to: endpoint, pairingCode: pairingCode)
    }

    static func send(
        method: String,
        path: String,
        to endpoint: NWEndpoint,
        pairingCode: String = "",
        headers extra: [String: String] = [:],
        body: Data = Data()
    ) async throws -> Data {
        let connection = NWConnection(to: endpoint, using: .tcp)
        let received = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Data, Error>) in
            let box = Box(continuation: continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    var request = "\(method) \(path) HTTP/1.1\r\nHost: herd\r\n"
                    if !HerdWire.Pairing.normalize(pairingCode).isEmpty {
                        request += "\(HerdWire.Pairing.headerName): "
                            + "\(HerdWire.Pairing.headerValue(pairingCode))\r\n"
                    }
                    for (name, value) in extra.sorted(by: { $0.key < $1.key }) {
                        request += "\(name): \(value)\r\n"
                    }
                    if !body.isEmpty {
                        request += "Content-Type: application/json\r\n"
                        request += "Content-Length: \(body.count)\r\n"
                    }
                    request += "Connection: close\r\n\r\n"
                    connection.send(
                        content: Data(request.utf8) + body,
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
        guard code != 401 else { throw Failure.needsPairingCode }
        if code == 403 {
            let reason = String(decoding: response[headerEnd.upperBound...], as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure.refused(reason)
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


/// The key this phone signs writes with, for one watcher.
///
/// In the Keychain: it is the thing that lets a phone start work on a Mac,
/// and on iOS the Keychain costs no prompt. Filed under the watcher's name and
/// the code it was made with, so a new code on the Mac quietly means a new
/// pairing here rather than a stream of refusals.
nonisolated struct WriteCredential {
    let deviceID: String
    let key: SymmetricKey

    private static func account(watcher: String, code: String) -> String {
        "\(watcher)|\(HerdWire.Pairing.normalize(code))"
    }

    private static let service = "com.malpern.LittleHerdMobile.write"

    static func load(watcher: String, code: String) -> WriteCredential? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(watcher: watcher, code: code),
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let stored = try? JSONDecoder().decode([String: Data].self, from: data),
              let id = stored["id"].map({ String(decoding: $0, as: UTF8.self) }),
              let key = stored["key"]
        else { return nil }
        return WriteCredential(deviceID: id, key: SymmetricKey(data: key))
    }

    func save(watcher: String, code: String) {
        Self.forget(watcher: watcher)
        let payload: [String: Data] = [
            "id": Data(deviceID.utf8),
            "key": key.withUnsafeBytes { Data($0) },
        ]
        guard let data = try? JSONEncoder().encode(payload) else { return }
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account(watcher: watcher, code: code),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        SecItemAdd(item as CFDictionary, nil)
    }

    /// Every credential for this watcher, whatever code it was made under.
    static func forget(watcher: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        var items: CFTypeRef?
        let listQuery = query.merging([
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]) { $1 }
        guard SecItemCopyMatching(listQuery as CFDictionary, &items) == errSecSuccess,
              let list = items as? [[String: Any]]
        else { return }
        for attributes in list {
            guard let account = attributes[kSecAttrAccount as String] as? String,
                  account.hasPrefix(watcher + "|")
            else { continue }
            SecItemDelete(query.merging([kSecAttrAccount as String: account]) { $1 } as CFDictionary)
        }
    }
}
