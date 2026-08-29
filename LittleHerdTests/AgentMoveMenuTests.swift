import Foundation
import Testing

@testable import LittleHerd

@Suite("Move to")
struct AgentMoveMenuTests {
    /// **Every machine is listed, including the ones that will not take it.**
    /// A drag onto an ineligible machine simply does not take, and that
    /// silence reads as the feature being off. The menu says which and why.
    @Test
    func aRefusalIsListedWithItsReason() {
        #expect(
            AgentMoveMenu.reason(.noCheckout(repository: "little-herd"))
                == "no checkout of little-herd"
        )
        #expect(AgentMoveMenu.reason(.noAgent) == "no agent installed")
        #expect(AgentMoveMenu.reason(.unknown) == "not reachable")
        #expect(AgentMoveMenu.reason(.excluded) == "not allowed to host work")
    }

    /// A machine that will take it says only its name — a reason is what you
    /// need when the answer is no.
    @Test
    func anEligibleMachineIsJustItsName() {
        #expect(
            AgentMoveMenu.reason(
                .eligible(
                    AgentInstallation(
                        provider: .claude, version: "1", path: "/x"
                    ),
                    .unverified
                )
            ) == nil
        )
    }

    /// The machine it is already on is not somewhere to move it to.
    @Test
    func theOriginIsNotOffered() {
        let session = AgentSession(
            id: "s", provider: .claude, projectName: "p",
            state: .waiting, updatedAt: Date(), progress: nil
        )
        let herd = [
            DestinationAccount(
                machine: MachineID("local"), name: "Air",
                symbolName: "laptopcomputer", report: nil, mayHostSessions: true
            ),
            DestinationAccount(
                machine: MachineID("mini"), name: "Mini",
                symbolName: "macmini", report: nil, mayHostSessions: true
            ),
        ]
        let items = AgentMoveMenu.items(
            moving: session,
            from: MachineID("local"),
            in: herd,
            requiresApproval: false,
            name: { $0 == MachineID("mini") ? "Mini" : "Air" },
            move: { _ in }
        )
        #expect(items.count == 1)
        #expect(items.first?.title.hasPrefix("Mini") == true)
    }
}
