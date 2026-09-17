import Foundation
import XCTest
import MCP
@testable import ClonieMCP

final class HandshakeCompatibilityTests: XCTestCase {
    func testStandardExperimentalObjectsInitializeAndListToolsOverStdio() throws {
        let vault = try MCPTestSupport.makeVault("handshake")
        defer { try? FileManager.default.removeItem(at: vault) }
        let client = StdioClient(binary: MCPTestSupport.productsDirectory.appendingPathComponent("clonie-mcp"),
                                 vault: vault, environment: MCPTestSupport.noModelEnvironment)
        try client.start()
        defer { client.stop() }
        let reply = try client.request(id: 1, method: "initialize", params: [
            "protocolVersion": "2025-11-25",
            "clientInfo": ["name": "object-capability-client", "version": "1"],
            "capabilities": ["experimental": ["example/extension": ["nested": ["enabled": true]]],
                             "roots": ["listChanged": true], "elicitation": ["form": [:], "url": [:]]]
        ])
        XCTAssertNil(reply["error"], "\(reply)")
        XCTAssertEqual(((reply["result"] as? [String: Any])?["serverInfo"] as? [String: Any])?["name"] as? String, "clonie")
        try client.notify(method: "notifications/initialized")
        let listed = try client.request(id: 2, method: "tools/list", params: [:])
        let names = ((listed["result"] as? [String: Any])?["tools"] as? [[String: Any]])?.compactMap { $0["name"] as? String }
        XCTAssertEqual(names?.sorted(), ToolServer.definitions.map(\.name).sorted())
    }

    func testOnlyUnsupportedObjectExtensionsAreRemoved() throws {
        let input = Data(#"{"jsonrpc":"2.0","id":7,"method":"initialize","params":{"protocolVersion":"2025-11-25","clientInfo":{"name":"test","version":"1"},"capabilities":{"experimental":{"object":{"enabled":true},"legacy":"kept"},"roots":{"listChanged":true},"elicitation":{"form":{}},"future":{"enabled":true}},"_meta":{"approval":"keep"}}}"#.utf8)
        let result = CompatibleStdioTransport.acceptingExperimentalCapabilities(input)
        let message = try XCTUnwrap(JSONSerialization.jsonObject(with: result) as? [String: Any])
        let params = try XCTUnwrap(message["params"] as? [String: Any])
        let caps = try XCTUnwrap(params["capabilities"] as? [String: Any])
        XCTAssertEqual(caps["experimental"] as? [String: String], ["legacy": "kept"])
        XCTAssertEqual((caps["roots"] as? [String: Bool])?["listChanged"], true)
        XCTAssertNotNil(caps["elicitation"])
        XCTAssertNotNil(caps["future"])
        XCTAssertEqual(params["_meta"] as? [String: String], ["approval": "keep"])
        _ = try JSONDecoder().decode(Initialize.Parameters.self, from: JSONSerialization.data(withJSONObject: params))
    }

    func testToolRequestsAndMalformedInputAreBytePreserved() {
        for text in [
            #"{"method":"tools/call","params":{"name":"vault_write","arguments":{"body":"preserve","experimental":{"object":{}}}},"_meta":{"approval":"required"}}"#,
            #"{"method":"initialize","params":{"capabilities":{"experimental":{"invalid":true}}}}"#,
            #"{"method":"initialize","params":{"capabilities":{}}}"#,
            "invalid json"
        ] {
            let data = Data(text.utf8)
            XCTAssertEqual(CompatibleStdioTransport.acceptingExperimentalCapabilities(data), data)
        }
    }
}
