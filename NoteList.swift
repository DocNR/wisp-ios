import Foundation

/// A user-curated list of note ids (NIP-51 kind 30003 "bookmark set").
///
/// Identified by `dTag` within a given `pubkey`. Note ids in `publicNotes` are
/// emitted as plain `["e", id]` tags; `privateNotes` are encrypted with NIP-44
/// (self-conversation key) into `event.content`.
struct NoteList: Codable, Identifiable, Hashable {
    let pubkey: String
    var dTag: String
    var name: String
    var publicNotes: [String]
    var privateNotes: [String]
    var createdAt: Int

    var id: String { dTag }

    var allNotes: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for n in publicNotes + privateNotes where seen.insert(n).inserted {
            out.append(n)
        }
        return out
    }

    func isPrivate(_ id: String) -> Bool {
        privateNotes.contains(id)
    }
}
