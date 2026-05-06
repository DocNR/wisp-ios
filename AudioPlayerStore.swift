import AVFoundation
import MediaPlayer
import Observation
import UIKit

/// Singleton owning the app's single background audio playback. Inline audio
/// rows in notes call `play(_:)`; the floating mini-player above the tab bar
/// observes published state. Lock-screen / Control Center / AirPods controls
/// are wired through MPNowPlayingInfoCenter + MPRemoteCommandCenter; iOS keeps
/// playback alive in the background because the target enables UIBackgroundModes
/// = audio and `MediaAudioSession.activatePlayback()` configures `.playback`.
@Observable
@MainActor
final class AudioPlayerStore {
    static let shared = AudioPlayerStore()

    private(set) var currentTrack: AudioTrack?
    private(set) var isPlaying: Bool = false
    private(set) var positionMs: Int64 = 0
    private(set) var durationMs: Int64 = 0
    private(set) var bufferedMs: Int64 = 0
    private(set) var speed: Float = 1.0
    private(set) var isBuffering: Bool = false

    static let speedSteps: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0]
    static let skipDeltaSeconds: Double = 15.0

    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var statusObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?
    private var durationObserver: NSKeyValueObservation?
    private var loadedRangesObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var artworkLoadTask: Task<Void, Never>?
    private var remoteCommandsWired = false

    private init() {}

    func isCurrent(url: String) -> Bool { currentTrack?.url == url }

    // MARK: - Transport

    func play(_ track: AudioTrack) {
        if let cur = currentTrack, cur.url == track.url, let p = player {
            MediaAudioSession.activatePlayback()
            p.play()
            // Rate must be re-applied on play() because AVPlayer can reset
            // when stalled / route-changed.
            if speed > 0 { p.rate = speed }
            return
        }

        teardownObservers()
        player?.pause()

        guard let url = URL(string: track.url) else { return }

        MediaAudioSession.activatePlayback()

        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        p.automaticallyWaitsToMinimizeStalling = true
        player = p
        currentTrack = track

        // New-track speed reset matches Android (ExoPlayer is rebuilt per URL).
        speed = 1.0
        isPlaying = false
        positionMs = 0
        durationMs = 0
        bufferedMs = 0
        isBuffering = true

        attachObservers(player: p, item: item)
        configureRemoteCommandsIfNeeded()
        updateNowPlayingInfo()
        loadArtworkAsync(for: track)

        p.play()
    }

    func togglePlayPause() {
        guard let p = player else { return }
        if p.timeControlStatus == .playing {
            p.pause()
        } else {
            MediaAudioSession.activatePlayback()
            p.play()
            if speed > 0 { p.rate = speed }
        }
    }

    func seek(toMs ms: Int64) {
        guard let p = player else { return }
        let clamped = max(0, ms)
        let target = CMTime(
            seconds: Double(clamped) / 1000.0,
            preferredTimescale: CMTimeScale(NSEC_PER_SEC)
        )
        p.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tickFromPlayer() }
        }
    }

    func skipForward() {
        guard player != nil else { return }
        let cap = durationMs > 0 ? durationMs : .max
        let next = min(cap, positionMs + Int64(Self.skipDeltaSeconds * 1000))
        seek(toMs: next)
    }

    func skipBackward() {
        guard player != nil else { return }
        let next = max(0, positionMs - Int64(Self.skipDeltaSeconds * 1000))
        seek(toMs: next)
    }

    func cycleSpeed() {
        guard let p = player else { return }
        let cur = speed
        let idx = Self.speedSteps.firstIndex(where: { abs($0 - cur) < 0.01 }) ?? 1
        let next = Self.speedSteps[(idx + 1) % Self.speedSteps.count]
        speed = next
        if p.timeControlStatus == .playing {
            p.rate = next
        } else {
            // `defaultRate` doesn't apply on next play() — store it on `speed`
            // and re-apply inside togglePlayPause / play.
        }
        updateNowPlayingInfo()
    }

    func close() {
        artworkLoadTask?.cancel()
        artworkLoadTask = nil
        teardownObservers()
        player?.pause()
        player = nil
        currentTrack = nil
        isPlaying = false
        positionMs = 0
        durationMs = 0
        bufferedMs = 0
        isBuffering = false
        speed = 1.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Observation

    private func attachObservers(player p: AVPlayer, item: AVPlayerItem) {
        let interval = CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tickFromPlayer() }
        }
        statusObserver = item.observe(\.status, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.tickFromPlayer() }
        }
        rateObserver = p.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.tickFromPlayer() }
        }
        durationObserver = item.observe(\.duration, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.tickFromPlayer() }
        }
        loadedRangesObserver = item.observe(\.loadedTimeRanges, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.tickFromPlayer() }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.player?.pause()
                self.player?.seek(to: .zero)
                self.tickFromPlayer()
            }
        }
    }

    private func teardownObservers() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
        }
        timeObserverToken = nil
        statusObserver?.invalidate(); statusObserver = nil
        rateObserver?.invalidate(); rateObserver = nil
        durationObserver?.invalidate(); durationObserver = nil
        loadedRangesObserver?.invalidate(); loadedRangesObserver = nil
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        endObserver = nil
    }

    private func tickFromPlayer() {
        guard let p = player, let item = p.currentItem else { return }
        isPlaying = (p.timeControlStatus == .playing)
        positionMs = max(0, Int64(CMTimeGetSeconds(p.currentTime()) * 1000))
        let d = CMTimeGetSeconds(item.duration)
        durationMs = (d.isFinite && d > 0) ? Int64(d * 1000) : 0
        if let last = item.loadedTimeRanges.last?.timeRangeValue {
            let end = CMTimeGetSeconds(last.start + last.duration)
            bufferedMs = end.isFinite ? Int64(end * 1000) : 0
        }
        // Keep `speed` as the user's selection; only mirror real rate when playing.
        if p.timeControlStatus == .playing, p.rate > 0 {
            speed = p.rate
        }
        isBuffering = (p.timeControlStatus == .waitingToPlayAtSpecifiedRate)
            || item.status == .unknown
        updateNowPlayingElapsed()
    }

    // MARK: - Now Playing + Remote Commands

    private func configureRemoteCommandsIfNeeded() {
        guard !remoteCommandsWired else { return }
        remoteCommandsWired = true

        let cc = MPRemoteCommandCenter.shared()

        cc.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in
                if !self.isPlaying { self.togglePlayPause() }
            }
            return .success
        }
        cc.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in
                if self.isPlaying { self.togglePlayPause() }
            }
            return .success
        }
        cc.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.togglePlayPause() }
            return .success
        }

        cc.skipForwardCommand.preferredIntervals = [NSNumber(value: Self.skipDeltaSeconds)]
        cc.skipForwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.skipForward() }
            return .success
        }
        cc.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.skipDeltaSeconds)]
        cc.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.skipBackward() }
            return .success
        }

        cc.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self,
                  let e = event as? MPChangePlaybackPositionCommandEvent
            else { return .commandFailed }
            Task { @MainActor in self.seek(toMs: Int64(e.positionTime * 1000)) }
            return .success
        }

        cc.nextTrackCommand.isEnabled = false
        cc.previousTrackCommand.isEnabled = false
    }

    private func updateNowPlayingInfo() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = track.displayTitle
        if let artist = track.artist { info[MPMediaItemPropertyArtist] = artist }
        info[MPMediaItemPropertyPlaybackDuration] = Double(durationMs) / 1000.0
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(positionMs) / 1000.0
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(speed) : 0.0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = Double(speed)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingElapsed() {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(positionMs) / 1000.0
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(speed) : 0.0
        if durationMs > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = Double(durationMs) / 1000.0
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtworkAsync(for track: AudioTrack) {
        artworkLoadTask?.cancel()
        guard let urlStr = track.artworkUrl,
              let url = URL(string: urlStr) else { return }
        let trackUrl = track.url
        artworkLoadTask = Task { [weak self] in
            guard let data = try? await URLSession.shared.data(from: url).0,
                  let image = UIImage(data: data)
            else { return }
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            await MainActor.run { [weak self] in
                guard let self, self.currentTrack?.url == trackUrl else { return }
                var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                info[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            }
        }
    }
}
