import Foundation

/// Errors raised while validating or reading the session sidecar.
public enum SessionStoreError: Error, Equatable, Sendable, LocalizedError {
    case vaultMissing(String)
    case vaultNotDirectory(String)
    case differentVault(expected: String, actual: String)
    case invalidSessionID(String)
    case sessionNotFound(String)
    case invalidMetadataPath(String)
    case symbolicLinkPath(String)
    case invalidSessionFile(String)
    case identifierMismatch(expected: String, found: String)
    case corruptSession(id: String, underlying: String)
    case unknownSchemaVersion(found: Int, supported: Int)
    case invalidSpeaker(String)

    public var errorDescription: String? {
        switch self {
        case .vaultMissing(let path): return "세션 볼트가 없다: \(path)"
        case .vaultNotDirectory(let path): return "세션 볼트가 폴더가 아니다: \(path)"
        case .differentVault(let expected, let actual):
            return "세션이 다른 볼트에 묶여 있다: \(expected) / \(actual)"
        case .invalidSessionID(let id): return "세션 식별자가 표준 UUID가 아니다: \(id)"
        case .sessionNotFound(let id): return "세션을 찾을 수 없다: \(id)"
        case .invalidMetadataPath(let path): return "세션 메타데이터 경로가 폴더가 아니다: \(path)"
        case .symbolicLinkPath(let path): return "세션 메타데이터 심볼릭 링크를 거부했다: \(path)"
        case .invalidSessionFile(let path): return "세션 파일 이름이 올바르지 않다: \(path)"
        case .identifierMismatch(let expected, let found):
            return "세션 파일 이름과 기록 식별자가 다르다: \(expected) / \(found)"
        case .corruptSession(let id, let underlying):
            return "세션 JSON을 읽을 수 없다 (\(id)): \(underlying)"
        case .unknownSchemaVersion(let found, let supported):
            return "지원하지 않는 세션 스키마 판이다: \(found), 지원: \(supported)"
        case .invalidSpeaker(let speaker): return "세션 발화자의 값이 올바르지 않다: \(speaker)"
        }
    }
}

/// A session file that could not be read while other valid records remained usable.
/// The file is never changed or removed as part of listing or recovery.
public struct SessionFileIssue: Equatable, Sendable {
    public var path: String
    public var message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }
}

/// Valid session records and diagnostics for files that were left untouched.
public struct SessionListResult: Equatable, Sendable {
    public var records: [SessionRecord]
    public var issues: [SessionFileIssue]

    public init(records: [SessionRecord], issues: [SessionFileIssue]) {
        self.records = records
        self.issues = issues
    }
}

/// Atomic persistence for one vault's conversation sessions.
public actor SessionStore {
    public let vaultURL: URL

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(vaultURL: URL, fileManager: FileManager = .default) {
        self.vaultURL = vaultURL.standardizedFileURL
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    /// Saves one record at `.clonie/sessions/<id>.json`.
    public func save(_ record: SessionRecord) throws {
        try ensureVaultExists()
        try validate(record)
        guard let sessionsURL = try sessionsDirectory(create: true) else {
            throw SessionStoreError.invalidMetadataPath(vaultURL.path)
        }
        let fileURL = sessionsURL.appendingPathComponent(record.id + ".json", isDirectory: false)
        try ensureNoSymbolicLink(at: fileURL)

        let data = try encoder.encode(record)
        try AtomicFile.write(data, to: fileURL, fileManager: fileManager)
    }

    public func load(id: String) throws -> SessionRecord {
        try ensureVaultExists()
        try validateCanonicalID(id)
        guard let sessionsURL = try sessionsDirectory(create: false) else {
            throw SessionStoreError.sessionNotFound(id)
        }
        let fileURL = sessionsURL.appendingPathComponent(id + ".json", isDirectory: false)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw SessionStoreError.sessionNotFound(id)
        }
        try ensureNoSymbolicLink(at: fileURL)
        return try readRecord(from: fileURL, expectedID: id)
    }

    /// Lists readable canonical session files, newest by start time first.
    /// Invalid files remain on disk and are available through `listWithIssues()`.
    public func list() throws -> [SessionRecord] {
        try listWithIssues().records
    }

    /// Lists readable sessions and reports each unreadable JSON file without
    /// changing it or preventing other records from being used.
    public func listWithIssues() throws -> SessionListResult {
        try ensureVaultExists()
        guard let sessionsURL = try sessionsDirectory(create: false) else {
            return SessionListResult(records: [], issues: [])
        }

        let urls = try fileManager.contentsOfDirectory(
            at: sessionsURL, includingPropertiesForKeys: [.isDirectoryKey], options: [])
        var records: [SessionRecord] = []
        var issues: [SessionFileIssue] = []
        records.reserveCapacity(urls.count)

        for url in urls {
            do {
                try ensureNoSymbolicLink(at: url)
                let values = try url.resourceValues(forKeys: [.isDirectoryKey])
                if values.isDirectory == true { continue }
                guard url.pathExtension == "json" else { continue }
                let id = url.deletingPathExtension().lastPathComponent
                guard Self.isCanonicalUUID(id) else {
                    throw SessionStoreError.invalidSessionFile(url.path)
                }
                records.append(try readRecord(from: url, expectedID: id))
            } catch {
                issues.append(SessionFileIssue(
                    path: url.path,
                    message: error.localizedDescription))
            }
        }

        records.sort {
            if $0.startedAt != $1.startedAt { return $0.startedAt > $1.startedAt }
            return $0.id < $1.id
        }
        issues.sort { $0.path < $1.path }
        return SessionListResult(records: records, issues: issues)
    }

    /// Marks sessions left in a running state by a previous process as
    /// interrupted. It only changes lifecycle metadata; microphone restart is
    /// deliberately outside this store.
    @discardableResult
    public func recoverInterrupted() throws -> Int {
        var records = try listWithIssues().records
        let now = Date().timeIntervalSince1970
        var recovered = 0
        var recoveredRecords: [SessionRecord] = []

        for index in records.indices {
            switch records[index].state {
            case .preparing, .active, .paused, .finishing:
                records[index].state = .interrupted
                records[index].endedAt = now
                records[index].events.append(SessionLifecycleEvent(
                    kind: "interrupted", time: now, detail: "Recovered after restart"))
                recovered += 1
                recoveredRecords.append(records[index])
            case .completed, .interrupted:
                continue
            }
        }

        for record in recoveredRecords {
            try save(record)
        }
        return recovered
    }
}

