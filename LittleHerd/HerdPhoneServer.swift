import Foundation
import Network
import os

/// The things about a request worth knowing.
nonisolated struct HerdRequest: Equatable, Sendable {
    let method: String
    /// The path with any query string removed.
    let path: String
    /// Header names lower-cased, values trimmed.
    var headers: [String: String] = [:]
    /// Exactly `Content-Length` bytes, for the writes that carry one.
    var body = Data()

    /// Parses a request from its bytes, or nothing if the headers have not all
    /// arrived yet.
    static func parse(_ data: Data) -> HerdRequest? {
        guard data.count <= 16_384, let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: data[..<headerEnd.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }
        let requestLine = lines.removeFirst()
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            return HerdRequest(method: "", path: "")
        }
        let target = parts[1].split(separator: "?", maxSplits: 1).first.map(String.init) ?? "/"
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard headers[name] == nil else { return nil }
            headers[name] = value
        }
        // Wait for the whole body before answering: a write read half-way
        // would be signed over bytes it never saw.
        guard headers["transfer-encoding"] == nil,
              let length = Int(headers["content-length"] ?? "0"), length >= 0
        else { return nil }
        let bodyStart = headerEnd.upperBound
        guard data.count - bodyStart == length else { return nil }
        let body = data.subdata(in: bodyStart ..< bodyStart + length)
        return HerdRequest(
            method: String(parts[0]).uppercased(),
            path: target,
            headers: headers,
            body: body
        )
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

/// The phone's existing build reads a snapshot before pairing. Keep that
/// protocol, but bind only to the chosen Tailscale address and implement only
/// the writes necessary to register an APNs token.
@MainActor
final class HerdPhoneServer {
    private static let log = Logger(subsystem: "com.malpern.LittleHerd", category: "herd-server")
    private let queue = DispatchQueue(label: "com.malpern.LittleHerd.herd-server")
    private let devices: HerdDeviceStore
    private let gate = HerdWriteGate()
    private let snapshot: @MainActor () -> HerdWire.Snapshot?
    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    private var binding: Binding?
    private var retryAfter: Date?

    struct Binding: Equatable {
        let address: IPv4Address
        let port: NWEndpoint.Port

        init?(address: String, port: UInt16) {
            guard let ip = IPv4Address(address), let endpointPort = NWEndpoint.Port(rawValue: port),
                  endpointPort != .any
            else { return nil }
            let bytes = Array(ip.rawValue)
            guard bytes[0] == 100, (64...127).contains(bytes[1]) else { return nil }
            self.address = ip
            self.port = endpointPort
        }
    }

    var pairingCode: String

    init(
        devices: HerdDeviceStore,
        pairingCode: String,
        snapshot: @escaping @MainActor () -> HerdWire.Snapshot?
    ) {
        self.devices = devices
        self.pairingCode = pairingCode
        self.snapshot = snapshot
    }

    func reconcile(binding desired: Binding?) {
        if desired != binding {
            stop()
            binding = desired
            retryAfter = nil
        }
        guard let binding, listener == nil, retryAfter.map({ $0 <= .now }) ?? true else { return }
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.requiredLocalEndpoint = .hostPort(
                host: .ipv4(binding.address),
                port: binding.port
            )
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self, weak listener] connection in
                Task { @MainActor in
                    guard let self, let listener, self.listener === listener else {
                        connection.cancel()
                        return
                    }
                    self.accept(connection)
                }
            }
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                Task { @MainActor in
                    guard let self, let listener, self.listener === listener else { return }
                    switch state {
                    case .ready:
                        Self.log.notice("Phone registration listening on port \(binding.port.rawValue)")
                    case .failed(let error):
                        self.listenerFailed(error)
                    default:
                        break
                    }
                }
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            listenerFailed(error)
        }
    }

    private func listenerFailed(_ error: any Error) {
        Self.log.error("Phone listener failed: \(String(describing: error), privacy: .public)")
        stop()
        retryAfter = .now.addingTimeInterval(15)
    }

    private func stop() {
        listener?.cancel()
        listener = nil
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
    }

    private func accept(_ connection: NWConnection) {
        guard connections.count < 16 else { connection.cancel(); return }
        let id = UUID()
        connections[id] = connection
        connection.start(queue: queue)
        receive(id: id, into: HerdRequestReader())
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            self?.finish(id)
        }
    }

    private func receive(id: UUID, into reader: HerdRequestReader) {
        connections[id]?.receive(minimumIncompleteLength: 1, maximumLength: 16_384) {
            [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, let connection = self.connections[id] else { return }
                if let data { reader.append(data) }
                if let request = reader.request {
                    connection.send(content: self.response(to: request), completion: .contentProcessed { [weak self] _ in
                        Task { @MainActor in self?.finish(id) }
                    })
                } else if error != nil || complete || reader.isOversized {
                    self.finish(id)
                } else {
                    self.receive(id: id, into: reader)
                }
            }
        }
    }

    private func finish(_ id: UUID) {
        connections.removeValue(forKey: id)?.cancel()
    }

    func response(to request: HerdRequest) -> Data {
        let hasCode = HerdWire.Pairing.accepts(request.headers["authorization"], code: pairingCode)
        switch (request.method, request.path) {
        case ("GET", "/health"):
            return text("200 OK", "little-herd watcher\n")
        case ("GET", "/herd"), ("GET", "/herd.json"):
            guard hasCode else { return text("401 Unauthorized", "pairing code required\n") }
            guard let snapshot = snapshot() else { return text("503 Service Unavailable", "watcher stopped\n") }
            return json(snapshot)
        case ("POST", "/pair"):
            guard hasCode else { return text("401 Unauthorized", "pairing code required\n") }
            guard let pair = try? HerdWire.decoder().decode(HerdWire.PairRequest.self, from: request.body),
                  let answer = try? devices.pair(pair, pairingCode: pairingCode)
            else { return text("400 Bad Request", "could not pair\n") }
            return json(answer)
        case ("POST", "/push"):
            switch gate.verify(request, keys: devices.key(for:)) {
            case .refused(let reason):
                return text("403 Forbidden", reason + "\n")
            case .accepted(let deviceID):
                guard let push = try? HerdWire.decoder().decode(HerdWire.PushRegistration.self, from: request.body),
                      push.isValid
                else { return text("400 Bad Request", "invalid push registration\n") }
                devices.setPush(push, for: deviceID)
                Self.log.notice("Registered a phone for \(push.environment, privacy: .public) APNs")
                return text("200 OK", "registered\n")
            }
        default:
            return text("404 Not Found", "no such path\n")
        }
    }

    private func json(_ value: some Encodable) -> Data {
        guard let body = try? HerdWire.encoder().encode(value) else {
            return text("500 Internal Server Error", "could not encode the herd\n")
        }
        return response("200 OK", contentType: "application/json", body: body)
    }

    private func text(_ status: String, _ message: String) -> Data {
        response(status, contentType: "text/plain; charset=utf-8", body: Data(message.utf8))
    }

    private func response(_ status: String, contentType: String, body: Data) -> Data {
        let head = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\n"
            + "Content-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}
