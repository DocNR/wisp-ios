import Foundation

/// Navigation route for hashtag-feed views. One of `tag` or `setDTag` is set;
/// the consumer looks up the matching `HashtagSet` via `HashtagSetRepository`
/// at navigation time so the route stays cheap and `Hashable`.
struct HashtagFeedRoute: Hashable {
    let tag: String?
    let setDTag: String?

    init(tag: String) {
        self.tag = Nip51Hashtags.normalize(tag) ?? tag.lowercased()
        self.setDTag = nil
    }

    init(setDTag: String) {
        self.tag = nil
        self.setDTag = setDTag
    }
}
