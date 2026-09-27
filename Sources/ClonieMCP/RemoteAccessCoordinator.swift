import Foundation

/// App-owned lifetime, separate from the immutable vault-bound relay worker.
/// A deep link can display this state; only a consent ticket for the displayed folder starts it.
@MainActor
public final class RemoteAccessCoordinator {
    public struct State: Encodable, Sendable {
        public var phase = "unavailable"
        public var vaultPath = ""
        public var consentID = UUID().uuidString
        public var allowProposals = true
        public var message = ""
        public var canDisconnect = false
    }
    public typealias Authenticate = @MainActor (URL) async throws -> URL
    typealias Run = @Sendable (URL, Bool, @escaping @Sendable () async throws -> String,
                              @escaping @Sendable (UUID) async -> Void) async throws -> Void
    public private(set) var state = State()
    public var didChange: ((State) -> Void)?
    private let session: RemoteLoginSession?
    private let callbackScheme: String
    private let run: Run?
    private var selected: URL?
    private var generation = UUID()
    private var operation: Task<Void, Never>?
    private var stopping = false

    public init(configuration: RemoteServiceConfiguration?, session: RemoteLoginSession?,
                callbackScheme: String, deviceID: UUID, vaultURL: URL?) {
        self.session = session; self.callbackScheme = callbackScheme
        if let configuration, session != nil {
            run = { url, allow, token, connected in
                let config = try RelayConfiguration(endpoint: configuration.relay, deviceID: deviceID,
                    vaultID: UUID(), clientID: configuration.chatClientID, allowProposals: allow)
                try await RelayConnection(configuration: config, tools: VaultTools(vaultURL: url))
                    .run(accessToken: token, didConnect: connected)
            }
        } else { run = nil }
        selected = vaultURL?.standardizedFileURL.resolvingSymlinksInPath()
        resetState()
        if let session {
            let initial = generation
            Task { [weak self] in
                let saved = (try? await session.hasCredentials()) ?? false
                guard let self, self.generation == initial else { return }
                self.state.canDisconnect = saved; self.publish()
            }
        }
    }

    init(session: RemoteLoginSession, vaultURL: URL?, run: @escaping Run) {
        self.session = session; self.callbackScheme = "com.local.clonie.qa"; self.run = run
        selected = vaultURL?.standardizedFileURL.resolvingSymlinksInPath()
        resetState()
    }

    public func connect(consentID: String, allowProposals: Bool, authenticate: @escaping Authenticate) {
        guard !stopping, operation == nil, consentID == state.consentID,
              let selected, let session, let run else { return }
        let id = UUID(); generation = id
        state.phase = "authenticating"; state.allowProposals = allowProposals; state.message = ""
        publish()
        operation = Task { [weak self, callbackScheme] in
            do {
                if try await !session.hasCredentials() {
                    let attempt = try await session.begin(callbackScheme: callbackScheme)
                    let callback = try await authenticate(attempt.authorizationURL)
                    try Task.checkCancellation()
                    try await session.complete(attempt, callback: callback)
                }
                // Fail before registering a grant when refresh/login cannot complete.
                _ = try await session.accessToken()
                try Task.checkCancellation()
                guard let self, self.generation == id else { return }
                self.state.canDisconnect = true; self.state.phase = "connecting"; self.publish()
                try await run(selected, allowProposals, { try await session.accessToken() }, { [weak self] _ in
                    await self?.connected(id)
                })
                self.finished(id, message: "연결이 끝났습니다. 다시 연결해 주세요.")
            } catch {
                guard !Task.isCancelled else { return }
                if error is CancellationError {
                    guard let self, self.generation == id else { return }
                    self.operation = nil; self.resetState(); self.publish(); return
                }
                self?.finished(id, message: error is RemoteLoginError
                    ? "로그인을 완료하지 못했습니다. 다시 연결해 주세요."
                    : "연결이 끊겼습니다. 네트워크를 확인하고 다시 연결해 주세요.")
            }
        }
    }

    private func connected(_ id: UUID) {
        guard generation == id, !stopping else { return }
        state.phase = "connected"; publish()
    }
    private func finished(_ id: UUID, message: String) {
        guard generation == id, !stopping else { return }
        operation = nil; state.phase = "failed"; state.message = message
        state.consentID = UUID().uuidString; publish()
    }

    /// New selection is published only after the old worker has finished cancellation/revocation.
    public func selectVault(_ url: URL?) async {
        await stop(signOut: false)
        selected = url?.standardizedFileURL.resolvingSymlinksInPath()
        resetState(); publish()
    }

    public func stop(signOut: Bool) async {
        // Serialize repeated disconnect/switch/quit requests, including their revocation tail.
        if stopping {
            if let operation { await operation.value }
            if signOut { await stop(signOut: true) }
            return
        }
        stopping = true; generation = UUID()
        state.phase = "stopping"; state.consentID = UUID().uuidString; publish()
        let old = operation
        old?.cancel()
        let session = self.session
        let cleanup = Task { [weak self] in
            await old?.value
            var message = ""
            var needsSignOutRetry = false
            if signOut, let session {
                do {
                    if try await !session.signOut() {
                        message = "이 Mac의 연결과 로그인 정보를 지웠습니다. 로그인 서비스의 권한 해제는 확인하지 못했습니다."
                    }
                } catch {
                    needsSignOutRetry = true
                    message = "연결은 멈췄지만 로그인 정보를 지우지 못했습니다. 연결 해제를 다시 눌러 주세요."
                }
            }
            guard let self else { return }
            if signOut {
                let remaining = (try? await session?.hasCredentials()) ?? false
                self.state.canDisconnect = needsSignOutRetry || remaining
            }
            self.operation = nil; self.stopping = false
            self.resetState(); self.state.message = message; self.publish()
        }
        operation = cleanup
        await cleanup.value
    }

    private func resetState() {
        state.phase = run == nil ? "unavailable" : (selected == nil ? "noVault" : "ready")
        state.vaultPath = selected?.path ?? ""
        state.consentID = UUID().uuidString; state.message = ""
    }
    private func publish() { didChange?(state) }
}
