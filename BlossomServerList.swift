import Foundation

enum BlossomServerList {
    static let defaultServer = "https://blossom.primal.net"
    static let kindServerList = 10063

    /// Set true while `MediaServersView` is on screen so background `refresh(...)`
    /// calls (e.g. from the composer) don't stomp the user's in-progress edits.
    nonisolated(unsafe) static var editorOpen = false

    /// Cached server list for the given pubkey, or the default fallback.
    static func cached(for pubkey: String) -> [String] {
        let stored = UserDefaults.standard.stringArray(forKey: storageKey(pubkey)) ?? []
        return stored.isEmpty ? [defaultServer] : stored
    }

    /// Persist a user-edited server list. Empty input is floored to the default
    /// so a stray "save []" never produces a kind-10063 with zero `server` tags.
    static func save(servers: [String], for pubkey: String) {
        let final = servers.isEmpty ? [defaultServer] : servers
        UserDefaults.standard.set(final, forKey: storageKey(pubkey))
    }

    /// Fetch the user's kind-10063 server list from their write relays and cache it.
    /// Falls back to `[defaultServer]` if no event is found. Cheap to call repeatedly —
    /// caller is expected to invoke on first composer open per session.
    static func refresh(for pubkey: String) async -> [String] {
        let writeRelays = topWriteRelays(for: pubkey, limit: 5)
        guard !writeRelays.isEmpty else {
            cache(servers: [defaultServer], for: pubkey)
            return [defaultServer]
        }
        let events = await RelayPool.query(
            relays: writeRelays,
            filter: NostrFilter(kinds: [kindServerList], authors: [pubkey], limit: 5),
            timeout: 6
        )
        let latest = events
            .filter { $0.kind == kindServerList }
            .max(by: { $0.createdAt < $1.createdAt })

        guard let event = latest else {
            cache(servers: [defaultServer], for: pubkey)
            return [defaultServer]
        }
        let servers = parseServers(event)
        let final = servers.isEmpty ? [defaultServer] : servers
        if !editorOpen {
            cache(servers: final, for: pubkey)
        }
        return final
    }

    private static func parseServers(_ event: NostrEvent) -> [String] {
        var out: [String] = []
        for tag in event.tags where tag.count >= 2 && tag[0] == "server" {
            let url = tag[1]
            if !url.isEmpty, !out.contains(url) { out.append(url) }
        }
        return out
    }

    private static func topWriteRelays(for pubkey: String, limit: Int) -> [String] {
        guard let board = RelayScoreBoard.load(pubkey: pubkey) else { return [] }
        return board.scoredRelays.prefix(limit).map(\.url)
    }

    private static func cache(servers: [String], for pubkey: String) {
        UserDefaults.standard.set(servers, forKey: storageKey(pubkey))
    }

    private static func storageKey(_ pubkey: String) -> String {
        "blossom_servers_\(pubkey)"
    }
}
