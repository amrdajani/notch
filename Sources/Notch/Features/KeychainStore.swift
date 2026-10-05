import Foundation
import Security

enum KeychainStore {
    private static let service = "com.amrdajani.notch"

    static func set(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query = baseQuery(account: account, dataProtection: true)
        SecItemDelete(query as CFDictionary)

        guard !value.isEmpty else {
            SecItemDelete(baseQuery(account: account, dataProtection: false) as CFDictionary)
            return
        }

        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecSuccess || status == errSecDuplicateItem {
            SecItemDelete(baseQuery(account: account, dataProtection: false) as CFDictionary)
        }
    }

    static func get(account: String) -> String? {
        if let value = copy(account: account, dataProtection: true) {
            return value
        }
        guard let legacy = copy(account: account, dataProtection: false) else { return nil }
        set(legacy, account: account)
        return legacy
    }

    private static func copy(account: String, dataProtection: Bool) -> String? {
        var query = baseQuery(account: account, dataProtection: dataProtection)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func baseQuery(account: String, dataProtection: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if dataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }
}
