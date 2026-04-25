import Foundation

enum Nip53 {
    static let kindLiveActivity = 30311
    static let kindLiveChatMessage = 1311

    struct LiveActivity: Hashable {
        let dTag: String
        let hostPubkey: String
        let streamerPubkey: String?
        let title: String?
        let summary: String?
        let image: String?
        let status: String?
        let streamingUrl: String?
        let participants: [Participant]
        let relayHints: [String]
        let createdAt: Int

        struct Participant: Hashable {
            let pubkey: String
            let role: String?
        }
    }

    static func aTagValue(host: String, dTag: String) -> String {
        "\(kindLiveActivity):\(host):\(dTag)"
    }

    static func getChatActivityRef(_ event: NostrEvent) -> String? {
        guard event.kind == kindLiveChatMessage else { return nil }
        return event.tags.first(where: { $0.count >= 2 && $0[0] == "a" })?[1]
    }

    static func parseLiveActivity(_ event: NostrEvent) -> LiveActivity? {
        guard event.kind == kindLiveActivity else { return nil }
        guard let dTag = event.tags.first(where: { $0.count >= 2 && $0[0] == "d" })?[1] else { return nil }

        func tag(_ name: String) -> String? {
            event.tags.first(where: { $0.count >= 2 && $0[0] == name })?[1]
        }

        var participants: [LiveActivity.Participant] = []
        for t in event.tags where t.count >= 2 && t[0] == "p" {
            var role: String? = nil
            if t.count >= 4 {
                let r = t[3]
                if !r.isEmpty { role = r }
            }
            participants.append(LiveActivity.Participant(pubkey: t[1], role: role))
        }

        let streamerPubkey = participants.first(where: {
            $0.role?.caseInsensitiveCompare("Host") == .orderedSame
        })?.pubkey

        var seenRelays = Set<String>()
        let relayHints = event.tags.compactMap { t -> String? in
            guard t.count >= 2, t[0] == "relay" || t[0] == "r" else { return nil }
            let url = t[1]
            guard url.hasPrefix("wss://") else { return nil }
            return seenRelays.insert(url).inserted ? url : nil
        }

        return LiveActivity(
            dTag: dTag,
            hostPubkey: event.pubkey,
            streamerPubkey: streamerPubkey,
            title: tag("title"),
            summary: tag("summary"),
            image: tag("image"),
            status: tag("status"),
            streamingUrl: tag("streaming"),
            participants: participants,
            relayHints: relayHints,
            createdAt: event.createdAt
        )
    }
}
