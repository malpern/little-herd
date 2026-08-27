import Foundation
import Testing
@testable import LittleHerd

/// What a machine will take, when a token is carried over it.
struct AgentDropEligibilityTests {
    private let air = MachineID("air")
    private let mini = MachineID("mini")
    private let linux = MachineID("linux")
    private let nas = MachineID("nas")

    private let claude = AgentInstallation(
        provider: .claude,
        version: "2.1.234",
        path: "/Users/x/.local/bin/claude"
    )

    private func session(directory: String?) -> AgentSession {
        AgentSession(
            id: "a",
            provider: .claude,
            projectName: "little-herd",
            state: .active,
            updatedAt: .now,
            progress: nil,
            title: "Panel redesign",
            activity: nil,
            model: "claude-opus-5",
            workingDirectory: directory
        )
    }

    private func account(
        _ machine: MachineID,
        report: DestinationReport?,
        auth: AgentAuthState = .unverified,
        mayHost: Bool = false
    ) -> DestinationAccount {
        DestinationAccount(
            machine: machine,
            name: machine.rawValue,
            symbolName: "laptopcomputer",
            report: report,
            mayHostSessions: mayHost,
            auth: auth,
            isVerifying: false
        )
    }

    private var carried: MachineAgentActivity {
        MachineAgentActivity(
            provider: .claude,
            sessions: [session(directory: "/Users/x/code/little-herd")]
        )
    }

    private func herd(
        miniReport: DestinationReport? = DestinationReport(
            installations: [],
            checkouts: [:]
        ),
        miniAuth: AgentAuthState = .unverified
    ) -> [DestinationAccount] {
        [
            account(
                air,
                report: DestinationReport(
                    installations: [claude],
                    checkouts: ["malpern/little-herd": "/Users/x/code/little-herd"]
                )
            ),
            account(mini, report: miniReport, auth: miniAuth),
            account(linux, report: nil),
            account(nas, report: nil),
        ]
    }

    private func can(_ machine: MachineID, _ accounts: [DestinationAccount]) -> Bool {
        AgentDropEligibility.canAccept(
            machine, carrying: carried, from: air, in: accounts
        )
    }

    /// **The regression this whole file exists to catch.** `mayHostSessions`
    /// defaults to off and its only setter was removed, so asking the full
    /// question would return `.excluded` for every machine and the herd would
    /// refuse a drag everywhere. Every account in these fixtures has it off.
    @Test
    func aMachineIsNotRefusedMerelyForHavingNoStoredIntent() {
        let accounts = herd(
            miniReport: DestinationReport(
                installations: [claude],
                checkouts: ["malpern/little-herd": "/Users/y/little-herd"]
            )
        )
        #expect(can(mini, accounts))
    }

    /// A machine with the agent but no copy of the work refuses, and says so.
    @Test
    func aMachineWithoutTheRepositoryRefuses() {
        let accounts = herd(
            miniReport: DestinationReport(
                installations: [claude],
                checkouts: ["malpern/something-else": "/Users/y/something-else"]
            )
        )
        #expect(!can(mini, accounts))
        #expect(
            AgentDropEligibility.eligibility(
                of: mini, carrying: carried, from: air, in: accounts
            ) == .noCheckout(repository: "malpern/little-herd")
        )
    }

    /// A machine with no agent refuses.
    @Test
    func aMachineWithNoAgentRefuses() {
        #expect(!can(mini, herd()))
    }

    /// A machine whose provider turned it down refuses — the case that is
    /// invisible from outside, since the binary is present and healthy.
    @Test
    func aMachineThatIsSignedOutRefuses() {
        let accounts = herd(
            miniReport: DestinationReport(
                installations: [claude],
                checkouts: ["malpern/little-herd": "/Users/y/little-herd"]
            ),
            miniAuth: .refused(reason: "credentials expired")
        )
        #expect(!can(mini, accounts))
    }

    /// A machine nobody has measured refuses, and that is not the same as
    /// being told no — the NAS runs no probe at all.
    @Test
    func anUnmeasuredMachineRefuses() {
        #expect(!can(nas, herd()))
        #expect(
            AgentDropEligibility.eligibility(
                of: nas, carrying: carried, from: air, in: herd()
            ) == .unknown
        )
    }

    /// The origin is never its own destination.
    @Test
    func theOriginIsNeverADestination() {
        #expect(!can(air, herd()))
    }

    /// Work outside every known checkout asks nobody the checkout question,
    /// rather than guessing at a repository.
    @Test
    func workOutsideAnyCheckoutDoesNotAskAboutOne() {
        let accounts = herd(
            miniReport: DestinationReport(installations: [claude], checkouts: [:])
        )
        let strayCarry = MachineAgentActivity(
            provider: .claude,
            sessions: [session(directory: "/Users/x/Downloads")]
        )
        #expect(
            AgentDropEligibility.repository(
                of: strayCarry, from: air, in: accounts
            ) == nil
        )
        #expect(
            AgentDropEligibility.canAccept(
                mini, carrying: strayCarry, from: air, in: accounts
            )
        )
    }

    /// A repository checked out inside another is named as itself.
    @Test
    func theInnermostCheckoutWins() {
        let report = DestinationReport(
            installations: [claude],
            checkouts: [
                "malpern/outer": "/Users/x/code",
                "malpern/inner": "/Users/x/code/inner",
            ]
        )
        #expect(report.repository(containing: "/Users/x/code/inner/deep") == "malpern/inner")
        #expect(report.repository(containing: "/Users/x/code/other") == "malpern/outer")
    }

    /// A sibling directory whose name merely starts the same way is not inside
    /// the checkout. Prefix matching without the separator says it is.
    @Test
    func aSiblingWithASharedPrefixIsNotInside() {
        let report = DestinationReport(
            installations: [claude],
            checkouts: ["malpern/little-herd": "/Users/x/code/little-herd"]
        )
        #expect(report.repository(containing: "/Users/x/code/little-herd-site") == nil)
    }
}
