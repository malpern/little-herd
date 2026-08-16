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

    /// A deleted secret must not still be answered from memory, and the next
    /// read should ask again rather than assume it is still gone.
    @Test
    func forgettingAnAccountLeavesNothingBehind() {
        let cache = SecretCache()
        cache.set("hunter2", for: "nas")
        cache.forget("nas")
        #expect(cache.value(for: "nas") == nil)
        #expect(cache.entry(for: "nas") == nil)
    }

    /// The half that was missing: a prompt the user dismisses leaves the read
    /// unsuccessful, and without remembering that, a monitor sampling every ten
    /// seconds asks again forever with no way to stop it.
    @Test
    func aFailedReadIsRememberedSoItIsNotAskedAgain() {
        let cache = SecretCache()
        cache.setMissing(for: "nas")

        #expect(cache.value(for: "nas") == nil)
        // Distinguishable from "never asked", which is what makes the caller
        // skip the keychain rather than retry it.
        #expect(cache.entry(for: "nas") == .missing)
    }

    /// Answering the prompt has to take effect at once, not next launch.
    @Test
    func aSecretArrivingLaterReplacesTheFailure() {
        let cache = SecretCache()
        cache.setMissing(for: "nas")
        cache.set("hunter2", for: "nas")
        #expect(cache.value(for: "nas") == "hunter2")
        #expect(cache.entry(for: "nas") == .value("hunter2"))
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

        cache.forget("one@nas:5001")
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

/// The keychain read must never be able to interrupt the user.
struct KeychainReadPolicyTests {
    /// The sampling loop reads every ten seconds. A read that can raise a modal
    /// password dialog turns that into a prompt on a timer, in the background,
    /// which is exactly what happened: an item whose access list named a
    /// different build of the app produced an endless series of dialogs.
    ///
    /// Asserted against the source, because the alternative is a test that
    /// hangs a headless runner on a real authorisation dialog — which is also
    /// something this project has already done to itself once.
    @Test
    func theKeychainReadIsConfiguredNeverToShowUI() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("LittleHerd/KeychainSecret.swift"),
            encoding: .utf8
        )

        // Must be the legacy-keychain control, not the data-protection one.
        //
        // kSecUseAuthenticationUI governs the data-protection keychain and does
        // nothing for this one — measured: a read carrying it still put up a
        // password dialog and blocked, while the same read wrapped in
        // SecKeychainSetUserInteractionAllowed(false) returns errSecAuthFailed
        // in a hundredth of a second. Shipping the wrong one is why the prompt
        // survived several attempts to stop it.
        #expect(source.contains("SecKeychainSetUserInteractionAllowed(false)"))
        #expect(
            !source.contains("kSecUseAuthenticationUIFail"),
            "that flag does not apply to this keychain and reads as a fix that is not one"
        )

        // Reading and checking are suppressed; saving is a foreground action
        // the user just asked for and may still authenticate.
        let readRange = try #require(source.range(of: "func readFromKeychain"))
        let readBody = String(source[readRange.lowerBound...].prefix(700))
        #expect(readBody.contains("withoutDialogs"))

        // Bounded by the helper's own definition, which sits between the two.
        let storeRange = try #require(source.range(of: "static func store("))
        let helperRange = try #require(
            source.range(of: "private static func withoutDialogs")
        )
        let storeBody = String(source[storeRange.lowerBound..<helperRange.lowerBound])
        #expect(!storeBody.contains("withoutDialogs {"))
    }
}
