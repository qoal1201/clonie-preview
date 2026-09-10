import XCTest
import MCP
import ClonieCore
@testable import ClonieMCP

/// MCP 껍데기 — 상류 `Client` 가 `InMemoryTransport` 로 우리 `Server` 를 부른다.
/// 도구 이름·스키마·JSON 모양이 계약이다. 논리는 `VaultToolsTests` 가 이미 잰다.
final class ToolServerTests: XCTestCase {
    private var vault: URL!
    private var client: Client!
    private var server: Server!

    override func setUp() async throws {
        vault = try MCPTestSupport.makeVault("server")
        try VaultStore(vaultURL: vault).save(MCPTestSupport.sampleDocument())
        let tools = VaultTools(vaultURL: vault, environment: MCPTestSupport.noModelEnvironment)
        server = await ToolServer.make(tools: tools)
        let pair = await InMemoryTransport.createConnectedPair()
        try await server.start(transport: pair.server)
        client = Client(name: "test-client", version: "0")
        _ = try await client.connect(transport: pair.client)
    }

    override func tearDown() async throws {
        await client.disconnect()
        await server.stop()
        try? FileManager.default.removeItem(at: vault)
    }

    private func callJSON(_ name: String, _ args: [String: Value]) async throws -> (json: [String: Any], isError: Bool) {
        let (content, isError) = try await client.callTool(name: name, arguments: args)
        guard case .text(let text, _, _) = content.first else { XCTFail("text 가 아니다: \(content)"); return ([:], true) }
        let obj = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] ?? [:]
        return (obj, isError ?? false)
    }

    func testListsVaultAndOriginalSourceToolsWithSchemas() async throws {
        let (tools, _) = try await client.listTools()
        XCTAssertEqual(tools.map(\.name).sorted(), ["vault_list", "vault_read", "vault_search", "vault_source_list", "vault_source_read", "vault_write"])
        let search = tools.first { $0.name == "vault_search" }!
        XCTAssertEqual(search.inputSchema.objectValue?["required"]?.arrayValue?.first?.stringValue, "query")
    }

    func testOriginalSourceRoundTripAndTraversalRejection() async throws {
        let raw = vault.appendingPathComponent("raw")
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
        try "다음 분기에 검색을 개선할 계획이다.".write(to: raw.appendingPathComponent("plan.txt"), atomically: true, encoding: .utf8)
        let listed = try await callJSON("vault_source_list", [:])
        XCTAssertFalse(listed.isError)
        let sources = listed.json["sources"] as! [[String: Any]]
        XCTAssertEqual(sources[0]["path"] as? String, "raw/plan.txt")
        let read = try await callJSON("vault_source_read", ["path": .string("raw/plan.txt")])
        XCTAssertEqual(read.json["text"] as? String, "다음 분기에 검색을 개선할 계획이다.")
        XCTAssertEqual(read.json["hash"] as? String, sources[0]["hash"] as? String)
        let (_, rejected) = try await client.callTool(name: "vault_source_read", arguments: ["path": .string("../secret.txt")])
        XCTAssertEqual(rejected, true)
    }

    func testSearchReturnsJSONHits() async throws {
        let r = try await callJSON("vault_search", ["query": .string("당번")])
        XCTAssertFalse(r.isError)
        XCTAssertEqual(r.json["mode"] as? String, "text")
        let hits = r.json["hits"] as? [[String: Any]]
        XCTAssertEqual(hits?.first?["id"] as? String, "f-fail")
    }

    func testReadUnknownIsAnErrorResult() async throws {
        let (content, isError) = try await client.callTool(name: "vault_read", arguments: ["id": .string("nope")])
        XCTAssertEqual(isError, true)
        guard case .text(let text, _, _) = content.first else { return XCTFail() }
        XCTAssertTrue(text.contains("nope"))
    }

    func testWriteThenReadRoundTripsThroughProtocol() async throws {
        let w = try await callJSON("vault_write", ["title": .string("프로토콜로 쓴 조각"),
                                                   "body": .string("본문"),
                                                   "question_ids": .array([.string("q-1")]),
                                                   "force": .bool(true)])
        XCTAssertEqual(w.json["written"] as? Bool, true)
        let id = w.json["id"] as! String
        let r = try await callJSON("vault_read", ["id": .string(id)])
        XCTAssertEqual(r.json["title"] as? String, "프로토콜로 쓴 조각")
        XCTAssertEqual(r.json["questionIds"] as? [String], ["q-1"])
    }

    func testUnknownToolIsAnError() async throws {
        let (_, isError) = try await client.callTool(name: "vault_explode", arguments: [:])
        XCTAssertEqual(isError, true)
    }

    func testDatesAreISO8601() async throws {
        let r = try await callJSON("vault_read", ["id": .string("f-deploy")])
        XCTAssertEqual(r.json["createdAt"] as? String, "2025-08-24T01:46:40Z")
    }

    private struct Unencodable: Encodable {
        struct Boom: Error {}
        func encode(to encoder: Encoder) throws { throw Boom() }
    }

    func testEncodingFailureBecomesToolErrorNotEmptySuccess() {
        let r = ToolServer.ok(Unencodable())
        XCTAssertEqual(r.isError, true)
        guard case .text(let text, _, _) = r.content.first else { return XCTFail() }
        XCTAssertTrue(text.hasPrefix("오류: 결과를 JSON 으로 못 만들었다"), text)
    }
}
