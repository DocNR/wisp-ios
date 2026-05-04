import SwiftUI

struct TransactionHistoryView: View {
    @Bindable var store: WalletStore
    @State private var isLoadingMore = false

    var body: some View {
        Group {
            if store.transactions.isEmpty {
                emptyState
            } else {
                transactionList
            }
        }
        .background(Color.wispBackground.ignoresSafeArea())
        .navigationTitle("Transactions")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
    }

    private var transactionList: some View {
        List {
            ForEach(store.transactions) { tx in
                WalletTransactionRow(tx: tx)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowBackground(Color.wispBackground)
                    .listRowSeparatorTint(Color.wispSurfaceVariant.opacity(0.4))
            }

            if store.hasMoreTransactions {
                HStack {
                    Spacer()
                    Button {
                        Task { await loadMore() }
                    } label: {
                        Group {
                            if isLoadingMore {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Text("Load more")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Color.wispZapColor)
                            }
                        }
                        .frame(height: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoadingMore)
                    Spacer()
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowBackground(Color.wispBackground)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .refreshable {
            await store.refreshTransactions()
        }
    }

    private func loadMore() async {
        isLoadingMore = true
        defer { isLoadingMore = false }
        await store.loadMoreTransactions()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.slash")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No transactions yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
