import Foundation

/// Authenticates a judgment request without changing its questions or response contract.
/// A Cloud token identifies the Clonie session; only the server may grant paid access.
public struct JevConnection: Sendable {
    public enum Route: Sendable { case cloud, typeSafePreview }
    public enum Failure: Error, Equatable { case invalidEndpoint, invalidCredential }

    public let route: Route
    private let endpoint: URL
    private let credential: String

    public static func cloud(endpoint: URL, accessToken: String,
                             allowLoopbackHTTP: Bool = false) throws -> Self {
        guard let parts = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
              let host = parts.host?.lowercased(), !host.isEmpty,
              host != "api.typesafe.ai", host != "api.typesafe.ai.",
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.scheme == "https" || (allowLoopbackHTTP && parts.scheme == "http" && host == "127.0.0.1")
        else { throw Failure.invalidEndpoint }
        return try Self(route: .cloud, endpoint: endpoint, credential: accessToken)
    }

    /// Retains the explicitly scoped developer connection used before Cloud exists.
    public static func typeSafePreview(apiKey: String) throws -> Self {
        try Self(route: .typeSafePreview, endpoint: JevEvidenceWire.endpoint, credential: apiKey)
    }

    private init(route: Route, endpoint: URL, credential: String) throws {
        let token = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, token.utf8.count <= 16_384,
              token.unicodeScalars.allSatisfy({ (33...126).contains($0.value) })
        else { throw Failure.invalidCredential }
        self.route = route
        self.endpoint = endpoint
        self.credential = token
    }

    /// Development wiring only. A future login supplies a Cloud session separately.
    /// Partial Cloud configuration fails closed; it never falls back to a provider key.
    /// Resolving a connection does not read documents, contact a server, or prove entitlement.
    public static func preview(environment: [String: String], vaultURL: URL) -> Self? {
        let cloudKeys = ["CLONIE_CLOUD_JEV_ENDPOINT", "CLONIE_CLOUD_ACCESS_TOKEN",
                         "CLONIE_CLOUD_PREVIEW_VAULT", "CLONIE_CLOUD_ALLOW_LOOPBACK"]
        func matchesVault(_ configured: String?) -> Bool {
            guard let path = configured?.trimmingCharacters(in: .whitespacesAndNewlines),
                  path.hasPrefix("/") else { return false }
            return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
                == vaultURL.standardizedFileURL.resolvingSymlinksInPath()
        }
        if cloudKeys.contains(where: { environment[$0] != nil }) {
            guard matchesVault(environment["CLONIE_CLOUD_PREVIEW_VAULT"]),
                  let address = environment["CLONIE_CLOUD_JEV_ENDPOINT"], let endpoint = URL(string: address),
                  let token = environment["CLONIE_CLOUD_ACCESS_TOKEN"] else { return nil }
            return try? cloud(endpoint: endpoint, accessToken: token,
                              allowLoopbackHTTP: environment["CLONIE_CLOUD_ALLOW_LOOPBACK"] == "1")
        }
        guard matchesVault(environment["CLONIE_JEV_PREVIEW_VAULT"]),
              let key = environment["TYPESAFE_API_KEY"] else { return nil }
        return try? typeSafePreview(apiKey: key)
    }

    func request(body: Data, purpose: String) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
        if route == .cloud { request.setValue(purpose, forHTTPHeaderField: "X-Clonie-Jev-Purpose") }
        request.httpBody = body
        return request
    }

    /// Never exposes server response text, tokens, or document content to the UI.
    public func failureMessage(for error: Error) -> String {
        if route == .cloud, case let JevEvidenceService.Failure.rejected(status) = error {
            switch status {
            case 401: return "Cloud 인증을 확인하지 못했어요. 기존 폴더와 검색은 계속 사용할 수 있어요."
            case 403: return "현재 계정에서 Cloud 기능을 사용할 수 없어요. 기존 폴더와 검색은 계속 사용할 수 있어요."
            case 429: return "Cloud 요청 한도에 도달했어요. 잠시 후 다시 시도해 주세요."
            default: break
            }
        }
        return "Jev 판정을 받지 못했어요. 이전 결과를 유지합니다. 다시 시도할 수 있어요."
    }
}
