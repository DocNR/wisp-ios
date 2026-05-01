import SwiftUI

struct WalletView: View {
    @Bindable var store: WalletStore
    @State private var setupMode: WalletMode? = nil
    @State private var showSend = false
    @State private var showReceive = false

    /// Show the dashboard immediately whenever there's a balance to render — even before
    /// the wallet has finished reconnecting on cold launch. The cached number comes from
    /// `WalletCache` and gets overwritten by the live response within a second or two.
    private var hasCachedDataOrConnected: Bool {
        store.balanceMsats != nil || !store.transactions.isEmpty
    }

    var body: some View {
        Group {
            if store.mode == nil {
                WalletModeSelectionView(onPick: { setupMode = $0 })
            } else if !hasCachedDataOrConnected && !store.isConnected {
                connectingView
            } else {
                walletDashboard
            }
        }
        .background(Color.wispBackground)
        .task { await store.startIfConfigured() }
        .sheet(item: $setupMode) { mode in
            NavigationStack {
                if mode == .nwc {
                    NwcSetupView(store: store, dismiss: { setupMode = nil })
                } else {
                    SparkSetupView(store: store, dismiss: { setupMode = nil })
                }
            }
        }
        .sheet(isPresented: $showSend) {
            NavigationStack {
                SendInvoiceSheet(store: store, dismiss: { showSend = false })
            }
        }
        .sheet(isPresented: $showReceive) {
            NavigationStack {
                ReceiveInvoiceSheet(store: store, dismiss: { showReceive = false })
            }
        }
    }

