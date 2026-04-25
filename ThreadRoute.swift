import Foundation

struct ThreadRoute: Hashable {
    let eventId: String
    /// Hint so the thread can start fetching the author's inbox relays before the event arrives.
    let authorPubkey: String?
}
