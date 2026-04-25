import SwiftUI

/// Bottom-sheet for adding a hashtag to one of the user's hashtag sets.
/// Shows existing sets (tap to add the hashtag) plus a "Create new set" row.
struct HashtagSetPickerSheet: View {
    let hashtag: String
    let keypair: Keypair

    @Environment(\.dismiss) private var dismiss
    @State private var repo = HashtagSetRepository.shared
    @State private var showCreate = false
    @State private var newSetName = ""

    private var normalizedTag: String {
        Nip51Hashtags.normalize(hashtag) ?? hashtag.lowercased()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add #\(normalizedTag) to a set")
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                if repo.hashtagSets.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("You don't have any hashtag sets yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Create your first set to start grouping hashtags.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 20)
                } else {
                    VStack(spacing: 0) {
                        ForEach(repo.hashtagSets) { set in
                            Button {
                                repo.addHashtag(normalizedTag, toSet: set.dTag, keypair: keypair)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "number")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.wispPrimary)
                                        .frame(width: 32, height: 32)
                                        .background(Color.wispSurfaceVariant.opacity(0.5),
                                                    in: RoundedRectangle(cornerRadius: 8))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(set.name)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                        Text("\(set.hashtags.count) hashtag\(set.hashtags.count == 1 ? "" : "s")")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if set.hashtags.contains(normalizedTag) {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(.green)
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(set.hashtags.contains(normalizedTag))
                        }
                    }
                }

                Button {
                    newSetName = ""
                    showCreate = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.wispPrimary)
                            .frame(width: 32, height: 32)
                        Text("Create new set with #\(normalizedTag)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 24)
            }
        }
        .background(Color.wispBackground)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .alert("New hashtag set", isPresented: $showCreate) {
            TextField("Set name", text: $newSetName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let trimmed = newSetName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                _ = repo.createHashtagSet(
                    name: trimmed,
                    initialHashtags: [normalizedTag],
                    keypair: keypair
                )
                dismiss()
            }
        } message: {
            Text("Give your new set a name. #\(normalizedTag) will be added automatically.")
        }
    }
}
