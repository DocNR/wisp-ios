import SwiftUI

/// Modal for sending a zap. Presented from the post card's bolt icon button.
struct ZapSheet: View {
    @Bindable var store: WalletStore
    let recipientPubkey: String
    let recipientLud16: String?
    let recipientName: String?
    let eventId: String?
    /// Optional preferred relays for the zap-request `relays` tag (e.g. live stream chat relays).
    var relayHints: [String] = []
    /// Optional extra zap-request tags (e.g. `["a", "30311:host:dTag"]` for stream zaps).
    var extraTags: [[String]] = []
    /// Fires after a successful zap, with the chosen sats amount. Used by zap polls to
    /// apply an optimistic tally update before the receipt round-trips through relays.
    var onSuccess: ((Int64) -> Void)? = nil
    var dismiss: () -> Void

    @State private var amountSats: Int64 = 21
    @State private var customAmountText: String = ""
    @State private var message: String = ""
    @State private var inFlight = false
    @State private var status: String?
    @State private var success = false

    private let presetAmounts: [Int64] = [21, 100, 1_000, 10_000, 100_000]

    var body: some View {
        NavigationStack {
            Form {
                if let lud16 = recipientLud16 {
                    Section("Recipient") {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(recipientName ?? "User").font(.subheadline.weight(.semibold))
                            Text(lud16).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section {
                        Text("Recipient has no lightning address — they cannot receive zaps.")
                            .foregroundStyle(.red)
                    }
                }

                Section("Amount") {
                    presetGrid
                    TextField("Custom (sats)", text: $customAmountText)
                        .keyboardType(.numberPad)
                        .onChange(of: customAmountText) { _, new in
                            if let v = Int64(new), v > 0 { amountSats = v }
                        }
                }

                Section("Note (optional)") {
                    TextField("Optional message", text: $message)
                }

                if let status {
                    Section { Text(status).font(.caption).foregroundStyle(success ? Color.wispRepostColor : .red) }
                }

                Section {
                    Button {
                        Task { await send() }
                    } label: {
                        if inFlight {
                            HStack { ProgressView(); Text("Zapping…") }
                        } else {
                            HStack {
                                Image(systemName: "bolt.fill").foregroundStyle(Color.wispZapColor)
                                Text("Send \(amountSats) sats")
                            }
                        }
                    }
                    .disabled(inFlight || recipientLud16 == nil || store.activeWallet == nil)
                }
            }
            .navigationTitle("Zap")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", action: dismiss) } }
        }
    }

    private var presetGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 80))]
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(presetAmounts, id: \.self) { sats in
                Button {
                    amountSats = sats
                    customAmountText = ""
                } label: {
                    Text(formatSats(sats))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(amountSats == sats ? Color.wispZapColor.opacity(0.25) : Color.wispSurfaceVariant.opacity(0.4),
                                    in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func send() async {
        guard let key = NostrKey.load() else { status = "No active account"; return }
        inFlight = true
        defer { inFlight = false }
        let result = await ZapSender.sendZap(
            keypair: key,
            wallet: store,
            recipientPubkey: recipientPubkey,
            recipientLud16: recipientLud16,
            eventId: eventId,
            amountSats: amountSats,
            message: message,
            relayHints: relayHints,
            extraTags: extraTags
        )
        switch result {
        case .success:
            Haptics.shared.zapBuzz()
            status = "⚡️ Zap sent"
            success = true
            onSuccess?(amountSats)
            try? await Task.sleep(for: .seconds(1))
            dismiss()
        case .failure(let err):
            status = err.localizedDescription
            success = false
        }
    }

    private func formatSats(_ sats: Int64) -> String {
        CurrencyFormatter.short(sats: sats)
    }
}
