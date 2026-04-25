import Foundation

/// A user-curated list of pubkeys (NIP-51 kind 30000 "follow set").
///
/// Identified by `dTag` within a given `pubkey`. Members live in two arrays:
/// `publicMembers` are emitted as plain `["p", hex]` tags; `privateMembers`
/// are encrypted with NIP-44 (self-conversation key) into `event.content`.
struct PeopleList: Codable, Identifiable, Hashable {
    let pubkey: String
    var dTag: String
    var name: String
    var publicMembers: [String]
    var privateMembers: [String]
    var createdAt: Int

    var id: String { dTag }

    var allMembers: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for m in publicMembers + privateMembers where seen.insert(m).inserted {
            out.append(m)
        }
        return out
    }

    func isPrivate(_ pubkey: String) -> Bool {
        privateMembers.contains(pubkey)
    }
}
