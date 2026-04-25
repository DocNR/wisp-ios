import SwiftUI
import UIKit

struct LightningInvoiceView: View {
    let invoice: String
    let amountSats: Int64?
    let summary: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(Color.wispZapColor)
                Text("Lightning Invoice")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let amountSats {
                    Text(CurrencyFormatter.full(sats: amountSats))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.wispZapColor)
                }
            }

            if let summary, !summary.isEmpty {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(4)
            }

            HStack(spacing: 8) {
                Button {
                    UIPasteboard.general.string = invoice
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.wispSurfaceVariant, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    if let u = URL(string: "lightning:\(invoice)") {
                        UIApplication.shared.open(u)
                    }
                } label: {
                    Label("Open in Wallet", systemImage: "bolt.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.wispZapColor.opacity(0.2), in: Capsule())
                        .foregroundStyle(Color.wispZapColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.wispSurfaceVariant.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.wispZapColor.opacity(0.4), lineWidth: 1)
        )
    }

    private func formatSats(_ n: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
