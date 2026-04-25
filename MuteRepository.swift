import Foundation
import Observation

/// Per-account store for muted words, blocked pubkeys, and muted thread roots, mirroring
/// Android's `MuteRepository`. Backed by per-pubkey UserDefaults entries and synced to
/// relays as a NIP-51 kind:10000 event with a NIP-44-encrypted private body.
///
/// Words are stored already-lowercased so the hot-path substring check in `SafetyFilter`
/// avoids per-event allocation.
@Observable
@MainActor
final class MuteRepository {
    static let shared = MuteRepository()

    private(set) var activePubkey: String?
    private(set) var mutedWords: Set<String> = []
    private(set) var blockedPubkeys: Set<String> = []
    private(set) var mutedThreads: Set<String> = []
    private(set) var lastUpdatedAt: Int = 0

    @ObservationIgnored private var binding = false
    @ObservationIgnored private var activePrivkey32: Data?
    @ObservationIgnored private var syncSubscription: RelaySubscription?
    @ObservationIgnored private var syncListener: Task<Void, Never>?

    private init() {}

    // MARK: - Lifecycle

    func bind(activePubkey pk: String, privkey32: Data?) {
        binding = true
        defer { binding = false }
        unbindSync()
        activePubkey = pk
        activePrivkey32 = privkey32
        let d = UserDefaults.standard
        mutedWords = Set(d.stringArray(forKey: Self.wordsKey(pk)) ?? [])
        blockedPubkeys = Set(d.stringArray(forKey: Self.pubkeysKey(pk)) ?? [])
        mutedThreads = Set(d.stringArray(forKey: Self.threadsKey(pk)) ?? [])
        lastUpdatedAt = d.integer(forKey: Self.updatedAtKey(pk))
    }

    func unbind() {
        binding = true
        defer { binding = false }
        unbindSync()
        activePubkey = nil
        activePrivkey32 = nil
        mutedWords = []
        blockedPubkeys = []
        mutedThreads = []
        lastUpdatedAt = 0
    }

    private func unbindSync() {
        syncListener?.cancel()
        syncListener = nil
        syncSubscription?.cancel()
        syncSubscription = nil
    }

    // MARK: - Mutators

    func addMutedWord(_ word: String) {
        let normalized = word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !mutedWords.contains(normalized) else { return }
        mutedWords.insert(normalized)
        commitChange()
    }

    func removeMutedWord(_ word: String) {
        let normalized = word.lowercased()
        guard mutedWords.remove(normalized) != nil else { return }
        commitChange()
    }

    func blockUser(_ pubkey: String) {
        guard !pubkey.isEmpty, !blockedPubkeys.contains(pubkey) else { return }
        blockedPubkeys.insert(pubkey)
        commitChange()
        // Eagerly purge their cached events so feed reseeds and notification hydration can't
        // resurface them.
        Task.detached { await EventStore.shared.removeByAuthor(pubkey) }
    }

    func unblockUser(_ pubkey: String) {
        guard blockedPubkeys.remove(pubkey) != nil else { return }
        commitChange()
    }

    func muteThread(_ rootEventId: String) {
        guard !rootEventId.isEmpty, !mutedThreads.contains(rootEventId) else { return }
        mutedThreads.insert(rootEventId)
        commitChange()
    }

    func unmuteThread(_ rootEventId: String) {
        guard mutedThreads.remove(rootEventId) != nil else { return }
        commitChange()
    }

    func containsMutedWord(_ content: String) -> Bool {
        guard !mutedWords.isEmpty else { return false }
        let lower = content.lowercased()
        for w in mutedWords where lower.contains(w) { return true }
        return false
    }

    func isBlocked(_ pubkey: String) -> Bool { blockedPubkeys.contains(pubkey) }

    func isThreadMuted(_ rootEventId: String) -> Bool { mutedThreads.contains(rootEventId) }

    // MARK: - Sync

