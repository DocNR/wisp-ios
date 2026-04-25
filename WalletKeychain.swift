import Foundation
import Security

/// Keychain helpers for wallet credentials. Mirrors `NostrKey`'s pattern:
/// generic password, service `com.wisp.nostr`, account name keyed by pubkey,
/// `WhenUnlockedThisDeviceOnly`. Values are deleted-then-added on update.
enum WalletKeychain {
    private static let service = "com.wisp.nostr"

    // MARK: - NWC connection URI

    static func saveNwcUri(_ uri: String, for pubkey: String) {
        save(value: uri, account: "nwc_\(pubkey)")
    }

    static func loadNwcUri(for pubkey: String) -> String? {
        load(account: "nwc_\(pubkey)")
    }

    static func deleteNwcUri(for pubkey: String) {
        delete(account: "nwc_\(pubkey)")
    }

    // MARK: - Spark mnemonic

    static func saveSparkMnemonic(_ mnemonic: String, for pubkey: String) {
        save(value: mnemonic, account: "spark_seed_\(pubkey)")
    }

    static func loadSparkMnemonic(for pubkey: String) -> String? {
        load(account: "spark_seed_\(pubkey)")
    }

    static func deleteSparkMnemonic(for pubkey: String) {
        delete(account: "spark_seed_\(pubkey)")
    }

    // MARK: - Internals

    private static func save(value: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
