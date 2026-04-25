import Foundation

/// Persisted summary of the most recent social graph computation. Mirrors the Android
/// `ExtendedNetworkCache`. Stored as JSON in `UserDefaults` under
/// `social_graph_cache_v1_<pubkey>`.
struct SocialGraphCache: Codable, Equatable {
    let computedAt: Int                          // epoch seconds
    let firstDegreePubkeys: [String]             // snapshot of follows used as input
    let qualifiedPubkeys: [String]               // 2nd-degree passing the threshold
    let relayUrls: [String]                      // ordered set-cover output (≤100)
    let stats: ComputeStats
    /// 2nd-degree pubkey → number of first-degree follows that follow them. Used by the
    /// detail sheet ("Followed by N of your follows") and to size second-degree nodes.
    let secondDegreeFollowerCount: [String: Int]
    /// 1st-degree pubkey → number of *other* first-degree follows that follow them.
    /// Drives first-degree node sizing in the visualization.
    let firstDegreeFollowerCount: [String: Int]

    static func key(pubkey: String) -> String { "social_graph_cache_v1_\(pubkey)" }

    static func load(pubkey: String) -> SocialGraphCache? {
        guard let data = UserDefaults.standard.data(forKey: key(pubkey: pubkey)) else { return nil }
        return try? JSONDecoder().decode(SocialGraphCache.self, from: data)
    }

    func save(pubkey: String) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key(pubkey: pubkey))
    }

    static func clear(pubkey: String) {
        UserDefaults.standard.removeObject(forKey: key(pubkey: pubkey))
    }

    /// Stale if older than 24h or if the user's follow list has drifted >10% since this
    /// cache was computed. Drift = |symmetric difference| / max(old, new).
    func isStale(currentFollows: [String], ttl: TimeInterval = 24 * 3600, driftThreshold: Double = 0.10) -> Bool {
        let now = Int(Date().timeIntervalSince1970)
        if Double(now - computedAt) >= ttl { return true }
        let oldSet = Set(firstDegreePubkeys)
        let newSet = Set(currentFollows)
        let symDiff = oldSet.symmetricDifference(newSet).count
        let denom = max(oldSet.count, newSet.count, 1)
        return Double(symDiff) / Double(denom) > driftThreshold
    }
}

struct ComputeStats: Codable, Equatable, Sendable {
    let followListsFetched: Int
    let totalFollows: Int
    let secondDegreeUnique: Int
    let qualifiedCount: Int
    let relayCount: Int
    let durationMs: Int
}
