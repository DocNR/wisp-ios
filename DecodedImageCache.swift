import UIKit

/// Process-wide in-memory cache of *decoded* image payloads, keyed by URL.
///
/// Why this exists: SwiftUI's `AsyncImage` and the project's `AnimatedImageView`
/// both rely on `URLSession.shared` + `URLCache` for transit caching. That
/// keeps the bytes around but each view re-mount has to decode them into a
/// `UIImage` (or a `CGImageSource` frame array for GIFs / APNG / animated
/// WebP) — a 30–80 ms operation that's enough to flash a loader as a row
/// scrolls back into a `LazyVStack`.
///
/// This cache holds the already-decoded result so a row that came back into
/// view renders instantly with no loader flash. NSCache evicts under memory
/// pressure on its own.
@MainActor
enum DecodedImageCache {
    /// Cap roughly proportional to the average size: still images are small,
    /// animated payloads are many MB each so the bound is much tighter.
    private static let staticCache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 256
        return c
    }()

    private static let animatedCache: NSCache<NSString, AnimatedPayloadBox> = {
        let c = NSCache<NSString, AnimatedPayloadBox>()
        c.countLimit = 48
        return c
    }()

    final class AnimatedPayloadBox {
        let payload: AnimatedImagePayload
        init(_ payload: AnimatedImagePayload) { self.payload = payload }
    }

    static func staticImage(for url: String) -> UIImage? {
        staticCache.object(forKey: url as NSString)
    }

    static func storeStatic(_ image: UIImage, for url: String) {
        staticCache.setObject(image, forKey: url as NSString)
    }

    static func animatedPayload(for url: String) -> AnimatedImagePayload? {
        animatedCache.object(forKey: url as NSString)?.payload
    }

    static func storeAnimated(_ payload: AnimatedImagePayload, for url: String) {
        animatedCache.setObject(AnimatedPayloadBox(payload), forKey: url as NSString)
    }
}