private extension SessionStore {
    static func isCanonicalUUID(_ value: String) -> Bool {
        guard let uuid = UUID(uuidString: value) else { return false }
        return value == uuid.uuidString.lowercased()
    }

    func validateCanonicalID(_ id: String) throws {
        guard Self.isCanonicalUUID(id) else {
            throw SessionStoreError.invalidSessionID(id)
        }
    }

    func validate(_ record: SessionRecord) throws {
        guard record.schemaVersion == SessionRecord.currentSchemaVersion else {
            throw SessionStoreError.unknownSchemaVersion(
                found: record.schemaVersion, supported: SessionRecord.currentSchemaVersion)
        }
        try validateCanonicalID(record.id)
        let actualVaultPath = vaultURL.path
        guard record.vaultPath == actualVaultPath else {
            throw SessionStoreError.differentVault(expected: record.vaultPath, actual: actualVaultPath)
        }
        for utterance in record.utterances {
            guard utterance.who == "me" || utterance.who == "them" else {
                throw SessionStoreError.invalidSpeaker(utterance.who)
            }
        }
    }

    func ensureVaultExists() throws {
        guard fileManager.fileExists(atPath: vaultURL.path) else {
            throw SessionStoreError.vaultMissing(vaultURL.path)
        }
        let values = try vaultURL.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else {
            throw SessionStoreError.vaultNotDirectory(vaultURL.path)
        }
    }

    func sessionsDirectory(create: Bool) throws -> URL? {
        let metadataURL = vaultURL.appendingPathComponent(".clonie", isDirectory: true)
        try ensureNoSymbolicLink(at: metadataURL)
        if !fileManager.fileExists(atPath: metadataURL.path) {
            guard create else { return nil }
            try fileManager.createDirectory(at: metadataURL, withIntermediateDirectories: false)
        } else {
            try ensureDirectory(at: metadataURL)
        }

        let sessionsURL = metadataURL.appendingPathComponent("sessions", isDirectory: true)
        try ensureNoSymbolicLink(at: sessionsURL)
        if !fileManager.fileExists(atPath: sessionsURL.path) {
            guard create else { return nil }
            try fileManager.createDirectory(at: sessionsURL, withIntermediateDirectories: false)
        } else {
            try ensureDirectory(at: sessionsURL)
        }
        return sessionsURL
    }

    func ensureDirectory(at url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else {
            throw SessionStoreError.invalidMetadataPath(url.path)
        }
    }

    func ensureNoSymbolicLink(at url: URL) throws {
        if (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil {
            throw SessionStoreError.symbolicLinkPath(url.path)
        }
    }

    func readRecord(from url: URL, expectedID: String) throws -> SessionRecord {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SessionStoreError.corruptSession(id: expectedID, underlying: String(describing: error))
        }

        if let object = try? JSONSerialization.jsonObject(with: data),
           let dictionary = object as? [String: Any],
           let schemaVersion = dictionary["schemaVersion"] as? Int,
           schemaVersion != SessionRecord.currentSchemaVersion {
            throw SessionStoreError.unknownSchemaVersion(
                found: schemaVersion, supported: SessionRecord.currentSchemaVersion)
        }

        let record: SessionRecord
        do {
            record = try decoder.decode(SessionRecord.self, from: data)
        } catch let error as SessionStoreError {
            throw error
        } catch {
            throw SessionStoreError.corruptSession(id: expectedID, underlying: String(describing: error))
        }
        guard record.id == expectedID else {
            throw SessionStoreError.identifierMismatch(expected: expectedID, found: record.id)
        }
        try validate(record)
        return record
    }
}
