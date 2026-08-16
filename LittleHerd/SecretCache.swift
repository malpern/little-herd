import Foundation

/// Remembers what the keychain said about a secret, for the life of the process
/// — including when it said nothing.
///
/// macOS asks the user to authorise keychain reads the item's access list does
/// not already cover, so how often Little Herd reads is something the user
/// experiences directly, as a password prompt. Caching successful reads is only
/// half of it: a prompt the user dismisses leaves the read unsuccessful, and a
/// monitor that samples every ten seconds would ask again, and again, with no
/// way to make it stop short of quitting.
///
/// So a failed read is remembered too. The user is asked at most once per launch
/// per account, and answering the prompt caches the value that comes back.
///
/// In memory only, never written anywhere: this exists to avoid re-reading, not
/// to avoid the keychain.
nonisolated final class SecretCache: @unchecked Sendable {
    enum Entry: Equatable {
        case value(String)
        /// Asked, and did not get one — absent, or the user dismissed the
        /// authorisation prompt.
        case missing
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    func entry(for account: String) -> Entry? {
        lock.withLock { entries[account] }
    }

    func value(for account: String) -> String? {
        guard case .value(let secret) = entry(for: account) else { return nil }
        return secret
    }

    func set(_ secret: String, for account: String) {
        lock.withLock { entries[account] = .value(secret) }
    }

    /// Records that asking produced nothing, so it is not asked again.
    func setMissing(for account: String) {
        lock.withLock { entries[account] = .missing }
    }

    /// Forgets an account entirely, so the next read asks again. Used when the
    /// secret is deleted, and when a new one is saved.
    func forget(_ account: String) {
        lock.withLock { entries[account] = nil }
    }

    func removeAll() {
        lock.withLock { entries.removeAll() }
    }
}
