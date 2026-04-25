import Foundation
import Observation

@Observable
@MainActor
final class SplashViewModel {
    var profilePictures: [String] = []
    var onlineCount: Int?

    @ObservationIgnored private var fetchTask: Task<Void, Never>?
    @ObservationIgnored private var metricsTask: Task<Void, Never>?

    private static let relayURL = URL(string: "wss://premium.primal.net")!
    private static let metricsURL = URL(string: "wss://api.nostrarchives.com/v1/ws/live-metrics")!
    private static let targetCount = 300

    init() {
        fetchTask = Task { await fetchProfilePictures() }
        metricsTask = Task { await connectLiveMetrics() }
    }

    func cancel() {
        fetchTask?.cancel()
        metricsTask?.cancel()
    }

    private func fetchProfilePictures() async {
        let session = URLSession(configuration: .default)
        let ws = session.webSocketTask(with: Self.relayURL)
        ws.resume()

        do {
            try await ws.send(.string("""
            ["REQ","splash",{"kinds":[0],"limit":300}]
            """))
        } catch {
            return
        }

        var pictures: [String] = []
        var seen = Set<String>()
        var eoseGraceDeadline: Date?
        let deadline = Date().addingTimeInterval(10)

        while pictures.count < Self.targetCount {
            if Date() >= deadline { break }
            if let grace = eoseGraceDeadline, Date() >= grace { break }
            if Task.isCancelled { break }

            do {
                let message = try await ws.receive()

                switch message {
                case .string(let text):
                    guard let data = text.data(using: String.Encoding.utf8),
                          let arr = try? JSONSerialization.jsonObject(with: data) as? [Any],
                          let type = arr.first as? String else { continue }

                    if type == "EVENT", arr.count >= 3,
                       let eventObj = arr[2] as? [String: Any],
                       let content = eventObj["content"] as? String,
                       let contentData = content.data(using: String.Encoding.utf8),
                       let profile = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any],
                       let pic = profile["picture"] as? String,
                       !pic.isEmpty, !seen.contains(pic) {
                        seen.insert(pic)
                        pictures.append(pic)
                        if pictures.count % 20 == 0 || pictures.count >= Self.targetCount {
                            self.profilePictures = pictures
                        }
                    } else if type == "EOSE" {
                        if eoseGraceDeadline == nil {
                            eoseGraceDeadline = Date().addingTimeInterval(2)
                        }
                    }
                default:
                    break
                }
            } catch {
                break
            }
        }

        if !pictures.isEmpty {
            self.profilePictures = pictures
        }

        try? await ws.send(.string("""
        ["CLOSE","splash"]
        """))
        ws.cancel(with: .normalClosure, reason: nil)
    }

    private func connectLiveMetrics() async {
        let session = URLSession(configuration: .default)
        let ws = session.webSocketTask(with: Self.metricsURL)
        ws.resume()

        while !Task.isCancelled {
            do {
                let message = try await ws.receive()
                switch message {
                case .string(let text):
                    guard let data = text.data(using: String.Encoding.utf8),
                          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let online = obj["online"] as? Int else { continue }
                    self.onlineCount = online
                default:
                    break
                }
            } catch {
                break
            }
        }

        ws.cancel(with: .normalClosure, reason: nil)
    }
}
