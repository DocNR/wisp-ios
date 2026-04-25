import Foundation

/// In-memory store for decrypted DM rumors. Mirrors Android's DmRepository design:
/// ephemeral conversation cache, persistent only for last-read / latest-seen-wrap timestamps.
@MainActor
@Observable
final class DmRepository {
    static let shared = DmRepository()

    /// conversationKey → ordered messages (ascending by createdAt)
    private(set) var conversations: [String: [DmMessage]] = [:]
    /// Track gift wrap ids we've already processed (across multiple relays).
    private var seenGiftWraps: Set<String> = []
    /// rumorId → (conversationKey, messageId), used to attach reactions/zaps later (future).
    private var rumorIndex: [String: (convKey: String, msgId: String)] = [:]

    private var activePubkey: String = ""

    /// Comma-joined sorted participant pubkeys; stable across sender/receiver.
    nonisolated static func conversationKey(participants: [String]) -> String {
        Set(participants).sorted().joined(separator: ",")
    }

    func bind(activePubkey: String) {
        if activePubkey != self.activePubkey {
            self.activePubkey = activePubkey
            // Reset volatile state when switching accounts.
            conversations = [:]
            seenGiftWraps = []
            rumorIndex = [:]
        }
    }

    @discardableResult
    func addMessage(_ msg: DmMessage, conversationKey: String) -> Bool {
        var existing = conversations[conversationKey] ?? []
        // Dedupe by composite id (giftWrapId:rumorCreatedAt) while merging relayUrls.
        if let i = existing.firstIndex(where: { $0.id == msg.id }) {
            var merged = existing[i]
            merged.relayUrls.formUnion(msg.relayUrls)
            existing[i] = merged
            conversations[conversationKey] = existing
            return false
        }
        existing.append(msg)
        existing.sort { $0.createdAt < $1.createdAt }
        conversations[conversationKey] = existing
        rumorIndex[msg.rumorId] = (conversationKey, msg.id)
        bumpLatestWrapTs(msg.createdAt)
        return true
    }

    func markGiftWrapSeen(_ giftWrapId: String) -> Bool {
        seenGiftWraps.insert(giftWrapId).inserted
    }

    func conversationList() -> [DmConversation] {
        conversations.compactMap { (key, msgs) -> DmConversation? in
            guard let last = msgs.last else { return nil }
            return DmConversation(conversationKey: key,
                                  participants: last.participants,
                                  messages: msgs,
                                  lastMessageAt: last.createdAt)
        }
        .sorted { $0.lastMessageAt > $1.lastMessageAt }
    }

    func conversation(_ key: String) -> DmConversation? {
        guard let msgs = conversations[key], let last = msgs.last else { return nil }
        return DmConversation(conversationKey: key,
                              participants: last.participants,
                              messages: msgs,
                              lastMessageAt: last.createdAt)
    }

    // MARK: - Persisted state (UserDefaults, scoped by active pubkey)

    private var lastReadKey: String { "dm_last_read_\(activePubkey)" }
    private var latestWrapKey: String { "dm_latest_wrap_ts_\(activePubkey)" }

    var lastReadTimestamp: Int {
        get { UserDefaults.standard.integer(forKey: lastReadKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastReadKey) }
    }

    var latestWrapTimestamp: Int {
        get { UserDefaults.standard.integer(forKey: latestWrapKey) }
    }

    func markAllRead() {
        let now = Int(Date().timeIntervalSince1970)
        lastReadTimestamp = now
    }

    var hasUnread: Bool {
        let last = lastReadTimestamp
        return conversations.values.contains { msgs in
            (msgs.last?.createdAt ?? 0) > last
        }
    }

    private func bumpLatestWrapTs(_ ts: Int) {
        if ts > latestWrapTimestamp {
            UserDefaults.standard.set(ts, forKey: latestWrapKey)
        }
    }
}
