import XCTest
import GhostbarCore
@testable import ClonieMCP

/// ★ 둘째 문의 핵심 자물쇠 — **앱(이 프로세스의 `VaultStore`)과 MCP 서버(빌드된 `clonie-mcp`,
/// 진짜 둘째 프로세스)가 같은 볼트를 동시에 든다.** ADR 0007 이 약속한 것을 잰다:
/// MCP 가 쓴 조각은 앱 저장에 살아남고, 앱이 쓴 조각은 MCP 가 읽는다. 잠금은 없다.
final class TwoProcessTests: XCTestCase {
    private var vault: URL!
    private var app: VaultStore!
    private var mcp: StdioClient!

    override func setUpWithError() throws {
        vault = try MCPTestSupport.makeVault("two-process")
        app = VaultStore(vaultURL: vault)
        try app.save(MCPTestSupport.sampleDocument())
        _ = try app.load()                                    // 앱이 떠서 볼트를 읽은 상태
        mcp = StdioClient(binary: MCPTestSupport.productsDirectory.appendingPathComponent("clonie-mcp"),
                          vault: vault, environment: MCPTestSupport.noModelEnvironment)
        try mcp.start()
        let r = try mcp.request(id: 1, method: "initialize",
                                params: ["protocolVersion": "2025-06-18", "capabilities": [:],
                                         "clientInfo": ["name": "two-process-test", "version": "0"]])
        XCTAssertEqual(((r["result"] as? [String: Any])?["serverInfo"] as? [String: Any])?["name"] as? String, "clonie")
        try mcp.notify(method: "notifications/initialized")
    }

    override func tearDownWithError() throws {
        mcp?.stop()
        try? FileManager.default.removeItem(at: vault)
    }

    private func call(_ id: Int, _ name: String, _ args: [String: Any]) throws -> [String: Any] {
        let r = try mcp.request(id: id, method: "tools/call", params: ["name": name, "arguments": args])
        let content = ((r["result"] as? [String: Any])?["content"] as? [[String: Any]]) ?? []
        let text = content.first?["text"] as? String ?? "{}"
        return try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] ?? [:]
    }

    func testFragmentWrittenByServerSurvivesAppSave() throws {
        let w = try call(2, "vault_write", ["title": "MCP 가 쓴 조각", "body": "둘째 문으로 들어온 문단", "force": true])
        XCTAssertEqual(w["written"] as? Bool, true)
        let path = w["path"] as! String
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent(path).path))

        // 앱이 자기 문서(MCP 조각을 모른다)를 그대로 저장한다 — 화면이 매 저장마다 하는 일.
        try app.save(MCPTestSupport.sampleDocument())

        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent(path).path),
                      "앱 저장이 MCP 조각을 지우거나 휴지통으로 보냈다")
        let back = try app.load()
        XCTAssertEqual(back.document.fragments.count, 4)
        XCTAssertTrue(back.document.fragments.contains { $0.title == "MCP 가 쓴 조각" })
    }

    func testAppEditAndServerWriteBothLand() throws {
        _ = try call(2, "vault_write", ["title": "MCP 둘째", "body": "본문", "force": true])
        var doc = MCPTestSupport.sampleDocument()
        doc.fragments[0].body = "앱에서 고친 본문"
        try app.save(doc)
        let back = try app.load()
        XCTAssertEqual(back.document.fragments.first { $0.id == "f-deploy" }?.body, "앱에서 고친 본문")
        XCTAssertTrue(back.document.fragments.contains { $0.title == "MCP 둘째" })
    }

    func testServerReadsWhatAppWrote() throws {
        var doc = MCPTestSupport.sampleDocument()
        doc.fragments.append(Fragment(id: "f-app-new", title: "앱이 방금 쓴 것", body: "앱 본문",
                                      questionIds: [], createdAt: Date(), updatedAt: Date()))
        try app.save(doc)
        let r = try call(2, "vault_read", ["id": "f-app-new"])
        XCTAssertEqual(r["title"] as? String, "앱이 방금 쓴 것")
    }

    func testServerNeverWritesIndexSidecar() throws {
        _ = try call(2, "vault_search", ["query": "배포"])
        _ = try call(3, "vault_write", ["title": "하나 더", "body": "본문", "force": true])
        let sidecar = VaultStore(vaultURL: vault).sidecarURL
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecar.appendingPathComponent("embeddings.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecar.appendingPathComponent("links.json").path))
    }

    func testVersionFlagPrintsAndExits() throws {
        let p = Process()
        p.executableURL = MCPTestSupport.productsDirectory.appendingPathComponent("clonie-mcp")
        p.arguments = ["--version"]
        let out = Pipe(); p.standardOutput = out
        try p.run(); p.waitUntilExit()
        XCTAssertEqual(String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines), ClonieMCPVersion.string)
        XCTAssertEqual(p.terminationStatus, 0)
    }

    /// `stderrText()` 는 메모리 버퍼만 읽는다 — 자식이 멎어도 안 멈춘다는 것을 20초 기다리지 않고 잰다.
    /// 서버는 `setUp` 에서 이미 볼트 줄을 stderr 에 찍었으니 그 문구가 버퍼에 들어올 때까지 짧게 폴링하고,
    /// 매 호출이 즉시 반환하는지(<1초) 도 같이 확인한다.
    func testStderrIsCapturedWithoutBlocking() throws {
        let deadline = Date().addingTimeInterval(2)
        var text = ""
        while Date() < deadline {
            let callStart = Date()
            text = mcp.stderrText()
            XCTAssertLessThan(Date().timeIntervalSince(callStart), 1,
                              "stderrText() 가 블로킹했다 — 버퍼가 아니라 파이프를 직접 읽은 것처럼 보인다")
            if text.contains("[clonie-mcp") { break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertTrue(text.contains("[clonie-mcp"), "stderr 버퍼에 부팅 로그가 안 들어왔다: \(text)")
    }
}
