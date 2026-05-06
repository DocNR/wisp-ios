import SwiftUI

/// Persistent mini audio player anchored above MainView's bottom tab bar.
/// Reads from the global `AudioPlayerStore`; renders nothing when no track is
/// loaded. Collapsed row is always visible while a track exists; tapping the
/// row or dragging up reveals the scrubber + speed + close controls.
struct MiniAudioPlayerView: View {
    @Environment(AudioPlayerStore.self) private var store
    @State private var expanded: Bool = false
    @State private var scrubbing: Bool = false
    @State private var scrubMs: Double = 0

    static let collapsedHeight: CGFloat = 56

    var body: some View {
        if let track = store.currentTrack {
            VStack(spacing: 0) {
                dragHandle
                collapsedRow(track: track)
                if expanded {
                    expandedControls
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(Color.wispSurface)
            .clipShape(.rect(topLeadingRadius: 16, topTrailingRadius: 16))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.wispSurfaceVariant.opacity(0.5))
                    .frame(height: 0.5)
            }
            .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: -2)
            .gesture(dragToToggle)
            .animation(.smooth(duration: 0.22), value: expanded)
        }
    }

    // MARK: - Subviews

    private var dragHandle: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.wispOnSurfaceVariant.opacity(0.4))
            .frame(width: 36, height: 4)
            .padding(.top, 6)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity)
    }

    private func collapsedRow(track: AudioTrack) -> some View {
        HStack(spacing: 10) {
            CachedAvatarView(url: track.artworkUrl, size: 40)

            Text(track.displayTitle)
                .font(.subheadline)
                .foregroundStyle(Color.wispOnSurface)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                store.skipBackward()
            } label: {
                Image(systemName: "gobackward.15")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.wispOnSurface)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                store.togglePlayPause()
            } label: {
                Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.wispOnSurface)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                store.skipForward()
            } label: {
                Image(systemName: "goforward.15")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.wispOnSurface)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { expanded.toggle() }
    }

    private var expandedControls: some View {
        let duration = max(0, Double(store.durationMs))
        let position = scrubbing ? scrubMs : Double(store.positionMs)
        let upper = max(1, duration)

        return VStack(spacing: 4) {
            HStack(spacing: 8) {
                Text(formatTime(ms: Int64(position)))
                    .font(.caption2)
                    .foregroundStyle(Color.wispOnSurfaceVariant)
                    .frame(width: 44, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { min(max(position, 0), upper) },
                        set: { newValue in
                            scrubbing = true
                            scrubMs = newValue
                        }
                    ),
                    in: 0...upper,
                    onEditingChanged: { editing in
                        if !editing {
                            store.seek(toMs: Int64(scrubMs))
                            scrubbing = false
                        }
                    }
                )
                .tint(Color.wispPrimary)
                .disabled(duration <= 0)

                Text(formatTime(ms: Int64(duration)))
                    .font(.caption2)
                    .foregroundStyle(Color.wispOnSurfaceVariant)
                    .frame(width: 44, alignment: .trailing)
            }

            HStack {
                Button {
                    store.cycleSpeed()
                } label: {
                    Text(formatSpeed(store.speed))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.wispPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Color.wispPrimary.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    store.close()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.wispOnSurfaceVariant)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    // MARK: - Gesture

    private var dragToToggle: some Gesture {
        DragGesture(minimumDistance: 4)
            .onEnded { value in
                if value.translation.height < -4, !expanded {
                    expanded = true
                } else if value.translation.height > 4, expanded {
                    expanded = false
                }
            }
    }

    // MARK: - Formatting

    private func formatTime(ms: Int64) -> String {
        if ms <= 0 { return "0:00" }
        let s = Int(ms / 1000)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func formatSpeed(_ s: Float) -> String {
        var t = String(format: "%.2f", s)
        while t.hasSuffix("0") { t.removeLast() }
        if t.hasSuffix(".") { t.removeLast() }
        return "\(t)x"
    }
}
