import Foundation
import Testing
@testable import LittleHerd

/// A relayed machine is read from the report file its receiver keeps, never by
/// logging in to it. The fixture is the shape `herd-relay-receiver` writes:
/// the sender's lines, normalised, plus the receiver's `received_at`.
struct RelayMetricsSamplerTests {
    /// Serves a sequence of file contents, and records what was asked.
    nonisolated final class FakeRelay: @unchecked Sendable {
        private let lock = NSLock()
        private var outputs: [String]
        private(set) var calls: [(host: String, command: String)] = []
        init(_ outputs: [String]) { self.outputs = outputs }
        func read(host: String, command: String) throws -> String {
            lock.lock(); defer { lock.unlock() }
            calls.append((host, command))
            return outputs.count > 1 ? outputs.removeFirst() : outputs[0]
        }
    }

    static let base = 1_763_400_000.0

    static func report(at reportedAt: Double, cpu: String, rx: Int = 1000, tx: Int = 2000) -> String {
        """
        report_version=1
        reported_at=\(Int(reportedAt))
        cores=4
        cpu=\(cpu)
        mem=8000000000 6000000000
        swap=1000 250
        network=\(rx) \(tx)
        disk=60000000000 45000000000
        temp_c=51.3
        received_at=\(Int(reportedAt) + 1)
        """
    }

    func sampler(_ relay: FakeRelay, report: String = "sandpiper", now: Double) -> RelayMetricsSampler {
        RelayMetricsSampler(
            relayHost: "malpern@mini",
            reportName: report,
            now: { Date(timeIntervalSince1970: now) },
            read: { host, command, _ in try relay.read(host: host, command: command) }
        )
    }

    @Test
    func readsTheReportFromTheRelayHostNotTheMachine() async throws {
        let relay = FakeRelay([Self.report(at: Self.base, cpu: "100 0 50 1000 10 0 5 0")])
        let snapshot = try await sampler(relay, now: Self.base + 5).sample()

        #expect(relay.calls.count == 1)
        #expect(relay.calls[0].host == "malpern@mini")
        #expect(relay.calls[0].command == "/bin/cat \"$HOME/.local/state/herd-relay/sandpiper.txt\"")
        #expect(snapshot.coreCount == 4)
        #expect(snapshot.readings[.disk]?.capacity == 60_000_000_000)
        #expect(snapshot.readings[.memory]?.auxiliaryValue == 2_000_000_000)
        #expect(snapshot.swap?.usedBytes == 250)
        // One report is not a rate.
        #expect(snapshot.readings[.cpu] == nil)
        #expect(snapshot.readings[.network] == nil)
    }

    @Test
    func ratesComeFromTheReportsOwnClock() async throws {
        let relay = FakeRelay([
            Self.report(at: Self.base, cpu: "100 0 100 800 0 0 0 0", rx: 1000, tx: 2000),
            // 10 s later on the Pi: 250 of 1000 jiffies busy, 5000 B in, 1000 B out.
            Self.report(at: Self.base + 10, cpu: "300 0 150 1550 0 0 0 0", rx: 6000, tx: 3000),
        ])
        let sampler = sampler(relay, now: Self.base + 12)
        _ = try await sampler.sample()
        let snapshot = try await sampler.sample()

        #expect(snapshot.readings[.cpu]?.value == 25)
        #expect(snapshot.readings[.network]?.auxiliaryValue == 500) // received B/s
        #expect(snapshot.readings[.network]?.capacity == 100) // sent B/s
    }

    @Test
    func readingTheSameReportTwiceDoesNotReadAsIdle() async throws {
        let first = Self.report(at: Self.base, cpu: "100 0 100 800 0 0 0 0")
        let second = Self.report(at: Self.base + 10, cpu: "300 0 150 1550 0 0 0 0")
        // The file had not changed by the third read.
        let relay = FakeRelay([first, second, second])
        let sampler = sampler(relay, now: Self.base + 15)
        _ = try await sampler.sample()
        _ = try await sampler.sample()
        let repeated = try await sampler.sample()

        #expect(repeated.readings[.cpu]?.value == 25)
    }

    @Test
    func aStaleReportIsAnOutageNotAReading() async throws {
        let relay = FakeRelay([Self.report(at: Self.base, cpu: "100 0 50 1000 10 0 5 0")])
        await #expect(throws: RemoteMonitorError.self) {
            _ = try await sampler(relay, now: Self.base + 600).sample()
        }
    }

    @Test
    func aReportMissingItsFiguresIsRejected() async throws {
        let relay = FakeRelay(["report_version=1\nreceived_at=\(Int(Self.base))\n"])
        await #expect(throws: RemoteMonitorError.self) {
            _ = try await sampler(relay, now: Self.base).sample()
        }
    }

    @Test
    func aReportNameCannotBecomeACommand() async throws {
        #expect(RelayMetricsSampler.isValidReportName("sandpiper"))
        #expect(RelayMetricsSampler.isValidReportName("pi-2"))
        for bad in ["", "../x", "a b", "x;rm -rf ~", "$(id)", "Sandpiper", String(repeating: "a", count: 33)] {
            #expect(!RelayMetricsSampler.isValidReportName(bad), "\(bad)")
        }
        let relay = FakeRelay(["ignored"])
        await #expect(throws: RemoteMonitorError.self) {
            _ = try await sampler(relay, report: "x;id", now: Self.base).sample()
        }
        #expect(relay.calls.isEmpty)
    }

    @Test
    func aRelayedMachineOffersNoActionsOnTheRelayHost() {
        let machine = MachineConfiguration(
            id: MachineID("sandpiper"),
            name: "Sandpiper Pi",
            shortName: "Pi",
            hostname: "mini",
            hardwareSummary: "Raspberry Pi 5",
            platform: .linux,
            connection: .relay,
            avatar: .calfMini,
            sshUser: "malpern",
            serverNames: [],
            supportsGPU: false,
            relayReport: "sandpiper"
        )
        #expect(MachineActions.actions(for: machine).isEmpty)
    }
}
