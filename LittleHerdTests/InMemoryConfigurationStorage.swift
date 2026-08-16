import Foundation
@testable import LittleHerd

/// Saved-herd storage that lives only in memory.
///
/// Tests used to point the store at a real `UserDefaults` suite, which left a
/// plist behind on every run — cfprefsd writes a domain back out when the test
/// process exits, so even a careful teardown could not win. Nothing here
/// touches the filesystem, so there is nothing to clean up.
@MainActor
final class InMemoryConfigurationStorage: MachineConfigurationStorage {
    private var data: Data?

    init(seededWith json: String? = nil) {
        data = json.map { Data($0.utf8) }
    }

    func loadConfigurationData() -> Data? { data }

    func saveConfigurationData(_ data: Data) { self.data = data }

    /// What is currently saved, for tests that check the written form rather
    /// than the decoded machines.
    var savedJSON: String { data.map { String(decoding: $0, as: UTF8.self) } ?? "" }
}
