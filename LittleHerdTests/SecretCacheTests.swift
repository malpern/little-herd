import Foundation
import Testing
@testable import LittleHerd

/// Tests the memory cache alone, never the keychain.
///
/// An earlier version of these tests wrote to the real keychain and hung the
/// suite: against an ad-hoc-signed test host every read raises an authorisation
/// dialog, and a headless runner waits on it forever — while putting a password
/// prompt in front of whoever happens to be at the machine.
struct SecretCacheTests {
    @Test
    func aStoredValueComesBack() {
        let cache = SecretCache()
        cache.set("hunter2", for: "nas")
        #expect(cache.value(for: "nas") == "hunter2")
    }

    @Test
    func anUnknownAccountHasNothing() {
        #expect(SecretCache().value(for: "nas") == nil)
    }

    /// The whole point: once a secret is known, asking again must not go back
    /// to the keychain, because going back means prompting the user.
    @Test
    func askingAgainIsAnsweredFromMemory() {
        let cache = SecretCache()
        cache.set("hunter2", for: "nas")
        for _ in 0..<10 {
            #expect(cache.value(for: "nas") == "hunter2")
        }
    }

    /// A cache that went stale would be worse than the prompts it removes: the
    /// NAS would keep failing to sign in with a password already corrected.
    @Test
    func aChangedSecretReplacesTheOldOne() {
        let cache = SecretCache()
        cache.set("old", for: "nas")
        cache.set("new", for: "nas")
        #expect(cache.value(for: "nas") == "new")
    }

    /// A deleted secret must not still be answered from memory.
    @Test
    func forgettingAnAccountLeavesNothingBehind() {
        let cache = SecretCache()
        cache.set("hunter2", for: "nas")
        cache.set(nil, for: "nas")
        #expect(cache.value(for: "nas") == nil)
    }

    /// Two NASes, or two accounts on one NAS, must not read each other's
    /// password.
    @Test
    func accountsDoNotSeeEachOther() {
        let cache = SecretCache()
        cache.set("first", for: "one@nas:5001")
        cache.set("second", for: "two@nas:5001")

        #expect(cache.value(for: "one@nas:5001") == "first")
        #expect(cache.value(for: "two@nas:5001") == "second")

        cache.set(nil, for: "one@nas:5001")
        #expect(cache.value(for: "two@nas:5001") == "second")
    }

    /// Reached from the monitor's sampling tasks, so concurrent access must not
    /// trip over itself.
    @Test
    func concurrentAccessIsSafe() async {
        let cache = SecretCache()
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<50 {
                group.addTask {
                    cache.set("secret-\(index % 5)", for: "account-\(index % 5)")
                    _ = cache.value(for: "account-\(index % 5)")
                }
            }
        }
        for index in 0..<5 {
            #expect(cache.value(for: "account-\(index)") == "secret-\(index)")
        }
    }
}
