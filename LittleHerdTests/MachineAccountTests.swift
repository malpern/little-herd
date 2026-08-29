import Foundation
import Testing

@testable import LittleHerd

@Suite("A machine is an account on a host")
struct MachineAccountTests {
    private func machine(user: String?) -> MachineConfiguration {
        MachineConfiguration(
            id: MachineID("mini"),
            name: "Mac mini",
            shortName: "Mini",
            hostname: "openclaw.local",
            hardwareSummary: "Mac mini",
            platform: .macOS,
            connection: .ssh,
            avatar: .calfMini,
            identityFile: nil,
            sshUser: user,
            serverNames: [],
            supportsGPU: false
        )
    }

    /// **Nothing changes for a machine that never had an account.** Every
    /// configuration already saved has none, and it must go on meaning what it
    /// meant: whatever `ssh` would pick.
    @Test
    func noAccountIsJustTheHost() {
        #expect(machine(user: nil).sshDestination == "openclaw.local")
        #expect(machine(user: "").sshDestination == "openclaw.local")
        #expect(machine(user: "   ").sshDestination == "openclaw.local")
    }

    /// And with one, it is the pair.
    @Test
    func anAccountIsCarriedWithTheHost() {
        #expect(machine(user: "malpern").sshDestination == "malpern@openclaw.local")
    }

    /// **The composed destination has to survive the guard on host names.**
    /// `SSHHostName` exists because a name beginning with a dash would be read
    /// by `ssh` as an option; adding an account must not slip past it or
    /// quietly fail it.
    @Test
    func theComposedDestinationIsStillAValidHost() {
        #expect(SSHHostName.isValid(machine(user: "malpern").sshDestination))
        #expect(SSHHostName.isValid(machine(user: nil).sshDestination))
        // And a hostile account name is refused rather than sent.
        let hostile = machine(user: "-oProxyCommand=touch /tmp/x")
        #expect(!SSHHostName.isValid(hostile.sshDestination))
    }

    /// One host under two accounts is two machines, with their own checkouts,
    /// agents and permissions — which is the entire reason for this.
    @Test
    func oneHostCanBeTwoMachines() {
        var work = machine(user: "clawd")
        work.name = "Mini (jobs)"
        var console = machine(user: "malpern")
        console.name = "Mini"
        #expect(work.sshDestination != console.sshDestination)
        #expect(work.hostname == console.hostname)
    }
}

@MainActor
@Suite("Two accounts on one host")
struct HerdAccountStoreTests {
    private func mini(_ user: String?, name: String) -> MachineConfiguration {
        MachineConfiguration(
            id: MachineID("mini-\(user ?? "default")"),
            name: name,
            shortName: name,
            hostname: "openclaw.local",
            hardwareSummary: "Mac mini",
            platform: .macOS,
            connection: .ssh,
            avatar: .calfMini,
            identityFile: nil,
            sshUser: user,
            serverNames: [],
            supportsGPU: false
        )
    }

    /// **Both accounts get in.** Deduplicating on hostname alone kept the
    /// second one out, which would have made the account field unusable by
    /// exactly the person who needed it.
    @Test
    func oneHostUnderTwoAccountsIsTwoEntries() {
        let store = MachineConfigurationStore(
            storage: InMemoryConfigurationStorage(),
            localMachine: .testLocal
        )
        store.add([mini("clawd", name: "Mini jobs")])
        store.add([mini("malpern", name: "Mini console")])
        #expect(store.machines.count { $0.hostname == "openclaw.local" } == 2)
    }

    /// The same account twice is still one machine.
    @Test
    func theSameAccountTwiceIsStillOne() {
        let store = MachineConfigurationStore(
            storage: InMemoryConfigurationStorage(),
            localMachine: .testLocal
        )
        store.add([mini("clawd", name: "Mini jobs")])
        store.add([mini("clawd", name: "Mini jobs again")])
        #expect(store.machines.count { $0.hostname == "openclaw.local" } == 1)
    }
}
