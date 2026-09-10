import Foundation
import CryptoKit
import PDFKit

/// Read-only originals shared by the app and its agent tools. Wiki output is never an input source.
public final class SourceCatalog {
    public struct Source: Codable, Equatable, Sendable {
        public let path: String
        public let hash: String
        public let bytes: Int
        public let supported: Bool
    }
    public struct Page: Codable, Sendable {
        public let path: String
        public let hash: String
        public let text: String
        public let offset: Int
        public let nextOffset: Int?
        public let totalCharacters: Int
        public let warnings: [String]
    }
    public enum SourceError: Error, CustomStringConvertible {
        case invalidPath, notAFile, unsupported(String), changedDuringRead
        public var description: String {
            switch self {
            case .invalidPath: return "원본 폴더 안의 상대 경로만 읽을 수 있다"
            case .notAFile: return "읽을 수 있는 일반 원본 파일이 아니다"
            case .unsupported(let ext): return "아직 읽지 못하는 원본 형식: \(ext)"
            case .changedDuringRead: return "읽는 동안 원본이 바뀌었다. 다시 읽어야 한다"
            }
        }
    }
    public let vaultURL: URL
    private let fm = FileManager.default
    public init(vaultURL: URL) { self.vaultURL = vaultURL.standardizedFileURL.resolvingSymlinksInPath() }
    private var hasRaw: Bool { fm.fileExists(atPath: vaultURL.appendingPathComponent("raw").path) }

    public func list() throws -> [Source] {
        let start = hasRaw ? vaultURL.appendingPathComponent("raw") : vaultURL
        guard start.resolvingSymlinksInPath().path.hasPrefix(vaultURL.path + "/") || start == vaultURL else {
            throw SourceError.invalidPath
        }
        guard let walk = fm.enumerator(at: start, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var result: [Source] = []
        for case let url as URL in walk {
            let relative = String(url.standardizedFileURL.path.dropFirst(vaultURL.path.count + 1))
            if relative == "wiki" || relative.hasPrefix("wiki/") { walk.skipDescendants(); continue }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true, values.isRegularFile == true else { continue }
            let safe = try sourceURL(relative)
            let data = try Data(contentsOf: safe, options: .mappedIfSafe)
            result.append(Source(path: relative, hash: Self.hash(data), bytes: data.count,
                                 supported: DocumentExtractor.extensions.contains(safe.pathExtension.lowercased())))
        }
        return result.sorted { $0.path < $1.path }
    }

    public func read(path: String, offset: Int = 0, limit: Int = 20_000) throws -> Page {
        let url = try sourceURL(path)
        guard DocumentExtractor.extensions.contains(url.pathExtension.lowercased()) else { throw SourceError.unsupported(url.pathExtension) }
        let before = try Data(contentsOf: url, options: .mappedIfSafe)
        let text = try DocumentExtractor.extractText(from: url)
        guard Self.hash(try Data(contentsOf: url, options: .mappedIfSafe)) == Self.hash(before) else { throw SourceError.changedDuringRead }
        let start = min(max(0, offset), text.count)
        let count = min(max(1, limit), 50_000)
        let content = String(text.dropFirst(start).prefix(count))
        let next = start + content.count
        var warnings: [String] = []
        if url.pathExtension.lowercased() == "pdf", let pdf = PDFDocument(url: url) {
            if (pdf.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                warnings.append("스캔 PDF의 글자 인식 결과다. 표·그림의 의미와 글자 인식 정확도는 확인이 필요하다.")
                if pdf.pageCount > DocumentExtractor.ocrPageLimit {
                    warnings.append("전체 \(pdf.pageCount)쪽 중 앞 \(DocumentExtractor.ocrPageLimit)쪽만 글자를 인식했다.")
                }
            } else if (0..<pdf.pageCount).contains(where: { (pdf.page(at: $0)?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                warnings.append("글자층이 없는 페이지가 있다. 해당 페이지의 그림·스캔 내용은 이 텍스트에 포함되지 않을 수 있다.")
            }
        }
        return Page(path: path, hash: Self.hash(before), text: content, offset: start,
                    nextOffset: next < text.count ? next : nil, totalCharacters: text.count, warnings: warnings)
    }

    private func sourceURL(_ path: String) throws -> URL {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\0"),
              !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." || $0.hasPrefix(".") }),
              parts.first != "wiki", !hasRaw || parts.first == "raw" else { throw SourceError.invalidPath }
        let url = vaultURL.appendingPathComponent(path).standardizedFileURL
        let resolved = url.resolvingSymlinksInPath()
        guard resolved.path.hasPrefix(vaultURL.path + "/"), resolved.path == url.path else { throw SourceError.invalidPath }
        let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true else { throw SourceError.notAFile }
        return url
    }
    private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
