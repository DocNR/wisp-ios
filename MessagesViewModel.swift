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
    @ObservationIgnored private var backfillTask: Task<Void, Never>?
    @ObservationIgnored private let repo = DmRepository.shared
    @ObservationIgnored private let profileRepo = ProfileRepository.shared

    /// Per-page cap for the historical backfill. Most relays default to ~500 events per
    /// REQ; we ask for that explicitly so we can detect a short page (= "you have it all"
    /// from this relay's perspective) and stop.
    private static let backfillPageLimit = 500
    /// Hard cap on backfill pages — at 500 wraps/page that's 10000 wraps, a generous ceiling
    /// for any human DM volume. Prevents runaway loops if a relay keeps sending non-empty pages.
    private static let backfillMaxPages = 20

    init(keypair: Keypair) {
        self.keypair = keypair
    }

    func start() async {
        guard subscription == nil else { return }
        repo.bind(activePubkey: keypair.pubkey)
        isLoading = true

        // 1. Resolve the DM subscription relay set: kind-10050 DM relays unioned with the
        //    user's NIP-65 read+write relays. No hardcoded defaults — every URL here came
        //    from the user's own published relay lists.
        let relays = await resolveDmSubscriptionRelays()

        // 2. Open persistent subscription for live delivery. NO `since` — wraps have
        //    randomized timestamps (NIP-17 spec allows up to 2 days in the past).
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

        // 3. Walk back through history. Most relays cap a single REQ response at 500-1000
        //    events, so for accounts with deep DM history the live subscription alone returns
        //    only the newest slice — older conversations and older messages within
        //    conversations are silently truncated. Page back with `until=<oldest-1>` until a
        //    page returns 0 events or fewer than the limit.
        backfillTask = Task { [weak self] in
            await self?.backfillHistory(relays: relays, privkey: priv)
        }
    }

    func stop() {
        backfillTask?.cancel()
        backfillTask = nil
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
            relayUrls: relayUrl.isEmpty ? [] : [relayUrl]
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

    /// Build the kind-1059 subscription target set. Always unions the user's kind-10050 DM
    /// relays with their NIP-65 read+write relays — gift wraps from older clients (or peers
    /// who haven't fetched the recipient's kind-10050) frequently land on NIP-65 relays even
    /// when a DM inbox is published, so excluding them silently drops conversations.
    /// Mirrors Android's `relayPool.sendToAll(dmReqMsg) + sendToDmRelays(dmReqMsg)`.
    private func resolveDmSubscriptionRelays() async -> [String] {
        // Hydrate from disk (instant) for the case where MessagesViewModel.start runs before
        // RelaySettingsRepository.bootstrap completes its async merge.
        RelaySettingsRepository.shared.ensureLoaded(pubkey: keypair.pubkey)

        var union: [String] = []
        union.append(contentsOf: RelaySettingsRepository.shared.dmRelays)
        let read = await RelayListRepository.shared.getReadRelays(keypair.pubkey)
        union.append(contentsOf: read)
        let write = await RelayListRepository.shared.getWriteRelays(keypair.pubkey)
        union.append(contentsOf: write)

        var seen = Set<String>()
        var canonical: [String] = []
        for url in union {
            guard let n = RelayUrlValidator.canonicalize(url) else { continue }
            if seen.insert(n).inserted { canonical.append(n) }
        }
        return canonical
    }

    /// Page backwards through gift-wrap history until exhausted. Each page is a fresh REQ
    /// fanned out to every relay in `relays`; events from all relays are deduped at the
    /// `DmRepository.markGiftWrapSeen` layer (so the live subscription and the backfill can
    /// both feed the same pipeline without double-processing).
    ///
    /// Stop conditions: empty page, short page (relay returned everything ≤ `until`), or
    /// `backfillMaxPages` reached.
    private func backfillHistory(relays: [String], privkey: Data) async {
        guard !relays.isEmpty else { return }
        var until: Int? = nil

        for _ in 0..<Self.backfillMaxPages {
            if Task.isCancelled { return }
            var filter = NostrFilter(
                kinds: [Nip17.Kind.giftWrap],
                pTags: [keypair.pubkey],
                limit: Self.backfillPageLimit
            )
            if let u = until { filter.until = u }

            let events = await RelayPool.query(relays: relays, filter: filter, timeout: 15)
            if events.isEmpty { return }

            for event in events {
                if Task.isCancelled { return }
                // No relay attribution available from RelayPool.query (EventCollector
                // doesn't track sources); pass the empty string. Worst case is the
                // DmMessage.relayUrls set is missing one provenance entry — display
                // is unaffected.
                await handleGiftWrap(event: event, relayUrl: "", privkey: privkey)
            }

            // Walk the cursor back. Use the oldest createdAt across the union so the next
            // page picks up where every relay in this round left off.
            let oldest = events.map(\.createdAt).min() ?? 0
            until = oldest - 1

            // Short page → the relays said "that's all I have older than `until`".
            if events.count < Self.backfillPageLimit { return }
        }
    }

    func privkeyData() -> Data {
        Hex.decode(keypair.privkey) ?? Data()
    }

    private func prefetchProfilesIfNeeded(participants: [String]) async {
        let missing = participants.filter { profileRepo.get($0) == nil }
        guard !missing.isEmpty else { return }
        let filter = NostrFilter(kinds: [0], authors: missing, limit: missing.count)
        let events = await RelayPool.query(
            relays: RelaySettingsRepository.indexerRelays, filter: filter, timeout: 5
        )
        for e in events { profileRepo.updateFromEvent(e) }
    }
}
