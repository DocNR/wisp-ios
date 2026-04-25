import Foundation

enum WalletMode: String {
    case nwc
    case spark

    private static func key(for pubkey: String) -> String { "wallet_mode_\(pubkey)" }

    static func load(for pubkey: String) -> WalletMode? {
        guard let raw = UserDefaults.standard.string(forKey: key(for: pubkey)) else { return nil }
        return WalletMode(rawValue: raw)
    }

    static func save(_ mode: WalletMode, for pubkey: String) {
        UserDefaults.standard.set(mode.rawValue, forKey: key(for: pubkey))
    }

    static func clear(for pubkey: String) {
        UserDefaults.standard.removeObject(forKey: key(for: pubkey))
    }
}
