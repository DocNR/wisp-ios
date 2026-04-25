import SwiftUI

struct RelaySetEditorSheet: View {
    let keypair: Keypair
    let editing: RelaySet?

    @Environment(\.dismiss) private var dismiss
    @State private var repo = RelaySetRepository.shared
    @State private var name: String = ""
    @State private var newRelay: String = ""
    @State private var newRelayError: String?
    @State private var workingRelays: [String] = []
    @State private var existingDTag: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Crypto", text: $name)
                        .textInputAutocapitalization(.words)
                }

                Section("Relays") {
                    ForEach(workingRelays, id: \.self) { url in
                        Text(URL(string: url)?.host ?? url)
                    }
                    .onDelete { offsets in
                        workingRelays.remove(atOffsets: offsets)
                    }
                    HStack {
                        TextField("wss://relay.example.com", text: $newRelay)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .keyboardType(.URL)
                        Button("Add") { addRelay() }
                            .disabled(newRelay.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if let newRelayError {
                        Text(newRelayError).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(existingDTag == nil ? "New relay set" : "Edit relay set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if let editing {
                    name = editing.name
                    workingRelays = editing.relays
                    existingDTag = editing.dTag
                }
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !workingRelays.isEmpty
    }

    private func addRelay() {
        var candidate = newRelay.trimmingCharacters(in: .whitespaces)
        if !candidate.contains("://") { candidate = "wss://\(candidate)" }
        guard let normalized = Nip51Lists.normalize(candidate) else {
            newRelayError = "Enter a valid wss:// or ws:// URL."
            return
        }
        newRelayError = nil
        if !workingRelays.contains(normalized) {
            workingRelays.append(normalized)
        }
        newRelay = ""
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let dTag = existingDTag {
            // Diff against existing set
            let existing = repo.relaySet(dTag: dTag)?.relays ?? []
            for url in existing where !workingRelays.contains(url) {
                repo.removeRelay(url, fromSet: dTag, keypair: keypair)
            }
            for url in workingRelays where !existing.contains(url) {
                repo.addRelay(url, toSet: dTag, keypair: keypair)
            }
            if let current = repo.relaySet(dTag: dTag), current.name != trimmed {
                repo.renameRelaySet(dTag: dTag, newName: trimmed, keypair: keypair)
            }
        } else {
            _ = repo.createRelaySet(name: trimmed, relays: workingRelays, keypair: keypair)
        }
        dismiss()
    }
}
