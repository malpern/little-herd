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
