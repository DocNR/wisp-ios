import Foundation

enum RelayFeedStatus: Equatable {
    case idle
    case connecting
    case streaming
    case noEvents
    case timedOut
    case connectionFailed(String)
}
