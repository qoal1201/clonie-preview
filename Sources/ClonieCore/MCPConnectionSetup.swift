import Foundation

/// Formats connection instructions only; does not run commands or change client settings.
public enum MCPConnectionSetup {
    public enum Failure: Error, Equatable {
        case unsupportedClient
        case invalidPath
        case encodingFailed
    }

    public static func text(client: String? = nil, command: String, vaultPath: String) throws -> String {
        guard !command.isEmpty, !vaultPath.isEmpty,
              !command.contains("\0"), !vaultPath.contains("\0") else {
            throw Failure.invalidPath
        }
        switch client ?? "json" {
        case "codex":
            return "codex mcp add clonie -- \(shellQuote(command)) --vault \(shellQuote(vaultPath))"
        case "claude":
            return "claude mcp add --transport stdio --scope user clonie -- \(shellQuote(command)) --vault \(shellQuote(vaultPath))"
        case "json":
            let config = ["mcpServers": ["clonie": ["command": command, "args": ["--vault", vaultPath]]]]
            let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
            guard let text = String(data: data, encoding: .utf8) else { throw Failure.encodingFailed }
            return text
        default:
            throw Failure.unsupportedClient
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
