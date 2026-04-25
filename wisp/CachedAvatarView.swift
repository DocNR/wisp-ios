import SwiftUI

struct CachedAvatarView: View {
    let url: String?
    let size: CGFloat
    /// When true, this avatar always loads regardless of the global auto-download
    /// setting. Use for own-user avatars in the drawer/header.
    var alwaysLoad: Bool = false

    @Environment(AppSettings.self) private var settings
    @State private var uiImage: UIImage?
    @State private var loadFailed = false
    @State private var manualLoad = false

    private var shouldLoad: Bool {
        alwaysLoad || settings.autoLoadMedia || manualLoad
    }

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else if loadFailed || url == nil || url?.isEmpty == true {
                placeholder
            } else if shouldLoad {
                placeholder
                    .task(id: url) { await loadImage() }
            } else {
                placeholder
                    .onTapGesture { manualLoad = true }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var placeholder: some View {
        Circle()
            .fill(Color.wispSurfaceVariant)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(.secondary)
            }
    }

    private func loadImage() async {
        guard let url, !url.isEmpty else {
            loadFailed = true
            return
        }

        if let cached = ImageCache.shared.get(url),
           let img = UIImage(data: cached) {
            uiImage = img
            return
        }

        guard let imageUrl = URL(string: url) else {
            loadFailed = true
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: imageUrl)
            guard let img = UIImage(data: data) else {
                loadFailed = true
                return
            }
            ImageCache.shared.store(data, for: url)
            uiImage = img
        } catch {
            loadFailed = true
        }
    }
}
