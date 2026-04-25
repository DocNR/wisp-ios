import Foundation

/// Navigation route for the trending-feeds screen. Carries no state — the
/// view's own `TrendingFeedViewModel` owns mode/metric/timeframe and the user
/// adjusts them via the in-screen filter bar.
struct TrendingFeedRoute: Hashable {}
