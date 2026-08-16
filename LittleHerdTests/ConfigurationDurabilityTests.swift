import Foundation
import Testing
@testable import LittleHerd

/// The saved herd is the only thing in Little Herd the user cannot reconstruct
/// by pointing it at the network again — a Tailscale-only machine does not
/// advertise Bonjour, so nothing will rediscover it. These tests are about not
/// losing it.
@MainActor
struct ConfigurationDurabilityTests {
    private func store(seededWith json: String) -> (MachineConfigurationStore, UserDefaults, String) {
        let suiteName = "LittleHerdTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(
            Data(json.utf8),
            forKey: LittleHerdPreferences.machineConfigurationsKey
        )
        return (MachineConfigurationStore(defaults: defaults), defaults, suiteName)
    }

    private func storedJSON(_ defaults: UserDefaults) -> String {
        let data = defaults.data(
            forKey: LittleHerdPreferences.machineConfigurationsKey
        ) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// A machine written by a NEWER build — here a connection kind this build
    /// does not know — must not take the rest of the herd down with it. Swift
    /// fails a whole array when one element throws, so this is the difference
    /// between losing one machine and losing all of them.
    @Test
    func oneUnreadableMachineDoesNotDestroyTheOthers() {
        let (store, defaults, suite) = store(seededWith: """
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
        defer { defaults.removePersistentDomain(forName: suite) }

        let names = store.machines.map(\.shortName)
        #expect(names.contains("Air"))
        #expect(names.contains("Linux"), "an unreadable NAS must not cost us the Linux box")
    }

    /// Reading is not a licence to write. Unreadable data must survive, so a
    /// newer build can still make sense of it — overwriting it with a default
    /// turns a temporary read problem into permanent loss.
    @Test
    func unreadableDataIsNotOverwrittenWithADefault() {
        let (store, defaults, suite) = store(seededWith: """
        [{"this":"is not a machine configuration at all"}]
        """)
        defer { defaults.removePersistentDomain(forName: suite) }

        // The app still has to run, so it falls back to the local Mac.
        #expect(!store.machines.isEmpty)
        // But what was on disk must still be there.
        #expect(
            storedJSON(defaults).contains("not a machine configuration"),
            "the original data was overwritten and is gone"
        )
    }

    /// The round trip an older build performs when the user changes anything:
    /// a machine it could not read must still be there afterwards.
    @Test
    func aMachineThisBuildCannotReadSurvivesAnEdit() {
        let (store, defaults, suite) = store(seededWith: """
        [{"platform":"macOS","hostname":"localhost","avatar":"chick-laptop",
          "serverNames":[],"id":"macBookAir","shortName":"Air",
          "hardwareSummary":"MacBook Air","connection":"local",
          "supportsGPU":true,"name":"Air"},
         {"platform":"storage","hostname":"nas.local","avatar":"piglet-nas",
          "serverNames":[],"id":"nas","shortName":"NAS",
          "hardwareSummary":"Network storage","connection":"teleporter",
          "supportsGPU":false,"name":"NAS"}]
        """)
        defer { defaults.removePersistentDomain(forName: suite) }

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
            storedJSON(defaults).contains("teleporter"),
            "the machine this build could not read was dropped on the next write"
        )
    }

    /// With genuinely nothing saved, seeding the local Mac is right.
    @Test
    func afirstLaunchStillSeedsTheLocalMac() {
        let suiteName = "LittleHerdTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = MachineConfigurationStore(defaults: defaults)
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

    private func store() -> (MachineConfigurationStore, UserDefaults, String) {
        let suite = "LittleHerdTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = MachineConfigurationStore(defaults: defaults)
        store.add([machine("alpha"), machine("beta"), machine("gamma")])
        return (store, defaults, suite)
    }

    @Test
    func movingAMachineChangesTheSavedOrder() {
        let (store, defaults, suite) = store()
        defer { defaults.removePersistentDomain(forName: suite) }

        let before = store.machines.map(\.id.rawValue)
        #expect(before == ["local", "alpha", "beta", "gamma"])

        // Drag "gamma" to the top.
        store.move(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        #expect(store.machines.map(\.id.rawValue) == ["gamma", "local", "alpha", "beta"])
    }

    /// An order that does not survive a relaunch is not an order.
    @Test
    func theOrderIsPersisted() {
        let (store, defaults, suite) = store()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.move(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        let reloaded = MachineConfigurationStore(defaults: defaults)
        #expect(reloaded.machines.map(\.id.rawValue) == ["gamma", "local", "alpha", "beta"])
    }

    /// The point of the feature: what Settings shows first is what the overview
    /// shows first.
    @Test
    func theOverviewFollowsTheSavedOrder() {
        let (store, defaults, suite) = store()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.move(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        let model = MonitorModel(configurations: store.machines)
        #expect(model.machines.map(\.machine.rawValue) == ["gamma", "local", "alpha", "beta"])
        #expect(model.diskMachines.map(\.machine.rawValue) == ["gamma", "local", "alpha", "beta"])
    }

    /// A move that changes nothing must not churn the saved data.
    @Test
    func movingAMachineOntoItselfChangesNothing() {
        let (store, defaults, suite) = store()
        defer { defaults.removePersistentDomain(forName: suite) }

        let before = store.machines
        store.move(fromOffsets: IndexSet(integer: 1), toOffset: 1)
        #expect(store.machines == before)
    }
}
