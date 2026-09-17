import Foundation
import XCTest
@testable import ClonieCore

final class MCPConnectionSetupTests: XCTestCase {
    private let command = "/Applications/Clonie.app/Contents/MacOS/clonie-mcp"
    private let vault = "/Users/test/내 저장소"

    func testAbsentClientPreservesJSONCompatibility() throws {
        let text = try MCPConnectionSetup.text(command: command, vaultPath: vault)
        let explicit = try MCPConnectionSetup.text(client: "json", command: command, vaultPath: vault)
        XCTAssertEqual(text, explicit)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let servers = try XCTUnwrap(object["mcpServers"] as? [String: [String: Any]])
        XCTAssertEqual(servers["clonie"]?["command"] as? String, command)
        XCTAssertEqual(servers["clonie"]?["args"] as? [String], ["--vault", vault])
    }

    func testClientCommandsHaveExplicitStdioArgumentBoundaries() throws {
        XCTAssertEqual(try MCPConnectionSetup.text(client: "codex", command: command, vaultPath: vault),
                       "codex mcp add clonie -- '\(command)' --vault '\(vault)'")
        XCTAssertEqual(try MCPConnectionSetup.text(client: "claude", command: command, vaultPath: vault),
                       "claude mcp add --transport stdio --scope user clonie -- '\(command)' --vault '\(vault)'")
    }

    func testShellArgumentsPreserveQuotesWhitespaceAndSubstitutionCharacters() throws {
        let specialCommand = "/Applications/Clonie's $(printf expanded) `printf backtick`\n앱/clonie-mcp"
        let specialVault = "/Users/test/space ' quote \" dollar $VALUE \\ slash\n줄바꿈"
        for client in ["codex", "claude"] {
            let text = try MCPConnectionSetup.text(client: client, command: specialCommand, vaultPath: specialVault)
            // A local stub prints argv; no client binary or generated server is executed.
            let process = Process(), pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", "\(client)() { printf '%s\\0' \"$@\"; }; " + text]
            process.standardOutput = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
            let args = String(decoding: data, as: UTF8.self).split(separator: "\0", omittingEmptySubsequences: false).dropLast().map(String.init)
            let prefix = client == "codex" ? ["mcp", "add", "clonie", "--"] : ["mcp", "add", "--transport", "stdio", "--scope", "user", "clonie", "--"]
            XCTAssertEqual(args, prefix + [specialCommand, "--vault", specialVault])
        }
    }

    func testUnknownClientAndUnrepresentablePathsAreRejected() {
        XCTAssertThrowsError(try MCPConnectionSetup.text(client: "other", command: command, vaultPath: vault)) {
            XCTAssertEqual($0 as? MCPConnectionSetup.Failure, .unsupportedClient)
        }
        for path in ["", "bad\0path"] {
            XCTAssertThrowsError(try MCPConnectionSetup.text(client: "codex", command: command, vaultPath: path)) {
                XCTAssertEqual($0 as? MCPConnectionSetup.Failure, .invalidPath)
            }
        }
    }
}
