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
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                displaySection
                if store.mode == .spark {
                    securitySection
                }
                dangerSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .background(Color.wispBackground.ignoresSafeArea())
        .navigationTitle("Wallet Settings")
        .navigationBarTitleDisplayMode(.inline)
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
        settingsGroup(header: "Display") {
            HStack {
                Text("Hide balance")
                    .font(.subheadline)
                Spacer()
                Toggle("", isOn: $balanceHidden)
                    .labelsHidden()
                    .tint(Color.wispZapColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    // MARK: - Security (Spark only)

    private var securitySection: some View {
        settingsGroup(header: "Security") {
            // Recovery phrase
            NavigationLink(value: WalletRoute.recoveryPhrase) {
                HStack(spacing: 12) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.wispZapColor)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recovery phrase")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        if !store.seedBackupAcknowledged {
                            Text("Not acknowledged")
                                .font(.footnote)
                                .foregroundStyle(Color.wispZapColor)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            Divider().opacity(0.25).padding(.leading, 50)

            // Relay backup
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "icloud.and.arrow.up")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .frame(width: 22)
                    Text("Relay backup")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Spacer()
                }

                relayBackupContent
                    .padding(.leading, 34)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    @ViewBuilder
    private var relayBackupContent: some View {
        switch store.relayBackupPublishState {
        case .idle:
            Button("Back up seed to relays") {
                Task { await store.publishRelayBackup() }
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color.wispZapColor)

        case .publishing:
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.75)
                Text("Publishing…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .success(let relays):
            VStack(alignment: .leading, spacing: 6) {
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
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.wispZapColor)
            }

        case .error(let msg):
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                }
                Button("Retry") {
                    store.resetRelayBackupPublish()
                    Task { await store.publishRelayBackup() }
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.wispZapColor)
            }
        }
    }

    // MARK: - Danger zone

    private var dangerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Danger Zone")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                if store.mode == .nwc {
                    Button {
                        showDisconnectAlert = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 15))
                                .foregroundStyle(.red)
                                .frame(width: 22)
                            Text("Disconnect wallet")
                                .font(.subheadline)
                                .foregroundStyle(.red)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        showDeleteAlert = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "trash")
                                .font(.system(size: 15))
                                .foregroundStyle(.red)
                                .frame(width: 22)
                            Text("Delete wallet")
                                .font(.subheadline)
                                .foregroundStyle(.red)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color.wispSurfaceVariant.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))

            Text(store.mode == .spark
                 ? "Deleting removes the wallet from this device. You can restore it with your recovery phrase."
                 : "Disconnecting removes the NWC connection string. Your wallet provider is unaffected.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Helper

    private func settingsGroup<Content: View>(header: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(header)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            VStack(spacing: 0) {
                content()
            }
            .background(Color.wispSurfaceVariant.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
        }
    }
}
