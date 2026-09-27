import Foundation
import MCP

/// Mac → HTTPS relay. The caller supplies an OAuth session after explicit local approval.
/// This component never chooses a vault, logs in, opens a port, or applies a Markdown change.
public struct RelayConfiguration: Sendable {
    public let endpoint: URL
    public let deviceID: UUID
    public let vaultID: UUID
    public let clientID: String
    public let allowProposals: Bool

    public init(endpoint: URL, deviceID: UUID, vaultID: UUID, clientID: String,
                allowProposals: Bool, allowLoopback: Bool = false) throws {
        let local = allowLoopback && endpoint.scheme == "http" && endpoint.host == "127.0.0.1"
        guard (endpoint.scheme == "https" || local), endpoint.host != nil,
              endpoint.user == nil, endpoint.password == nil, endpoint.query == nil, endpoint.fragment == nil,
              endpoint.path.isEmpty || endpoint.path == "/", !clientID.isEmpty, clientID.utf8.count <= 512 else {
            throw RelayFailure.invalidConfiguration
        }
        self.endpoint = endpoint
        self.deviceID = deviceID
        self.vaultID = vaultID
        self.clientID = clientID
        self.allowProposals = allowProposals
    }
}

public enum RelayFailure: Error, CustomStringConvertible, Equatable {
    case invalidConfiguration, invalidResponse, responseTooLarge, invalidJob, disconnected
    case rejected(Int)
    public var description: String {
        switch self {
        case .invalidConfiguration: return "relay_invalid_configuration"
        case .invalidResponse: return "relay_invalid_response"
        case .responseTooLarge: return "relay_response_too_large"
        case .invalidJob: return "relay_invalid_job"
        case .disconnected: return "relay_disconnected"
        case .rejected(let status): return "relay_rejected_\(status)"
        }
    }
}

private struct RelayGrant: Decodable, Sendable {
    let grantID: UUID
    let lease: String
}

struct RelayJob: Decodable, Sendable {
    let id: UUID
    let name: String
    let arguments: [String: Value]
    let deadline: Double

    func validate(allowProposals: Bool, now: Date = Date()) throws {
        guard deadline.isFinite, deadline > now.timeIntervalSince1970 * 1000,
              deadline <= now.addingTimeInterval(60).timeIntervalSince1970 * 1000,
              ToolServer.definitions.contains(where: { $0.name == name }),
              name != "vault_write" || allowProposals else { throw RelayFailure.invalidJob }
    }
}

private struct RelayPoll: Decodable { let job: RelayJob? }

public struct RelayConnection: Sendable {
    private let configuration: RelayConfiguration
    private let tools: VaultTools

    public init(configuration: RelayConfiguration, tools: VaultTools) {
        self.configuration = configuration
        self.tools = tools
    }

    /// One grant, bound to the VaultTools instance for this run. Cancel and await this task
    /// before switching folders or signing out. No reconnection or replay occurs implicitly.
    public func run(accessToken: @escaping @Sendable () async throws -> String,
                    didConnect: @escaping @Sendable (UUID) async -> Void = { _ in }) async throws {
        let http = RelayHTTP()
        defer { http.close() }
        let registration: [String: Value] = [
            "deviceID": .string(configuration.deviceID.uuidString),
            "vaultID": .string(configuration.vaultID.uuidString),
            "clientID": .string(configuration.clientID),
            "allowProposals": .bool(configuration.allowProposals),
            "writeContract": .string(ClonieMCPVersion.writeContract),
        ]
        let data = try await request(http, "device/grants", body: JSONEncoder().encode(registration), accessToken: accessToken)
        let grant = try JSONDecoder().decode(RelayGrant.self, from: data)
        guard grant.lease.utf8.count == 43, grant.lease.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else {
            throw RelayFailure.invalidResponse
        }
        await didConnect(grant.grantID)
        do {
            var completed = Set<UUID>()
            while true {
                try Task.checkCancellation()
                let poll = try await request(http, "device/grants/\(grant.grantID)/poll", grant: grant, accessToken: accessToken)
                guard let job = try JSONDecoder().decode(RelayPoll.self, from: poll).job else { continue }
                try Task.checkCancellation()
                try job.validate(allowProposals: configuration.allowProposals)
                // A repeated ID is a broken connection, not permission to create a second proposal.
                guard completed.insert(job.id).inserted, completed.count <= 10_000 else { throw RelayFailure.invalidJob }
                let result = await ToolServer.call(job.name, job.arguments, tools: tools)
                try Task.checkCancellation()
                _ = try await request(http, "device/grants/\(grant.grantID)/results/\(job.id)",
                                      body: JSONEncoder().encode(result), grant: grant, accessToken: accessToken)
            }
        } catch {
            // The running request may already have created a pending proposal; cancellation cannot
            // undo it. The app remains the only path to approval. Revoke even if the parent cancelled.
            await Task.detached {
                let cleanup = RelayHTTP(timeout: 3)
                defer { cleanup.close() }
                _ = try? await request(cleanup, "device/grants/\(grant.grantID)", method: "DELETE",
                                       grant: grant, accessToken: accessToken)
            }.value
            if Task.isCancelled || error is CancellationError { throw CancellationError() }
            throw (error as? RelayFailure) ?? RelayFailure.disconnected
        }
    }

    private func request(_ http: RelayHTTP, _ path: String, method: String = "POST", body: Data? = nil,
                         grant: RelayGrant? = nil, accessToken: @Sendable () async throws -> String) async throws -> Data {
        let token = try await accessToken()
        guard !token.isEmpty, token.utf8.count <= 16_384,
              token.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "._~-".contains($0)) }) else {
            throw RelayFailure.invalidConfiguration
        }
        var request = URLRequest(url: configuration.endpoint.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let grant { request.setValue(grant.lease, forHTTPHeaderField: "X-Clonie-Lease") }
        request.httpBody = body
        return try await http.fetch(request)
    }
}

private final class RelayHTTP: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let session: URLSession
    init(timeout: TimeInterval = 30) {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.waitsForConnectivity = false
        session = URLSession(configuration: config, delegate: RelayNoRedirect(), delegateQueue: nil)
        super.init()
    }
    func close() { session.invalidateAndCancel() }
    func fetch(_ request: URLRequest) async throws -> Data {
        if let body = request.httpBody, body.count > 2_097_152 { throw RelayFailure.responseTooLarge }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw RelayFailure.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw RelayFailure.rejected(response.statusCode) }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 2_097_152 else { throw RelayFailure.responseTooLarge }
            data.append(byte)
        }
        return data
    }
}

private final class RelayNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
