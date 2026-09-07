import Foundation
import Testing

@testable import LittleHerd

/// What a drag can do with a machine — the three-way that lets a machine with
/// a fixable gap lift to meet the drag instead of staying put.
@Suite("Drop disposition")
struct DropDispositionTests {
    private func account(
        _ id: String, agent: AgentTaskProvider?, checkout: Bool
    ) -> DestinationAccount {
        DestinationAccount(
            machine: MachineID(id), name: id, symbolName: "desktopcomputer",
            report: DestinationReport(
                installations: agent.map {
                    [AgentInstallation(provider: $0, version: "1", path: "/x/\($0.rawValue)")]
                } ?? [],
                checkouts: checkout ? ["little-herd": "/x/little-herd"] : [:]
            ),
            mayHostSessions: true, auth: .unverified, isVerifying: false
        )
    }

    private func session(_ p: AgentTaskProvider) -> AgentSession {
        AgentSession(
            id: "\(p.rawValue):s", provider: p, projectName: "little-herd",
            state: .waiting, updatedAt: .now, progress: nil,
            workingDirectory: "/x/little-herd"
        )
    }

    private func disposition(
        to id: String, herd: [DestinationAccount], provider: AgentTaskProvider = .claude
    ) -> AgentDropEligibility.DropDisposition {
        AgentDropEligibility.disposition(
            of: MachineID(id),
            carrying: MachineAgentActivity(provider: provider, sessions: [session(provider)]),
            from: MachineID("a"), in: herd
        )
    }

    /// A machine with the agent and the checkout is ready — unchanged.
    @Test
    func aReadyMachineIsReady() {
        let herd = [
            account("a", agent: .claude, checkout: true),
            account("b", agent: .claude, checkout: true),
        ]
        #expect(disposition(to: "b", herd: herd) == .ready)
    }

    /// **A missing checkout is fixable — it lifts.** Whether the clone can
    /// actually run is decided at the drop, when the source's remote is known;
    /// here it is optimistic, so the machine is reachable at all.
    @Test
    func amissingCheckoutIsFixable() {
        let herd = [
            account("a", agent: .claude, checkout: true),
            account("b", agent: .claude, checkout: false),
        ]
        #expect(disposition(to: "b", herd: herd) == .fixable)
        // `canAccept` stays "ready as it is" — a fixable machine is NOT ready,
        // so it answers false there. The drag reaches it through `disposition`
        // instead, which is the whole point of the three-way.
        #expect(
            !AgentDropEligibility.canAccept(
                MachineID("b"),
                carrying: MachineAgentActivity(provider: .claude, sessions: [session(.claude)]),
                from: MachineID("a"), in: herd
            ),
            "canAccept means ready-as-is, which a fixable machine is not"
        )
    }

    /// A missing Claude is fixable — its installer is one command.
    @Test
    func amissingClaudeIsFixable() {
        let herd = [
            account("a", agent: .claude, checkout: true),
            account("b", agent: nil, checkout: true),
        ]
        #expect(disposition(to: "b", herd: herd) == .fixable)
    }

    /// **A missing Codex is a refusal, not a fix.** No one-command install, so
    /// nothing `--fix` could run — the machine stays put.
    @Test
    func amissingCodexRefuses() {
        let herd = [
            account("a", agent: .codex, checkout: true),
            account("b", agent: nil, checkout: true),
        ]
        #expect(disposition(to: "b", herd: herd, provider: .codex) == .refuse)
        #expect(
            !AgentDropEligibility.canAccept(
                MachineID("b"),
                carrying: MachineAgentActivity(provider: .codex, sessions: [session(.codex)]),
                from: MachineID("a"), in: herd
            )
        )
    }

    /// The origin never accepts its own card, fixable or not.
    @Test
    func theOriginNeverAccepts() {
        let herd = [account("a", agent: .claude, checkout: true)]
        #expect(disposition(to: "a", herd: herd) == .refuse)
    }
}
