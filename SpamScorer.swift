import Foundation

/// On-device spam scorer. Loads the bundled LightGBM forest and calibration table on first
/// use, then for each author scores up to 10 of their most recent notes through the feature
/// extractor, runs the forest, applies sigmoid + piecewise calibration, and caches the
/// result. Mirrors Android's `NSpamClassifier.score`.
///
/// Inference runs inside a `Task.detached(priority: .utility)` so it never bogs the actor
/// or the UI. Callers receive an async `Float` (>= 0.7 = spam in the Android default).
actor SpamScorer {
    static let shared = SpamScorer()

    static let spamThreshold: Float = 0.7

    private var model: LightGbmModel?
    private var calibration: NSpamCalibration?
    private var warmedUp = false
    private var warmupError: String?

    /// FIFO eviction is enough — spam scores rarely change during a session and the cap is high.
    private let cacheCap = 4096
    private var cache: [String: Float] = [:]
    private var cacheOrder: [String] = []

    private init() {}

    // MARK: - Warmup

    func warmUp() async throws {
        if warmedUp { return }
        guard let modelUrl = Bundle.main.url(forResource: "model", withExtension: "txt", subdirectory: "nspam"),
              let calibUrl = Bundle.main.url(forResource: "calibration", withExtension: "npz", subdirectory: "nspam") else {
            // Try without subdirectory in case bundle layout is flat.
            try await warmUpFlat()
            return
        }
        let modelData = try Data(contentsOf: modelUrl)
        let calibData = try Data(contentsOf: calibUrl)
        model = try LightGbmModel.parse(data: modelData)
        calibration = try NSpamCalibration.load(data: calibData)
        warmedUp = true
    }

    private func warmUpFlat() async throws {
        guard let modelUrl = Bundle.main.url(forResource: "model", withExtension: "txt"),
              let calibUrl = Bundle.main.url(forResource: "calibration", withExtension: "npz") else {
            throw NSError(domain: "SpamScorer", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "NSpam model bundle resources missing"])
        }
        model = try LightGbmModel.parse(data: try Data(contentsOf: modelUrl))
        calibration = try NSpamCalibration.load(data: try Data(contentsOf: calibUrl))
        warmedUp = true
    }

    // MARK: - Score

    /// Returns the cached score if available, otherwise extracts features and runs inference
    /// off the actor on a `Task.detached`. Returns nil if the model isn't loaded yet.
    func score(pubkey: String, recentEvents: [NostrEvent]) async -> Float? {
        if let cached = cache[pubkey] { return cached }
        guard let model, let calibration, !recentEvents.isEmpty else { return nil }

        // Cap to 10 most-recent notes per the Android default.
        let capped = recentEvents
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(10)
            .map { NSpamNoteInput(content: $0.content, tags: $0.tags, createdAt: $0.createdAt) }

        let modelLocal = model
        let calibrationLocal = calibration
        let result: Float = await Task.detached(priority: .utility) {
            let features = NSpamFeatures.extractFeatures(capped)
            let margin = modelLocal.rawMargin(features: features)
            let raw = Float(1.0 / (1.0 + exp(-margin)))
            return calibrationLocal.score(rawScore: raw)
        }.value

        insertCached(pubkey: pubkey, score: result)
        return result
    }

    func cachedScore(pubkey: String) -> Float? { cache[pubkey] }

    func invalidate(pubkey: String) {
        cache[pubkey] = nil
        cacheOrder.removeAll { $0 == pubkey }
    }

    func clearCache() {
        cache.removeAll()
        cacheOrder.removeAll()
    }

    var isReady: Bool { warmedUp }

    // MARK: - Private

    private func insertCached(pubkey: String, score: Float) {
        if cache[pubkey] != nil {
            cache[pubkey] = score
            return
        }
        cache[pubkey] = score
        cacheOrder.append(pubkey)
        if cacheOrder.count > cacheCap {
            let evict = cacheOrder.removeFirst()
            cache[evict] = nil
        }
    }
}
