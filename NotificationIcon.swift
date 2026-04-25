import SwiftUI

enum NotificationStyle {
    static func icon(_ kind: NotificationKind) -> String {
        switch kind {
        case .reply:    "bubble.right.fill"
        case .reaction: "heart.fill"
        case .repost:   "arrow.2.squarepath"
        case .zap:      "bolt.fill"
        case .quote:    "quote.bubble.fill"
        case .mention:  "at.circle.fill"
        case .dm:       "envelope.fill"
        case .pollVote: "checkmark.circle.fill"
        }
    }

    static func tint(_ kind: NotificationKind) -> Color {
        switch kind {
        case .reaction: .pink
        case .repost:   .wispRepostColor
        case .zap:      .wispZapColor
        default:        .wispPrimary
        }
    }

    static func actionText(_ kind: NotificationKind) -> String {
        switch kind {
        case .reply:    "replied"
        case .reaction: "reacted"
        case .repost:   "reposted"
        case .zap:      "zapped"
        case .quote:    "quoted"
        case .mention:  "mentioned you"
        case .dm:       "messaged you"
        case .pollVote: "voted on your poll"
        }
    }

    static func formatSats(_ sats: Int64) -> String {
        if sats >= 1_000_000 { return String(format: "%.1fM", Double(sats) / 1_000_000) }
        if sats >= 1_000 { return String(format: "%.1fk", Double(sats) / 1_000) }
        return "\(sats)"
    }
}

struct NotificationTypeIcon: View {
    let kind: NotificationKind

    var body: some View {
        Image(systemName: NotificationStyle.icon(kind))
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(NotificationStyle.tint(kind))
            .clipShape(Circle())
    }
}