    /// Build a fresh kind:10000 event reflecting the current state and publish to the user's
    /// write relays. Self-encrypted via NIP-44; tags are empty so other clients see only an
    /// opaque blob.
    func republish(privkey32: Data) async {
        guard let pk = activePubkey else { return }
        let words = mutedWords
        let pubkeys = blockedPubkeys
        let threads = mutedThreads
        let createdAt = max(Int(Date().timeIntervalSince1970), lastUpdatedAt + 1)
        do {
            let event = try Nip51Mute.buildSignedMuteEvent(
                privkey32: privkey32,
                ownPubkey: pk,
                blockedPubkeys: pubkeys,
                mutedWords: words,
                mutedThreads: threads,
                createdAt: createdAt
            )
            lastUpdatedAt = createdAt
            UserDefaults.standard.set(createdAt, forKey: Self.updatedAtKey(pk))
            let writeRelays = await RelayListRepository.shared.getWriteRelays(pk)
            let relays = writeRelays.isEmpty ? Self.fallbackRelays : writeRelays
            _ = await RelayPool.publish(event: event, to: relays, timeout: 6)
        } catch {
            // Encryption / signing failure: keep the local state so the user isn't left without
            // their list. Next mutation will re-attempt.
        }
    }

    /// Open a long-lived subscription for our own kind:10000 and merge any newer event we see.
    /// Also kicks one immediate `RelayPool.query` for fast hydration on launch.
    func startSync(privkey32: Data) {
        guard let pk = activePubkey else { return }
        unbindSync()
        let priv = privkey32
        let pubkey = pk

        Task { [weak self] in
            let writeRelays = await RelayListRepository.shared.getWriteRelays(pubkey)
            let relays = writeRelays.isEmpty ? Self.fallbackRelays : writeRelays
            let filter = NostrFilter(kinds: [Nip51Mute.kindMuteList], authors: [pubkey], limit: 5)
            // Quick hydration first.
            let initial = await RelayPool.query(relays: relays, filter: filter, timeout: 6)
            for event in initial {
                await self?.merge(event: event, privkey32: priv)
            }
            await MainActor.run {
                guard let self else { return }
                let sub = RelayPool.subscribe(relays: relays, filter: filter, id: "mute-self-sync")
                self.syncSubscription = sub
                self.syncListener = Task { [weak self] in
                    for await (event, _) in sub.events {
                        await self?.merge(event: event, privkey32: priv)
                    }
                }
            }
        }
    }

    /// Apply an inbound kind:10000 if it's newer than our local state. Merges decrypted
    /// private body with any public tags (some clients still publish public ["p", x]).
    func merge(event: NostrEvent, privkey32: Data) async {
        guard event.kind == Nip51Mute.kindMuteList,
              event.pubkey == activePubkey,
              event.createdAt > lastUpdatedAt else { return }

        let parsed = (try? Nip51Mute.decryptAndParse(event: event, privkey32: privkey32))
            ?? Nip51Mute.parsePublicTags(event: event)

        mutedWords = parsed.words
        blockedPubkeys = parsed.pubkeys
        mutedThreads = parsed.threads
        lastUpdatedAt = event.createdAt

        guard let pk = activePubkey else { return }
        let d = UserDefaults.standard
        d.set(Array(mutedWords), forKey: Self.wordsKey(pk))
        d.set(Array(blockedPubkeys), forKey: Self.pubkeysKey(pk))
        d.set(Array(mutedThreads), forKey: Self.threadsKey(pk))
        d.set(lastUpdatedAt, forKey: Self.updatedAtKey(pk))
        await SafetyFilter.shared.rebuildSnapshot()
    }

    // MARK: - Storage keys

    static func wordsKey(_ pubkey: String) -> String { "muted_words_\(pubkey)" }
    static func pubkeysKey(_ pubkey: String) -> String { "blocked_pubkeys_\(pubkey)" }
    static func threadsKey(_ pubkey: String) -> String { "muted_threads_\(pubkey)" }
    static func updatedAtKey(_ pubkey: String) -> String { "mute_list_updated_at_\(pubkey)" }

    static let fallbackRelays = [
        "wss://relay.damus.io",
        "wss://relay.primal.net",
        "wss://nos.lol",
        "wss://relay.nostr.band"
    ]

    // MARK: - Private

    private func commitChange() {
        if binding { return }
        guard let pk = activePubkey else { return }
        let d = UserDefaults.standard
        d.set(Array(mutedWords), forKey: Self.wordsKey(pk))
        d.set(Array(blockedPubkeys), forKey: Self.pubkeysKey(pk))
        d.set(Array(mutedThreads), forKey: Self.threadsKey(pk))
        Task { await SafetyFilter.shared.rebuildSnapshot() }
        if let priv = activePrivkey32 {
            Task { [priv] in await self.republish(privkey32: priv) }
        }
    }
}
