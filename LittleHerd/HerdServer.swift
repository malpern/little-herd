import Foundation
import Network

/// The watcher, answering a phone.
///
/// **A listener, not a daemon.** Item 18 already defines a Mac whose job is to
/// notice the herd while nobody is looking; item 6 wanted a phone that could
/// see the herd without sampling it. Those are one job. The watcher is running
/// anyway, has the herd in memory anyway, and lives on the Mac that stays awake
/// anyway — so it serves what it already knows on a port, and advertises the
/// port on the local network so a phone can find it without being told. There
/// is no second process to keep alive and nothing to install.
///
/// **It serves the running model, not a fresh probe.** The command line
/// re-probes on every verb, and that was the right call for a tool meant to
/// work while the app is closed. A phone refreshing every few seconds is the
/// opposite case: a probe per request would `ssh` into every machine each time
/// somebody glanced at their phone, and the app has already sampled the herd
/// ten seconds ago. What the phone gets is what the dashboard would draw.
///
/// **Just enough HTTP.** A request line, headers up to the blank line, and a
/// response with a body. No keep-alive, no chunking, no TLS — one request per
/// connection, closed after the answer. Written by hand because the whole of it
/// is forty lines and the alternative is a dependency for the sake of `GET`.
/// It is not a web server and must not grow into one.
///
/// **Reads only, and only on your own network.** Nothing here changes a machine
/// or moves work, and the listener binds to every interface on purpose — a
/// tailnet address is how the phone reaches a watcher from outside the house.
/// That means anyone on those networks can read the herd. Acceptable for a
/// spike on a private network; a token handed over at pairing is the honest
/// next step before this is on by default, and `move` from a phone must not
/// exist until then.
@MainActor
final class HerdServer {
    /// Where the snapshot comes from. Called on the main actor, once per
    /// request, because the model it reads is main-actor state.
    typealias SnapshotProvider = @MainActor () -> HerdWire.Snapshot

    private(set) var port: UInt16?
    private(set) var isListening = false
    private(set) var lastError: String?
    /// Whether the local network has been told. Separate from listening on
    /// purpose — see `HerdAdvertiser`.
    private(set) var isAdvertised = false
    private(set) var advertisingError: String?
    /// How many requests have been answered since start. Shown in Settings so
    /// a person can see the phone actually reached this Mac, which is the one
    /// thing a green switch cannot say.
    private(set) var requestsAnswered = 0

    private var listener: NWListener?
    private var advertiser: HerdAdvertiser?
    private let queue = DispatchQueue(label: "com.malpern.LittleHerd.herd-server")
    private let provider: SnapshotProvider
    private let watcherName: String

    init(watcherName: String, provider: @escaping SnapshotProvider) {
        self.watcherName = watcherName
        self.provider = provider
    }

    /// Starts listening on `port`, or on the default. `0` asks the system for
    /// any free port, which is how the tests avoid colliding with a running app.
    func start(port requested: UInt16 = HerdWire.defaultPort) {
        guard listener == nil else { return }
        lastError = nil
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(
                using: parameters,
                on: NWEndpoint.Port(rawValue: requested) ?? .any
            )
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    self?.listenerStateChanged(state, listener: listener)
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in
                    self?.accept(connection)
                }
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            lastError = String(describing: error)
        }
    }

    func stop() {
        advertiser?.stop()
        advertiser = nil
        isAdvertised = false
        listener?.cancel()
        listener = nil
        isListening = false
        port = nil
    }

    private func listenerStateChanged(_ state: NWListener.State, listener: NWListener) {
        switch state {
        case .ready:
            isListening = true
            port = listener.port?.rawValue
            if let port, advertiser == nil {
                let advertiser = HerdAdvertiser(name: watcherName, port: port)
                advertiser.onChange = { [weak self] published, error in
                    self?.isAdvertised = published
                    self?.advertisingError = error
                }
                self.advertiser = advertiser
                advertiser.start()
            }
        case let .failed(error):
            isListening = false
            lastError = String(describing: error)
            listener.cancel()
            if self.listener === listener { self.listener = nil }
        case .cancelled:
            isListening = false
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        let reader = HerdRequestReader()
        connection.stateUpdateHandler = { state in
            if case .failed = state { connection.cancel() }
        }
        connection.start(queue: queue)
        receive(on: connection, into: reader)
    }

    /// Reads until the headers end, then answers. A body is ignored: nothing
    /// here accepts one.
    private func receive(on connection: NWConnection, into reader: HerdRequestReader) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) {
            [weak self] data, _, isComplete, error in
            Task { @MainActor [weak self] in
                guard let self else { connection.cancel(); return }
                if let data { reader.append(data) }
                if let request = reader.request {
                    self.respond(to: request, on: connection)
                } else if error != nil || isComplete || reader.isOversized {
                    connection.cancel()
                } else {
                    self.receive(on: connection, into: reader)
                }
            }
        }
    }

    private func respond(to request: HerdRequest, on connection: NWConnection) {
        let response = HerdServer.response(for: request, snapshot: provider)
        requestsAnswered += 1
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    /// The answer to a request, as bytes. Static and pure so it can be tested
    /// without a socket.
    static func response(
        for request: HerdRequest,
        snapshot: SnapshotProvider
    ) -> Data {
        switch (request.method, request.path) {
        case ("GET", "/herd"), ("GET", "/herd.json"):
            let body = (try? HerdWire.encoder().encode(snapshot())) ?? Data()
            return http(status: "200 OK", contentType: "application/json", body: body)
        case ("GET", "/"), ("GET", "/health"):
            return http(
                status: "200 OK",
                contentType: "text/plain; charset=utf-8",
                body: Data("little-herd watcher\n".utf8)
            )
        case ("GET", _):
            return http(
                status: "404 Not Found",
                contentType: "text/plain; charset=utf-8",
                body: Data("no such path; try /herd\n".utf8)
            )
        default:
            return http(
                status: "405 Method Not Allowed",
                contentType: "text/plain; charset=utf-8",
                body: Data("reads only\n".utf8)
            )
        }
    }

    private static func http(status: String, contentType: String, body: Data) -> Data {
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "Connection: close\r\n"
        head += "Server: little-herd/\(HerdWire.version)\r\n"
        head += "\r\n"
        return Data(head.utf8) + body
    }
}

