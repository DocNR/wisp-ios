import Foundation
import GiphyUISDK

/// One-shot Giphy SDK bootstrap. Reads the API key from a bundled resource
/// (`wisp/Resources/giphy-api-key.txt`, gitignored) and falls back to the
/// hard-coded development key embedded below so the GIF picker still works in
/// fresh checkouts. Call `GiphyConfig.bootstrap()` once at app launch — it
/// no-ops on subsequent calls.
enum GiphyConfig {
    /// Development fallback. Replace with a project-owned key in production by
    /// dropping it into `wisp/Resources/giphy-api-key.txt`.
    private static let fallbackKey = "skps5dg1WqyfynjZBkwa6ziTBJC2KLzx"

    static let apiKey: String = {
        if let url = Bundle.main.url(forResource: "giphy-api-key", withExtension: "txt"),
           let raw = try? String(contentsOf: url, encoding: .utf8) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return fallbackKey
    }()

    private static var didConfigure = false

    static func bootstrap() {
        guard !didConfigure else { return }
        didConfigure = true
        Giphy.configure(apiKey: apiKey)
    }
}
