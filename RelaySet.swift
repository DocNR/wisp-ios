import Foundation

struct RelaySet: Codable, Identifiable, Equatable, Hashable {
    let pubkey: String
    let dTag: String
    var name: String
    var relays: [String]
    var createdAt: Int

    var id: String { "\(pubkey):\(dTag)" }
}
