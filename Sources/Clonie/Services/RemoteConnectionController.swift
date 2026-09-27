import AppKit
import AuthenticationServices
import ClonieMCP

/// Native authentication is the only browser flow. Consent/status stay in the existing HTML settings.
@MainActor
final class RemoteConnectionController {
    let access: RemoteAccessCoordinator
    private let browser = RemoteBrowserLogin()
    private var sleepObserver: NSObjectProtocol?

    init() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.local.clonie"
        var config: RemoteServiceConfiguration?
        if let url = Bundle.main.url(forResource: "RemoteConnection", withExtension: "json"),
           let data = try? Data(contentsOf: url), data.count <= 16_384,
           let decoded = try? JSONDecoder().decode(RemoteServiceConfiguration.self, from: data),
           (try? decoded.validate()) != nil { config = decoded }
        let session = config.flatMap {
            try? RemoteLoginSession(configuration: $0, storage: RemoteKeychainStore(
                service: bundleID + ".remote-login", account: $0.credentialAccount))
        }
        let key = "remoteConnection.deviceID"
        let device = UserDefaults.standard.string(forKey: key).flatMap(UUID.init(uuidString:)) ?? UUID()
        // QA's bundle has its own defaults and keychain service; no user credentials are read.
        UserDefaults.standard.set(device.uuidString, forKey: key)
        access = RemoteAccessCoordinator(configuration: config, session: session, callbackScheme: bundleID,
                                         deviceID: device, vaultURL: VaultLocation.selected)
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.access.stop(signOut: false) }
            }
    }

    func handle(_ body: [String: Any], window: NSWindow) {
        switch body["action"] as? String {
        case "connect":
            guard let consent = body["consentID"] as? String,
                  let allow = body["allowProposals"] as? Bool else { return }
            access.connect(consentID: consent, allowProposals: allow) { [browser] url in
                try await browser.open(url, in: window)
            }
        case "disconnect": Task { await access.stop(signOut: true) }
        case "cancel": Task { await access.stop(signOut: false) }
        default: break
        }
    }
}

@MainActor
private final class RemoteBrowserLogin: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<URL, Error>?
    private var operation: UUID?
    private weak var window: NSWindow?

    func open(_ url: URL, in window: NSWindow) async throws -> URL {
        try Task.checkCancellation()
        guard session == nil else { throw RemoteLoginError.credentials }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.window = window; self.operation = id; self.continuation = continuation
                let login = ASWebAuthenticationSession(url: url,
                    callbackURLScheme: Bundle.main.bundleIdentifier ?? "com.local.clonie") { [weak self] callback, error in
                    Task { @MainActor in
                        if let callback { self?.finish(id, .success(callback)) }
                        else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                            self?.finish(id, .failure(CancellationError()))
                        }
                        else { self?.finish(id, .failure(error == nil ? RemoteLoginError.callback : RemoteLoginError.denied)) }
                    }
                }
                session = login
                login.presentationContextProvider = self
                if !login.start() { finish(id, .failure(RemoteLoginError.denied)) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.operation == id else { return }
                self?.session?.cancel()
                self?.finish(id, .failure(CancellationError()))
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // The caller owns this window for the full login operation.
        window ?? NSWindow()
    }
    private func finish(_ id: UUID, _ result: Result<URL, Error>) {
        guard operation == id else { return }
        let pending = continuation
        continuation = nil; session = nil; operation = nil
        pending?.resume(with: result)
    }
}
