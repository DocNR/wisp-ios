import SwiftUI

struct RelayPickerSheet: View {
    let keypair: Keypair
    let onSelectRelay: (String) -> Void
    let onSelectRelaySet: (RelaySet) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var repo = RelaySetRepository.shared
    @State private var urlInput: String = ""
    @State private var inputError: String?
    @State private var showSetEditor = false
    @State private var editingSet: RelaySet?
    @State private var expandedSetIds = Set<String>()

    var body: some View {
        NavigationStack {
            List {
                Section("Browse a relay") {
                    HStack {
                        TextField("wss://relay.example.com", text: $urlInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .keyboardType(.URL)
                            .onSubmit { browse() }
                        Button("Browse") { browse() }
                            .disabled(urlInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if let inputError {
                        Text(inputError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Favorites") {
                    if repo.favoriteRelays.isEmpty {
                        Text("Tap the star next to a relay to add it here.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(repo.favoriteRelays, id: \.self) { url in
                            relayRow(url: url)
                        }
                    }
                }

                Section("Relay sets") {
                    if repo.relaySets.isEmpty {
                        Text("Group multiple relays into a single feed.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(repo.relaySets) { set in
                            relaySetRow(set: set)
                        }
                    }
                    Button {
                        editingSet = nil
                        showSetEditor = true
                    } label: {
                        Label("Create relay set", systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle("Relay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showSetEditor) {
                RelaySetEditorSheet(keypair: keypair, editing: editingSet)
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func relayRow(url: String) -> some View {
        HStack(spacing: 12) {
            Button {
                onSelectRelay(url)
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(.secondary)
                    Text(displayName(url))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Button {
                repo.toggleFavorite(url, keypair: keypair)
            } label: {
                Image(systemName: repo.isFavorite(url) ? "star.fill" : "star")
                    .foregroundStyle(repo.isFavorite(url) ? Color.yellow : Color.secondary)
            }
            .buttonStyle(.borderless)
            if !repo.relaySets.isEmpty {
                Menu {
                    ForEach(repo.relaySets) { set in
                        let inSet = set.relays.contains(url)
                        Button {
                            if inSet {
                                repo.removeRelay(url, fromSet: set.dTag, keypair: keypair)
                            } else {
                                repo.addRelay(url, toSet: set.dTag, keypair: keypair)
                            }
                        } label: {
                            Label(set.name, systemImage: inSet ? "checkmark" : "plus")
                        }
                    }
                } label: {
                    Image(systemName: "rectangle.stack.badge.plus")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func relaySetRow(set: RelaySet) -> some View {
        let expanded = expandedSetIds.contains(set.id)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    onSelectRelaySet(set)
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.stack")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(set.name)
                            Text("\(set.relays.count) relay\(set.relays.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Button {
                    editingSet = set
                    showSetEditor = true
                } label: {
                    Image(systemName: "pencil")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                Button {
                    if expanded { expandedSetIds.remove(set.id) }
                    else { expandedSetIds.insert(set.id) }
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            if expanded {
                ForEach(set.relays, id: \.self) { url in
                    HStack {
                        Text(displayName(url))
                            .font(.footnote)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(role: .destructive) {
                            repo.removeRelay(url, fromSet: set.dTag, keypair: keypair)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.leading, 24)
                }
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                repo.deleteRelaySet(dTag: set.dTag, keypair: keypair)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Actions

    private func browse() {
        let raw = urlInput.trimmingCharacters(in: .whitespaces)
        var candidate = raw
        if !candidate.contains("://") { candidate = "wss://\(candidate)" }
        guard let normalized = Nip51Lists.normalize(candidate) else {
            inputError = "Enter a valid wss:// or ws:// URL."
            return
        }
        inputError = nil
        urlInput = ""
        onSelectRelay(normalized)
        dismiss()
    }

    private func displayName(_ url: String) -> String {
        URL(string: url)?.host ?? url
    }
}
