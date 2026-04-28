import SwiftUI
import AVKit
import AVFoundation
import Observation

@MainActor
@Observable
final class GlobalVideoMute {
    static let shared = GlobalVideoMute()
    var isMuted: Bool = true
    private init() {}
}

struct InlineVideoView: View {
    let meta: MediaMeta
    @Environment(AppSettings.self) private var settings
    @State private var loaded = false
    @State private var player: AVPlayer?
    @State private var showFullScreen = false
    @State private var muteState = GlobalVideoMute.shared

    /// Source aspect ratio (W / H) parsed from the imeta `dim` tag, with a
    /// 16:9 fallback. Tall portraits report something like 9/16 ≈ 0.56.
    private var nativeAspect: CGFloat {
        ContentParser.parseAspectRatio(meta.dimension) ?? (16.0 / 9.0)
    }

    /// Floor on the rendered box's aspect ratio (W / H). Sources taller than
    /// this — typical 9:16 phone video — get clamped so the player fills full
    /// card width without rendering at near-double width tall. Content is
    /// cropped (resizeAspectFill) so there are no black bars on the sides.
    /// Landscape and squarish sources render at their native aspect.
    private let minDisplayAspect: CGFloat = 4.0 / 5.0

    private var displayAspect: CGFloat {
        max(nativeAspect, minDisplayAspect)
    }

    private var videoGravity: AVLayerVideoGravity {
        nativeAspect < minDisplayAspect ? .resizeAspectFill : .resizeAspect
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black)

            if loaded, let player {
                CroppingVideoPlayer(player: player, gravity: videoGravity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onAppear {
                        MediaAudioSession.activatePlayback()
                        player.isMuted = muteState.isMuted
                        player.play()
                    }
                    .onDisappear {
                        player.pause()
                    }
                    .onChange(of: muteState.isMuted) { _, newValue in
                        player.isMuted = newValue
                    }

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            muteState.isMuted.toggle()
                        } label: {
                            Image(systemName: muteState.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                                .padding(8)
                                .background(Color.black.opacity(0.55), in: Circle())
                        }

                        Button {
                            showFullScreen = true
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                                .padding(8)
                                .background(Color.black.opacity(0.55), in: Circle())
                        }
                    }
                    .padding(8)
                }
            } else {
                Button {
                    initPlayer()
                    loaded = true
                } label: {
                    ZStack {
                        Color.black.opacity(0.001)
                        VStack(spacing: 8) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 56))
                                .foregroundStyle(.white)
                            Text("Tap to play")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                }
                .buttonStyle(.plain)
                .onAppear {
                    if settings.autoLoadMedia && settings.videoAutoplay {
                        initPlayer()
                        loaded = true
                    }
                }
            }
        }
        .aspectRatio(displayAspect, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .fullScreenCover(isPresented: $showFullScreen) {
            FullScreenVideoView(url: meta.url)
        }
    }

    private func initPlayer() {
        guard let url = URL(string: meta.url) else { return }
        let p = AVPlayer(url: url)
        p.isMuted = muteState.isMuted
        player = p
    }
}

/// `AVPlayerLayer` wrapper that exposes `videoGravity` (which `VideoPlayer`
/// does not). Used by `InlineVideoView` so portrait sources can fill the
/// rendered box via `.resizeAspectFill` instead of letterboxing.
struct CroppingVideoPlayer: UIViewRepresentable {
    let player: AVPlayer
    let gravity: AVLayerVideoGravity

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = gravity
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
        uiView.playerLayer.videoGravity = gravity
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

struct FullScreenVideoView: View {
    let url: String
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onAppear {
                        MediaAudioSession.activatePlayback()
                        player.play()
                    }
                    .onDisappear { player.pause() }
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(Color.black.opacity(0.6), in: Circle())
                    }
                    .padding()
                }
                Spacer()
            }
        }
        .task {
            if let videoURL = URL(string: url) {
                player = AVPlayer(url: videoURL)
            }
        }
    }
}
