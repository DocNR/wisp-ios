import Foundation
import Observation

@Observable
@MainActor
final class MessagesViewModel {
    let keypair: Keypair

    var conversations: [DmConversation] = []
    var hasUnread: Bool = false
    var isLoading: Bool = false

    @ObservationIgnored private var subscription: RelaySubscription?
    @ObservationIgnored private var listenerTask: Task<Void, Never>?
    @ObservationIgnored private var dmRelayCache: [String]?
    @ObservationIgnored private let repo = DmRepository.shared
    @ObservationIgnored private let profileRepo = ProfileRepository.shared

    /// Indexer / fallback relays to subscribe for inbound gift wraps when the user has no kind:10050.
    private static let fallbackRelays = [
        "wss://relay.damus.io",
        "wss://relay.primal.net",
        "wss://nos.lol",
        "wss://relay.nostr.band",
        "wss://nostr.wine"
    ]

    init(keypair: Keypair) {
        self.keypair = keypair
    }

    func start() async {
        guard subscription == nil else { return }
        repo.bind(activePubkey: keypair.pubkey)
        isLoading = true

        // 1. Resolve DM relays (kind 10050). If user has none, fall back to a default broadcast set.
        let inbox = await resolveOwnDmRelays()
        let relays = inbox.isEmpty ? Self.fallbackRelays : inbox

        // 2. Open persistent subscription. NO `since` — wraps have randomized timestamps.
        let filter = NostrFilter(kinds: [Nip17.Kind.giftWrap], pTags: [keypair.pubkey])
        let sub = RelayPool.subscribe(relays: relays, filter: filter, id: "dms")
        subscription = sub
        let priv = privkeyData()

        listenerTask = Task { [weak self] in
            for await (event, relayUrl) in sub.events {
                guard let self else { break }
                await self.handleGiftWrap(event: event, relayUrl: relayUrl, privkey: priv)
            }
        }

        refreshSnapshot()
        isLoading = false
    }

    func stop() {
        listenerTask?.cancel()
        listenerTask = nil
        subscription?.cancel()
        subscription = nil
    }

    func markAllRead() {
        repo.markAllRead()
        hasUnread = false
    }

    private func handleGiftWrap(event: NostrEvent, relayUrl: String, privkey: Data) async {
        guard event.kind == Nip17.Kind.giftWrap else { return }
        // Dedupe across relays first (cheap) before attempting decryption (expensive).
        guard repo.markGiftWrapSeen(event.id) else {
            // Already processed: still merge relayUrl into the existing message if present.
            mergeRelayUrl(giftWrapId: event.id, relayUrl: relayUrl)
            return
        }

        let rumor: Rumor
        do {
            rumor = try Nip17.unwrapGiftWrap(recipientPrivkey32: privkey, giftWrap: event)
        } catch {
            return
        }

        // v1 scope: chat messages only. Reactions/files arrive as different rumor kinds and are
        // dropped silently for now.
        guard rumor.kind == Nip17.Kind.chatMessage else { return }

        // Safety check on the inner rumor — kind:1059 wrappers are pure transport so we filter
        // on what's actually inside.
        let safetyEvent = NostrEvent(
            id: rumor.id, pubkey: rumor.pubkey, kind: rumor.kind, createdAt: rumor.createdAt,
            tags: rumor.tags, content: rumor.content, sig: ""
        )
        if SafetyFilter.shared.shouldDrop(event: safetyEvent, context: .messages) { return }

        let participants = Nip17.getConversationParticipants(rumor: rumor, myPubkey: keypair.pubkey)
        let convKey = DmRepository.conversationKey(participants: participants + [keypair.pubkey])
        let replyTo = rumor.tags.first { $0.count >= 2 && $0[0] == "e" }?[1]

        let msg = DmMessage(
            id: "\(event.id):\(rumor.createdAt)",
            senderPubkey: rumor.pubkey,
            content: rumor.content,
            createdAt: rumor.createdAt,
            giftWrapId: event.id,
            rumorId: rumor.id,
            replyToId: replyTo,
            participants: participants,
            relayUrls: [relayUrl]
        )
        repo.addMessage(msg, conversationKey: convKey)
        refreshSnapshot()
        await prefetchProfilesIfNeeded(participants: participants + [rumor.pubkey])
    }

    private func mergeRelayUrl(giftWrapId: String, relayUrl: String) {
        // Best-effort merge for already-seen messages. Cheap path; only need conversation lookup.
        for (key, msgs) in repo.conversations {
            if let i = msgs.firstIndex(where: { $0.giftWrapId == giftWrapId }) {
                var msg = msgs[i]
                msg.relayUrls.insert(relayUrl)
                repo.addMessage(msg, conversationKey: key)
                return
            }
        }
    }

    func refreshSnapshot() {
        conversations = repo.conversationList()
        hasUnread = repo.hasUnread
    }

    // MARK: - Relay resolution

    private func resolveOwnDmRelays() async -> [String] {
        if let cached = dmRelayCache { return cached }
        let filter = NostrFilter(kinds: [10050], authors: [keypair.pubkey], limit: 1)
        let events = await RelayPool.query(relays: Self.fallbackRelays, filter: filter, timeout: 4)
        let latest = events.max(by: { $0.createdAt < $1.createdAt })
        let relays = latest?.tags.compactMap { tag -> String? in
            guard tag.count >= 2, tag[0] == "relay" else { return nil }
            return tag[1]
        } ?? []
        dmRelayCache = relays
        return relays
    }

    func privkeyData() -> Data {
        Hex.decode(keypair.privkey) ?? Data()
    }

    private func prefetchProfilesIfNeeded(participants: [String]) async {
        let missing = participants.filter { profileRepo.get($0) == nil }
        guard !missing.isEmpty else { return }
        let filter = NostrFilter(kinds: [0], authors: missing, limit: missing.count)
        let events = await RelayPool.query(relays: Self.fallbackRelays, filter: filter, timeout: 5)
        for e in events { profileRepo.updateFromEvent(e) }
    }
}
