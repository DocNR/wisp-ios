import SwiftUI

/// Sheet shown from the post bookmark icon. Lets the user check-toggle which
/// note lists contain the given event, and offers a "Quick create" row to
/// spin up a new list and add the note in one tap.
struct AddToNoteListSheet: View {
    let keypair: Keypair
    let event: NostrEvent

    @Environment(\.dismiss) private var dismiss
    @State private var repo = NoteListRepository.shared
    @State private var showCreate = false
    @State private var newListName = ""
    @State private var isPrivate = false

    private var noteId: String { event.id.lowercased() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Bookmark to lists")
                    .font(.headline)

                privacyToggle

                if repo.lists.isEmpty {
                    emptyState
                } else {
                    listsSection
                }

                createButton

                Spacer(minLength: 24)
            }
            .padding(20)
        }
        .background(Color.wispBackground.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .alert("New note list", isPresented: $showCreate) {
            TextField("List name", text: $newListName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let trimmed = newListName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                if let created = repo.createList(name: trimmed, keypair: keypair) {
                    repo.addNote(noteId, to: created.dTag, isPrivate: isPrivate, keypair: keypair)
                }
            }
        } message: {
            Text("Give your new list a name. The current note will be added automatically.")
        }
    }

    private var privacyToggle: some View {
        HStack(spacing: 8) {
            Image(systemName: isPrivate ? "lock.fill" : "lock.open")
                .foregroundStyle(isPrivate ? Color.wispPrimary : .secondary)
            Text(isPrivate ? "Private (encrypted)" : "Public")
                .font(.subheadline)
                .foregroundStyle(isPrivate ? .primary : .secondary)
            Spacer()
            Toggle("", isOn: $isPrivate)
                .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.wispSurfaceVariant.opacity(0.25),
                    in: RoundedRectangle(cornerRadius: 10))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("You don't have any note lists yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Create one to bookmark this post.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.wispSurfaceVariant.opacity(0.4),
                    in: RoundedRectangle(cornerRadius: 12))
    }

    private var listsSection: some View {
        VStack(spacing: 0) {
            ForEach(repo.lists) { list in
                listRow(list)
                if list.id != repo.lists.last?.id {
                    Divider().overlay(Color.wispSurfaceVariant.opacity(0.4))
                }
            }
        }
        .background(Color.wispSurfaceVariant.opacity(0.25),
                    in: RoundedRectangle(cornerRadius: 12))
    }

    private func listRow(_ list: NoteList) -> some View {
        let alreadyIn = list.publicNotes.contains(noteId) || list.privateNotes.contains(noteId)
        return Button {
            if alreadyIn {
                repo.removeNote(noteId, from: list.dTag, keypair: keypair)
            } else {
                repo.addNote(noteId, to: list.dTag, isPrivate: isPrivate, keypair: keypair)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: alreadyIn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18))
                    .foregroundStyle(alreadyIn ? Color.wispPrimary : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(list.name)
                            .font(.subheadline.weight(.medium))
                        if !list.privateNotes.isEmpty {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("\(list.allNotes.count) note\(list.allNotes.count == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var createButton: some View {
        Button {
            newListName = ""
            showCreate = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.wispPrimary)
                Text("Create new list with this note")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(12)
            .background(Color.wispSurfaceVariant.opacity(0.4),
                        in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
