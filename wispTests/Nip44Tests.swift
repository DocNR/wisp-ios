import Foundation
import Testing
@testable import wisp

struct Nip44Tests {

    // MARK: - Padding boundaries (subset of NIP-44 v2 official vectors)

    @Test func paddingBoundaries() {
        let cases: [(input: Int, expected: Int)] = [
            (1, 32), (16, 32), (32, 32),
            (33, 64), (37, 64), (45, 64),
            (49, 64), (64, 64),
            (65, 96), (100, 128), (111, 128),
            (200, 224), (250, 256),
            (320, 320), (383, 384), (384, 384),
            (400, 448), (500, 512),
            (515, 640), (700, 768), (1000, 1024),
            (1024, 1024), (1025, 1280),
            (2000, 2048), (2048, 2048), (2049, 2560)
        ]
        for c in cases {
            #expect(Nip44.calcPaddedLen(c.input) == c.expected, "calcPaddedLen(\(c.input)) -> \(Nip44.calcPaddedLen(c.input)), expected \(c.expected)")
        }
    }

    // MARK: - Encrypt/decrypt round trip

    @Test func encryptDecryptRoundtrip() throws {
        // 32 zero bytes is invalid as a secp256k1 privkey, so generate a real one.
        let priv1 = Schnorr.randomPrivkey()
        let priv2 = Schnorr.randomPrivkey()
        let pub2 = try Schnorr.xonlyPubkey(privkey32: priv2)
        let pub1 = try Schnorr.xonlyPubkey(privkey32: priv1)

        let key1 = try Nip44.getConversationKey(privkey32: priv1, peerXonlyPubkey32: pub2)
        let key2 = try Nip44.getConversationKey(privkey32: priv2, peerXonlyPubkey32: pub1)
        // Conversation key is symmetric.
        #expect(key1 == key2)

        let plaintext = "hello, encrypted world! 🔐"
        let payload = try Nip44.encrypt(plaintext: plaintext, conversationKey: key1)
        let decrypted = try Nip44.decrypt(payload: payload, conversationKey: key2)
        #expect(decrypted == plaintext)
    }

    @Test func decryptRejectsTamperedMac() throws {
        let priv1 = Schnorr.randomPrivkey()
        let priv2 = Schnorr.randomPrivkey()
        let pub2 = try Schnorr.xonlyPubkey(privkey32: priv2)
        let key = try Nip44.getConversationKey(privkey32: priv1, peerXonlyPubkey32: pub2)

        let payload = try Nip44.encrypt(plaintext: "secret", conversationKey: key)
        var bytes = Data(base64Encoded: payload)!
        // Flip a bit in the MAC region (last 32 bytes).
        bytes[bytes.count - 1] ^= 0x01
        let tampered = bytes.base64EncodedString()
        #expect(throws: Nip44.Error.macMismatch) {
            try Nip44.decrypt(payload: tampered, conversationKey: key)
        }
    }

    @Test func decryptRejectsWrongVersion() throws {
        let priv1 = Schnorr.randomPrivkey()
        let priv2 = Schnorr.randomPrivkey()
        let pub2 = try Schnorr.xonlyPubkey(privkey32: priv2)
        let key = try Nip44.getConversationKey(privkey32: priv1, peerXonlyPubkey32: pub2)

        let payload = try Nip44.encrypt(plaintext: "secret", conversationKey: key)
        var bytes = Data(base64Encoded: payload)!
        bytes[0] = 0xFF
        let tampered = bytes.base64EncodedString()
        #expect(throws: Nip44.Error.invalidVersion) {
            try Nip44.decrypt(payload: tampered, conversationKey: key)
        }
    }
}

struct Nip17Tests {

