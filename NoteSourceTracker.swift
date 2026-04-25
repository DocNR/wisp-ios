import Foundation
import Observation

/// In-memory map of `eventId → Set<relayUrl>`, populated by RelayPool whenever an EVENT
/// is received from any relay (via `query` or `subscribe`). PostCardView's expander
/// reads from this to render the "Seen on" row. Cleared on logout.
@Observable
@MainActor
final class NoteSourceTracker {
    static let shared = NoteSourceTracker()

    private(set) var sources: [String: Set<String>] = [:]

    private init() {}

    func record(eventId: String, relayUrl: String) {
        sources[eventId, default: []].insert(relayUrl)
    }

    func relays(for eventId: String) -> [String] {
        guard let set = sources[eventId] else { return [] }
        return Array(set).sorted()
    }

    func clear() {
        sources.removeAll()
    }
}
