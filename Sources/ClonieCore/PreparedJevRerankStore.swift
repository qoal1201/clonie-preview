import Foundation

/// One document scored by a completed Jev rerank request.
///
/// Candidate text is deliberately absent. Callers must resolve the current
/// document by `id`/`path` and compare `revision` before applying a score.
public struct PreparedJevRerankCandidate: Codable, Equatable, Sendable {
    public let id: String
    public let path: String
    public let revision: String
    public let score: Double

    public init(id: String, path: String, revision: String, score: Double) throws {
        self.id = id
        self.path = path
        self.revision = revision
        self.score = score
        try validate()
    }

    fileprivate func validate() throws {
        try PreparedJevRerankValidation.identifier(id, field: "candidate.id", maximumBytes: 1_024)
        try PreparedJevRerankValidation.path(path)
        try PreparedJevRerankValidation.identifier(
            revision, field: "candidate.revision", maximumBytes: 1_024)
        guard score.isFinite, (0 ... 1).contains(score) else {
            throw PreparedJevRerankStoreError.invalidScore
        }
    }
}

/// The complete context required to decide whether a prior rerank is still applicable.
public struct PreparedJevRerankRecord: Codable, Equatable, Sendable {
    public let query: String
    public let sourceID: String?
    public let scope: String?
    public let corpusFingerprint: String
    public let modelVersion: String
    public let policyVersion: String
    public let candidates: [PreparedJevRerankCandidate]

    public init(query: String,
                sourceID: String? = nil,
                scope: String? = nil,
                corpusFingerprint: String,
                modelVersion: String,
                policyVersion: String,
                candidates: [PreparedJevRerankCandidate]) throws {
        self.query = query
        self.sourceID = sourceID
        self.scope = scope
        self.corpusFingerprint = corpusFingerprint
        self.modelVersion = modelVersion
        self.policyVersion = policyVersion
        self.candidates = candidates
        try validate()
    }

    fileprivate func validate() throws {
        try PreparedJevRerankValidation.text(query, field: "query", maximumBytes: 8_192)
        if let sourceID {
            try PreparedJevRerankValidation.identifier(
                sourceID, field: "sourceID", maximumBytes: 1_024)
        }
        if let scope {
            try PreparedJevRerankValidation.identifier(scope, field: "scope", maximumBytes: 256)
        }
        try PreparedJevRerankValidation.identifier(
            corpusFingerprint, field: "corpusFingerprint", maximumBytes: 512)
        try PreparedJevRerankValidation.identifier(
            modelVersion, field: "modelVersion", maximumBytes: 256)
        try PreparedJevRerankValidation.identifier(
            policyVersion, field: "policyVersion", maximumBytes: 256)
        guard !candidates.isEmpty else { throw PreparedJevRerankStoreError.emptyCandidates }
        guard candidates.count <= PreparedJevRerankStore.maximumCandidatesPerRecord else {
            throw PreparedJevRerankStoreError.tooManyCandidates
        }
        var ids = Set<String>(), paths = Set<String>()
        for candidate in candidates {
            try candidate.validate()
            guard ids.insert(candidate.id).inserted, paths.insert(candidate.path).inserted else {
                throw PreparedJevRerankStoreError.duplicateCandidate
            }
        }
    }

    fileprivate var contextKey: ContextKey {
        ContextKey(query: query, sourceID: sourceID, scope: scope,
                   corpusFingerprint: corpusFingerprint,
                   modelVersion: modelVersion, policyVersion: policyVersion)
    }

}

public enum PreparedJevRerankStoreError: Error, Equatable, Sendable, LocalizedError {
    case vaultMissing(String)
    case vaultNotDirectory(String)
    case symbolicLinkPath(String)
    case metadataTooLarge
    case invalidMetadata
    case unknownSchemaVersion(Int)
    case tooManyRecords
    case tooManyCandidates
    case emptyCandidates
    case invalidValue(String)
    case invalidPath(String)
    case invalidScore
    case duplicateCandidate

    public var errorDescription: String? {
        switch self {
        case .vaultMissing(let path): return "Jev 준비 결과의 볼트가 없다: \(path)"
        case .vaultNotDirectory(let path): return "Jev 준비 결과의 볼트가 폴더가 아니다: \(path)"
        case .symbolicLinkPath(let path): return "Jev 준비 결과 메타데이터 경로가 심볼릭 링크다: \(path)"
        case .metadataTooLarge: return "Jev 준비 결과 메타데이터가 너무 크다"
        case .invalidMetadata: return "Jev 준비 결과 메타데이터가 올바르지 않다"
        case .unknownSchemaVersion(let version):
            return "지원하지 않는 Jev 준비 결과 메타데이터 판이다: \(version)"
        case .tooManyRecords: return "Jev 준비 결과 기록 수가 너무 많다"
        case .tooManyCandidates: return "Jev 준비 결과 후보 수가 너무 많다"
        case .emptyCandidates: return "Jev 준비 결과 후보가 비어 있다"
        case .invalidValue(let field): return "Jev 준비 결과 값이 올바르지 않다: \(field)"
        case .invalidPath(let path): return "Jev 준비 결과 경로가 올바르지 않다: \(path)"
        case .invalidScore: return "Jev 준비 결과 점수가 유한한 0...1 값이 아니다"
        case .duplicateCandidate: return "Jev 준비 결과 후보가 중복됐다"
        }
    }
}

