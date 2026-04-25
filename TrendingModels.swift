import Foundation

/// Two top-level views inside the Trending screen.
enum TrendingMode: Hashable {
    case notes
    case users
}

/// Engagement metric used to rank trending notes. Slugs match the path
/// segments served by `feeds.nostrarchives.com/notes/trending/<metric>/<timeframe>`.
enum TrendingMetric: String, CaseIterable, Hashable {
    case reactions
    case replies
    case reposts
    case zaps

    var slug: String { rawValue }

    var label: String {
        switch self {
        case .reactions: return "Reactions"
        case .replies: return "Replies"
        case .reposts: return "Reposts"
        case .zaps: return "Zaps"
        }
    }

    var iconName: String {
        switch self {
        case .reactions: return "heart"
        case .replies: return "arrowshape.turn.up.left"
        case .reposts: return "arrow.2.squarepath"
        case .zaps: return "bolt"
        }
    }
}

/// Time window for trending-note ranking. Slugs match the path segments
/// served by the relay.
enum TrendingTimeframe: String, CaseIterable, Hashable {
    case today
    case week
    case month
    case year
    case all

    var slug: String {
        switch self {
        case .today: return "today"
        case .week: return "7d"
        case .month: return "30d"
        case .year: return "1y"
        case .all: return "all"
        }
    }

    var label: String {
        switch self {
        case .today: return "Today"
        case .week: return "7d"
        case .month: return "30d"
        case .year: return "1y"
        case .all: return "All"
        }
    }
}

enum TrendingRelay {
    static let usersURL = "wss://feeds.nostrarchives.com/users/upandcoming"

    static func notesURL(metric: TrendingMetric, timeframe: TrendingTimeframe) -> String {
        "wss://feeds.nostrarchives.com/notes/trending/\(metric.slug)/\(timeframe.slug)"
    }
}
