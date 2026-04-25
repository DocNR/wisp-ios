import SwiftUI

struct InlineImageView: View {
    let meta: MediaMeta
    @Environment(AppSettings.self) private var settings
    @State private var showFullScreen = false
    @State private var manualLoad = false

    var body: some View {
        let aspect = ContentParser.parseAspectRatio(meta.dimension)
        let height = aspect.map { width(for: $0) } ?? 200

        Group {
            if settings.autoLoadMedia || manualLoad {
                AsyncImage(url: URL(string: meta.url)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .onTapGesture { showFullScreen = true }
                    case .failure:
                        placeholder(systemName: "photo", height: 200)
                    default:
                        placeholder(systemName: nil, height: height)
                            .overlay { ProgressView() }
                    }
                }
            } else {
                Button {
                    manualLoad = true
                } label: {
                    placeholder(systemName: "photo", height: height)
                        .overlay {
                            VStack(spacing: 6) {
                                Image(systemName: "arrow.down.circle")
                                    .font(.title2)
                                Text("Tap to load image")
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .fullScreenCover(isPresented: $showFullScreen) {
            FullScreenImageView(url: meta.url)
        }
    }

    private func placeholder(systemName: String?, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.wispSurfaceVariant)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay {
                if let systemName {
                    Image(systemName: systemName)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
    }

    private func width(for aspect: CGFloat) -> CGFloat {
        if aspect >= 1 { return 220 }
        return 320
    }
}

struct FullScreenImageView: View {
    let url: String
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            AsyncImage(url: URL(string: url)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = lastScale * value
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation { scale = scale > 1 ? 1 : 2; lastScale = scale }
                        }
                default:
                    ProgressView().tint(.white)
                }
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
    }
}
