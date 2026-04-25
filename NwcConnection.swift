import Foundation

/// Parsed `nostr+walletconnect://<wallet_pubkey>?relay=<wss>&secret=<hex>&lud16=<addr>` URI.
/// `clientPubkey` is the x-only pubkey derived from `clientSecret`.
struct NwcConnection {
    let walletServicePubkey: Data   // 32 bytes (x-only)
    let relays: [String]
    let clientSecret: Data          // 32 bytes
    let clientPubkey: Data          // 32 bytes (x-only)
    let lud16: String?
    var encryption: Nip47.Encryption

    /// Best-effort URI parser. Accepts unencoded `relay=wss://...` (most clients copy/paste them
    /// that way), multiple `relay=` params, and stray whitespace.
    static func parse(_ raw: String) -> NwcConnection? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let scheme = "nostr+walletconnect://"
        guard trimmed.lowercased().hasPrefix(scheme) else { return nil }
        let body = String(trimmed.dropFirst(scheme.count))

        let parts = body.split(separator: "?", maxSplits: 1)
        guard let pubkeyHex = parts.first.map(String.init), pubkeyHex.count == 64,
              let pubkey = Hex.decode(pubkeyHex) else { return nil }

        var relays: [String] = []
        var secretHex: String?
        var lud16: String?

        if parts.count == 2 {
            for kv in parts[1].split(separator: "&") {
                let kvParts = kv.split(separator: "=", maxSplits: 1).map(String.init)
                guard kvParts.count == 2 else { continue }
                let key = kvParts[0]
                let value = kvParts[1].removingPercentEncoding ?? kvParts[1]
                switch key {
                case "relay":
                    relays.append(value.trimmingCharacters(in: .whitespaces))
                case "secret":
                    secretHex = value.trimmingCharacters(in: .whitespaces)
                case "lud16":
                    lud16 = value.trimmingCharacters(in: .whitespaces)
                default:
                    break
                }
            }
        }

        guard !relays.isEmpty,
              let secretHex,
              let secret = Hex.decode(secretHex), secret.count == 32 else {
            return nil
        }
        guard let clientPub = try? Schnorr.xonlyPubkey(privkey32: secret) else { return nil }

        return NwcConnection(
            walletServicePubkey: pubkey,
            relays: relays,
            clientSecret: secret,
            clientPubkey: clientPub,
            lud16: lud16,
            encryption: .nip04
        )
    }

    func with(encryption: Nip47.Encryption) -> NwcConnection {
        var copy = self
        copy.encryption = encryption
        return copy
    }
}
