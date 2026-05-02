import SwiftUI

struct TransactionHistoryView: View {
    @Bindable var store: WalletStore

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
        }
        .listStyle(.plain)
        .refreshable {
            await store.refreshTransactions()
        }
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
