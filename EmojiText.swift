import SwiftUI
import UIKit

/// Renders a string that may contain NIP-30 `:shortcode:` emoji references
/// resolved against `emojiMap`. Used wherever a profile's display-name might
/// contain a custom emoji (feed cards, profile header, replies, notifications,
/// search results, drawer, …).
///
/// Behaviour:
///   • If `name` has no shortcodes that resolve in `emojiMap`, falls through to
///     a plain `Text` so it composes with `.font`, `.foregroundStyle`, etc.
///     just like a Text would.
///   • Otherwise, hands off to a `UITextView`-backed renderer that uses
///     `NSTextAttachment` to inline the emoji image, mirroring the approach in
///     `RichInlineTextView`.
struct EmojiText: View {
    let raw: String
    let emojiMap: [String: String]
    var font: UIFont = .preferredFont(forTextStyle: .subheadline)
    var weight: UIFont.Weight? = nil
    var color: UIColor = .label
    var lineLimit: Int? = 1

    @ObservedObject private var emojiCache = EmojiImageCache.shared

    var body: some View {
        if !hasResolvableShortcodes {
            Text(raw)
        } else {
            EmojiTextRepresentable(
                raw: raw,
                emojiMap: emojiMap,
                font: applyWeight(font),
                color: color,
                lineLimit: lineLimit,
                emojiVersion: emojiCache.version
            )
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var hasResolvableShortcodes: Bool {
        guard !emojiMap.isEmpty else { return false }
        // Quick reject: check there's at least one ":" pair before paying the
        // regex cost.
        guard raw.contains(":") else { return false }
        let ns = raw as NSString
        let matches = EmojiText.shortcodeRegex.matches(in: raw, range: NSRange(location: 0, length: ns.length))
        for m in matches where m.numberOfRanges >= 2 {
            let r = m.range(at: 1)
            if r.location != NSNotFound, emojiMap[ns.substring(with: r)] != nil {
                return true
            }
        }
        return false
    }

    private func applyWeight(_ base: UIFont) -> UIFont {
        guard let weight else { return base }
        let descriptor = base.fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight]
        ])
        return UIFont(descriptor: descriptor, size: base.pointSize)
    }

    fileprivate static let shortcodeRegex = try! NSRegularExpression(pattern: #":([a-zA-Z0-9_-]+):"#)
}

extension EmojiText {
    /// SwiftUI-flavoured initializer: takes a `Font.TextStyle` and an optional
    /// weight/color so callers don't have to construct a `UIFont` manually.
    init(
        _ raw: String,
        emojiMap: [String: String],
        textStyle: UIFont.TextStyle = .subheadline,
        weight: UIFont.Weight? = nil,
        color: UIColor = .label,
        lineLimit: Int? = 1
    ) {
        self.raw = raw
        self.emojiMap = emojiMap
        self.font = UIFont.preferredFont(forTextStyle: textStyle)
        self.weight = weight
        self.color = color
        self.lineLimit = lineLimit
    }
}

private struct EmojiTextRepresentable: UIViewRepresentable {
    let raw: String
    let emojiMap: [String: String]
    let font: UIFont
    let color: UIColor
    let lineLimit: Int?
    /// Forces SwiftUI to re-evaluate when the emoji cache picks up a new image.
    let emojiVersion: Int

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.backgroundColor = .clear
        tv.isEditable = false
        tv.isSelectable = false
        tv.isScrollEnabled = false
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.textContainer.lineBreakMode = .byTruncatingTail
        tv.setContentCompressionResistancePriority(.required, for: .vertical)
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        // Trigger any not-yet-loaded emoji fetches.
        for (_, url) in emojiMap {
            EmojiImageCache.shared.ensureLoaded(url)
        }
        uiView.textContainer.maximumNumberOfLines = lineLimit ?? 0
        uiView.attributedText = buildAttributed()
        uiView.invalidateIntrinsicContentSize()
    }

    private func buildAttributed() -> NSAttributedString {
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let combined = NSMutableAttributedString()
        let ns = raw as NSString
        let matches = EmojiText.shortcodeRegex.matches(in: raw, range: NSRange(location: 0, length: ns.length))

        var lastEnd = 0
        for m in matches where m.numberOfRanges >= 2 {
            let r = m.range
            let scR = m.range(at: 1)
            guard scR.location != NSNotFound else { continue }
            let shortcode = ns.substring(with: scR)
            guard let url = emojiMap[shortcode] else { continue }

            if r.location > lastEnd {
                combined.append(NSAttributedString(
                    string: ns.substring(with: NSRange(location: lastEnd, length: r.location - lastEnd)),
                    attributes: baseAttrs
                ))
            }

            if let image = EmojiImageCache.shared.image(for: url) {
                let attachment = NSTextAttachment()
                let target = font.lineHeight * 1.05
                let aspect = image.size.width > 0 && image.size.height > 0
                    ? image.size.width / image.size.height
                    : 1.0
                attachment.image = image
                attachment.bounds = CGRect(x: 0, y: font.descender, width: target * aspect, height: target)
                let attach = NSMutableAttributedString(attachment: attachment)
                attach.addAttributes(baseAttrs, range: NSRange(location: 0, length: attach.length))
                combined.append(attach)
            } else {
                combined.append(NSAttributedString(string: ":\(shortcode):", attributes: baseAttrs))
            }
            lastEnd = r.location + r.length
        }
        if lastEnd < ns.length {
            combined.append(NSAttributedString(
                string: ns.substring(from: lastEnd),
                attributes: baseAttrs
            ))
        }
        return combined
    }
}
