import SwiftUI
import UIKit
import GiphyUISDK

/// SwiftUI wrapper around the official Giphy `GiphyViewController`. Presented
/// as a sheet from the composer; on selection it hands back the original GIF
/// URL, which the composer pastes into the post body. The existing inline
/// image renderer takes care of display once the note is published.
struct GifPickerView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var onSelect: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect, onDismiss: { dismiss() })
    }

    func makeUIViewController(context: Context) -> GiphyViewController {
        GiphyConfig.bootstrap()
        let vc = GiphyViewController()
        vc.mediaTypeConfig = [.gifs, .stickers, .recents]
        vc.theme = GPHTheme(type: colorScheme == .dark ? .dark : .light)
        vc.shouldLocalizeSearch = true
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: GiphyViewController, context: Context) {
        uiViewController.theme = GPHTheme(type: colorScheme == .dark ? .dark : .light)
    }

    final class Coordinator: NSObject, GiphyDelegate {
        let onSelect: (String) -> Void
        let onDismiss: () -> Void

        init(onSelect: @escaping (String) -> Void, onDismiss: @escaping () -> Void) {
            self.onSelect = onSelect
            self.onDismiss = onDismiss
        }

        func didSelectMedia(giphyViewController: GiphyViewController, media: GPHMedia, contentType: GPHContentType) {
            // Prefer the original GIF URL. Fall back to other renditions only
            // if `original` is missing (rare, but defensive).
            let url = media.url(rendition: .original, fileType: .gif)
                ?? media.url(rendition: .fixedHeight, fileType: .gif)
                ?? media.url(rendition: .downsized, fileType: .gif)
            if let url {
                onSelect(url)
            }
            onDismiss()
        }

        func didDismiss(controller: GiphyViewController?) {
            onDismiss()
        }
    }
}
