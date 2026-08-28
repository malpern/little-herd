import Foundation

@testable import LittleHerd

extension MachineConfiguration {
    /// A stand-in for "this Mac" with a name nothing else uses.
    ///
    /// Tests must never seed a store with `MachineConfiguration.local()`,
    /// whose default name is the computer's own. `MachineConfigurationStore.add`
    /// treats a same-named machine as a duplicate, so a fixture called
    /// "Mac mini" is silently dropped on a Mac that is called "Mac mini" — two
    /// tests that passed on a laptop named "air" failed on the mini for that
    /// reason and no other. Anything host-derived in a fixture is a test that
    /// only happens to pass.
    nonisolated static let testLocal = MachineConfiguration(
        id: MachineID("local"),
        name: "Test Local Mac",
        shortName: "This Mac",
        hostname: "localhost",
        hardwareSummary: "This Mac",
        platform: .macOS,
        connection: .local,
        avatar: .chickLaptop,
        identityFile: nil,
        serverNames: [],
        supportsGPU: true
    )
}
