import Foundation

enum NotificationKind: String, Hashable {
    case reply
    case reaction
    case repost
    case zap
    case quote
    case mention
    case dm
    case pollVote
}

struct ZapEntry: Hashable {
    let pubkey: String
    let sats: Int64
    let message: String
    let createdAt: Int
    let receiptEventId: String
    let isPrivate: Bool
}

struct FlatNotificationItem: Identifiable, Hashable {
    let id: String
    let kind: NotificationKind
    let actorPubkey: String
    let referencedEventId: String
    let timestamp: Int
    var emoji: String? = nil
    var emojiUrl: String? = nil
    var zapSats: Int64 = 0
    var zapMessage: String = ""
    var isPrivateZap: Bool = false
    var quoteEventId: String? = nil
    var actorEventId: String? = nil
    var dmPeerPubkey: String? = nil
    var dmConversationKey: String? = nil
    var dmUnread: Int = 0
    var relayHints: [String] = []
    /// Option ids chosen by a kind-1018 poll voter (for `.pollVote` items).
    var voteOptionIds: [String] = []
    /// Index of the option zapped on a kind-6969 zap poll (annotates `.zap` items
    /// whose target is one of our zap polls).
    var zapPollOptionIndex: Int? = nil
}

/// Aggregates notifications targeting the same note (for reactions/zaps/reposts) or stands
/// alone (replies/quotes/mentions/DMs). One row per group in the UI.
enum NotificationGroup: Identifiable, Hashable {
    case reactions(
        id: String,
        refEventId: String,
        emojiByActor: [String: String],
        emojiUrlByActor: [String: String],
        zaps: [ZapEntry],
        reposters: [String],
        latestTs: Int
    )
    case reply(
        id: String,
        sender: String,
        replyEventId: String,
        refEventId: String?,
        latestTs: Int,
        relayHints: [String]
    )
    case quote(
        id: String,
        sender: String,
        actorEventId: String,
        quoteEventId: String,
        latestTs: Int,
        relayHints: [String]
    )
    case mention(
        id: String,
        sender: String,
        eventId: String,
        latestTs: Int,
        relayHints: [String]
    )
    case dm(
        id: String,
        peer: String,
        conversationKey: String,
        lastMessageTs: Int,
        unread: Int
    )
    /// Aggregated kind-1018 poll votes against one of the active user's polls.
    /// `votersByOptionId` keys are option ids chosen, values are voter pubkeys.
    /// A voter that picked multiple options appears in every chosen bucket.
    case pollVotes(
        id: String,
        refEventId: String,
        votersByOptionId: [String: [String]],
        latestTs: Int
    )

    var id: String {
        switch self {
        case .reactions(let id, _, _, _, _, _, _): id
        case .reply(let id, _, _, _, _, _): id
        case .quote(let id, _, _, _, _, _): id
        case .mention(let id, _, _, _, _): id
        case .dm(let id, _, _, _, _): id
        case .pollVotes(let id, _, _, _): id
        }
    }

    var latestTs: Int {
        switch self {
        case .reactions(_, _, _, _, _, _, let ts): ts
        case .reply(_, _, _, _, let ts, _): ts
        case .quote(_, _, _, _, let ts, _): ts
        case .mention(_, _, _, let ts, _): ts
        case .dm(_, _, _, let ts, _): ts
        case .pollVotes(_, _, _, let ts): ts
        }
    }

    var primaryActor: String {
        switch self {
        case .reactions(_, _, let emojiByActor, _, let zaps, let reposters, _):
            emojiByActor.keys.first ?? zaps.first?.pubkey ?? reposters.first ?? ""
        case .reply(_, let s, _, _, _, _): s
        case .quote(_, let s, _, _, _, _): s
        case .mention(_, let s, _, _, _): s
        case .dm(_, let p, _, _, _): p
        case .pollVotes(_, _, let map, _):
            map.values.flatMap { $0 }.first ?? ""
        }
    }

    var kind: NotificationKind {
        switch self {
        case .reactions: .reaction
        case .reply: .reply
        case .quote: .quote
        case .mention: .mention
        case .dm: .dm
        case .pollVotes: .pollVote
        }
    }
}

struct NotificationSummary: Hashable {
    var replyCount: Int = 0
    var reactionCount: Int = 0
    var zapCount: Int = 0
    var zapSats: Int64 = 0
    var repostCount: Int = 0
    var mentionCount: Int = 0
    var quoteCount: Int = 0
    var dmCount: Int = 0
    var pollVoteCount: Int = 0
}

enum NotificationFilterChip: String, CaseIterable, Hashable {
    case all
    case replies
    case mentions
    case zaps
    case reactions
    case reposts
    case quotes
    case dms
    case polls

    var label: String {
        switch self {
        case .all: "All"
        case .replies: "Replies"
        case .mentions: "Mentions"
        case .zaps: "Zaps"
        case .reactions: "Reactions"
        case .reposts: "Reposts"
        case .quotes: "Quotes"
        case .dms: "DMs"
        case .polls: "Polls"
        }
    }

    func matches(_ group: NotificationGroup) -> Bool {
        switch (self, group) {
        case (.all, _): true
        case (.replies, .reply): true
        case (.mentions, .mention): true
        case (.quotes, .quote): true
        case (.dms, .dm): true
        case (.polls, .pollVotes): true
        case (.reactions, .reactions(_, _, let m, _, _, _, _)) where !m.isEmpty: true
        case (.zaps, .reactions(_, _, _, _, let z, _, _)) where !z.isEmpty: true
        case (.reposts, .reactions(_, _, _, _, _, let r, _)) where !r.isEmpty: true
        default: false
        }
    }
}
