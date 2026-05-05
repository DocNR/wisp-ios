import Foundation

/// NIP-47 wallet over a single relay socket. Mirrors the Android NwcRepository:
/// connect → fetch wallet info (kind 13194) → negotiate encryption → subscribe for
/// kind 23195 responses → fan requests through `sendRequest`, matching responses to
/// in-flight requests by the response event's `e` tag.
@MainActor
final class NwcWallet: Wallet {
    private let pubkey: String

    private(set) var balanceMsats: Int64?
    private(set) var isConnected: Bool = false
    /// Node alias as advertised by the connected wallet service via NIP-47
    /// `get_info`. Lazily populated after `connect()`; nil until the first
    /// successful fetch and reset on disconnect. Cached to UserDefaults so
    /// cold launches surface the last-known alias immediately.
    private(set) var nodeAlias: String?

    let statusLog: AsyncStream<String>
    let paymentReceived: AsyncStream<Int64>
    let balanceUpdates: AsyncStream<Int64>
    private let statusContinuation: AsyncStream<String>.Continuation
    private let paymentContinuation: AsyncStream<Int64>.Continuation
    private let balanceContinuation: AsyncStream<Int64>.Continuation

    private var connection: NwcConnection?
    private var subscription: RelaySubscription?
    private var subscriptionTask: Task<Void, Never>?
    private var pendingRequests: [String: CheckedContinuation<Nip47.Response, Error>] = [:]

    init(pubkey: String) {
        self.pubkey = pubkey
        self.nodeAlias = UserDefaults.standard.string(forKey: Self.aliasCacheKey(pubkey: pubkey))
        var sCont: AsyncStream<String>.Continuation!
        self.statusLog = AsyncStream { c in sCont = c }
        self.statusContinuation = sCont
        var pCont: AsyncStream<Int64>.Continuation!
        self.paymentReceived = AsyncStream { c in pCont = c }
        self.paymentContinuation = pCont
        var bCont: AsyncStream<Int64>.Continuation!
        self.balanceUpdates = AsyncStream { c in bCont = c }
        self.balanceContinuation = bCont
    }

    private static func aliasCacheKey(pubkey: String) -> String { "nwc_node_alias_\(pubkey)" }

    func hasConnection() -> Bool {
        WalletKeychain.loadNwcUri(for: pubkey) != nil
    }

    /// Returns the `lud16` lightning address embedded in the NWC connection string, if present.
    var lud16: String? {
        guard let uri = WalletKeychain.loadNwcUri(for: pubkey) else { return nil }
        return NwcConnection.parse(uri)?.lud16
    }

    func saveConnection(_ uri: String) {
        WalletKeychain.saveNwcUri(uri, for: pubkey)
    }

    func clearConnection() {
        WalletKeychain.deleteNwcUri(for: pubkey)
        UserDefaults.standard.removeObject(forKey: Self.aliasCacheKey(pubkey: pubkey))
        nodeAlias = nil
        disconnect()
    }

    /// Fire a NIP-47 `get_info` request to the connected wallet service and
    /// cache the returned alias. No-op when not connected. Errors and
    /// missing-alias responses are silently ignored — the UI just keeps
    /// showing nothing extra next to the NWC logo.
    func fetchNodeAlias() async {
        guard isConnected else { return }
        let result = await send(.getInfo) { response -> String? in
            guard case .getInfo(let alias, _, _) = response else {
                throw WalletError.decodeFailed("expected get_info response")
            }
            let trimmed = alias?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (trimmed?.isEmpty ?? true) ? nil : trimmed
        }
        if case .success(let alias?) = result {
            nodeAlias = alias
            UserDefaults.standard.set(alias, forKey: Self.aliasCacheKey(pubkey: pubkey))
        }
    }

    func connect() async {
        guard let uri = WalletKeychain.loadNwcUri(for: pubkey) else {
            emit("No NWC connection saved")
            return
        }
        guard var conn = NwcConnection.parse(uri) else {
            emit("Invalid NWC connection string")
            return
        }

        disconnect()
        emit("Negotiating encryption…")

        // Fetch wallet info (kind 13194) for encryption negotiation. Many wallets don't
        // publish one — fall back to NIP-04 in that case (per spec).
        let infoEvents = await RelayPool.query(
            relays: conn.relays,
            filter: NostrFilter(
                kinds: [Nip47.infoKind],
                authors: [Hex.encode(conn.walletServicePubkey)],
                limit: 1
            ),
            timeout: 5
        )
        // Default to NIP-44 when no info event is found — modern wallets expect it.
        let encryption = infoEvents.first.map(Nip47.parseInfoEncryption) ?? .nip44
        conn = conn.with(encryption: encryption)
        emit("Encryption: \(encryption == .nip44 ? "NIP-44" : "NIP-04")")
        connection = conn

        // Open a persistent subscription for our responses.
        let filter = NostrFilter(
            kinds: [Nip47.responseKind],
            pTags: [Hex.encode(conn.clientPubkey)]
        )
        let sub = RelayPool.subscribe(relays: conn.relays, filter: filter, id: "nwc-\(UUID().uuidString.prefix(6))")
        subscription = sub
        subscriptionTask = Task { [weak self] in
            for await (event, _) in sub.events {
                await self?.handleResponse(event: event)
            }
        }

        isConnected = true
        emit("Connected")
    }

