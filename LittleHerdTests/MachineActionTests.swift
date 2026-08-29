import Foundation
import Testing

@testable import LittleHerd

@Suite("What you can do with a machine")
struct MachineActionTests {
    private func machine(
        _ connection: MachineConnection,
        platform: MachinePlatform = .macOS,
        user: String? = nil,
        host: String = "openclaw.local"
    ) -> MachineConfiguration {
        MachineConfiguration(
            id: MachineID("m"),
            name: "M",
            shortName: "M",
            hostname: host,
            hardwareSummary: "",
            platform: platform,
            connection: connection,
            avatar: .calfMini,
            identityFile: nil,
            sshUser: user,
            serverNames: [],
            supportsGPU: false
        )
    }

    /// **The account travels with the shell.** A machine configured as one
    /// login must open a shell on that login, not on whichever one ssh would
    /// have picked — which is the whole reason the account field exists.
    @Test
    func aShellOpensOnTheAccountTheMachineIs() {
        let actions = MachineActions.actions(for: machine(.ssh, user: "malpern"))
        let shell = actions.first { $0.title.contains("SSH") }
        #expect(shell?.url.absoluteString == "ssh://malpern@openclaw.local")
    }

    /// Offering to connect to the Mac this is running on reads as a mistake in
    /// the list; a shell here is a Terminal window away.
    @Test
    func thereIsNothingToOpenOnThisMac() {
        #expect(MachineActions.actions(for: machine(.local)).isEmpty)
    }

    /// **A hostile hostname never becomes a URL.** `SSHHostName` exists because
    /// a name beginning with a dash is read by ssh as an option, and a context
    /// menu is one more place it could be handed one.
    @Test
    func aHostileHostnameIsRefused() {
        let hostile = machine(.ssh, host: "-oProxyCommand=touch /tmp/x")
        #expect(MachineActions.actions(for: hostile).isEmpty)
    }

    /// The NAS is a web console and a file server. It is not a shell: DSM
    /// restricts shell access to administrators, so offering one would be an
    /// invitation to a permission denied.
    @Test
    func theNASOffersItsConsoleRatherThanAShell() {
        let actions = MachineActions.actions(for: machine(.dsm, platform: .storage))
        #expect(actions.contains { $0.title == "Open DSM" })
        #expect(actions.contains { $0.title == "Browse Files" })
        #expect(!actions.contains { $0.title.contains("SSH") })
    }

    /// Screen sharing is a Mac thing; a Linux box gets a shell and no offer of
    /// a desktop that is probably not running.
    @Test
    func onlyAMacIsOfferedItsScreen() {
        #expect(
            MachineActions.actions(for: machine(.ssh))
                .contains { $0.title == "Screen Sharing" }
        )
        #expect(
            !MachineActions.actions(for: machine(.ssh, platform: .linux))
                .contains { $0.title == "Screen Sharing" }
        )
    }
}
