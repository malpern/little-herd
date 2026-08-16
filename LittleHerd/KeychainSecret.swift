import Foundation
import Security

/// The DSM password, kept in the login keychain rather than in preferences.
///
/// `machineConfigurationsV1` is a plist in `~/Library/Preferences` that anything
/// running as the user can read; a NAS admin password does not belong there.
nonisolated enum KeychainSecret {
    static let service = "com.malpern.LittleHerd.synology"

    /// One entry per account-on-a-host, so two NASes, or two accounts on one
    /// NAS, cannot overwrite each other.
    static func account(for endpoint: SynologyDSMEndpoint) -> String {
        "\(endpoint.username)@\(endpoint.host):\(endpoint.port)"
    }

    /// Read secrets are kept in memory for the life of the process.
    ///
    /// macOS asks the user to authorise each keychain read that is not already
    /// covered by the item's access list, and a monitor that signs in again
    /// whenever its session lapses would ask repeatedly. Reading once per launch
    /// is enough: the value cannot change underneath us without going through
    /// `store` or `delete`, which both update this.
    static let cache = SecretCache()

    @discardableResult
    static func store(_ secret: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        // Updating in place keeps whatever access the user has already granted;
        // deleting and re-adding would re-prompt on every password change.
        let update: [String: Any] = [
            kSecValueData as String: Data(secret.utf8)
        ]
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            update as CFDictionary
        )
        if updateStatus == errSecSuccess {
            cache.set(secret, for: account)
            return true
        }

        guard updateStatus == errSecItemNotFound else { return false }

        var insert = query
        insert[kSecValueData as String] = Data(secret.utf8)
        insert[kSecAttrAccessible as String] =
            kSecAttrAccessibleAfterFirstUnlock
        guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else {
            return false
        }
        cache.set(secret, for: account)
        return true
    }

    /// The password for a NAS, read from the keychain at most once per launch.
    static func read(account: String) -> String? {
        if let cached = cache.value(for: account) { return cached }
        let secret = readFromKeychain(account: account)
        cache.set(secret, for: account)
        return secret
    }

    private static func readFromKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let secret = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return secret
    }

    @discardableResult
    static func delete(account: String) -> Bool {
        cache.set(nil, for: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    static func exists(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }
}
