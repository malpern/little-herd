import Foundation

/// Remembers secrets already read from the keychain, for the life of the
/// process.
///
/// macOS asks the user to authorise each keychain read the item's access list
/// does not already cover, so how often Little Herd reads is something the user
/// experiences directly — as a password prompt. A monitor that signs in again
/// whenever its session lapses, or whose machines are rebuilt when a
/// certificate is recorded, would ask repeatedly for the same secret.
///
/// Deliberately in memory only and never written anywhere: it exists to avoid
/// re-reading, not to avoid the keychain.
nonisolated final class SecretCache: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func value(for account: String) -> String? {
        lock.withLock { values[account] }
    }

    /// Passing `nil` forgets the account, so a deleted secret is not still
    /// answered from memory.
    func set(_ secret: String?, for account: String) {
        lock.withLock { values[account] = secret }
    }

    func removeAll() {
        lock.withLock { values.removeAll() }
    }
}
