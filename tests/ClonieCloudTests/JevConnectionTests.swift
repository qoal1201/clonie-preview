import Foundation
import XCTest
@testable import ClonieCloud

final class JevConnectionTests: XCTestCase {
    private let endpoint = URL(string: "https://cloud-test.invalid/v1/jev/evaluate")!
    private let vault = URL(fileURLWithPath: "/tmp/clonie-cloud-vault", isDirectory: true)

    func testCloudRoutesAllJudgmentsWithoutAProviderKeyOrChangingTheirMeaning() throws {
        let cloud = try JevConnection.cloud(endpoint: endpoint, accessToken: " session-token ")
        let direct = try JevConnection.typeSafePreview(apiKey: "provider-secret")
        let candidate = JevEvidenceWire.Candidate(id: "note", revision: "r1", text: "내가 보완할 메모")
        let document = JevGalaxyWire.Document(id: "note", title: "주제", text: candidate.text)
        func requests(_ connection: JevConnection) throws -> [URLRequest] {
            [try JevEvidenceWire.prepare(query: "이유", candidates: [candidate], connection: connection).urlRequest,
             try JevEvidenceWire.prepareSupplement(note: "회고", candidates: [candidate], connection: connection).urlRequest,
             try JevEvidenceWire.prepareRerank(query: "이유", candidates: [candidate], connection: connection).urlRequest,
             try JevGalaxyWire.prepare(documents: [document], anchors: [document], connection: connection).request]
        }
        for ((request, provider), purpose) in zip(zip(try requests(cloud), try requests(direct)),
                                                 ["evidence", "supplement", "rerank", "galaxy"]) {
            XCTAssertEqual(request.url, endpoint)
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer session-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Clonie-Jev-Purpose"), purpose)
            let body = try XCTUnwrap(request.httpBody)
            XCTAssertEqual(try JSONSerialization.jsonObject(with: body) as? NSDictionary,
                           try JSONSerialization.jsonObject(with: XCTUnwrap(provider.httpBody)) as? NSDictionary)
            XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("session-token"))
            XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("provider-secret"))
        }
    }

    func testInsecureAndCredentialBearingEndpointsFailClosed() {
        for address in ["http://cloud-test.invalid/evaluate", "https://user:secret@cloud-test.invalid/evaluate",
                        "https://cloud-test.invalid/evaluate?token=secret", "https://cloud-test.invalid/#secret",
                        "https://api.typesafe.ai/v1/systemone", "https://API.TYPESAFE.AI./v1/systemone"] {
            XCTAssertThrowsError(try JevConnection.cloud(endpoint: URL(string: address)!, accessToken: "token"))
        }
        for token in [" ", "line\nbreak", "two tokens", "secret\rheader", String(repeating: "x", count: 16_385)] {
            XCTAssertThrowsError(try JevConnection.cloud(endpoint: endpoint, accessToken: token))
        }
    }

    func testLoopbackHTTPNeedsExplicitDevelopmentOptInAndNeverAllowsLAN() throws {
        let loopback = URL(string: "http://127.0.0.1:9876/v1/jev/evaluate")!
        XCTAssertThrowsError(try JevConnection.cloud(endpoint: loopback, accessToken: "token"))
        XCTAssertNoThrow(try JevConnection.cloud(endpoint: loopback, accessToken: "token", allowLoopbackHTTP: true))
        for host in ["localhost", "192.168.0.5", "127.0.0.1.attacker.invalid"] {
            XCTAssertThrowsError(try JevConnection.cloud(endpoint: URL(string: "http://\(host)/evaluate")!,
                                                          accessToken: "token", allowLoopbackHTTP: true))
        }
    }

    func testCloudPreviewRequiresTheSelectedVaultAndDoesNotFallBackToDeveloperKey() throws {
        let direct = ["TYPESAFE_API_KEY": "developer-key", "CLONIE_JEV_PREVIEW_VAULT": vault.path]
        XCTAssertEqual(JevConnection.preview(environment: direct, vaultURL: vault)?.route, .typeSafePreview)
        var environment = direct
        environment["CLONIE_CLOUD_JEV_ENDPOINT"] = endpoint.absoluteString
        XCTAssertNil(JevConnection.preview(environment: environment, vaultURL: vault))
        environment["CLONIE_CLOUD_ACCESS_TOKEN"] = "session-token"
        environment["CLONIE_CLOUD_PREVIEW_VAULT"] = vault.path
        XCTAssertEqual(JevConnection.preview(environment: environment, vaultURL: vault)?.route, .cloud)
        XCTAssertNil(JevConnection.preview(environment: environment, vaultURL: vault.appendingPathComponent("other")))
        environment["CLONIE_CLOUD_ACCESS_TOKEN"] = ""
        XCTAssertNil(JevConnection.preview(environment: environment, vaultURL: vault))
    }

    func testCloudPreviewWorksWithoutAnyTypeSafeCredential() throws {
        let connection = try XCTUnwrap(JevConnection.preview(environment: [
            "CLONIE_CLOUD_JEV_ENDPOINT": endpoint.absoluteString,
            "CLONIE_CLOUD_ACCESS_TOKEN": "session-token",
            "CLONIE_CLOUD_PREVIEW_VAULT": vault.path
        ], vaultURL: vault))
        XCTAssertEqual(connection.route, .cloud)
        XCTAssertNil(JevConnection.preview(environment: [:], vaultURL: vault))
    }

    func testAuthenticatedCloudResponsePassesThroughExistingGalaxyParser() async throws {
        let connection = try JevConnection.cloud(endpoint: endpoint, accessToken: "active-test-session")
        let doc = JevGalaxyWire.Document(id: "notes/review", title: "회고", text: "원문 발췌")
        let prepared = try JevGalaxyWire.prepare(documents: [doc], anchors: [doc], connection: connection)
        let config = JevEvidenceService.ephemeralConfiguration()
        config.protocolClasses = [CloudSessionProtocol.self]
        let result = try await JevEvidenceService.fetch(prepared.request, configuration: config)
        let assignments = try JevGalaxyWire.parse(result, for: prepared)
        XCTAssertEqual(assignments.map(\.documentID), [doc.id])
        XCTAssertEqual(assignments.map(\.group), [0])
    }

    func testServerDenialIsAnErrorAndNeverBecomesAJudgment() async throws {
        for status in [401, 403, 429] {
            let connection = try JevConnection.cloud(endpoint: endpoint, accessToken: "rejected-\(status)")
            let request = connection.request(body: Data("{}".utf8), purpose: "galaxy")
            let config = JevEvidenceService.ephemeralConfiguration()
            config.protocolClasses = [CloudSessionProtocol.self]
            do {
                _ = try await JevEvidenceService.fetch(request, configuration: config)
                XCTFail("The client's configured session must not bypass a server denial")
            } catch {
                XCTAssertEqual(error as? JevEvidenceService.Failure, .rejected(statusCode: status))
                let message = connection.failureMessage(for: error)
                XCTAssertTrue(message.contains("Cloud"))
                XCTAssertFalse(message.contains("server-private-detail"))
                XCTAssertFalse(message.contains("rejected-"))
            }
        }
    }
}

/// Simulates an entitled/denied server response, not real authentication or Jev quality.
private final class CloudSessionProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard request.url?.host == "cloud-test.invalid", request.httpMethod == "POST",
              request.value(forHTTPHeaderField: "X-Clonie-Jev-Purpose") == "galaxy" else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return
        }
        let token = request.value(forHTTPHeaderField: "Authorization") ?? ""
        let status = token == "Bearer active-test-session" ? 200 : Int(token.split(separator: "-").last ?? "") ?? 401
        let body = status == 200
            ? #"{"model":"jev-1.13.0","answers":{"q0":{"type":"choice","choice":"a0","probabilities":{"a0":0.9,"none":0.1},"confidence":0.8}}}"#
            : "server-private-detail"
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
                                                            httpVersion: "HTTP/1.1", headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
