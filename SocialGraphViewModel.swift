import Foundation
import Observation

/// Drives the Social Graph screen. Wraps `SocialGraphRepository` with `@Observable` state
/// and exposes `compute()` / `cancel()` for the UI.
@Observable
@MainActor
final class SocialGraphViewModel {
    let pubkey: String

    var state: DiscoveryState = .idle
    var cache: SocialGraphCache?

    @ObservationIgnored private var computeTask: Task<Void, Never>?

    init(pubkey: String) {
        self.pubkey = pubkey
        self.cache = SocialGraphCache.load(pubkey: pubkey)
    }

    var isComputing: Bool {
        switch state {
        case .idle, .complete, .failed: return false
        default: return true
        }
    }

    var hasCache: Bool { cache != nil }

    func compute() {
        guard computeTask == nil else { return }
        let pk = pubkey
        let stream = SocialGraphRepository.shared.compute(pubkey: pk)
        computeTask = Task { [weak self] in
            for await s in stream {
                guard let self else { return }
                self.state = s
                if case .complete = s {
                    self.cache = SocialGraphCache.load(pubkey: pk)
                }
            }
            self?.computeTask = nil
        }
    }

    func cancel() {
        computeTask?.cancel()
        computeTask = nil
    }

    /// Used by the UI's idle-with-cache header to show "3h ago" / "2 days ago".
    var cachedAgeDescription: String? {
        guard let cache else { return nil }
        let now = Int(Date().timeIntervalSince1970)
        let elapsed = max(0, now - cache.computedAt)
        switch elapsed {
        case ..<60: return "just now"
        case ..<3600: return "\(elapsed / 60)m ago"
        case ..<86_400: return "\(elapsed / 3600)h ago"
        default: return "\(elapsed / 86_400)d ago"
        }
    }
}
