import Foundation
import CryptoKit
import Security

/// Public deployment metadata, supplied by the signed app bundle, never by a deep link.
public struct RemoteServiceConfiguration: Codable, Sendable {
    public let relay: URL
    public let issuer: URL
    public let desktopClientID: String
    public let chatClientID: String

    public init(relay: URL, issuer: URL, desktopClientID: String, chatClientID: String) throws {
        self.relay = relay; self.issuer = issuer
        self.desktopClientID = desktopClientID; self.chatClientID = chatClientID
        try validate()
    }

    public func validate() throws {
        for url in [relay, issuer] {
            guard url.scheme == "https", let host = url.host, !host.isEmpty,
                  url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
                  url.path.isEmpty || url.path == "/" else { throw RemoteLoginError.configuration }
        }
        for id in [desktopClientID, chatClientID] {
            guard !id.isEmpty, id.utf8.count <= 512, !id.contains(where: { $0.isWhitespace || $0.isNewline })
            else { throw RemoteLoginError.configuration }
        }
        guard desktopClientID != chatClientID else { throw RemoteLoginError.configuration }
    }

    public var resource: String { relay.appendingPathComponent("mcp").absoluteString }
    public var credentialAccount: String {
        SHA256.hash(data: Data([issuer.absoluteString, resource, desktopClientID].joined(separator: "\n").utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}

public enum RemoteLoginError: Error, Equatable {
    case configuration, callback, denied, credentials, response, network, keychain
}

/// A one-use PKCE transaction. No access/refresh tokens cross the WebView bridge.
public struct RemoteLoginAttempt: Sendable {
    public let authorizationURL: URL
    let redirect: URL
    let state: String
    let verifier: String
    let issuer: URL

    public init(configuration: RemoteServiceConfiguration, callbackScheme: String) throws {
        try configuration.validate()
        guard ["com.local.clonie", "com.local.clonie.qa"].contains(callbackScheme),
              let redirect = URL(string: "\(callbackScheme)://oauth/callback") else {
            throw RemoteLoginError.configuration
        }
        self.redirect = redirect; issuer = configuration.issuer
        state = try Self.random(); verifier = try Self.random()
        var url = URLComponents(url: configuration.issuer.appendingPathComponent("authorize"), resolvingAgainstBaseURL: false)!
        url.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: configuration.desktopClientID),
            .init(name: "redirect_uri", value: redirect.absoluteString),
            .init(name: "audience", value: configuration.resource),
            .init(name: "resource", value: configuration.resource),
            .init(name: "scope", value: "clonie:device offline_access"),
            // After app logout, do not silently pick a different browser's saved account.
            .init(name: "prompt", value: "login"),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: Self.challenge(verifier)),
            .init(name: "code_challenge_method", value: "S256"),
        ]
        authorizationURL = url.url!
    }

    func code(from callback: URL) throws -> String {
        guard var parts = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              callback.fragment == nil else { throw RemoteLoginError.callback }
        let items = parts.queryItems ?? []
        parts.query = nil
        guard parts.url == redirect, Set(items.map(\.name)).count == items.count,
              items.first(where: { $0.name == "state" })?.value == state else { throw RemoteLoginError.callback }
        if let returnedIssuer = items.first(where: { $0.name == "iss" })?.value,
           returnedIssuer != issuer.absoluteString { throw RemoteLoginError.callback }
        guard !items.contains(where: { $0.name == "error" }) else { throw RemoteLoginError.denied }
        guard let code = items.first(where: { $0.name == "code" })?.value,
              !code.isEmpty, code.utf8.count <= 4096 else { throw RemoteLoginError.callback }
        return code
    }

    static func challenge(_ verifier: String) -> String { base64(Data(SHA256.hash(data: Data(verifier.utf8)))) }
    private static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw RemoteLoginError.credentials
        }
        return base64(Data(bytes))
    }
    private static func base64(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

public protocol RemoteCredentialStore: Sendable {
    func load() throws -> String?
    func save(_ refreshToken: String) throws
    func clear() throws
}

/// Only the refresh token is persisted. Neither UserDefaults nor the vault stores credentials.
public struct RemoteKeychainStore: RemoteCredentialStore {
    private let service: String
    private let account: String
    public init(service: String, account: String) { self.service = service; self.account = account }
    private var query: [String: Any] {
        // This Developer ID app uses the Mac login keychain and its per-app ACL.
        // Data Protection Keychain would additionally require a provisioned app ID entitlement.
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account, kSecUseDataProtectionKeychain as String: false]
    }
    public func load() throws -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let token = String(data: data, encoding: .utf8), !token.isEmpty else { throw RemoteLoginError.keychain }
        return token
    }
    public func save(_ refreshToken: String) throws {
        let attributes: [String: Any] = [kSecValueData as String: Data(refreshToken.utf8)]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var acl: SecAccess?
            guard SecAccessCreate("Clonie 로그인" as CFString, nil, &acl) == errSecSuccess, let acl else {
                throw RemoteLoginError.keychain
            }
            var item = query.merging(attributes) { _, new in new }
            item[kSecAttrAccess as String] = acl // nil trusted list above means the calling app only.
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw RemoteLoginError.keychain }
    }
    public func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw RemoteLoginError.keychain }
    }
}

