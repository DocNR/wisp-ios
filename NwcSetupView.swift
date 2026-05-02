import SwiftUI

struct NwcSetupView: View {
    @Bindable var store: WalletStore
    var dismiss: () -> Void
    @State private var uri: String = ""
    @State private var status: String?
    @State private var inFlight = false
    @State private var showScanner = false

    private var isValidUri: Bool {
        uri.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("nostr+walletconnect://")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                // Logo + header
                VStack(spacing: 14) {
                    Image("NwcLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                    Text("Nostr Wallet Connect")
                        .font(.title2.weight(.semibold))
                    Text("Paste the connection string from your NWC-compatible wallet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 8)

                // Input card
                VStack(alignment: .leading, spacing: 0) {
                    TextEditor(text: $uri)
                        .frame(minHeight: 120)
                        .font(.system(.footnote, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .scrollContentBackground(.hidden)
                        .padding(14)

                    Divider().opacity(0.3)

                    HStack(spacing: 0) {
                        Button {
                            if let s = UIPasteboard.general.string { uri = s }
                        } label: {
                            Label("Paste", systemImage: "doc.on.clipboard")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.wispZapColor)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)

                        Divider().frame(height: 24)

                        Button {
                            showScanner = true
                        } label: {
                            Label("Scan QR", systemImage: "qrcode.viewfinder")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.wispZapColor)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color.wispSurfaceVariant.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))

                // Hint
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 1)
                    Text("Connection string starts with nostr+walletconnect://")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Status
                if let status {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(status)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Connect button
                Button {
                    Task { await connect() }
                } label: {
                    Group {
                        if inFlight {
                            ProgressView().tint(.white)
                        } else {
                            Text("Connect")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        isValidUri ? Color.wispZapColor : Color.wispSurfaceVariant,
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!isValidUri || inFlight)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background(Color.wispBackground.ignoresSafeArea())
        .navigationTitle("Connect Wallet")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Close", action: dismiss) }
        }
        .fullScreenCover(isPresented: $showScanner) {
            QRCodeScannerView(
                onScanned: { code in
                    uri = code.trimmingCharacters(in: .whitespacesAndNewlines)
                    showScanner = false
                },
                onCancel: { showScanner = false }
            )
            .ignoresSafeArea()
        }
    }

    private func connect() async {
        inFlight = true
        defer { inFlight = false }
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        let ok = await store.connectNwc(uri: trimmed)
        if ok {
            dismiss()
        } else {
            status = store.lastStatus ?? "Could not connect — check the connection string"
        }
    }
}
