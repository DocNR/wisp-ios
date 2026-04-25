import Foundation
import CoreGraphics

enum ComposeMode {
    case new
    case reply(parent: NostrEvent, root: NostrEvent?)
    case quote(NostrEvent)

    var allowsGalleryToggle: Bool {
        switch self {
        case .new: return true
        case .reply, .quote: return false
        }
    }

    /// Polls can be authored in `.new` and `.reply` contexts (Android allows both).
    /// Quote-as-poll is unsupported because the quote URL would push the poll question
    /// out of the visible content.
    var allowsPollToggle: Bool {
        switch self {
        case .new, .reply: return true
        case .quote: return false
        }
    }
}

/// Pending media awaiting upload or already-uploaded with metadata.
struct ComposeAttachment: Identifiable {
    let id: UUID
    /// Public Blossom URL once uploaded. Pre-upload it's nil.
    var url: String?
    let mime: String
    let dim: CGSize
    let durationSec: Int?
    let sha256Hex: String?
    /// Local copy of the bytes — kept around until upload completes so we can render
    /// a thumbnail. Cleared once `url` is set.
    var localBytes: Data?

    var isVideo: Bool { mime.hasPrefix("video/") }
}

/// A confirmed mention inserted into the composer text.
struct InsertedMention: Hashable {
    let displayName: String
    let pubkey: String
}
