import SwiftUI

struct DiscoverGroupsView: View {
    @Bindable var viewModel: GroupListViewModel
    let onClose: () -> Void

    @State private var groups: [DiscoveredGroup] = []
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                if isLoading {
                    ProgressView().controlSize(.large)
                } else if groups.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 32)).foregroundStyle(.tertiary)
                        Text("No public groups found").foregroundStyle(.secondary)
                    }
                } else {
                    List(groups) { group in
                        HStack(spacing: 12) {
                            CachedAvatarView(url: group.metadata.picture, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.metadata.name ?? group.metadata.groupId)
                                    .font(.subheadline.weight(.semibold))
                                if let about = group.metadata.about {
                                    Text(about).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Text("\(group.memberCount) members · \(group.relayUrl)")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Button("Join") { Task { await join(group) } }
                                .buttonStyle(.bordered)
                        }
                    }
                }
                if let error {
                    VStack {
                        Spacer()
                        Text(error).font(.caption).foregroundStyle(.red)
                            .padding(8).background(Color.wispSurfaceVariant)
                    }
                }
            }
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { onClose() } }
            }
            .task {
                await load()
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        groups = await viewModel.discoverGroups()
    }

    private func join(_ group: DiscoveredGroup) async {
        let res = await viewModel.joinGroup(relayUrl: group.relayUrl, groupId: group.metadata.groupId)
        switch res {
        case .success:
            groups.removeAll { $0.id == group.id }
        case .failure(let e):
            error = "Join failed: \(e)"
        }
    }
}
