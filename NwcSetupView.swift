import SwiftUI

struct NwcSetupView: View {
    @Bindable var store: WalletStore
    var dismiss: () -> Void
    @State private var uri: String = ""
    @State private var status: String?
    @State private var inFlight = false

    var body: some View {
        Form {
            Section("Connection string") {
                TextEditor(text: $uri)
                    .frame(minHeight: 140)
                    .font(.system(.footnote, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("Paste from clipboard") {
                    if let s = UIPasteboard.general.string { uri = s }
                }
            }
            Section {
                Text("Looks like `nostr+walletconnect://<wallet pubkey>?relay=wss://...&secret=<hex>`")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let status {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button {
                    Task { await connect() }
                } label: {
                    if inFlight { ProgressView() } else { Text("Connect") }
                }
                .disabled(uri.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || inFlight)
            }
        }
        .navigationTitle("NWC")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", action: dismiss) } }
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
