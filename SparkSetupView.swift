import SwiftUI

/// Spark wallet setup: pick from Create / Restore-from-seed / Restore-from-relays.
/// Restore-from-relays runs automatically on appear and shows results inline.
struct SparkSetupView: View {
    @Bindable var store: WalletStore
    var dismiss: () -> Void
    @State private var mode: PickerMode = .pick
    @State private var newMnemonic: String?
    @State private var restoreEntry: String = ""
    @State private var restoreError: String?
    @State private var inFlight = false

    enum PickerMode { case pick, create, restoreSeed, restoreRelays }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color.wispBackground.ignoresSafeArea())
        .navigationTitle("Spark Wallet")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close", action: dismiss) }
            if mode != .pick {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { mode = .pick; restoreEntry = ""; newMnemonic = nil; store.resetRelayBackupSearch() } label: {
                        Image(systemName: "chevron.left")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .pick:           pickSection
        case .create:         createSection
        case .restoreSeed:    restoreFromSeedSection
        case .restoreRelays:  restoreFromRelaysSection
        }
    }

    private var pickSection: some View {
        VStack(spacing: 0) {
            Button { startCreate() } label: {
                row(icon: "plus.circle.fill", title: "Create new wallet", subtitle: "Generate a fresh 12-word seed")
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 56)
            Button { mode = .restoreSeed } label: {
                row(icon: "arrow.uturn.backward.circle.fill", title: "Restore from seed phrase", subtitle: "12 / 15 / 18 / 21 / 24 words")
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 56)
            Button { mode = .restoreRelays; Task { await store.searchRelayBackup() } } label: {
                row(icon: "icloud.and.arrow.down.fill", title: "Restore from relays", subtitle: "Encrypted backup published from another device")
            }
            .buttonStyle(.plain)
        }
        .background(Color.wispSurfaceVariant.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
    }

    private func row(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(Color.wispZapColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    // MARK: - Create

    private func startCreate() {
        do {
            newMnemonic = try Bip39.newMnemonic()
            mode = .create
        } catch {
            restoreError = "Failed to generate mnemonic: \(error.localizedDescription)"
        }
    }

    private var createSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your recovery phrase").font(.subheadline.weight(.semibold))
            Text("Write these 12 words down somewhere safe. Anyone with this phrase controls your funds.")
                .font(.caption).foregroundStyle(.secondary)
            if let mnemonic = newMnemonic {
                Text(mnemonic)
                    .font(.system(.subheadline, design: .monospaced))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.wispSurfaceVariant.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                    .textSelection(.enabled)
            }
            Button {
                guard let mnemonic = newMnemonic else { return }
                Task { await connect(with: mnemonic) }
            } label: {
                Group {
                    if inFlight { ProgressView() } else { Text("I've backed this up — continue") }
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(.white)
                .background(Color.wispZapColor, in: RoundedRectangle(cornerRadius: 10))
            }
            .disabled(inFlight || newMnemonic == nil)
            .buttonStyle(.plain)
            if let restoreError {
                Text(restoreError).font(.caption).foregroundStyle(.red)
            }
        }
    }

    // MARK: - Restore from seed

    private var restoreFromSeedSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recovery phrase").font(.subheadline.weight(.semibold))
            TextEditor(text: $restoreEntry)
                .frame(minHeight: 110)
                .font(.system(.subheadline, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(8)
                .background(Color.wispSurfaceVariant.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            if let restoreError {
                Text(restoreError).font(.caption).foregroundStyle(.red)
            }
            Button {
                let trimmed = restoreEntry.trimmingCharacters(in: .whitespacesAndNewlines)
                if let err = Bip39.validate(trimmed) {
                    restoreError = err
                    return
                }
                restoreError = nil
                Task { await connect(with: trimmed) }
            } label: {
                Group {
                    if inFlight { ProgressView() } else { Text("Restore wallet") }
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(.white)
                .background(Color.wispZapColor, in: RoundedRectangle(cornerRadius: 10))
            }
            .disabled(restoreEntry.isEmpty || inFlight)
            .buttonStyle(.plain)
        }
    }

    // MARK: - Restore from relays

    private var restoreFromRelaysSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Encrypted relay backup").font(.subheadline.weight(.semibold))
            relayBackupBody
            if let restoreError {
                Text(restoreError).font(.caption).foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var relayBackupBody: some View {
        switch store.relayBackupSearchState {
        case .idle:
            Button("Search relays") { Task { await store.searchRelayBackup() } }
        case .searching:
            HStack { ProgressView(); Text("Searching relays…") }
        case .notFound:
            VStack(alignment: .leading, spacing: 8) {
                Text("No backup found on your relays.").font(.subheadline)
                Button("Search again") { Task { await store.searchRelayBackup() } }
            }
        case .found(let entry):
            foundCard(entry: entry)
        case .multiple(let entries):
            ForEach(entries) { entry in
                Button { store.selectBackupToRestore(entry) } label: {
                    foundCard(entry: entry)
                }
                .buttonStyle(.plain)
            }
        case .error(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text("Search failed: \(message)").font(.subheadline).foregroundStyle(.red)
                Button("Retry") { Task { await store.searchRelayBackup() } }
            }
        }
    }

    @ViewBuilder
    private func foundCard(entry: BackupEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.wispRepostColor)
                Text("Backup found").font(.subheadline.weight(.semibold))
                Spacer()
                if let id = entry.walletId { Text(id).font(.caption2.monospaced()).foregroundStyle(.tertiary) }
            }
            Text("Created \(relativeTime(from: entry.createdAt))")
                .font(.caption).foregroundStyle(.secondary)
            Button {
                Task { await connect(with: entry.mnemonic) }
            } label: {
                if inFlight { ProgressView() } else { Text("Restore this wallet") }
            }
            .buttonStyle(.borderedProminent)
            .disabled(inFlight)
        }
        .padding(14)
        .background(Color.wispSurfaceVariant.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Connect

    private func connect(with mnemonic: String) async {
        inFlight = true
        defer { inFlight = false }
        let ok = await store.connectSpark(mnemonic: mnemonic)
        if ok {
            dismiss()
        } else {
            restoreError = store.lastStatus ?? "Failed to initialize wallet"
        }
    }
}
