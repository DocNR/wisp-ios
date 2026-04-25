import SwiftUI

struct DrawerRow: View {
    let icon: String
    let label: String
    var indented: Bool = false
    var tint: Color? = nil
    var trailingChevron: ChevronState = .none
    let action: () -> Void

    enum ChevronState {
        case none
        case collapsed
        case expanded
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(tint ?? .secondary)
                    .frame(width: 24, height: 24)

                Text(label)
                    .font(.body)
                    .foregroundStyle(tint ?? Color.primary)

                Spacer()

                switch trailingChevron {
                case .none:
                    EmptyView()
                case .collapsed:
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                case .expanded:
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, indented ? 36 : 12)
            .padding(.trailing, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