/// A small, vault-scoped cache of successful prepared Jev reranks.
///
/// It does not perform inference, contact a service, or modify Markdown. A
/// caller may reuse a record only after its full context and live candidate
/// revisions still match.
public actor PreparedJevRerankStore {
    public static let currentSchemaVersion = 1
    public static let sidecarFileName = "prepared-jev-reranks.json"
    public static let maximumRecords = 12
    /// Matches the native Jev wire's bounded rerank candidate set.
    public static let maximumCandidatesPerRecord = 8
    public static let maximumFileBytes = 256 * 1_024

    public let vaultURL: URL
    public let recordsURL: URL

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(vaultURL: URL, fileManager: FileManager = .default) {
        self.vaultURL = vaultURL.standardizedFileURL
        self.recordsURL = vaultURL.standardizedFileURL
            .appendingPathComponent(".clonie", isDirectory: true)
            .appendingPathComponent(Self.sidecarFileName, isDirectory: false)
        self.fileManager = fileManager
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    /// Inserts or replaces the exact context, preserving at most the 12 most
    /// recently saved contexts. Invalid existing metadata is left untouched.
    public func save(_ record: PreparedJevRerankRecord) throws {
        try ensureVaultAndPaths()
        try record.validate()
        var records = try readRecords()
        records.removeAll { $0.contextKey == record.contextKey }
        records.append(record)
        if records.count > Self.maximumRecords {
            records.removeFirst(records.count - Self.maximumRecords)
        }
        try writeRecords(records)
    }

    public func loadAll() throws -> [PreparedJevRerankRecord] {
        try ensureVaultAndPaths()
        return try readRecords()
    }

    private func readRecords() throws -> [PreparedJevRerankRecord] {
        guard fileManager.fileExists(atPath: recordsURL.path) else { return [] }
        let attributes = try fileManager.attributesOfItem(atPath: recordsURL.path)
        if let size = attributes[.size] as? NSNumber, size.intValue > Self.maximumFileBytes {
            throw PreparedJevRerankStoreError.metadataTooLarge
        }
        do {
            let data = try Data(contentsOf: recordsURL, options: [.mappedIfSafe])
            guard data.count <= Self.maximumFileBytes else {
                throw PreparedJevRerankStoreError.metadataTooLarge
            }
            let file = try decoder.decode(PreparedJevReranksFile.self, from: data)
            guard file.schemaVersion == Self.currentSchemaVersion else {
                throw PreparedJevRerankStoreError.unknownSchemaVersion(file.schemaVersion)
            }
            guard file.records.count <= Self.maximumRecords else {
                throw PreparedJevRerankStoreError.tooManyRecords
            }
            var keys = Set<ContextKey>()
            for record in file.records {
                try record.validate()
                guard keys.insert(record.contextKey).inserted else {
                    throw PreparedJevRerankStoreError.invalidMetadata
                }
            }
            return file.records
        } catch let error as PreparedJevRerankStoreError {
            throw error
        } catch {
            throw PreparedJevRerankStoreError.invalidMetadata
        }
    }

    private func writeRecords(_ records: [PreparedJevRerankRecord]) throws {
        guard records.count <= Self.maximumRecords else {
            throw PreparedJevRerankStoreError.tooManyRecords
        }
        for record in records { try record.validate() }
        let data = try encoder.encode(PreparedJevReranksFile(
            schemaVersion: Self.currentSchemaVersion, records: records))
        guard data.count <= Self.maximumFileBytes else {
            throw PreparedJevRerankStoreError.metadataTooLarge
        }
        try AtomicFile.write(data, to: recordsURL, fileManager: fileManager)
    }

    private func ensureVaultAndPaths() throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: vaultURL.path, isDirectory: &isDirectory) else {
            throw PreparedJevRerankStoreError.vaultMissing(vaultURL.path)
        }
        guard isDirectory.boolValue else {
            throw PreparedJevRerankStoreError.vaultNotDirectory(vaultURL.path)
        }
        let sidecar = recordsURL.deletingLastPathComponent()
        if isSymbolicLink(sidecar) {
            throw PreparedJevRerankStoreError.symbolicLinkPath(sidecar.path)
        }
        if isSymbolicLink(recordsURL) {
            throw PreparedJevRerankStoreError.symbolicLinkPath(recordsURL.path)
        }
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
    }
}

private struct PreparedJevReranksFile: Codable {
    let schemaVersion: Int
    let records: [PreparedJevRerankRecord]
}

private struct ContextKey: Hashable {
    let query: String
    let sourceID: String?
    let scope: String?
    let corpusFingerprint: String
    let modelVersion: String
    let policyVersion: String
}

private enum PreparedJevRerankValidation {
    static func text(_ value: String, field: String, maximumBytes: Int) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.utf8.count <= maximumBytes,
              !value.contains("\0") else {
            throw PreparedJevRerankStoreError.invalidValue(field)
        }
    }

    static func identifier(_ value: String, field: String, maximumBytes: Int) throws {
        guard !value.isEmpty, value.utf8.count <= maximumBytes,
              !value.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7f }) else {
            throw PreparedJevRerankStoreError.invalidValue(field)
        }
    }

    static func path(_ value: String) throws {
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        guard !value.isEmpty, value.utf8.count <= 4_096,
              !value.hasPrefix("/"), !value.hasPrefix("~"), !value.contains("\\"),
              !value.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7f }),
              !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
              !VaultEntryCatalog.isExcluded(relativePath: value) else {
            throw PreparedJevRerankStoreError.invalidPath(value)
        }
    }
}
