import Foundation
import CryptoKit

public enum DocumentImportStatus: String, Codable, Sendable { case success, partial, failed, cancelled }
public enum DocumentImportStage: String, Codable, Sendable { case queued, preserving, preparing, converting, saving, completed }

public struct DocumentImportProgress: Codable, Sendable {
    public let id: String
    public let name: String
    public let stage: DocumentImportStage
    public let completed: Int
    public let total: Int
}

public struct DocumentImportResult: Codable, Sendable {
    public let id: String
    public let name: String
    public let status: DocumentImportStatus
    public let originalPath: String?
    public let markdownPath: String?
    public let message: String?
    public let warnings: [String]
    public let retryable: Bool
}

public struct DocumentConversion: Sendable {
    public let markdown: String
    public let partial: Bool
    public let warnings: [String]
    public init(markdown: String, partial: Bool = false, warnings: [String] = []) {
        self.markdown = markdown; self.partial = partial; self.warnings = warnings
    }
}

/// Only PDF/Word conversion requires a prepared runtime. Plain text and HWPX remain local.
public protocol DocumentConversionService: Sendable {
    func prepare() async throws
    func convert(_ source: URL) async throws -> DocumentConversion
    func cancel() async
}

/// Persists each original before attempting conversion. Receipts belong to the vault, so a
/// failed job can be retried after relaunch without duplicating its original or replacing edits.
public actor DocumentImporter {
    private let vault: URL
    private let converter: any DocumentConversionService
    private let fm = FileManager.default
    private var cancelled = false
    private var running = false

    public init(vaultURL: URL, runtimeRoot: URL? = nil, resourceDirectory: URL? = nil) {
        vault = vaultURL.standardizedFileURL.resolvingSymlinksInPath()
        converter = DoclingRuntime(runtimeRoot: runtimeRoot, resourceDirectory: resourceDirectory)
    }

    public init(vaultURL: URL, converter: any DocumentConversionService) {
        vault = vaultURL.standardizedFileURL.resolvingSymlinksInPath()
        self.converter = converter
    }

    public func cancel() async { cancelled = true; await converter.cancel() }

    public func prepare(onProgress: @Sendable (DocumentImportProgress) -> Void = { _ in }) async throws {
        onProgress(.init(id: "runtime", name: "문서 변환 준비", stage: .preparing, completed: 0, total: 1))
        try await converter.prepare()
        onProgress(.init(id: "runtime", name: "문서 변환 준비", stage: .completed, completed: 1, total: 1))
    }

    public func importFiles(urls: [URL], destination: String,
                            onProgress: @Sendable (DocumentImportProgress) -> Void = { _ in }) async -> [DocumentImportResult] {
        await performImport(urls: urls, destination: destination, resumeID: nil, onProgress: onProgress)
    }

    public func history() -> [DocumentImportResult] {
        guard let directory = try? safeURL(".clonie/imports"),
              let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        return files.filter { $0.pathExtension == "json" }.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }.compactMap { file in
            guard let safe = try? safeURL(relative(file)), let data = try? Data(contentsOf: safe),
                  let receipt = try? JSONDecoder().decode(Receipt.self, from: data),
                  receipt.id == file.deletingPathExtension().lastPathComponent,
                  let original = try? safeURL(receipt.originalPath), fm.fileExists(atPath: original.path) else { return nil }
            return result(receipt, name: receipt.name ?? original.lastPathComponent)
        }
    }

    public func retry(id: String, onProgress: @Sendable (DocumentImportProgress) -> Void = { _ in }) async -> DocumentImportResult {
        do {
            guard id.count == 64, id.allSatisfy({ $0.isHexDigit }) else { throw ImportError.receipt }
            let receipt = try JSONDecoder().decode(Receipt.self, from: Data(contentsOf: receiptURL(id)))
            guard receipt.id == id else { throw ImportError.receipt }
            let source = try safeURL(receipt.originalPath)
            let destination = receipt.destination ?? relative(source.deletingLastPathComponent().deletingLastPathComponent())
            return await performImport(urls: [source], destination: destination, resumeID: id, onProgress: onProgress)[0]
        } catch {
            return .init(id: id, name: "가져온 문서", status: .failed, originalPath: nil, markdownPath: nil,
                         message: Self.message(error), warnings: [], retryable: false)
        }
    }

    private func performImport(urls: [URL], destination: String, resumeID: String?,
                               onProgress: @Sendable (DocumentImportProgress) -> Void) async -> [DocumentImportResult] {
        guard !running else {
            return urls.map { .init(id: UUID().uuidString, name: $0.lastPathComponent, status: .failed,
                                   originalPath: nil, markdownPath: nil, message: "진행 중인 가져오기가 끝난 뒤 다시 시도해 주세요.", warnings: [], retryable: true) }
        }
        running = true; cancelled = false
        defer { running = false }
        var results: [DocumentImportResult] = []
        for (index, source) in urls.enumerated() {
            var name = source.lastPathComponent
            var id = UUID().uuidString
            var record: Receipt?
            func progress(_ stage: DocumentImportStage) {
                onProgress(.init(id: id, name: name, stage: stage,
                                 completed: stage == .completed ? index + 1 : index, total: urls.count))
            }
            do {
                try checkCancellation()
                let folder = try safeURL(destination, allowRoot: true)
                var isDirectory: ObjCBool = false
                guard fm.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else { throw ImportError.destination }
                let access = source.startAccessingSecurityScopedResource()
                defer { if access { source.stopAccessingSecurityScopedResource() } }
                let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else { throw ImportError.source }
                let bytes = try Data(contentsOf: source, options: .mappedIfSafe)
                let hash = Self.hash(bytes)
                let identity = (destination + "\0" + name).precomposedStringWithCanonicalMapping + "\0" + hash
                id = resumeID ?? Self.hash(Data(identity.utf8))
                progress(.queued)
                let receiptURL = try receiptURL(id)
                if fm.fileExists(atPath: receiptURL.path) {
                    record = try JSONDecoder().decode(Receipt.self, from: Data(contentsOf: receiptURL))
                    guard record?.id == id else { throw ImportError.receipt }
                    guard record?.sourceHash == hash else { throw ImportError.originalChanged }
                    name = record?.name ?? name
                }
                let ext = source.pathExtension.lowercased()
                let direct = ["md", "markdown"].contains(ext)
                if record == nil {
                    let originalFolder = direct ? folder : folder.appendingPathComponent("원본", isDirectory: true)
                    _ = try safeURL(relative(originalFolder), allowRoot: true)
                    try fm.createDirectory(at: originalFolder, withIntermediateDirectories: true)
                    let original = uniqueURL(in: originalFolder, name: name)
                    record = Receipt(id: id, sourceHash: hash, originalPath: relative(original), markdownPath: direct ? relative(original) : nil,
                                     name: name, destination: destination)
                    // Save the reservation first. If the process stops after the copy, retry recovers it.
                    try save(record!, to: receiptURL)
                }
                var receipt = record!
                let original = try safeURL(receipt.originalPath)
                progress(.preserving)
                if fm.fileExists(atPath: original.path) {
                    guard try Self.hash(Data(contentsOf: original)) == hash else { throw ImportError.originalChanged }
                } else {
                    try bytes.write(to: original, options: .withoutOverwriting)
                }
                try checkCancellation()
                if direct {
                    receipt.status = .success; receipt.markdownHash = hash; receipt.message = nil
                    try save(receipt, to: receiptURL); record = receipt
                    results.append(result(receipt, name: name)); progress(.completed); continue
                }
                if let path = receipt.markdownPath, fm.fileExists(atPath: try safeURL(path).path) {
                    let current = try Data(contentsOf: safeURL(path))
                    if receipt.status == .success || Self.hash(current) != receipt.markdownHash {
                        // A user's edited conversion is the same imported document, not a new job.
                        let edited = Self.hash(current) != receipt.markdownHash
                        results.append(result(receipt, name: name, warnings: edited ? ["이미 있는 변환 문서의 수정을 보존했습니다."] : []))
                        progress(.completed); continue
                    }
                }
                let conversion: DocumentConversion
                if ["pdf", "docx"].contains(ext) {
                    progress(.preparing)
                    try await converter.prepare()
                    try checkCancellation()
                    _ = try safeURL(receipt.originalPath)
                    guard try Self.hash(Data(contentsOf: original)) == hash else { throw ImportError.originalChanged }
                    progress(.converting)
                    conversion = try await converter.convert(original)
                } else {
                    progress(.converting)
                    let text = try await Task.detached { try DocumentExtractor.extractText(from: original) }.value
                    conversion = DocumentConversion(markdown: text, warnings: ext == "hwpx" ? ["HWPX 본문 텍스트입니다. 표·각주·머리말의 순서를 원본과 확인해 주세요."] : [])
                }
                try checkCancellation()
                _ = try safeURL(receipt.originalPath)
                guard try Self.hash(Data(contentsOf: original)) == hash else { throw ImportError.originalChanged }
                guard !conversion.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ImportError.empty }
                let markdownURL: URL
                if let path = receipt.markdownPath { markdownURL = try safeURL(path) }
                else {
                    markdownURL = uniqueURL(in: folder, name: URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent + ".md")
                    receipt.markdownPath = relative(markdownURL)
                    try save(receipt, to: receiptURL); record = receipt
                }
                // Link components are escaped independently, so names containing brackets, # or spaces work.
                let link = "원본/" + original.lastPathComponent
                let escapedLink = link.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~")))! }.joined(separator: "/")
                let header = "<!-- clonie:converted source-sha256=\(hash) -->\n[원본 보기](\(escapedLink))\n\n"
                let output = Data((header + conversion.markdown + "\n").utf8)
                progress(.saving)
                _ = try safeURL(relative(markdownURL))
                if fm.fileExists(atPath: markdownURL.path) {
                    guard let previous = receipt.markdownHash,
                          try Self.hash(Data(contentsOf: markdownURL)) == previous else { throw ImportError.markdownChanged }
                    try output.write(to: markdownURL, options: .atomic)
                } else {
                    // Reserve the digest before creating a new file, so an interrupted final
                    // receipt write can be recovered without mistaking our output for an edit.
                    receipt.markdownHash = Self.hash(output)
                    try save(receipt, to: receiptURL); record = receipt
                    try output.write(to: markdownURL, options: .withoutOverwriting)
                }
                receipt.markdownHash = Self.hash(output)
                receipt.status = conversion.partial ? .partial : .success
                receipt.warnings = conversion.warnings
                receipt.message = nil
                try save(receipt, to: receiptURL); record = receipt
                results.append(result(receipt, name: name))
            } catch {
                let isCancelled = cancelled || Task.isCancelled || error is CancellationError
                let preserved = record.flatMap { r -> String? in
                    guard let url = try? safeURL(r.originalPath), fm.fileExists(atPath: url.path) else { return nil }
                    return r.originalPath
                }
                let message = isCancelled ? "가져오기를 취소했습니다. 저장된 원본은 유지됩니다." : Self.message(error)
                if var receipt = record, preserved != nil {
                    receipt.status = isCancelled ? .cancelled : .partial
                    receipt.message = message
                    if let url = try? receiptURL(id) { try? save(receipt, to: url) }
                }
                results.append(.init(id: id, name: name, status: isCancelled ? .cancelled : (preserved == nil ? .failed : .partial),
                                     originalPath: preserved, markdownPath: record?.markdownPath.flatMap { path in
                                         guard let url = try? safeURL(path), fm.fileExists(atPath: url.path) else { return nil }; return path
                                     }, message: message, warnings: [], retryable: true))
            }
            progress(.completed)
        }
        return results
    }

    private struct Receipt: Codable {
        let id: String
        let sourceHash: String
        let originalPath: String
        var markdownPath: String?
        var name: String? = nil
        var destination: String? = nil
        var markdownHash: String? = nil
        var status: DocumentImportStatus = .partial
        var warnings: [String] = []
        var message: String? = nil
    }
    private func result(_ r: Receipt, name: String, warnings: [String] = []) -> DocumentImportResult {
        let markdown = r.markdownPath.flatMap { path -> String? in
            guard let url = try? safeURL(path), fm.fileExists(atPath: url.path) else { return nil }
            return path
        }
        let status: DocumentImportStatus = r.status == .success && markdown == nil ? .partial : r.status
        return .init(id: r.id, name: name, status: status, originalPath: r.originalPath, markdownPath: markdown,
              message: r.message ?? (r.status == .partial ? "일부 내용을 변환하지 못했습니다. 원본과 비교해 주세요." : nil),
              warnings: r.warnings + warnings, retryable: status != .success && warnings.isEmpty)
    }
    private func receiptURL(_ id: String) throws -> URL {
        let dir = try safeURL(".clonie/imports")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return try safeURL(".clonie/imports/\(id).json")
    }
    private func save(_ receipt: Receipt, to url: URL) throws {
        _ = try safeURL(relative(url))
        try JSONEncoder().encode(receipt).write(to: url, options: .atomic)
    }
    private func checkCancellation() throws { if cancelled || Task.isCancelled { throw CancellationError() } }
    private func relative(_ url: URL) -> String { String(url.standardizedFileURL.path.dropFirst(vault.path.count + 1)) }
    private func safeURL(_ path: String, allowRoot: Bool = false) throws -> URL {
        if path.isEmpty, allowRoot { return vault }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\0"), !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else { throw ImportError.destination }
        let url = vault.appendingPathComponent(path).standardizedFileURL
        guard url.path.hasPrefix(vault.path + "/"), url.resolvingSymlinksInPath().path == url.path else { throw ImportError.destination }
        return url
    }
    private func uniqueURL(in folder: URL, name: String) -> URL {
        var candidate = folder.appendingPathComponent(name)
        let base = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        var suffix = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) (\(suffix))" + (ext.isEmpty ? "" : ".\(ext)")); suffix += 1
        }
        return candidate
    }
    private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private enum ImportError: Error { case destination, source, receipt, originalChanged, markdownChanged, empty }
    private static func message(_ error: Error) -> String {
        if let error = error as? DocumentExtractor.ExtractError { return error.message }
        if let error = error as? DoclingRuntime.RuntimeError { return error.localizedDescription }
        switch error as? ImportError {
        case .destination: return "저장소 안의 실제 폴더를 선택해 주세요. 바로가기 폴더에는 저장할 수 없습니다."
        case .source: return "일반 파일만 가져올 수 있습니다."
        case .receipt: return "이전 가져오기 기록을 읽지 못했습니다."
        case .originalChanged: return "보관된 원본이 변경되어 재시도를 멈췄습니다. 변경된 파일을 보존했습니다."
        case .markdownChanged: return "변환 문서가 변경되어 덮어쓰지 않았습니다."
        case .empty: return "변환한 문서에서 글자를 찾지 못했습니다. 원본은 보존했습니다."
        default: return "파일을 가져오지 못했습니다. 폴더 권한과 여유 공간을 확인한 뒤 다시 시도해 주세요."
        }
    }
}
