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
        for tool in tools {
            XCTAssertEqual(tool.annotations.readOnlyHint, tool.name != "vault_write", tool.name)
            XCTAssertEqual(tool.annotations.destructiveHint, false, tool.name)
            XCTAssertEqual(tool.annotations.openWorldHint, false, tool.name)
        }
        let proposal = try XCTUnwrap(tools.first { $0.name == "vault_write" })
        XCTAssertEqual(proposal.annotations.idempotentHint, false,
                       "An uncertain proposal response must not invite automatic retries.")
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

    func testListIdentifiesTheConnectedVaultWithoutNeedingSearchOrWrites() async throws {
        let before = try FileManager.default.contentsOfDirectory(atPath: vault.path).sorted()
        let r = try await callJSON("vault_list", ["limit": .int(1)])
        XCTAssertFalse(r.isError)
        XCTAssertEqual(r.json["vaultPath"] as? String, vault.path)
        XCTAssertEqual((r.json["fragments"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: vault.path).sorted(), before)
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
                                                   "path": .string("프로젝트/세션 기록.md"),
                                                   "question_ids": .array([.string("q-1")]),
                                                   "force": .bool(true)])
        XCTAssertEqual(w.json["written"] as? Bool, false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent("프로젝트/세션 기록.md").path))
        try VaultStore(vaultURL: vault).approveProposal(id: w.json["proposalID"] as! String)
        XCTAssertEqual(w.json["path"] as? String, "프로젝트/세션 기록.md")
        let id = w.json["id"] as! String
        let r = try await callJSON("vault_read", ["id": .string(id)])
        XCTAssertEqual(r.json["title"] as? String, "프로토콜로 쓴 조각")
        XCTAssertEqual(r.json["questionIds"] as? [String], ["q-1"])
    }

    func testUnknownToolIsAnError() async throws {
        let (_, isError) = try await client.callTool(name: "vault_explode", arguments: [:])
        XCTAssertEqual(isError, true)
    }

    func testProposalRequiresMatchingReadRevisionAndNeverOverwritesNewerDocument() async throws {
        let store = VaultStore(vaultURL: vault)
        let (_, unreadError) = try await client.callTool(name: "vault_write", arguments: [
            "id": .string("f-fail"), "title": .string("수정"), "body": .string("읽지 않은 수정")])
        XCTAssertEqual(unreadError, true)
        XCTAssertTrue(try store.proposals().isEmpty)

        let read = try await callJSON("vault_read", ["id": .string("f-fail")])
        let revision = try XCTUnwrap(read.json["revision"] as? String)
        _ = try await callJSON("vault_read", ["id": .string("f-deploy")])
        let (_, wrongIDError) = try await client.callTool(name: "vault_write", arguments: [
            "id": .string("f-deploy"), "revision": .string(revision),
            "title": .string("다른 문서"), "body": .string("버전을 잘못 연결한 수정")])
        XCTAssertEqual(wrongIDError, true)
        XCTAssertTrue(try store.proposals().isEmpty)

        var newer = try store.load().document
        newer.fragments[newer.fragments.firstIndex { $0.id == "f-fail" }!].body = "사용자가 나중에 보완한 사실"
        try store.save(newer)
        let proposed = try await callJSON("vault_write", [
            "id": .string("f-fail"), "revision": .string(revision),
            "title": .string("수정 제안"), "body": .string("이전 문서를 기준으로 한 수정")])
        XCTAssertFalse(proposed.isError)
        XCTAssertEqual(proposed.json["written"] as? Bool, false)
        let proposalID = try XCTUnwrap(proposed.json["proposalID"] as? String)
        XCTAssertThrowsError(try store.approveProposal(id: proposalID)) { error in
            guard case VaultMutationError.conflict = error else { return XCTFail("예상한 충돌이 아님: \(error)") }
        }
        XCTAssertEqual(try store.load().document.fragments.first { $0.id == "f-fail" }?.body,
                       "사용자가 나중에 보완한 사실")
        XCTAssertEqual(try store.proposals().map(\.id), [proposalID])
    }

    func testProposalProtectsOriginalAndRejectsNewOriginalPath() async throws {
        let raw = vault.appendingPathComponent("raw")
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
        let original = raw.appendingPathComponent("source.md")
        let bytes = Data("# 원본\n\n보존할 사실".utf8)
        try bytes.write(to: original)
        let listed = try await callJSON("vault_list", [:])
        let fragments = try XCTUnwrap(listed.json["fragments"] as? [[String: Any]])
        let id = try XCTUnwrap(fragments.first { $0["path"] as? String == "raw/source.md" }?["id"] as? String)
        let read = try await callJSON("vault_read", ["id": .string(id)])
        let revision = try XCTUnwrap(read.json["revision"] as? String)
        let (errorContent, updateError) = try await client.callTool(name: "vault_write", arguments: [
            "id": .string(id), "revision": .string(revision),
            "title": .string("바뀐 원본"), "body": .string("변경")])
        XCTAssertEqual(updateError, true)
        guard case .text(let errorText, _, _) = errorContent.first else { return XCTFail("보호 오류 응답 누락") }
        XCTAssertTrue(errorText.contains(VaultToolError.readOnlySource("raw/source.md").description))
        let (_, createError) = try await client.callTool(name: "vault_write", arguments: [
            "path": .string("raw/new.md"), "title": .string("새 원본"), "body": .string("변경")])
        XCTAssertEqual(createError, true)
        XCTAssertEqual(try Data(contentsOf: original), bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: raw.appendingPathComponent("new.md").path))
        XCTAssertTrue(try VaultStore(vaultURL: vault).proposals().isEmpty)
    }

    func testGroupedProposalsAllowPartialApprovalWithoutWritingRemainingDocument() async throws {
        let store = VaultStore(vaultURL: vault)
        let first = try await callJSON("vault_write", [
            "title": .string("첫 문서"), "body": .string("첫 제안"),
            "path": .string("notes/a.md"), "task_title": .string("결정 보완")])
        let taskID = try XCTUnwrap(first.json["taskID"] as? String)
        let second = try await callJSON("vault_write", [
            "title": .string("둘째 문서"), "body": .string("둘째 제안"),
            "path": .string("notes/b.md"), "task_id": .string(taskID)])
        XCTAssertFalse(first.isError)
        XCTAssertFalse(second.isError)
        XCTAssertEqual(try store.proposals().map(\.taskTitle), ["결정 보완", "결정 보완"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent("notes/a.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent("notes/b.md").path))

        try store.approveProposal(id: XCTUnwrap(first.json["proposalID"] as? String), body: "사용자가 고쳐 승인한 본문")
        let remaining = try XCTUnwrap(store.proposals().first)
        XCTAssertEqual(try store.proposals().count, 1)
        XCTAssertEqual(remaining.id, second.json["proposalID"] as? String)
        XCTAssertEqual(remaining.path, "notes/b.md")
        XCTAssertEqual(remaining.taskID, taskID)
        XCTAssertEqual(remaining.taskTitle, "결정 보완")
        let read = try await callJSON("vault_read", ["id": .string(try XCTUnwrap(first.json["id"] as? String))])
        XCTAssertEqual(read.json["body"] as? String, "사용자가 고쳐 승인한 본문")
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent("notes/a.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent("notes/b.md").path))
        try store.rejectProposal(id: remaining.id)
        XCTAssertTrue(try store.proposals().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent("notes/b.md").path))
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
        XCTAssertNil(r.structuredContent)
        guard case .text(let text, _, _) = r.content.first else { return XCTFail() }
        XCTAssertTrue(text.hasPrefix("오류: 결과를 JSON 으로 못 만들었다"), text)
    }
}
