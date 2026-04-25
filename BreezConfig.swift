import Foundation

/// Reads the Breez Spark API key from a bundled resource file.
/// Drop your key (one line) into `wisp/Resources/breez-api-key.txt` (gitignored).
enum BreezConfig {
    static let apiKey: String = {
        guard let url = Bundle.main.url(forResource: "breez-api-key", withExtension: "txt"),
              let raw = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }()

    static var hasApiKey: Bool { !apiKey.isEmpty }
}
