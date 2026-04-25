import Foundation

struct DmMessage: Identifiable, Equatable {
    /// Stable composite id: "<giftWrapId>:<rumorCreatedAt>". Encodes which envelope delivered
    /// this message so duplicate gift wraps from multiple relays collapse cleanly.
    let id: String
    let senderPubkey: String
    let content: String
    /// Rumor's createdAt (the actual semantic time the message was authored), NOT the wrap's
    /// randomized time.
    let createdAt: Int
    let giftWrapId: String
    let rumorId: String
    let replyToId: String?
    /// All conversation participants except the local user, sorted.
    let participants: [String]
    var relayUrls: Set<String> = []
}

struct DmConversation: Identifiable, Equatable {
    var id: String { conversationKey }
    let conversationKey: String
    let participants: [String]
    let messages: [DmMessage]
    let lastMessageAt: Int

    var isGroup: Bool { participants.count > 1 }
    var peerPubkey: String { participants.first ?? conversationKey }
}