    private var connectingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(store.lastStatus ?? "Connecting…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Reconnect") {
                Task { await store.startIfConfigured() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var walletDashboard: some View {
        ScrollView {
            VStack(spacing: 28) {
                balanceCard
                actionRow
                if !store.isConnected {
                    reconnectingBanner
                }
                if !store.transactions.isEmpty {
                    transactionsList
                }
                modeFooter
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 16)
        }
        .refreshable {
            _ = await store.fetchBalance()
            await store.refreshTransactions()
        }
        .task { await store.refreshTransactions() }
    }

    private var balanceCard: some View {
        let sats = store.balanceMsats.map { $0 / 1000 } ?? 0
        return VStack(spacing: 4) {
            Text(CurrencyFormatter.formatNumber(sats))
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .contentTransition(.numericText(value: Double(sats)))
                .animation(.easeInOut(duration: 0.25), value: sats)
            Text("sats")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var reconnectingBanner: some View {
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.7)
            Text(store.lastStatus ?? "Reconnecting…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.wispSurfaceVariant.opacity(0.4), in: Capsule())
    }

    private var actionRow: some View {
        HStack(spacing: 32) {
            circularAction(label: "Send", systemImage: "arrow.up", action: { showSend = true })
            circularAction(label: "Receive", systemImage: "arrow.down", action: { showReceive = true })
        }
        .frame(maxWidth: .infinity)
    }

    private func circularAction(label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Color.wispZapColor, in: Circle())
                Text(label)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }

    private var transactionsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Transactions")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
            ForEach(store.transactions.prefix(20)) { tx in
                transactionRow(tx)
                if tx.id != store.transactions.prefix(20).last?.id {
                    Divider().opacity(0.25).padding(.leading, 52)
                }
            }
        }
    }

    @ViewBuilder
    private func transactionRow(_ tx: WalletTransaction) -> some View {
        // For outgoing zaps we recorded the recipient's pubkey at send time; look up their profile.
        let recipientPubkey = tx.counterpartyPubkey ?? ZapSender.recipient(forPaymentHash: tx.paymentHash)
        let profile = recipientPubkey.flatMap { ProfileRepository.shared.get($0) }
        let isIncoming = tx.type == .incoming
        let amountColor: Color = isIncoming ? Color.wispRepostColor : .red.opacity(0.85)
        let sats = abs(tx.amountMsats) / 1000
        let feeSats = tx.feeMsats / 1000

        HStack(alignment: .center, spacing: 12) {
            ZStack {
                if let profile {
                    CachedAvatarView(url: profile.picture, size: 40)
                } else {
                    Circle()
                        .fill((isIncoming ? Color.wispRepostColor : Color.red).opacity(0.18))
                        .frame(width: 40, height: 40)
                    Image(systemName: isIncoming ? "arrow.down" : "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(amountColor)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(profile?.displayString ?? (tx.description?.isEmpty == false ? tx.description! : (isIncoming ? "Received" : "Sent")))
                    .font(.subheadline.weight(profile != nil ? .semibold : .regular))
                    .lineLimit(1)
                Text(relativeTime(from: Int(tx.settledAt ?? tx.createdAt)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(isIncoming ? "+" : "-")\(CurrencyFormatter.formatNumber(sats))")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(amountColor)
                    Text("sats")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if !isIncoming, feeSats > 0 {
                    Text("Fee: \(CurrencyFormatter.formatNumber(feeSats)) sats")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
    }

    private var modeFooter: some View {
        HStack {
            Text("Mode:").font(.caption2).foregroundStyle(.tertiary)
            Text(store.mode == .nwc ? "Nostr Wallet Connect" : "Breez Spark")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Switch") {
                setupMode = store.mode == .nwc ? .spark : .nwc
            }
            .font(.caption)
        }
        .padding(.top, 12)
    }

}

// MARK: - Mode selection

struct WalletModeSelectionView: View {
    let onPick: (WalletMode) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bolt.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.wispZapColor)
                .padding(.top, 36)
            Text("Connect a wallet").font(.title3.weight(.semibold))
            Text("Wisp supports zaps with an embedded Spark wallet or via Nostr Wallet Connect.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(spacing: 12) {
                modeCard(
                    icon: "key.horizontal.fill",
                    title: "Spark wallet",
                    subtitle: "Self-custody, embedded. Create new or restore from seed/relays.",
                    action: { onPick(.spark) }
                )
                modeCard(
                    icon: "bolt.shield.fill",
                    title: "Nostr Wallet Connect",
                    subtitle: "Paste a connection string from Alby, Mutiny, etc.",
                    action: { onPick(.nwc) }
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func modeCard(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(Color.wispZapColor)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color.wispSurfaceVariant.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Send / receive sheets

struct SendInvoiceSheet: View {
    @Bindable var store: WalletStore
    var dismiss: () -> Void
    @State private var invoice: String = ""
    @State private var status: String?
    @State private var inFlight = false
    @State private var showScanner = false

    var body: some View {
        Form {
            Section("Lightning invoice (bolt11)") {
                TextEditor(text: $invoice)
                    .frame(minHeight: 120)
                    .font(.system(.footnote, design: .monospaced))
                HStack(spacing: 12) {
                    Button {
                        showScanner = true
                    } label: {
                        Label("Scan QR", systemImage: "qrcode.viewfinder")
                    }
                    Button("Paste") {
                        if let s = UIPasteboard.general.string { invoice = s }
                    }
                }
            }
            if let decoded = Bolt11.decode(invoice) {
                Section("Decoded") {
                    if let amt = decoded.amountSats { Text("\(amt) sats") }
                    if let desc = decoded.description, !desc.isEmpty { Text(desc).lineLimit(3) }
                }
            }
            if let status { Text(status).font(.caption).foregroundStyle(.secondary) }

            Section {
                Button {
                    Task { await pay() }
                } label: {
                    if inFlight { ProgressView() } else { Text("Pay") }
                }
                .disabled(invoice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || inFlight)
            }
        }
        .navigationTitle("Send")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", action: dismiss) } }
        .fullScreenCover(isPresented: $showScanner) {
            QRCodeScannerView(
                onScanned: { code in
                    invoice = normalizeInvoice(code)
                    showScanner = false
                },
                onCancel: { showScanner = false }
            )
            .ignoresSafeArea()
        }
    }

    private func pay() async {
        inFlight = true
        defer { inFlight = false }
        let trimmed = normalizeInvoice(invoice)
        switch await store.payInvoice(trimmed) {
        case .success: status = "Paid"; dismiss()
        case .failure(let err): status = err.localizedDescription
        }
    }

    /// Strip `lightning:` prefix and uppercase noise that some QR encoders use.
    private func normalizeInvoice(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = s.range(of: "lightning:", options: .caseInsensitive) {
            s = String(s[range.upperBound...])
        }
        return s
    }
}

struct ReceiveInvoiceSheet: View {
    @Bindable var store: WalletStore
    var dismiss: () -> Void
    @State private var amount: String = ""
    @State private var description: String = ""
    @State private var invoice: String?
    @State private var status: String?
    @State private var inFlight = false

    var body: some View {
        Form {
            if let inv = invoice {
                Section {
                    VStack(spacing: 12) {
                        QRCodeImage(payload: inv.uppercased(), sideLength: 240)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                        // bech32 (bolt11) is lowercase but QR uses alphanumeric mode when uppercase,
                        // which produces a denser code that scans more reliably from across the room.
                        Text("Show this QR to the sender")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Invoice") {
                    Text(inv)
                        .font(.system(.footnote, design: .monospaced))
                        .lineLimit(4)
                        .textSelection(.enabled)
                    HStack {
                        Button {
                            UIPasteboard.general.string = inv
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        Spacer()
                        ShareLink(item: inv) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                Section {
                    Button("New invoice") {
                        invoice = nil
                        amount = ""
                        description = ""
                    }
                }
            } else {
                Section("Amount (sats)") {
                    TextField("21", text: $amount).keyboardType(.numberPad)
                }
                Section("Description (optional)") {
                    TextField("For coffee", text: $description)
                }
                Section {
                    Button {
                        Task { await create() }
                    } label: {
                        if inFlight { ProgressView() } else { Text("Create invoice") }
                    }
                    .disabled(Int64(amount) == nil || inFlight)
                }
            }
            if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
        }
        .navigationTitle("Receive")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", action: dismiss) } }
    }

    private func create() async {
        guard let sats = Int64(amount) else { return }
        inFlight = true
        defer { inFlight = false }
        switch await store.makeInvoice(amountSats: sats, description: description) {
        case .success(let inv): invoice = inv
        case .failure(let err): status = err.localizedDescription
        }
    }
}