    func disconnect() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
        subscription?.cancel()
        subscription = nil
        connection = nil
        isConnected = false
        for (_, cont) in pendingRequests { cont.resume(throwing: WalletError.notConnected) }
        pendingRequests.removeAll()
    }

    // MARK: - RPC

    func fetchBalance() async -> Result<Int64, WalletError> {
        await send(.getBalance) { response in
            guard case .balance(let msats) = response else {
                throw WalletError.decodeFailed("expected balance response")
            }
            return msats
        }.map { msats in
            self.balanceMsats = msats
            self.balanceContinuation.yield(msats)
            return msats
        }
    }

    func payInvoice(_ bolt11: String) async -> Result<String, WalletError> {
        // Payments can take minutes — disable the timeout. A timeout here does NOT mean
        // the payment failed; the wallet may still complete it.
        await send(.payInvoice(bolt11: bolt11), timeout: 0) { response in
            guard case .payInvoice(let preimage, _) = response else {
                throw WalletError.decodeFailed("expected pay_invoice response")
            }
            return preimage
        }
    }

    func makeInvoice(amountMsats: Int64, description: String) async -> Result<String, WalletError> {
        await send(.makeInvoice(amountMsats: amountMsats, description: description)) { response in
            guard case .makeInvoice(let invoice, _) = response else {
                throw WalletError.decodeFailed("expected make_invoice response")
            }
            return invoice
        }
    }

    func listTransactions(limit: Int, offset: Int) async -> Result<[WalletTransaction], WalletError> {
        await send(.listTransactions(limit: limit, offset: offset)) { response in
            guard case .listTransactions(let txs) = response else {
                throw WalletError.decodeFailed("expected list_transactions response")
            }
            return txs.map { tx in
                WalletTransaction(
                    type: tx.type == "incoming" ? .incoming : .outgoing,
                    description: tx.description,
                    paymentHash: tx.paymentHash,
                    amountMsats: tx.amountMsats,
                    feeMsats: tx.feesPaidMsats,
                    createdAt: tx.createdAt,
                    settledAt: tx.settledAt,
                    counterpartyPubkey: nil
                )
            }
        }
    }

    // MARK: - Internals

    private func send<T>(_ request: Nip47.Request, timeout: TimeInterval = 30, _ map: @escaping (Nip47.Response) throws -> T) async -> Result<T, WalletError> {
        guard let conn = connection else { return .failure(.notConnected) }
        do {
            let event = try Nip47.buildRequestEvent(connection: conn, request: request)
            try await RelayPool.publish(event: event, to: conn.relays, timeout: 6)
            emit("Request sent (\(event.kind))")

            let response: Nip47.Response = try await withCheckedThrowingContinuation { cont in
                pendingRequests[event.id] = cont
                if timeout > 0 {
                    Task { [weak self] in
                        try? await Task.sleep(for: .seconds(timeout))
                        await self?.timeoutRequest(eventId: event.id)
                    }
                }
            }
            return .success(try map(response))
        } catch let err as WalletError {
            return .failure(err)
        } catch {
            return .failure(.other(error.localizedDescription))
        }
    }

    private func timeoutRequest(eventId: String) {
        if let cont = pendingRequests.removeValue(forKey: eventId) {
            emit("Request timed out")
            cont.resume(throwing: WalletError.timeout)
        }
    }

    private func handleResponse(event: NostrEvent) async {
        guard let conn = connection else { return }
        guard let requestId = event.tags.first(where: { $0.count >= 2 && $0[0] == "e" })?[1] else { return }
        guard let cont = pendingRequests.removeValue(forKey: requestId) else { return }
        do {
            let response = try Nip47.parseResponseEvent(connection: conn, event: event)
            cont.resume(returning: response)
        } catch {
            cont.resume(throwing: error)
        }
    }

    private func emit(_ message: String) {
        statusContinuation.yield(message)
    }
}
