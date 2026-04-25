import Foundation

/// Navigation route for a people-list feed. Resolves to a `PeopleList` via
/// `PeopleListRepository.shared.list(dTag:)` at navigation time.
struct PeopleListFeedRoute: Hashable {
    let dTag: String
}
