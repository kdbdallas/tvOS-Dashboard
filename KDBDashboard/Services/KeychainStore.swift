import Foundation
import Security

/// Stores sensitive strings (OAuth tokens, passwords) in the Keychain
enum KeychainStore {
    private static let service = Bundle.main.bundleIdentifier ?? "com.port21.KDBDashboard"
    private static let installMarkerKey = "KeychainInstallMarker"

    /// Returns the string saved for a key, if any
    static func string(forKey key: String) -> String? {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Saves a string for a key, or removes it when the value is nil
    @discardableResult
    static func set(_ value: String?, forKey key: String) -> Bool {
        guard let value, let data = value.data(using: .utf8) else {
            remove(forKey: key)
            return true
        }

        let query = baseQuery(forKey: key)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)

        if status == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(newItem as CFDictionary, nil)
        }

        return status == errSecSuccess
    }

    /// Removes the string saved for a key
    static func remove(forKey key: String) {
        SecItemDelete(baseQuery(forKey: key) as CFDictionary)
    }

    /// Moves a value saved in UserDefaults by an earlier version of the app into the Keychain
    static func migrateFromUserDefaults(key: String) {
        let defaults = UserDefaults.standard
        guard let value = defaults.string(forKey: key) else { return }

        // Only drop the UserDefaults copy once the Keychain has it, so a failed write doesn't sign the user out
        if string(forKey: key) != nil || set(value, forKey: key) {
            defaults.removeObject(forKey: key)
        }
    }

    /// Keychain items outlive the app, so clear any left over from a previous install
    /// Call once at launch, before any service loads its credentials
    static func removeAllIfFreshInstall() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: installMarkerKey) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
        defaults.set(true, forKey: installMarkerKey)
    }

    private static func baseQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }
}
