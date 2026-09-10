import Foundation

/// Explicit, isolated QA launch settings. A missing setting must never fall back to a user's vault.
public struct QASessionConfiguration: Equatable, Sendable {
    public let id: String
    public let vaultURL: URL
    public var outputDirectory: String { "/tmp/clonie-qa-\(id)" }
    public func signal(_ action: String) -> String { "com.local.clonie.qa.\(action).\(id)" }

    public enum ConfigurationError: Error { case invalidSession, invalidVault }

    public init(environment: [String: String]) throws {
        guard let id = environment["CLONIE_QA_SESSION"], !id.isEmpty, id.count <= 64,
              id.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")).contains($0) })
        else { throw ConfigurationError.invalidSession }
        guard let path = environment["CLONIE_QA_VAULT"], path.hasPrefix("/"), path != "/",
              !path.contains("\0"), !path.split(separator: "/").contains("..") else { throw ConfigurationError.invalidVault }
        let vaultURL = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        guard vaultURL.path != "/" else { throw ConfigurationError.invalidVault }
        self.id = id
        self.vaultURL = vaultURL
    }
}
