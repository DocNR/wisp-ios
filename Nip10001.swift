import Foundation

/// NIP-51 kind-10001 — pinned notes.
/// Spec: https://github.com/nostr-protocol/nips/blob/master/51.md
///
/// Replaceable list event whose `e` tags reference the pinned note ids in display order.
enum Nip10001 {

    static let kindPinned: Int = 10001

    /// Extract pinned event ids (in order) from a kind-10001 event.
    static func pinnedIds(from event: NostrEvent) -> [String] {
        event.tags.compactMap { tag in
            tag.count >= 2 && tag[0] == "e" ? tag[1] : nil
        }
    }

    /// Build the tag set for a kind-10001 event from a list of pinned event ids.
    /// Optional `relayHint` is appended to each `e` tag for outbox-style discovery.
    static func buildTags(pinnedIds: [String], relayHint: String = "") -> [[String]] {
        pinnedIds.map { id in
            relayHint.isEmpty ? ["e", id] : ["e", id, relayHint]
        }
    }
}
