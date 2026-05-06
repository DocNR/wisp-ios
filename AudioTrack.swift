import Foundation

struct AudioTrack: Hashable, Sendable {
    let url: String
    let title: String?
    let artist: String?
    let artworkUrl: String?
    let authorPubkey: String?

    init(
        url: String,
        title: String? = nil,
        artist: String? = nil,
        artworkUrl: String? = nil,
        authorPubkey: String? = nil
    ) {
        self.url = url
        self.title = title
        self.artist = artist
        self.artworkUrl = artworkUrl
        self.authorPubkey = authorPubkey
    }

    var displayTitle: String {
        if let t = title, !t.isEmpty { return t }
        let last = URL(string: url)?.deletingPathExtension().lastPathComponent ?? ""
        return last.isEmpty ? "Audio" : last
    }
}
