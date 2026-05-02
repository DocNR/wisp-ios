import SwiftUI

// MARK: - Navigation routes

enum WalletRoute: Hashable {
    case settings
    case transactions
    case recoveryPhrase
}

// MARK: - Main wallet view

struct WalletView: View {
    @Bindable var store: WalletStore
    @State private var setupMode: WalletMode? = nil
    @State private var showSend = false
    @State private var showReceive = false
    @AppStorage private var balanceHidden: Bool

    /// Show the dashboard immediately whenever there's a balance to render — even before
    /// the wallet has finished reconnecting on cold launch. The cached number comes from
    /// `WalletCache` and gets overwritten by the live response within a second or two.
    private var hasCachedDataOrConnected: Bool {
        store.balanceMsats != nil || !store.transactions.isEmpty
    }

    init(store: WalletStore) {
        self.store = store
        _balanceHidden = AppStorage(wrappedValue: false, "balanceHidden_\(store.keypair.pubkey)")
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
        .navigationDestination(for: WalletRoute.self) { route in
            switch route {
            case .settings:
                WalletSettingsView(store: store)
            case .transactions:
                TransactionHistoryView(store: store)
            case .recoveryPhrase:
                RecoveryPhraseView(store: store)
            }
        }
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

    // MARK: - Connecting

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

    // MARK: - Dashboard

    private var walletDashboard: some View {
        ScrollView {
            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                VStack(spacing: 24) {
                    seedBackupBanner

                    balanceCard
                        .padding(.top, 8)

                    actionRow

                    if !store.isConnected {
                        reconnectingBanner
                    }

                    recentTransactionsSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .refreshable {
            _ = await store.fetchBalance()
            await store.refreshTransactions()
        }
        .task { await store.refreshTransactions() }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(alignment: .center) {
            walletLogo
            Spacer()
            NavigationLink(value: WalletRoute.settings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .contentShape(Rectangle())
            }
        }
    }

    @ViewBuilder
    private var walletLogo: some View {
        if store.mode == .spark {
            if UIImage(named: "SparkBreezLogo") != nil {
                Image("SparkBreezLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 22)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.wispZapColor)
                    Text("Spark / Breez")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
            }
        } else {
            if UIImage(named: "NwcLogo") != nil {
                Image("NwcLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 22)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.shield.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.wispZapColor)
                    Text("Nostr Wallet Connect")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    // MARK: - Seed backup banner

    @ViewBuilder
    private var seedBackupBanner: some View {
        if store.mode == .spark && !store.seedBackupAcknowledged {
            NavigationLink(value: WalletRoute.recoveryPhrase) {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.wispZapColor)
                        .font(.system(size: 18))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Back up your recovery phrase")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("Tap to view and acknowledge your seed phrase")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.wispZapColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Balance

    private var balanceCard: some View {
        let sats = store.balanceMsats.map { $0 / 1000 } ?? 0
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { balanceHidden.toggle() }
        } label: {
            VStack(spacing: 4) {
                if balanceHidden {
                    Text("* * * * *")
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                } else {
                    Text(CurrencyFormatter.formatNumber(sats))
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText(value: Double(sats)))
                        .animation(.easeInOut(duration: 0.25), value: sats)
                }
                HStack(spacing: 4) {
                    Text("sats")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Image(systemName: balanceHidden ? "eye.slash" : "eye")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Reconnecting banner

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

    // MARK: - Action row

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

    // MARK: - Recent transactions

    @ViewBuilder
    private var recentTransactionsSection: some View {
        if !store.transactions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Recent")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    NavigationLink(value: WalletRoute.transactions) {
                        Text("All transactions")
                            .font(.subheadline)
                            .foregroundStyle(Color.wispZapColor)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 8)

                let recent = Array(store.transactions.prefix(5))
                ForEach(recent) { tx in
                    WalletTransactionRow(tx: tx)
                    if tx.id != recent.last?.id {
                        Divider().opacity(0.25).padding(.leading, 52)
                    }
                }
            }
            .padding(.top, 8)
        }
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
