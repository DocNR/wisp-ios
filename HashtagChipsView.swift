import SwiftUI

struct HashtagChipsView: View {
    let hashtags: [String]

    var body: some View {
        if hashtags.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(hashtags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Image(systemName: "number")
                                .font(.system(size: 10, weight: .semibold))
                            Text(tag)
                                .font(.caption.weight(.medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.wispSurfaceVariant.opacity(0.6),
                                    in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(Color.wispPrimary)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }
}
