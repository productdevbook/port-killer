import Foundation
import Security

enum PluginSecrets {
    static func value(plugin: String, key: String) -> String? {
        var query = baseQuery(plugin: plugin, key: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard unsafe SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func set(_ value: String, plugin: String, key: String) {
        let query = baseQuery(plugin: plugin, key: key)
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }

    private static func baseQuery(plugin: String, key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.portkiller.app.plugin.\(plugin)",
            kSecAttrAccount as String: key,
        ]
    }
}
