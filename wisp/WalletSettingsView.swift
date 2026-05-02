import SwiftUI

struct WalletSettingsView: View {
    @Bindable var store: WalletStore
    @Environment(\.dismiss) private var dismiss

    @State private var showDisconnectAlert = false
    @State private var showDeleteAlert = false
    @AppStorage private var balanceHidden: Bool

    init(store: WalletStore) {
        self.store = store
        _balanceHidden = AppStorage(wrappedValue: false, "balanceHidden_\(store.keypair.pubkey)")
    }

    var body: some View {
        Form {
            displaySection
            if store.mode == .spark {
                securitySection
            }
            dangerSection
        }
        .background(Color.wispBackground.ignoresSafeArea())
        .scrollContentBackground(.hidden)
        .navigationTitle("Wallet Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .alert("Disconnect wallet?", isPresented: $showDisconnectAlert) {
            Button("Disconnect", role: .destructive) {
                store.resetToNoWallet()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your NWC connection will be removed. You can reconnect at any time.")
        }
        .alert("Delete wallet?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                store.resetToNoWallet()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete your Spark wallet from this device. Make sure you have your recovery phrase before proceeding.")
        }
    }

    // MARK: - Display

    private var displaySection: some View {
        Section("Display") {
            Toggle("Hide balance", isOn: $balanceHidden)
        }
    }

    // MARK: - Security (Spark only)

    private var securitySection: some View {
        Section("Security") {
            NavigationLink(value: WalletRoute.recoveryPhrase) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recovery phrase")
                        if !store.seedBackupAcknowledged {
                            Text("Not acknowledged")
                                .font(.caption)
                                .foregroundStyle(Color.wispZapColor)
                        }
                    }
                } icon: {
                    Image(systemName: "key.fill")
                        .foregroundStyle(Color.wispZapColor)
                }
            }

            relayBackupRow
        }
    }

    @ViewBuilder
    private var relayBackupRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text("Relay backup")
            } icon: {
                Image(systemName: "icloud.and.arrow.up")
                    .foregroundStyle(.secondary)
            }
            .font(.body)

            switch store.relayBackupPublishState {
            case .idle:
                Button("Back up seed to relays") {
                    Task { await store.publishRelayBackup() }
                }
                .font(.subheadline)
                .foregroundStyle(Color.wispZapColor)
            case .publishing:
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text("Publishing…").font(.caption).foregroundStyle(.secondary)
                }
            case .success(let relays):
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Backed up to \(relays.count) relay\(relays.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Back up again") {
                    store.resetRelayBackupPublish()
                    Task { await store.publishRelayBackup() }
                }
                .font(.caption)
                .foregroundStyle(Color.wispZapColor)
                .padding(.top, 2)
            case .error(let msg):
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                }
                Button("Retry") {
                    store.resetRelayBackupPublish()
                    Task { await store.publishRelayBackup() }
                }
                .font(.caption)
                .foregroundStyle(Color.wispZapColor)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Danger zone

    private var dangerSection: some View {
        Section {
            if store.mode == .nwc {
                Button(role: .destructive) {
                    showDisconnectAlert = true
                } label: {
                    Label("Disconnect wallet", systemImage: "xmark.circle")
                }
            } else {
                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    Label("Delete wallet", systemImage: "trash")
                }
            }
        } header: {
            Text("Danger Zone")
        } footer: {
            if store.mode == .spark {
                Text("Deleting will remove the wallet from this device. You can restore it with your recovery phrase.")
            } else {
                Text("Disconnecting removes the NWC connection string. Your wallet provider is unaffected.")
            }
        }
    }
}
