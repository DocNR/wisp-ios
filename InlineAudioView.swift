import SwiftUI

/// Inline audio attachment shown inside a note. Holds no AVPlayer of its own —
/// it commands the global `AudioPlayerStore` and observes its state. This
/// way audio survives the parent `PostCardView` being recycled by `LazyVStack`,
/// and the floating mini-player above the tab bar takes over playback chrome.
struct InlineAudioView: View {
    let meta: MediaMeta
    var authorPubkey: String? = nil
    var authorProfile: ProfileData? = nil
    @Environment(AudioPlayerStore.self) private var store
    @State private var hasBeenTapped: Bool = false

    private var isCurrent: Bool { store.isCurrent(url: meta.url) }

    private var displayName: String {
        let last = URL(string: meta.url)?.deletingPathExtension().lastPathComponent ?? ""
        return last.isEmpty ? "Audio" : last
    }

    private func makeTrack() -> AudioTrack {
        AudioTrack(
            url: meta.url,
            title: authorProfile?.displayString,
            artist: nil,
            artworkUrl: authorProfile?.picture,
            authorPubkey: authorPubkey
        )
    }

    var body: some View {
        if hasBeenTapped || isCurrent {
            activeStrip
        } else {
            tapToPlayRow
        }
    }

    private var tapToPlayRow: some View {
        Button {
            hasBeenTapped = true
            store.play(makeTrack())
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.wispPrimary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Tap to play audio")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Color.wispSurfaceVariant.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var activeStrip: some View {
        let position = isCurrent ? Double(store.positionMs) / 1000 : 0
        let duration = isCurrent ? max(0.001, Double(store.durationMs) / 1000) : 0.001
        let playing = isCurrent && store.isPlaying

        return HStack(spacing: 12) {
            Button {
                if isCurrent {
                    store.togglePlayPause()
                } else {
                    store.play(makeTrack())
                }
            } label: {
                Image(systemName: playing ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.wispPrimary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                ProgressView(value: position, total: duration)
                    .tint(Color.wispPrimary)

                HStack {
                    Text(formatTime(position))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatTime(duration))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color.wispSurfaceVariant.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
