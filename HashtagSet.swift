import Foundation

/// A user-curated set of hashtags (NIP-51 kind 30015 "interest set").
///
/// Identified by `dTag` within a given `pubkey`. Hashtags are stored normalized
/// (lowercase, no leading `#`). `createdAt` matches the underlying event so
/// newer-wins merge semantics work when bootstrapping from relays.
struct HashtagSet: Codable, Identifiable, Hashable {
    let pubkey: String
    var dTag: String
    var name: String
    var hashtags: [String]
    var createdAt: Int

    var id: String { dTag }
}
