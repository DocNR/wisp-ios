import Foundation

/// Persistent, AUTH-aware connection manager for NIP-29 group relays.
///
/// Unlike `RelayPool` (one-shot sockets per call), `GroupRelayPool` keeps one
/// `URLSessionWebSocketTask` open per relay URL with auto-reconnect, handles NIP-42
/// AUTH frames in-line, and demultiplexes incoming `EVENT` frames to per-subscription
/// `AsyncStream`s. Mirrors the Android `RelayPool.ensureGroupRelay` pattern.
actor GroupRelayPool {

    static let shared = GroupRelayPool()

    enum PublishResult: Equatable {
        case ok
        case duplicate
        case authRequired(challenge: String?)
        case rejected(message: String)
        case timeout
        case network
    }

    // MARK: - Private state

    private final class RelayState {
        let url: String
        var socket: URLSessionWebSocketTask?
        var session: URLSession?
        var listenerTask: Task<Void, Never>?
        var reconnectTask: Task<Void, Never>?
        var subscriptions: [String: SubscriptionState] = [:]
        /// `subId` -> filter JSON; replayed verbatim on reconnect.
        var subscriptionFilters: [String: String] = [:]
        /// id -> continuation, for in-flight `publish` calls awaiting an `OK` frame.
        var pendingPublishes: [String: AsyncStream<PublishResult>.Continuation] = [:]
        var isConnecting: Bool = false
        var isAuthenticated: Bool = false
        var lastChallenge: String?
        var keypair: Keypair?
        /// Tracks listeners awaiting AUTH completion.
        var authCompletionContinuations: [CheckedContinuation<Void, Never>] = []
        var reconnectAttempt: Int = 0

        init(url: String) { self.url = url }
    }

    private final class SubscriptionState {
        let subId: String
        let continuation: AsyncStream<NostrEvent>.Continuation
        init(subId: String, continuation: AsyncStream<NostrEvent>.Continuation) {
            self.subId = subId
            self.continuation = continuation
        }
    }

    private var relays: [String: RelayState] = [:]
    /// Reference counts per (relay, group) so we know when a relay can be torn down.
    private var groupCountByRelay: [String: Int] = [:]

    // MARK: - Public API

    /// Open (or refresh keypair on) a persistent connection to `url`. Idempotent.
    func ensureRelay(_ url: String, keypair: Keypair) {
        let state = relays[url] ?? RelayState(url: url)
        state.keypair = keypair
        relays[url] = state
        groupCountByRelay[url, default: 0] += 1
        if state.socket == nil && !state.isConnecting {
            connect(state)
        }
    }

    /// Decrement the refcount for `url`; if it reaches zero, close the socket and forget it.
    func releaseRelay(_ url: String) {
        guard let state = relays[url] else { return }
        let count = (groupCountByRelay[url] ?? 1) - 1
        if count <= 0 {
            groupCountByRelay.removeValue(forKey: url)
            tearDown(state)
            relays.removeValue(forKey: url)
        } else {
            groupCountByRelay[url] = count
        }
    }

    /// Force-close every persistent connection. Call on logout.
    func shutdownAll() {
        for state in relays.values { tearDown(state) }
        relays.removeAll()
        groupCountByRelay.removeAll()
    }

    /// Open a long-lived subscription on `relayUrl`. Caller must `cancel()` the
    /// returned subscription when done.
    func subscribe(relayUrl: String, filter: NostrFilter, subId: String) -> AsyncStream<NostrEvent> {
        guard let state = relays[relayUrl] else {
            return AsyncStream { $0.finish() }
        }
        let stream = AsyncStream<NostrEvent> { continuation in
            let sub = SubscriptionState(subId: subId, continuation: continuation)
            state.subscriptions[subId] = sub
            let filterJSON = filter.toJSON()
            state.subscriptionFilters[subId] = filterJSON
            sendREQ(state: state, subId: subId, filterJSON: filterJSON)
            continuation.onTermination = { [weak self, weak state] _ in
                guard let self, let state else { return }
                Task { await self.cancelSubscription(state: state, subId: subId) }
            }
        }
        return stream
    }

    /// Cancel a single subscription.
    func cancelSubscription(relayUrl: String, subId: String) {
        guard let state = relays[relayUrl] else { return }
        cancelSubscription(state: state, subId: subId)
    }

    /// Publish an event to a single relay. Awaits the OK reply (or AUTH challenge / timeout).
    func publish(_ event: NostrEvent, to relayUrl: String,
                 timeout: TimeInterval = 10) async -> PublishResult {
        guard let state = relays[relayUrl] else { return .network }
        let stream = AsyncStream<PublishResult> { continuation in
            state.pendingPublishes[event.id] = continuation
        }
        send(state: state, payload: "[\"EVENT\",\(event.toJSON())]")
        let timeoutTask = Task {
            try? await Task.sleep(for: .seconds(timeout))
            if let cont = state.pendingPublishes.removeValue(forKey: event.id) {
                cont.yield(.timeout)
                cont.finish()
            }
        }
        var iterator = stream.makeAsyncIterator()
        let result = await iterator.next() ?? .timeout
        timeoutTask.cancel()
        return result
    }

    /// Publish then, on `auth-required:` rejection, wait for AUTH and retry once.
    /// Mirrors Android's `publishAdminEvent` retry semantics.
    func publishWithAuthRetry(_ event: NostrEvent, to relayUrl: String,
                              authWaitSeconds: TimeInterval = 5,
                              publishTimeout: TimeInterval = 10) async -> PublishResult {
        await waitForAuthIfNeeded(relayUrl: relayUrl, timeout: authWaitSeconds)
        let first = await publish(event, to: relayUrl, timeout: publishTimeout)
        switch first {
        case .authRequired:
            await waitForAuthIfNeeded(relayUrl: relayUrl, timeout: authWaitSeconds)
            return await publish(event, to: relayUrl, timeout: publishTimeout)
        default:
            return first
        }
    }

    /// Block (up to `timeout`) until the relay has sent an AUTH challenge AND we've
    /// completed AUTH. Returns immediately if already authenticated or if no challenge
    /// arrived (best-effort — public relays just time out and proceed).
    func waitForAuthIfNeeded(relayUrl: String, timeout: TimeInterval = 5) async {
        guard let state = relays[relayUrl] else { return }
        if state.isAuthenticated { return }
        if state.lastChallenge == nil { return } // No challenge yet; nothing to wait for.
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                guard let self else { return }
                await self.awaitAuth(state: state)
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
            }
            await group.next()
            group.cancelAll()
        }
    }

    private func awaitAuth(state: RelayState) async {
        if state.isAuthenticated { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            state.authCompletionContinuations.append(cont)
        }
    }

    // MARK: - Connection lifecycle

    private func connect(_ state: RelayState) {
        guard let url = URL(string: state.url) else { return }
        state.isConnecting = true
        state.isAuthenticated = false
        state.lastChallenge = nil
        let session = URLSession(configuration: .default)
        let socket = session.webSocketTask(with: url)
        state.session = session
        state.socket = socket
        socket.resume()

        // Re-send every active subscription's REQ.
        for (subId, filterJSON) in state.subscriptionFilters {
            sendREQ(state: state, subId: subId, filterJSON: filterJSON)
        }

        let task = Task { [weak self, weak state] in
            guard let self, let state, let socket = state.socket else { return }
            await self.runReader(state: state, socket: socket)
        }
        state.listenerTask = task
        state.isConnecting = false
        state.reconnectAttempt = 0
    }

    private func tearDown(_ state: RelayState) {
        state.listenerTask?.cancel()
        state.reconnectTask?.cancel()
        state.socket?.cancel(with: .goingAway, reason: nil)
        state.socket = nil
        state.session = nil
        state.isAuthenticated = false
        state.lastChallenge = nil
        for sub in state.subscriptions.values { sub.continuation.finish() }
        state.subscriptions.removeAll()
        state.subscriptionFilters.removeAll()
        for (_, cont) in state.pendingPublishes {
            cont.yield(.network); cont.finish()
        }
        state.pendingPublishes.removeAll()
        for cont in state.authCompletionContinuations { cont.resume() }
        state.authCompletionContinuations.removeAll()
    }

    private func scheduleReconnect(_ state: RelayState) {
        guard relays[state.url] != nil else { return } // released
        state.reconnectAttempt += 1
        let delay = min(30, pow(2.0, Double(state.reconnectAttempt - 1)))
        state.socket?.cancel(with: .goingAway, reason: nil)
        state.socket = nil
        state.session = nil
        state.isAuthenticated = false
        state.lastChallenge = nil
        state.reconnectTask?.cancel()
        state.reconnectTask = Task { [weak self, weak state] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, let state else { return }
            await self.connect(state)
        }
    }

    private func runReader(state: RelayState, socket: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let msg = try await socket.receive()
                guard case .string(let text) = msg else { continue }
                handleFrame(state: state, text: text)
            } catch {
                // Connection dropped — schedule reconnect (only if still tracked).
                if relays[state.url] != nil {
                    scheduleReconnect(state)
                }
                return
            }
        }
    }

    // MARK: - Frame handling

    private func handleFrame(state: RelayState, text: String) {
        guard let data = text.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let type = arr.first as? String else { return }

        switch type {
        case "EVENT":
            guard arr.count >= 3,
                  let subId = arr[1] as? String,
                  let obj = arr[2] as? [String: Any],
                  let event = NostrEvent(json: obj) else { return }
            state.subscriptions[subId]?.continuation.yield(event)

        case "EOSE":
            // Persistent stream stays open; nothing to do.
            break

        case "OK":
            guard arr.count >= 3,
                  let eventId = arr[1] as? String,
                  let ok = arr[2] as? Bool else { return }
            let message = arr.count >= 4 ? (arr[3] as? String ?? "") : ""
            if let cont = state.pendingPublishes.removeValue(forKey: eventId) {
                let result: PublishResult
                if ok {
                    result = .ok
                } else if message.lowercased().hasPrefix("duplicate:") {
                    result = .duplicate
                } else if message.lowercased().hasPrefix("auth-required:") {
                    result = .authRequired(challenge: state.lastChallenge)
                } else {
                    result = .rejected(message: message)
                }
                cont.yield(result)
                cont.finish()
            }

        case "AUTH":
            guard arr.count >= 2, let challenge = arr[1] as? String else { return }
            state.lastChallenge = challenge
            authenticate(state: state, challenge: challenge)

        case "CLOSED":
            // A relay told us our REQ was killed. Replay it after a short delay.
            guard arr.count >= 2, let subId = arr[1] as? String,
                  let filterJSON = state.subscriptionFilters[subId] else { return }
            let reason = (arr.count >= 3 ? (arr[2] as? String ?? "") : "").lowercased()
            // If the relay closed for auth-required, wait for AUTH then re-fire.
            let needsAuth = reason.contains("auth-required")
            Task { [weak self, weak state] in
                if needsAuth {
                    try? await Task.sleep(for: .seconds(2))
                }
                guard let self, let state else { return }
                await self.replayREQ(state: state, subId: subId, filterJSON: filterJSON)
            }

        case "NOTICE":
            // Informational; ignore.
            break

        default:
            break
        }
    }

    private func authenticate(state: RelayState, challenge: String) {
        guard let keypair = state.keypair else { return }
        do {
            let event = try Nip42.buildAuthEvent(challenge: challenge,
                                                 relayUrl: state.url,
                                                 keypair: keypair)
            send(state: state, payload: "[\"AUTH\",\(event.toJSON())]")
            state.isAuthenticated = true
            for cont in state.authCompletionContinuations { cont.resume() }
            state.authCompletionContinuations.removeAll()
        } catch {
            // Sign failed — leave isAuthenticated false; pending awaiters will time out.
        }
    }

    // MARK: - Send helpers

    private func sendREQ(state: RelayState, subId: String, filterJSON: String) {
        send(state: state, payload: "[\"REQ\",\"\(subId)\",\(filterJSON)]")
    }

    private func send(state: RelayState, payload: String) {
        guard let socket = state.socket else { return }
        socket.send(.string(payload)) { _ in /* fire and forget; reader will detect drops */ }
    }

    private func cancelSubscription(state: RelayState, subId: String) {
        state.subscriptions.removeValue(forKey: subId)?.continuation.finish()
        state.subscriptionFilters.removeValue(forKey: subId)
        send(state: state, payload: "[\"CLOSE\",\"\(subId)\"]")
    }

    private func replayREQ(state: RelayState, subId: String, filterJSON: String) {
        // Only re-fire if the subscription still exists (caller hasn't cancelled).
        guard state.subscriptions[subId] != nil else { return }
        sendREQ(state: state, subId: subId, filterJSON: filterJSON)
    }
}
