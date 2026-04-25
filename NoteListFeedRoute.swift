import Foundation

/// Navigation route for a note-list feed. Resolves to a `NoteList` via
/// `NoteListRepository.shared.list(dTag:)` at navigation time.
struct NoteListFeedRoute: Hashable {
    let dTag: String
}
