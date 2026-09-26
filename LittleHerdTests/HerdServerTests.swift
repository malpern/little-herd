import Foundation
import Testing

@testable import LittleHerd

/// The watcher answering a phone.
@Suite("Herd server")
struct HerdServerTests {
    // MARK: - The wire

    /// A snapshot survives the trip through JSON unchanged, dates included.
    /// The phone decodes what the Mac encodes with the same two functions, so
    /// this is the one test that stands in for the phone.
    @Test
    func aSnapshotRoundTripsThroughJSON() throws {
        let snapshot = Self.snapshot()
        let data = try HerdWire.encoder().encode(snapshot)
        let decoded = try HerdWire.decoder().decode(HerdWire.Snapshot.self, from: data)
        #expect(decoded == snapshot)
        #expect(decoded.version == HerdWire.version)
    }

    /// The counts a phone shows at a glance come from the session states,
    /// and waiting is not active: a waiting session is blocked on a person
    /// and costs the machine nothing.
    @Test
    func sessionCountsTellActiveFromWaiting() {
        let machine = Self.snapshot().machines[0]
        #expect(machine.activeSessionCount == 1)
        #expect(machine.waitingSessionCount == 1)
    }

    // MARK: - Just enough HTTP

    @Test
    func aRequestIsReadOnceItsHeadersHaveEnded() {
        let partial = Data("GET /herd HTTP/1.1\r\nHost: x\r\n".utf8)
        #expect(HerdRequest.parse(partial) == nil)

        let whole = partial + Data("\r\n".utf8)
        #expect(HerdRequest.parse(whole) == HerdRequest(method: "GET", path: "/herd"))
    }

    /// A query string is not part of the path, and a lower-case method is
    /// still the method. Both are what a hand-typed `curl` produces.
    @Test
    func theQueryStringIsDroppedAndTheMethodNormalised() {
        let request = HerdRequest.parse(Data("get /herd?t=1 HTTP/1.1\r\n\r\n".utf8))
        #expect(request == HerdRequest(method: "GET", path: "/herd"))
    }

    @Test
    func theHerdIsServedAsJSONAndEverythingElseIsRefused() throws {
        let herd = HerdServer.response(
            for: HerdRequest(method: "GET", path: "/herd"),
            snapshot: { Self.snapshot() }
        )
        let text = String(decoding: herd, as: UTF8.self)
        #expect(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(text.contains("Content-Type: application/json"))
        let body = try #require(text.components(separatedBy: "\r\n\r\n").last)
        let decoded = try HerdWire.decoder().decode(
            HerdWire.Snapshot.self,
            from: Data(body.utf8)
        )
        #expect(decoded.machines.map(\.name) == ["Mac mini", "Linux"])

        let missing = HerdServer.response(
            for: HerdRequest(method: "GET", path: "/anything"),
            snapshot: { Self.snapshot() }
        )
        #expect(String(decoding: missing, as: UTF8.self).hasPrefix("HTTP/1.1 404"))

        // Reads only. There is no write to refuse yet, and this is what keeps
        // it that way until a pairing step exists.
        let write = HerdServer.response(
            for: HerdRequest(method: "POST", path: "/herd"),
            snapshot: { Self.snapshot() }
        )
        #expect(String(decoding: write, as: UTF8.self).hasPrefix("HTTP/1.1 405"))
    }

    /// The whole path, through a real socket: start on any free port, fetch
    /// with the same client the phone uses, decode. Anything the parser or
    /// the framing gets wrong shows up here as a hang or a decode failure.
    ///
    /// **Advertising is deliberately not asserted.** Under the test host
    /// macOS refuses the Bonjour registration (`-65555 NoAuth`, the Local
    /// Network privacy gate), and the first build of the server let that
    /// refusal take the port down with it — which is exactly what this test
    /// caught. The port must serve whether or not the network was told.
    @Test
    func aRealClientCanFetchTheHerd() async throws {
        let server = await HerdServer(watcherName: "Test Mac") { Self.snapshot() }
        await server.start(port: 0)
        let port = try await Self.waitForPort(server)
        let url = try #require(URL(string: "http://127.0.0.1:\(port)/herd"))
        let (data, response) = try await URLSession.shared.data(from: url)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        let decoded = try HerdWire.decoder().decode(HerdWire.Snapshot.self, from: data)
        // The body is whatever the provider said, byte for byte through the
        // socket; the name given to the server is only what Bonjour announces.
        #expect(decoded == Self.snapshot())
        #expect(await server.requestsAnswered == 1)

        await server.stop()
    }

    // MARK: - Fixtures

    @MainActor
    private static func waitForPort(_ server: HerdServer) async throws -> UInt16 {
        for _ in 0..<200 {
            if let port = server.port, server.isListening { return port }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw HerdServerTestError.neverListened(server.lastError ?? "no error reported")
    }

    private enum HerdServerTestError: Error {
        case neverListened(String)
    }

    private static func snapshot() -> HerdWire.Snapshot {
        let now = Date(timeIntervalSince1970: 1_758_900_000)
        return HerdWire.Snapshot(
            watcher: "Micah’s MacBook Air",
            generatedAt: now,
            machines: [
                HerdWire.Machine(
                    id: "macMini",
                    name: "Mac mini",
                    shortName: "Mini",
                    avatar: "calf-mini",
                    platform: "macOS",
                    isStorage: false,
                    isWatcher: false,
                    state: "live",
                    lastUpdated: now,
                    unavailability: nil,
                    cpuPercent: 41.5,
                    sustainedCPUPercent: 38,
                    memoryPressure: "normal",
                    memoryUsedBytes: 12e9,
                    memoryTotalBytes: 24e9,
                    diskUsedPercent: 81,
                    volumes: [
                        HerdWire.Volume(
                            id: "/",
                            name: "Macintosh HD",
                            usedBytes: 810e9,
                            totalBytes: 1000e9,
                            health: nil
                        ),
                    ],
                    sessions: [
                        HerdWire.Session(
                            id: "claude:0d5f1234-aaaa",
                            short: "0d5f1234",
                            provider: "claude",
                            state: "active",
                            title: "Teach the herd to hold its own backups",
                            updatedAt: now,
                            activity: "Editing MonitorModel.swift",
                            workingDirectory: "/Users/clawd/local-code/little-herd",
                            contextTokens: 120_000,
                            model: "claude-opus-5"
                        ),
                        HerdWire.Session(
                            id: "codex:9f00",
                            short: "9f00",
                            provider: "codex",
                            state: "waiting",
                            title: "emailtriage",
                            updatedAt: now,
                            activity: nil,
                            workingDirectory: nil,
                            contextTokens: nil,
                            model: nil
                        ),
                    ]
                ),
                HerdWire.Machine(
                    id: "linux",
                    name: "Linux",
                    shortName: "Linux",
                    avatar: "goat-rack",
                    platform: "linux",
                    isStorage: false,
                    isWatcher: false,
                    state: "offline",
                    lastUpdated: nil,
                    unavailability: "“linux” didn’t answer. Likely asleep or off the network.",
                    cpuPercent: nil,
                    sustainedCPUPercent: nil,
                    memoryPressure: nil,
                    memoryUsedBytes: nil,
                    memoryTotalBytes: nil,
                    diskUsedPercent: nil,
                    volumes: [],
                    sessions: []
                ),
            ]
        )
    }
}
