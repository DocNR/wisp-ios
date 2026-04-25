import SwiftUI

struct NotificationComposer: View {
    let targetEvent: NostrEvent
    let groupId: String
    @Binding var sending: Bool
    let viewModel: NotificationsViewModel

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Reply…", text: $text, axis: .vertical)
                .focused($focused)
                .lineLimit(1...8)
                .padding(10)
                .background(Color.wispSurfaceVariant.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .disabled(sending)

            Button {
                send()
            } label: {
                Image(systemName: sending ? "hourglass" : "paperplane.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(canSend ? Color.wispPrimary : Color.wispSurfaceVariant)
                    .clipShape(Circle())
            }
            .disabled(!canSend)
        }
    }

    private var canSend: Bool {
        !sending && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        let body = text
        sending = true
        Task {
            defer { sending = false }
            do {
                try await viewModel.sendQuickReply(targetEvent: targetEvent, text: body, groupId: groupId)
                await MainActor.run {
                    text = ""
                    focused = false
                }
            } catch {
                // Surfacing send errors is deferred to v2; the optimistic row already shows.
            }
        }
    }
}
