import Foundation

/// Markdown 본문에서 사람이 누른 로컬 파일 링크를 볼트 안의 실제 파일로 푼다.
///
/// 화면이 보내는 경로는 신뢰하지 않는다. 링크는 현재 md 파일 기준의 상대경로여야 하고,
/// symlink를 모두 푼 실제 목적지도 볼트 안이어야 한다. 숨은 사이드카와 실행 파일은 열지 않는다.
public struct VaultReferenceResolver {
    public enum ResolveError: Error, Equatable, LocalizedError {
        case invalidSource(String)
        case invalidReference(String)
        case outsideVault(String)
        case hidden(String)
        case unsupported(String)
        case missing(String)
        case executable(String)

        public var errorDescription: String? {
            switch self {
            case .invalidSource: return "출처를 단 md 파일의 경로가 올바르지 않다"
            case .invalidReference: return "로컬 상대경로 링크가 아니다"
            case .outsideVault: return "링크가 볼트 밖을 가리킨다"
            case .hidden: return "숨은 파일은 출처 링크로 열지 않는다"
            case .unsupported(let ext): return "열 수 없는 출처 형식이다: .\(ext)"
            case .missing: return "출처 파일을 찾지 못했다"
            case .executable: return "실행 파일은 출처 링크로 열지 않는다"
            }
        }
    }

    public static let supportedExtensions: Set<String> = [
        "md", "markdown", "txt", "pdf", "docx", "hwpx",
    ]

    public let vaultURL: URL
    private let fileManager: FileManager

    public init(vaultURL: URL, fileManager: FileManager = .default) {
        self.vaultURL = vaultURL
        self.fileManager = fileManager
    }

    public func resolve(reference rawReference: String,
                        from sourceRelativePath: String) throws -> URL {
        let root = vaultURL.resolvingSymlinksInPath().standardizedFileURL
        let source = try validatedSource(sourceRelativePath, root: root)
        let reference = try decodedPath(rawReference)

        let components = reference.split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
        guard !components.contains(where: { $0.isEmpty }) else {
            throw ResolveError.invalidReference(rawReference)
        }
        guard !components.contains(where: { $0.hasPrefix(".") && $0 != ".." && $0 != "." }) else {
            throw ResolveError.hidden(rawReference)
        }

        let lexical = source.deletingLastPathComponent()
            .appendingPathComponent(reference).standardizedFileURL
        guard isInside(lexical, root: root) else {
            throw ResolveError.outsideVault(rawReference)
        }
        let resolved = lexical.resolvingSymlinksInPath().standardizedFileURL
        guard isInside(resolved, root: root) else {
            throw ResolveError.outsideVault(rawReference)
        }
        let relativeResolved = String(resolved.path.dropFirst(root.path.count + 1))
        guard !relativeResolved.split(separator: "/").contains(where: { $0.hasPrefix(".") }) else {
            throw ResolveError.hidden(rawReference)
        }

        let ext = resolved.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(ext) else {
            throw ResolveError.unsupported(ext)
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: resolved.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              (try? resolved.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        else { throw ResolveError.missing(rawReference) }
        guard !fileManager.isExecutableFile(atPath: resolved.path) else {
            throw ResolveError.executable(rawReference)
        }
        return resolved
    }

    private func validatedSource(_ relativePath: String, root: URL) throws -> URL {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/"), !relativePath.contains("\\"),
              !hasScheme(relativePath),
              ["md", "markdown"].contains((relativePath as NSString).pathExtension.lowercased())
        else { throw ResolveError.invalidSource(relativePath) }
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains(where: {
            $0.isEmpty || $0 == "." || $0 == ".." || $0.hasPrefix(".")
        }) else { throw ResolveError.invalidSource(relativePath) }
        let source = root.appendingPathComponent(relativePath).standardizedFileURL
        guard isInside(source, root: root) else { throw ResolveError.invalidSource(relativePath) }
        return source
    }

    private func decodedPath(_ raw: String) throws -> String {
        var reference = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if reference.hasPrefix("<"), reference.hasSuffix(">") {
            reference.removeFirst()
            reference.removeLast()
        }
        // 파일 링크의 fragment/query는 Finder에 넘길 파일 이름이 아니다.
        reference = String(reference.prefix { $0 != "#" && $0 != "?" })
        guard !reference.isEmpty, !reference.hasPrefix("/"), !reference.hasPrefix("~"),
              !reference.contains("\\"), !reference.contains("\0"), !hasScheme(reference),
              let decoded = reference.removingPercentEncoding,
              !decoded.hasPrefix("/"), !decoded.hasPrefix("~"), !decoded.contains("\\"),
              !decoded.contains("\0"), !hasScheme(decoded)
        else { throw ResolveError.invalidReference(raw) }
        return decoded
    }

    private func hasScheme(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*:"#,
                    options: .regularExpression) != nil
    }

    private func isInside(_ url: URL, root: URL) -> Bool {
        url.path.hasPrefix(root.path + "/")
    }
}