    @Test func giftWrapRoundtrip() throws {
        let alicePriv = Schnorr.randomPrivkey()
        let bobPriv = Schnorr.randomPrivkey()
        let alicePub = Hex.encode(try Schnorr.xonlyPubkey(privkey32: alicePriv))
        let bobPub = Hex.encode(try Schnorr.xonlyPubkey(privkey32: bobPriv))

        let createdAt = Int(Date().timeIntervalSince1970)
        let wrap = try Nip17.createGiftWrap(
            senderPrivkey32: alicePriv,
            senderPubkey: alicePub,
            recipientPubkey: bobPub,
            message: "Hello Bob",
            rumorCreatedAt: createdAt
        )
        #expect(wrap.kind == 1059)
        #expect(wrap.tags.contains(["p", bobPub]))

        let rumor = try Nip17.unwrapGiftWrap(recipientPrivkey32: bobPriv, giftWrap: wrap)
        #expect(rumor.pubkey == alicePub)
        #expect(rumor.kind == 14)
        #expect(rumor.content == "Hello Bob")
        #expect(rumor.createdAt == createdAt)
    }

    @Test func unwrapWithWrongRecipientFails() throws {
        let alicePriv = Schnorr.randomPrivkey()
        let bobPriv = Schnorr.randomPrivkey()
        let evePriv = Schnorr.randomPrivkey()
        let alicePub = Hex.encode(try Schnorr.xonlyPubkey(privkey32: alicePriv))
        let bobPub = Hex.encode(try Schnorr.xonlyPubkey(privkey32: bobPriv))

        let wrap = try Nip17.createGiftWrap(
            senderPrivkey32: alicePriv,
            senderPubkey: alicePub,
            recipientPubkey: bobPub,
            message: "secret",
            rumorCreatedAt: Int(Date().timeIntervalSince1970)
        )
        #expect(throws: (any Error).self) {
            _ = try Nip17.unwrapGiftWrap(recipientPrivkey32: evePriv, giftWrap: wrap)
        }
    }

    @Test func conversationKeyIsStableAndSorted() {
        let a = "aaaa"
        let b = "bbbb"
        let c = "cccc"
        #expect(DmRepository.conversationKey(participants: [a, b]) == DmRepository.conversationKey(participants: [b, a]))
        #expect(DmRepository.conversationKey(participants: [c, a, b]) == "\(a),\(b),\(c)")
    }

    @Test func rumorIdIsDeterministic() {
        let pubkey = String(repeating: "a", count: 64)
        let id1 = NostrEvent.computeId(pubkey: pubkey, createdAt: 1700000000, kind: 14, tags: [["p", "x"]], content: "hi")
        let id2 = NostrEvent.computeId(pubkey: pubkey, createdAt: 1700000000, kind: 14, tags: [["p", "x"]], content: "hi")
        #expect(id1 == id2)
        #expect(id1.count == 64)  // 32 bytes hex
    }

    @Test func randomizedTimestampIsInPast() {
        let now = Int(Date().timeIntervalSince1970)
        for _ in 0..<20 {
            let ts = Nip17.randomizeTimestamp(now)
            #expect(ts <= now)
            #expect(ts > now - 86400)  // within 1 day
        }
    }
}

struct SchnorrTests {

    @Test func signAndVerifyRoundtrip() throws {
        let priv = Schnorr.randomPrivkey()
        let pub = try Schnorr.xonlyPubkey(privkey32: priv)
        let message = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let sig = try Schnorr.sign(messageId32: message, privkey32: priv)
        #expect(sig.count == 64)
        #expect(Schnorr.verify(sig64: sig, messageId32: message, xonlyPubkey32: pub))
    }

    @Test func ecdhIsSymmetric() throws {
        let a = Schnorr.randomPrivkey()
        let b = Schnorr.randomPrivkey()
        let aPub = try Schnorr.xonlyPubkey(privkey32: a)
        let bPub = try Schnorr.xonlyPubkey(privkey32: b)
        let s1 = try Schnorr.ecdhRawX(privkey32: a, xonlyPubkey32: bPub)
        let s2 = try Schnorr.ecdhRawX(privkey32: b, xonlyPubkey32: aPub)
        #expect(s1 == s2)
        #expect(s1.count == 32)
    }
}
