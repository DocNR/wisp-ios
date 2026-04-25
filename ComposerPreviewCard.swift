import SwiftUI

struct ComposerPreviewCard: View {
    let content: String
    let tags: [[String]]
    let userProfile: ProfileData?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                CachedAvatarView(url: userProfile?.picture, size: 32)
                Text(userProfile?.displayString ?? "you")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Preview")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.wispSurfaceVariant.opacity(0.7), in: Capsule())
                    .foregroundStyle(.secondary)
            }

            RichContentView(
                content: content,
                tags: tags,
                profiles: [:],
                showLinkPreviews: false
            )
        }
        .padding(12)
        .background(Color.wispSurfaceVariant.opacity(0.4),
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.wispSurfaceVariant, lineWidth: 1)
        )
        .padding(.horizontal, 12)
    }
}
