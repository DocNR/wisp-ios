import Foundation

/// Common abstraction over a Lightning wallet backend.
///
/// Implementations:
/// - `NwcWallet` — talks to a remote wallet service over NIP-47.
/// - `SparkWallet` — embedded self-custodial wallet via the Breez Spark SDK.
///
/// All amounts are millisats unless otherwise noted.
@MainActor
protocol Wallet: AnyObject {
    var balanceMsats: Int64? { get }
    var isConnected: Bool { get }
    var statusLog: AsyncStream<String> { get }
    var paymentReceived: AsyncStream<Int64> { get }
    /// Emits whenever the wallet's balance changes internally (e.g. from a Spark `.synced` event
    /// or an NWC notification). Lets `WalletStore` keep its `@Observable` balance in sync without
    /// having to poll.
    var balanceUpdates: AsyncStream<Int64> { get }

    func hasConnection() -> Bool
    func connect() async
    func disconnect()
    func fetchBalance() async -> Result<Int64, WalletError>
    func payInvoice(_ bolt11: String) async -> Result<String, WalletError>
    func makeInvoice(amountMsats: Int64, description: String) async -> Result<String, WalletError>
    func listTransactions(limit: Int, offset: Int) async -> Result<[WalletTransaction], WalletError>
}

struct WalletTransaction: Identifiable {
    var id: String { paymentHash }
    let type: TransactionType
    let description: String?
    let paymentHash: String
    let amountMsats: Int64
    let feeMsats: Int64
    let createdAt: Int64
    let settledAt: Int64?
    let counterpartyPubkey: String?

    enum TransactionType: String {
        case incoming
        case outgoing
    }
}

enum WalletError: Error, LocalizedError {
    case notConnected
    case decodeFailed(String)
    case rpcError(code: String, message: String)
    case timeout
    case unsupportedEncryption
    case insufficientBalance
    case other(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: "Wallet not connected"
        case .decodeFailed(let m): "Decode failed: \(m)"
        case .rpcError(let code, let m): "\(code): \(m)"
        case .timeout: "Request timed out"
        case .unsupportedEncryption: "Wallet does not support requested encryption"
        case .insufficientBalance: "Insufficient balance"
        case .other(let m): m
        }
    }
}
