import Foundation

/// 서버가 자기를 소개할 때 쓰는 판. `clonie-mcp --version` 이 이걸 찍는다.
public enum ClonieMCPVersion {
    public static let string = "0.2.0"

    /// The plugin must not connect to older servers that wrote Markdown immediately.
    public static let writeContract = "proposal-v1"
}
