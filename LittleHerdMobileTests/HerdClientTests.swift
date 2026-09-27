import Foundation
import Testing

@testable import LittleHerdMobile

/// The phone's side of the wire, without a Mac.
@Suite("Reading the herd")
struct HerdClientTests {
    /// What people type: a bare Tailscale name, a name with a port, an IPv4
    /// with a port, and an IPv6 literal — whose colons are not a port.
    @Test
    func aTypedAddressIsReadTheWayAPersonMeantIt() {
        #expect(
            WatcherEndpoint.typed(from: " mini.tail9d0bb8.ts.net ")
                == .typed(host: "mini.tail9d0bb8.ts.net", port: HerdWire.defaultPort)
        )
        #expect(
            WatcherEndpoint.typed(from: "mini.local:8000")
                == .typed(host: "mini.local", port: 8000)
        )
        #expect(
            WatcherEndpoint.typed(from: "100.74.233.94:7841")
                == .typed(host: "100.74.233.94", port: 7841)
        )
        #expect(
            WatcherEndpoint.typed(from: "fd7a::1")
                == .typed(host: "fd7a::1", port: HerdWire.defaultPort)
        )
        #expect(
            WatcherEndpoint.typed(from: "[fd7a::1]:9000")
                == .typed(host: "fd7a::1", port: 9000)
        )
        #expect(WatcherEndpoint.typed(from: "   ") == nil)
    }

    /// The name a person sees hides the default port and shows any other.
    @Test
    func aTypedAddressIsShownWithoutTheDefaultPort() {
        #expect(WatcherEndpoint.typed(host: "mini", port: HerdWire.defaultPort).displayName == "mini")
        #expect(WatcherEndpoint.typed(host: "mini", port: 8000).displayName == "mini:8000")
    }

    @Test
    func theBodyIsWhatFollowsTheHeaders() throws {
        let raw = Data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"a\":1}".utf8)
        #expect(try HerdFetcher.parse(raw) == Data("{\"a\":1}".utf8))
    }

    /// A 401 is a different conversation from any other failure: it means
    /// the phone reached the right Mac and has the wrong (or no) code.
    @Test
    func aRefusalForTheCodeIsToldApart() {
        let raw = Data("HTTP/1.1 401 Unauthorized\r\nContent-Length: 0\r\n\r\n".utf8)
        #expect(throws: HerdFetcher.Failure.needsPairingCode) {
            try HerdFetcher.parse(raw)
        }
        let other = Data("HTTP/1.1 500 Oops\r\n\r\n".utf8)
        #expect(throws: HerdFetcher.Failure.status(500)) {
            try HerdFetcher.parse(other)
        }
        #expect(throws: HerdFetcher.Failure.badResponse) {
            try HerdFetcher.parse(Data("not http at all".utf8))
        }
    }

    /// The fixture the harness draws from has to decode with the same
    /// decoder the phone uses, or the harness shows a screen the phone
    /// never would.
    @Test
    func theFixtureHerdDecodes() throws {
        let url = try #require(Bundle(for: Marker.self).url(forResource: "fixture-herd", withExtension: "json")
            ?? Bundle.main.url(forResource: "fixture-herd", withExtension: "json"))
        let snapshot = try HerdWire.decoder().decode(HerdWire.Snapshot.self, from: Data(contentsOf: url))
        #expect(snapshot.machines.count == 4)
        #expect(snapshot.machines.contains { $0.isStorage })
        #expect(snapshot.machines.flatMap(\.sessions).contains { $0.state == "stalled" })
    }

    /// A watcher from before moves and alerts sends none of the new fields,
    /// and the phone must still read it — the two update on different days.
    @Test
    func anOlderWatcherStillDecodes() throws {
        let old = #"""
        {"version":1,"watcher":"Mac","generatedAt":"2026-09-26T12:00:00Z","machines":[
         {"id":"m","name":"Mac","shortName":"Mac","avatar":"calf-mini","platform":"macOS",
          "isStorage":false,"isWatcher":true,"state":"live","volumes":[],"sessions":[
           {"id":"claude:1","short":"1","provider":"claude","state":"waiting","title":"t",
            "updatedAt":"2026-09-26T12:00:00Z"}]}]}
        """#
        let snapshot = try HerdWire.decoder().decode(HerdWire.Snapshot.self, from: Data(old.utf8))
        #expect(snapshot.acceptsWrites == nil)
        #expect(snapshot.machines[0].cpuHistory == nil)
        // No verdict from the watcher means the phone offers no move.
        #expect(!snapshot.machines[0].sessions[0].isMovable)
    }

    /// Moving is the watcher's decision: refused, or nowhere to go, is not
    /// movable however the session looks.
    @Test
    func onlyTheWatchersVerdictMakesASessionMovable() throws {
        let url = try #require(Bundle.main.url(forResource: "fixture-herd", withExtension: "json"))
        let snapshot = try HerdWire.decoder().decode(HerdWire.Snapshot.self, from: Data(contentsOf: url))
        let sessions = snapshot.machines.flatMap(\.sessions)
        #expect(sessions.contains { $0.isMovable })
        #expect(sessions.filter { $0.state == "stalled" }.allSatisfy { !$0.isMovable })
        #expect(sessions.filter { $0.state == "completed" }.allSatisfy { !$0.isMovable })
    }

    /// A pushed alert arrives with the episode id as its identifier; opening
    /// it has to find the machine from that alone.
    @Test
    func aPushedAlertNamesItsMachine() {
        #expect(HerdNotifier.machine(fromCollapseID: "macMini:diskFull") == "macMini")
        #expect(HerdNotifier.machine(fromCollapseID: "transfer:herd/x") == nil)
        #expect(HerdNotifier.machine(fromCollapseID: "nonsense") == nil)
    }

    /// Waiting before stalled before working, oldest first within each — the
    /// session kept waiting longest is the one to answer.
    @Test
    func theAIListPutsTheLongestWaitFirst() {
        func session(_ id: String, _ state: String, _ minutesAgo: Double) -> HerdWire.Session {
            HerdWire.Session(
                id: id, short: id, provider: "claude", state: state, title: id,
                updatedAt: Date(timeIntervalSinceNow: -minutesAgo * 60),
                activity: nil, workingDirectory: nil, contextTokens: nil, model: nil
            )
        }
        let sorted = [
            session("work", "active", 90),
            session("newWait", "waiting", 1),
            session("stall", "stalled", 500),
            session("oldWait", "waiting", 60),
        ].sorted(by: AIOverview.order)
        #expect(sorted.map(\.id) == ["oldWait", "newWait", "stall", "work"])
    }

    private final class Marker {}
}
