import SwiftUI

enum MessagesTab: String, CaseIterable, Identifiable {
    case dms
    case rooms
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dms: "Direct Messages"
        case .rooms: "Chat Rooms"
        }
    }
}

struct MessagesView: View {
    @Bindable var viewModel: MessagesViewModel
    @Bindable var groupListVM: GroupListViewModel
    @State private var tab: MessagesTab = .dms
    @State private var navPath = NavigationPath()
    @State private var showingNewDm = false

    var body: some View {
        NavigationStack(path: $navPath) {
            VStack(spacing: 0) {
                tabBar

                Divider().overlay(Color.wispSurfaceVariant.opacity(0.5))

                ZStack {
                    switch tab {
                    case .dms:
                        DmListView(
                            viewModel: viewModel,
                            onTap: { conv in navPath.append(conv) },
                            onCompose: { showingNewDm = true }
                        )
                    case .rooms:
                        GroupListView(viewModel: groupListVM,
                                      onTap: { room in navPath.append(room) })
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.wispBackground)
            .navigationDestination(for: DmConversation.self) { conv in
                DmConversationView(keypair: viewModel.keypair, participants: conv.participants)
            }
            .navigationDestination(for: GroupRoom.self) { room in
                GroupRoomView(viewModel: GroupRoomViewModel(
                    keypair: viewModel.keypair, relayUrl: room.relayUrl,
                    groupId: room.groupId, repository: groupListVM.repository))
            }
        }
        .sheet(isPresented: $showingNewDm) {
            NewDmSheet(keypair: viewModel.keypair) { recipientHex in
                showingNewDm = false
                let conv = DmConversation(
                    conversationKey: DmRepository.conversationKey(participants: [recipientHex, viewModel.keypair.pubkey]),
                    participants: [recipientHex],
                    messages: [],
                    lastMessageAt: 0
                )
                navPath.append(conv)
            }
        }
        .onAppear {
            viewModel.refreshSnapshot()
            viewModel.markAllRead()
            // Idempotent — start() guards on `subscription == nil`, so this only does work
            // after MainView.onDisappear has torn the subscription down.
            Task { await viewModel.start() }
        }
    }

    @ViewBuilder
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(MessagesTab.allCases) { t in
                Button {
                    tab = t
                } label: {
                    VStack(spacing: 4) {
                        Text(t.title)
                            .font(.subheadline.weight(t == tab ? .semibold : .regular))
                            .foregroundStyle(t == tab ? Color.wispPrimary : .secondary)
                        Rectangle()
                            .fill(t == tab ? Color.wispPrimary : Color.clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
    }
}

struct ChatRoomsPlaceholderView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3.sequence")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("Chat rooms coming soon")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("NIP-29 group chats will land in a future update.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension DmConversation: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(conversationKey)
    }
}