/// The two things about a request worth knowing.
nonisolated struct HerdRequest: Equatable, Sendable {
    let method: String
    /// The path with any query string removed.
    let path: String

    /// Parses a request from its bytes, or nothing if the headers have not all
    /// arrived yet. Only the request line is read; headers are skipped past.
    static func parse(_ data: Data) -> HerdRequest? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: data[..<headerEnd.lowerBound], as: UTF8.self)
        guard let requestLine = head.split(separator: "\r\n", maxSplits: 1).first else {
            return nil
        }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            return HerdRequest(method: "", path: "")
        }
        let target = parts[1].split(separator: "?", maxSplits: 1).first.map(String.init) ?? "/"
        return HerdRequest(method: String(parts[0]).uppercased(), path: target)
    }
}

/// Accumulates one connection's bytes until a request can be read from them.
@MainActor
final class HerdRequestReader {
    private var buffer = Data()
    private static let limit = 16384

    func append(_ data: Data) { buffer.append(data) }

    var request: HerdRequest? { HerdRequest.parse(buffer) }

    /// Headers that never end are not a request; close rather than buffer
    /// forever.
    var isOversized: Bool { buffer.count > Self.limit }
}

/// Tells the local network where the watcher is.
///
/// **Kept apart from the listener, because the two fail differently.** The
/// first build attached the Bonjour service to the `NWListener`, and when
/// registration was refused — `-65555 NoAuth`, the Local Network privacy gate
/// — the listener failed with it and the port went away. That is the wrong
/// coupling: a phone reaching a watcher by a Tailscale name never needed
/// Bonjour, and a refused announcement should cost only the announcement.
/// Now the port stays up and Settings says the herd was not advertised.
///
/// `NetService` rather than `DNSServiceRegister` because discovery in this
/// app already runs on `NetServiceBrowser`; the two are the same age and the
/// same API family, and a second way of talking to mDNSResponder is one more
/// thing to keep in step.
@MainActor
final class HerdAdvertiser: NSObject, NetServiceDelegate {
    private let service: NetService
    /// Published or not, and why not.
    var onChange: ((Bool, String?) -> Void)?

    init(name: String, port: UInt16) {
        service = NetService(
            domain: "local.",
            type: HerdWire.serviceType + ".",
            name: name,
            port: Int32(port)
        )
        super.init()
        service.setTXTRecord(NetService.data(fromTXTRecord: [
            "v": Data(String(HerdWire.version).utf8),
        ]))
        service.delegate = self
    }

    func start() {
        service.publish()
    }

    func stop() {
        service.stop()
        service.delegate = nil
    }

    nonisolated func netServiceDidPublish(_ sender: NetService) {
        Task { @MainActor in self.onChange?(true, nil) }
    }

    nonisolated func netService(
        _ sender: NetService,
        didNotPublish errorDict: [String: NSNumber]
    ) {
        let code = errorDict[NetService.errorCode]?.intValue ?? 0
        let reason = code == -65555
            ? "macOS refused to announce it on the local network (-65555). "
                + "Allow Little Herd under Privacy & Security › Local Network."
            : "Bonjour error \(code)"
        Task { @MainActor in self.onChange?(false, reason) }
    }
}