/// Serializes refresh rotation and invalidates any late login/refresh when disconnected.
public actor RemoteLoginSession {
    typealias SendRequest = @Sendable (URLRequest) async throws -> Data
    private let configuration: RemoteServiceConfiguration
    private let storage: any RemoteCredentialStore
    private let send: SendRequest
    private var access: (token: String, expires: Date)?
    private var revision = UUID()
    private var refresh: (id: UUID, task: Task<TokenResponse, Error>)?
    private var loginID: UUID?
    private var loginState: String?

    public init(configuration: RemoteServiceConfiguration, storage: any RemoteCredentialStore) throws {
        try configuration.validate()
        self.configuration = configuration; self.storage = storage
        send = { try await RemoteLoginHTTP.send($0) }
    }
    init(configuration: RemoteServiceConfiguration, storage: any RemoteCredentialStore, send: @escaping SendRequest) {
        self.configuration = configuration; self.storage = storage; self.send = send
    }
    public func hasCredentials() throws -> Bool { try storage.load() != nil }

    public func begin(callbackScheme: String) throws -> RemoteLoginAttempt {
        let attempt = try RemoteLoginAttempt(configuration: configuration, callbackScheme: callbackScheme)
        // A new login invalidates an older browser callback, even within the same process.
        refresh?.task.cancel(); refresh = nil; access = nil
        revision = UUID(); loginID = revision; loginState = attempt.state
        return attempt
    }

    public func complete(_ attempt: RemoteLoginAttempt, callback: URL) async throws {
        guard let id = loginID, id == revision, loginState == attempt.state else { throw RemoteLoginError.callback }
        loginID = nil; loginState = nil
        let code = try attempt.code(from: callback)
        let request = form("oauth/token", ["grant_type": "authorization_code", "code": code,
                    "redirect_uri": attempt.redirect.absoluteString, "code_verifier": attempt.verifier])
        let token = try await decode(request)
        try Task.checkCancellation()
        guard id == revision else { throw CancellationError() }
        try persist(token, previous: nil)
    }

    public func accessToken() async throws -> String {
        try Task.checkCancellation()
        if let access, access.expires.timeIntervalSinceNow > 30 { return access.token }
        let generation = revision
        let previous = try storage.load()
        guard let previous else { throw RemoteLoginError.credentials }
        let work: (id: UUID, task: Task<TokenResponse, Error>)
        if let refresh { work = refresh }
        else {
            let request = form("oauth/token", ["grant_type": "refresh_token", "refresh_token": previous])
            let transport = send
            work = (UUID(), Task { try Self.parse(await transport(request)) })
            refresh = work
        }
        do {
            let token = try await work.task.value
            guard generation == revision else { throw CancellationError() }
            if refresh?.id == work.id {
                refresh = nil
                try persist(token, previous: previous)
            }
            try Task.checkCancellation()
            guard let access else { throw RemoteLoginError.credentials }
            return access.token
        } catch {
            if generation == revision, refresh?.id == work.id {
                refresh = nil; access = nil
                // A failed exchange may already have rotated the token at the provider.
                // Never retry the old refresh token or silently restore it.
                try storage.clear()
            }
            throw error
        }
    }

    /// Call after the relay task has stopped, so its final grant revocation can still authenticate.
    /// Local removal succeeds independently of the provider being online.
    public func signOut() async throws -> Bool {
        revision = UUID(); loginID = nil; loginState = nil
        refresh?.task.cancel(); refresh = nil; access = nil
        let old = try storage.load()
        try storage.clear()
        guard let old else { return true }
        do { _ = try await send(form("oauth/revoke", ["token": old, "token_type_hint": "refresh_token"])); return true }
        catch { return false }
    }

    private struct TokenResponse: Decodable, Sendable {
        let access_token: String
        let token_type: String
        let expires_in: Double
        let refresh_token: String?
        let scope: String?
    }
    private func decode(_ request: URLRequest) async throws -> TokenResponse { try Self.parse(await send(request)) }
    private static func parse(_ data: Data) throws -> TokenResponse {
        guard let token = try? JSONDecoder().decode(TokenResponse.self, from: data),
              token.token_type.lowercased() == "bearer", !token.access_token.isEmpty,
              token.access_token.utf8.count <= 16_384,
              token.access_token.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "._~-".contains($0)) }),
              token.expires_in.isFinite, (1...604_800).contains(token.expires_in),
              token.scope == nil || token.scope!.split(separator: " ").contains("clonie:device") else {
            throw RemoteLoginError.response
        }
        return token
    }
    private func persist(_ token: TokenResponse, previous: String?) throws {
        guard let renewed = token.refresh_token ?? previous, !renewed.isEmpty,
              renewed.utf8.count <= 16_384 else { throw RemoteLoginError.response }
        try storage.save(renewed)
        access = (token.access_token, Date().addingTimeInterval(token.expires_in))
    }
    private func form(_ path: String, _ values: [String: String]) -> URLRequest {
        var request = URLRequest(url: configuration.issuer.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        request.httpBody = Data(values.merging(["client_id": configuration.desktopClientID]) { _, new in new }
            .sorted { $0.key < $1.key }.map {
                "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
            }.joined(separator: "&").utf8)
        return request
    }
}

private final class RemoteLoginHTTP: NSObject, URLSessionTaskDelegate {
    static func send(_ request: URLRequest) async throws -> Data {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 20
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config, delegate: RemoteLoginHTTP(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw RemoteLoginError.credentials
            }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 65_536 else { throw RemoteLoginError.response }
                data.append(byte)
            }
            return data
        } catch let error as RemoteLoginError { throw error }
        catch { if Task.isCancelled { throw CancellationError() }; throw RemoteLoginError.network }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
