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
        let store = MachineConfigurationStore(storage: storage, localMachine: .testLocal)
        store.replace(with: [configuration("mini"), configuration("linux")])

        // The same call the control makes, so the test covers the path the
        // view actually takes rather than one that merely resembles it.
        store.setMayHostSessions(true, on: MachineID("mini"))

        let relaunched = MachineConfigurationStore(storage: storage, localMachine: .testLocal)
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
        let store = MachineConfigurationStore(storage: storage, localMachine: .testLocal)
        var mini = configuration("mini")
        mini.mayHostSessions = true
        store.replace(with: [mini])

        store.setMayHostSessions(false, on: MachineID("mini"))

        let relaunched = MachineConfigurationStore(storage: storage, localMachine: .testLocal)
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
        MachineConfigurationStore(storage: saved, localMachine: .testLocal)
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

/// A permission is about a machine, and an id is not one.
@MainActor
struct DestinationGrantBindingTests {
    private func configuration(
        _ id: String,
        hostname: String
    ) -> MachineConfiguration {
        MachineConfiguration(
            id: MachineID(id),
            name: id,
            shortName: id,
            hostname: hostname,
            hardwareSummary: id,
            platform: .macOS,
            connection: .ssh,
            avatar: .calfMini,
            identityFile: nil,
            serverNames: [],
            supportsGPU: false
        )
    }

    /// **The point of the whole thing.** `id` is minted at discovery and never
    /// changes; `hostname` is an ordinary editable field. Re-pointing an entry
    /// at another box must not carry an approval given to the old one.
    @Test
    func aGrantDoesNotFollowTheEntryToAnotherHost() {
        var mini = configuration("mini", hostname: "mini.local")
        mini.mayHostSessions = true
        #expect(mini.mayHostSessions)

        mini.hostname = "someone-elses-box.local"
        #expect(!mini.mayHostSessions)
    }

    /// And it comes back if the entry is pointed home again, because the grant
    /// was never withdrawn — only suspended by the mismatch.
    @Test
    func itHoldsAgainWhenThePointerReturns() {
        var mini = configuration("mini", hostname: "mini.local")
        mini.mayHostSessions = true
        mini.hostname = "elsewhere.local"
        mini.hostname = "mini.local"
        #expect(mini.mayHostSessions)
    }

    /// Withdrawing clears the record as well, so a later re-grant is a fresh
    /// decision rather than a revival of an old one.
    @Test
    func withdrawingForgetsWhatItWasGrantedFor() {
        var mini = configuration("mini", hostname: "mini.local")
        mini.mayHostSessions = true
        mini.mayHostSessions = false
        #expect(mini.mayHostSessionsGrantedFor == nil)
        #expect(!mini.mayHostSessions)
    }

    /// **A grant made before this existed is honoured as it stands.**
    /// Invalidating every permission somebody already gave, on the first launch
    /// after an update, is a worse answer than trusting them.
    @Test
    func aGrantFromBeforeThisExistedStillHolds() {
        var mini = configuration("mini", hostname: "mini.local")
        mini.mayHostSessionsPreference = true
        mini.mayHostSessionsGrantedFor = nil
        #expect(mini.mayHostSessions)
    }

    /// A machine that was never allowed is not allowed by a matching host.
    @Test
    func aMatchingHostIsNotItselfPermission() {
        var mini = configuration("mini", hostname: "mini.local")
        mini.mayHostSessionsGrantedFor = "mini.local"
        #expect(!mini.mayHostSessions)
    }
}
