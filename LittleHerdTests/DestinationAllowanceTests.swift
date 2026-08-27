import Foundation
import Testing
@testable import LittleHerd

/// Allowing a machine to take work has to outlive the process.
///
/// **This is the test that would have caught the first version.** The control
/// was wired to `MachineMonitorModel.setMayHostSessions`, which changes memory
/// and nothing else — persistence flowed the other way, from a Settings
/// checkbox that edited the stored configuration. The toggle worked perfectly
/// and was forgotten on the next launch, which for a permission is worse than
/// not having one.
@MainActor
struct DestinationAllowanceTests {
    private func configuration(_ id: String) -> MachineConfiguration {
        MachineConfiguration(
            id: MachineID(id),
            name: id,
            shortName: id,
            hostname: "\(id).local",
            hardwareSummary: id,
            platform: .macOS,
            connection: .ssh,
            avatar: .calfMini,
            identityFile: nil,
            serverNames: [],
            supportsGPU: false
        )
    }

    /// Written through the store, so a second store reading the same bytes
    /// finds it — which is what a relaunch is.
    @Test
    func anAllowanceSurvivesARelaunch() throws {
        let storage = InMemoryConfigurationStorage()
        let store = MachineConfigurationStore(storage: storage)
        store.replace(with: [configuration("mini"), configuration("linux")])

        // The same call the control makes, so the test covers the path the
        // view actually takes rather than one that merely resembles it.
        store.setMayHostSessions(true, on: MachineID("mini"))

        let relaunched = MachineConfigurationStore(storage: storage)
        #expect(
            relaunched.machines.first { $0.id == MachineID("mini") }?
                .mayHostSessions == true
        )
        // And it is granted to one machine, not to the herd.
        #expect(
            relaunched.machines.first { $0.id == MachineID("linux") }?
                .mayHostSessions == false
        )
    }

    /// Withdrawing it persists too, or a mis-click could only ever be undone
    /// until the next launch.
    @Test
    func withdrawingAnAllowancePersistsAsWell() throws {
        let storage = InMemoryConfigurationStorage()
        let store = MachineConfigurationStore(storage: storage)
        var mini = configuration("mini")
        mini.mayHostSessions = true
        store.replace(with: [mini])

        store.setMayHostSessions(false, on: MachineID("mini"))

        let relaunched = MachineConfigurationStore(storage: storage)
        #expect(
            relaunched.machines.first { $0.id == MachineID("mini") }?
                .mayHostSessions == false
        )
    }

    /// Setting it to what it already is changes nothing, so a control that
    /// redraws does not push the whole herd back through the monitors.
    @Test
    func settingItToWhatItAlreadyIsIsNotAChange() {
        let store = MachineConfigurationStore(
            storage: InMemoryConfigurationStorage()
        )
        store.replace(with: [configuration("mini")])

        #expect(store.setMayHostSessions(false, on: MachineID("mini")) == false)
        #expect(store.setMayHostSessions(true, on: MachineID("mini")))
    }

    /// An unknown machine is not silently created.
    @Test
    func allowingAMachineTheHerdDoesNotHaveDoesNothing() {
        let store = MachineConfigurationStore(
            storage: InMemoryConfigurationStorage()
        )
        store.replace(with: [configuration("mini")])

        #expect(store.setMayHostSessions(true, on: MachineID("ghost")) == false)
        #expect(store.machines.count == 1)
    }

    /// A herd saved before this key existed still decodes, and reads as not
    /// allowed rather than throwing the machine away. The preference is
    /// optional in the stored form for exactly this reason.
    @Test
    func aHerdSavedWithoutTheKeyStillLoads() throws {
        // Written by encoding a real configuration and stripping the key, so
        // the fixture cannot drift from the shape the app actually saves —
        // a hand-typed one missed a field and decoded to nothing at all.
        let saved = InMemoryConfigurationStorage()
        MachineConfigurationStore(storage: saved)
            .replace(with: [configuration("mini")])
        var entries = try #require(
            JSONSerialization.jsonObject(
                with: Data(saved.savedJSON.utf8)
            ) as? [[String: Any]]
        )
        for index in entries.indices {
            entries[index].removeValue(forKey: "mayHostSessionsPreference")
        }
        let stripped = try JSONSerialization.data(withJSONObject: entries)

        let store = MachineConfigurationStore(
            storage: InMemoryConfigurationStorage(
                seededWith: String(decoding: stripped, as: UTF8.self)
            )
        )

        let mini = try #require(
            store.machines.first { $0.id == MachineID("mini") }
        )
        #expect(mini.mayHostSessions == false)
        #expect(mini.mayHostSessionsPreference == nil)
    }
}
