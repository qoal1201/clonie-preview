import CryptoKit
import Foundation

/// Filesystem entries are independent of editable/indexed Markdown documents.
public struct VaultEntry: Codable, Equatable, Sendable {
    public let id: String
    public let path: String
    public let kind: String
    public let byteCount: Int
    public let revision: String
    public let manageable: Bool
}

public struct VaultEntryCatalog {
    public let rootURL: URL
    private let fm: FileManager

    public init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL.resolvingSymlinksInPath().standardizedFileURL
        self.fm = fileManager
    }

    /// Tool internals are not user documents; ordinary dotfiles and .github remain visible.
    public static func isExcluded(relativePath: String) -> Bool {
        relativePath.split(separator: "/").contains {
            [".git", ".clonie", ".build", ".swiftpm", "node_modules", ".venv", "__pycache__", ".pytest_cache", ".DS_Store"].contains(String($0))
                || $0.hasPrefix(".clonie-move-") || ($0.hasPrefix(".") && $0.contains(".tmp-"))
        }
    }

    public func entries() throws -> [VaultEntry] {
        var rows: [VaultEntry] = []
        func visit(_ directory: URL, prefix: String) throws {
            for url in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isPackageKey]) {
                let path = prefix.isEmpty ? url.lastPathComponent : prefix + "/" + url.lastPathComponent
                if Self.isExcluded(relativePath: path) { continue }
                let item = try entry(at: path)
                rows.append(item)
                if item.kind == "folder" { try visit(url, prefix: path) }
            }
        }
        try visit(rootURL, prefix: "")
        return rows.sorted { $0.path < $1.path }
    }

    /// Validates every parent; symbolic links are visible leaves, never traversal paths.
    public func url(at path: String) throws -> URL {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\0"),
              !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
              !Self.isExcluded(relativePath: path) else { throw VaultMutationError.invalidPath(path) }
        var cursor = rootURL
        for part in parts.dropLast() {
            cursor.appendPathComponent(String(part), isDirectory: true)
            let attrs = try fm.attributesOfItem(atPath: cursor.path)
            guard attrs[.type] as? FileAttributeType == .typeDirectory,
                  (try cursor.resourceValues(forKeys: [.isPackageKey])).isPackage != true
            else { throw VaultMutationError.outsideVault(path) }
        }
        return rootURL.appendingPathComponent(path).standardizedFileURL
    }

    public func entry(at path: String) throws -> VaultEntry {
        let url = try url(at: path)
        let attrs = try fm.attributesOfItem(atPath: url.path)
        let type = attrs[.type] as? FileAttributeType
        let package = type == .typeDirectory && (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) == true
        let kind = type == .typeSymbolicLink ? "symlink" : package ? "package" : type == .typeDirectory ? "folder" : "file"
        // POSIX permits literal backslashes. Show them without aborting the entire
        // catalog, while the mutation/reference protocol still rejects these paths.
        let manageable = !path.contains("\\") && !path.hasPrefix("~")
            && (type == .typeRegular || (type == .typeDirectory && !package))
        let device = (attrs[.systemNumber] as? NSNumber)?.stringValue
        let inode = (attrs[.systemFileNumber] as? NSNumber)?.stringValue
        let id = device != nil && inode != nil ? "fs:\(device!):\(inode!)" : "path:\(path)"
        let bytes = (attrs[.size] as? NSNumber)?.intValue ?? 0
        let modified = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let created = (attrs[.creationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let value = "\(id)|\(kind)|\(bytes)|\(modified)|\(created)"
        let hash = SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
        return VaultEntry(id: id, path: path, kind: kind, byteCount: bytes,
                          revision: hash, manageable: manageable)
    }
}
