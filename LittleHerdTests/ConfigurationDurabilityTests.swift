import Foundation
import Testing
@testable import LittleHerd

/// The saved herd is the only thing in Little Herd the user cannot reconstruct
/// by pointing it at the network again — a Tailscale-only machine does not
/// advertise Bonjour, so nothing will rediscover it. These tests are about not
/// losing it.
@MainActor
struct ConfigurationDurabilityTests {
    private func store(
        seededWith json: String
    ) -> (MachineConfigurationStore, InMemoryConfigurationStorage) {
        let storage = InMemoryConfigurationStorage(seededWith: json)
        return (MachineConfigurationStore(storage: storage, localMachine: .testLocal), storage)
    }

    private func storedJSON(_ storage: InMemoryConfigurationStorage) -> String {
        storage.savedJSON
    }

    /// A machine written by a NEWER build — here a connection kind this build
    /// does not know — must not take the rest of the herd down with it. Swift
    /// fails a whole array when one element throws, so this is the difference
    /// between losing one machine and losing all of them.
    @Test
    func oneUnreadableMachineDoesNotDestroyTheOthers() {
        let (store, storage) = store(seededWith: """
        [{"platform":"macOS","hostname":"localhost","avatar":"chick-laptop",
          "serverNames":[],"id":"macBookAir","shortName":"Air",
          "hardwareSummary":"MacBook Air","connection":"local",
          "supportsGPU":true,"name":"Air"},
         {"platform":"linux","hostname":"linux","avatar":"ox-gpu",
          "serverNames":[],"id":"linux","shortName":"Linux",
          "hardwareSummary":"Linux","connection":"ssh",
          "supportsGPU":false,"name":"Linux"},
         {"platform":"storage","hostname":"nas.local","avatar":"piglet-nas",
          "serverNames":[],"id":"nas","shortName":"NAS",
          "hardwareSummary":"Network storage","connection":"teleporter",
          "supportsGPU":false,"name":"NAS"}]
        """)

        let names = store.machines.map(\.shortName)
        #expect(names.contains("Air"))
        #expect(names.contains("Linux"), "an unreadable NAS must not cost us the Linux box")
    }

    /// Reading is not a licence to write. Unreadable data must survive, so a
    /// newer build can still make sense of it — overwriting it with a default
    /// turns a temporary read problem into permanent loss.
    @Test
    func unreadableDataIsNotOverwrittenWithADefault() {
        let (store, storage) = store(seededWith: """
        [{"this":"is not a machine configuration at all"}]
        """)

        // The app still has to run, so it falls back to the local Mac.
        #expect(!store.machines.isEmpty)
        // But what was on disk must still be there.
        #expect(
            storedJSON(storage).contains("not a machine configuration"),
            "the original data was overwritten and is gone"
        )
    }

    /// The round trip an older build performs when the user changes anything:
    /// a machine it could not read must still be there afterwards.
    @Test
    func aMachineThisBuildCannotReadSurvivesAnEdit() {
        let (store, storage) = store(seededWith: """
        [{"platform":"macOS","hostname":"localhost","avatar":"chick-laptop",
          "serverNames":[],"id":"macBookAir","shortName":"Air",
          "hardwareSummary":"MacBook Air","connection":"local",
          "supportsGPU":true,"name":"Air"},
         {"platform":"storage","hostname":"nas.local","avatar":"piglet-nas",
          "serverNames":[],"id":"nas","shortName":"NAS",
          "hardwareSummary":"Network storage","connection":"teleporter",
          "supportsGPU":false,"name":"NAS"}]
        """)

        store.add([
            MachineConfiguration(
                id: MachineID("linux"),
                name: "Linux",
                shortName: "Linux",
                hostname: "linux",
                hardwareSummary: "Linux",
                platform: .linux,
                connection: .ssh,
                avatar: .oxGPU,
                identityFile: nil,
                serverNames: [],
                supportsGPU: false
            )
        ])

        #expect(store.machines.contains { $0.shortName == "Linux" })
        #expect(
            storedJSON(storage).contains("teleporter"),
            "the machine this build could not read was dropped on the next write"
        )
    }

    /// With genuinely nothing saved, seeding the local Mac is right.
    @Test
    func afirstLaunchStillSeedsTheLocalMac() {
        let store = MachineConfigurationStore(
            storage: InMemoryConfigurationStorage()
        )
        #expect(store.machines.count == 1)
        #expect(store.machines[0].connection == .local)
    }
}

/// The saved order is the order everywhere, so rearranging in Settings has to
/// survive a relaunch and reach the overview.
@MainActor
struct MachineOrderTests {
    private func machine(_ id: String, _ connection: MachineConnection = .ssh) -> MachineConfiguration {
        MachineConfiguration(
            id: MachineID(id),
            name: id.capitalized,
            shortName: id.capitalized,
            hostname: id,
            hardwareSummary: "Test",
            platform: connection == .local ? .macOS : .linux,
            connection: connection,
            avatar: .oxGPU,
            identityFile: nil,
            serverNames: [],
            supportsGPU: false
        )
    }

    private func store() -> (MachineConfigurationStore, InMemoryConfigurationStorage) {
        let storage = InMemoryConfigurationStorage()
        let store = MachineConfigurationStore(storage: storage, localMachine: .testLocal)
        store.add([machine("alpha"), machine("beta"), machine("gamma")])
        return (store, storage)
    }

    @Test
    func movingAMachineChangesTheSavedOrder() {
        let (store, storage) = store()

        let before = store.machines.map(\.id.rawValue)
        #expect(before == ["local", "alpha", "beta", "gamma"])

        // Drag "gamma" to the top.
        store.move(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        #expect(store.machines.map(\.id.rawValue) == ["gamma", "local", "alpha", "beta"])
    }

    /// An order that does not survive a relaunch is not an order.
    @Test
    func theOrderIsPersisted() {
        let (store, storage) = store()

        store.move(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        let reloaded = MachineConfigurationStore(storage: storage, localMachine: .testLocal)
        #expect(reloaded.machines.map(\.id.rawValue) == ["gamma", "local", "alpha", "beta"])
    }

    /// The point of the feature: what Settings shows first is what the overview
    /// shows first.
    @Test
    func theOverviewFollowsTheSavedOrder() {
        let (store, storage) = store()

        store.move(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        let model = MonitorModel(configurations: store.machines)
        #expect(model.machines.map(\.machine.rawValue) == ["gamma", "local", "alpha", "beta"])
        #expect(model.diskMachines.map(\.machine.rawValue) == ["gamma", "local", "alpha", "beta"])
    }

    /// A move that changes nothing must not churn the saved data.
    @Test
    func movingAMachineOntoItselfChangesNothing() {
        let (store, storage) = store()

        let before = store.machines
        store.move(fromOffsets: IndexSet(integer: 1), toOffset: 1)
        #expect(store.machines == before)
    }
}
