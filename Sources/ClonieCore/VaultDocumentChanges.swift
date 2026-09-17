import Darwin
import Foundation

/// The exact Markdown bytes are retained so restoration also preserves unknown frontmatter and encoding.
public struct VaultDocumentSnapshot: Codable, Equatable, Sendable {
    public let title: String
    public let body: String
    public let bytes: Data
    public let fingerprint: String
    public var markdown: String {
        String(data: bytes, encoding: .utf8) ?? String(data: bytes, encoding: .utf16) ?? String(decoding: bytes, as: UTF8.self)
    }

    init(fragment: Fragment, bytes: Data, path: String) {
        title = fragment.title
        body = fragment.body
        self.bytes = bytes
        fingerprint = VaultStore.fileRevision(data: bytes, relativePath: path).fingerprint
    }
}

public struct VaultDocumentChange: Codable, Equatable, Identifiable, Sendable {
    public enum Operation: String, Codable, Sendable { case create, update }
    public let id: String
    public let source: String
    public let fragmentID: String
    public let path: String
    public let title: String
    public let operation: Operation
    public let performedAt: Date
    public var reviewedAt: Date?
    public var restoredAt: Date?
    public let before: VaultDocumentSnapshot?
    public let after: VaultDocumentSnapshot
    // A prepared record is never presented as successful without checking the actual after bytes.
    var applied: Bool
    var failed: Bool = false
    var restoringAt: Date?
}

public struct VaultDocumentChangeRestoreResult: Equatable, Sendable {
    public let warning: String?
}

extension VaultStore {
    public var documentChangesURL: URL { sidecarURL.appendingPathComponent("document-changes", isDirectory: true) }

    /// Cooperating Clonie processes serialize document saves and journal reads/updates.
    /// External editors do not honor this advisory lock; fingerprints remain the final check.
    func withDocumentWriteLock<T>(_ body: () throws -> T) throws -> T {
        try ensurePrivateDirectory(sidecarURL)
        let path = sidecarURL.appendingPathComponent("document-write.lock").path
        let fd = open(path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }

    private func ensurePrivateDirectory(_ url: URL) throws {
        if let attrs = try? fm.attributesOfItem(atPath: url.path) {
            guard attrs[.type] as? FileAttributeType == .typeDirectory else {
                throw VaultMutationError.outsideVault(url.lastPathComponent)
            }
        } else {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func changeURL(_ id: String) throws -> URL {
        guard UUID(uuidString: id) != nil else { throw VaultMutationError.operationNotFound(id) }
        try ensurePrivateDirectory(documentChangesURL)
        let url = documentChangesURL.appendingPathComponent(id + ".json")
        if let attrs = try? fm.attributesOfItem(atPath: url.path), attrs[.type] as? FileAttributeType != .typeRegular {
            throw VaultMutationError.outsideVault(id)
        }
        return url
    }

    private func writeChange(_ change: VaultDocumentChange) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        try AtomicFile.write(try encoder.encode(change), to: changeURL(change.id), fileManager: fm)
    }

    static func documentChangeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    private func readChange(_ id: String) throws -> VaultDocumentChange {
        let url = try changeURL(id)
        guard fm.fileExists(atPath: url.path) else { throw VaultMutationError.operationNotFound(id) }
        let record = try Self.documentChangeDecoder().decode(VaultDocumentChange.self, from: Data(contentsOf: url))
        guard record.id == id, record.source == "mcp" else { throw VaultMutationError.corruptRecord(id) }
        return record
    }

    /// Caller holds the write lock and has checked the expected document revision.
    func prepareDocumentChange(fragment: Fragment, path: String, before: ParsedFile?, afterBytes: Data) throws -> VaultDocumentChange {
        let previous: VaultDocumentSnapshot?
        if let before {
            let url = try checkedDocumentURL(path)
            previous = VaultDocumentSnapshot(fragment: before.fragment, bytes: try Data(contentsOf: url), path: path)
        } else { previous = nil }
        let record = VaultDocumentChange(id: UUID().uuidString, source: "mcp", fragmentID: fragment.id,
                                         path: path, title: fragment.title, operation: before == nil ? .create : .update,
                                         performedAt: Date(), before: previous,
                                         after: VaultDocumentSnapshot(fragment: fragment, bytes: afterBytes, path: path), applied: false)
        // Failure here prevents the document write: there must be a durable before image first.
        try writeChange(record)
        return record
    }

    func cancelDocumentChange(_ prepared: VaultDocumentChange) {
        var record = prepared
        record.failed = true
        try? writeChange(record)
    }

    func commitDocumentChange(_ prepared: VaultDocumentChange) -> String? {
        var record = prepared
        record.applied = true
        do { try writeChange(record); return nil }
        catch { return "문서는 저장됐지만 변경 기록의 완료 표시를 저장하지 못했다. 같은 쓰기를 반복하지 말고 앱 변경 내역에서 확인한다." }
    }

    private func checkedDocumentURL(_ path: String) throws -> URL {
        let catalog = VaultEntryCatalog(rootURL: vaultURL, fileManager: fm)
        let entry = try catalog.entry(at: path)
        guard entry.kind == "file", entry.manageable,
              ["md", "markdown"].contains((path as NSString).pathExtension.lowercased()) else {
            throw VaultMutationError.outsideVault(path)
        }
        return try catalog.url(at: path)
    }

    private func diskFingerprint(_ path: String) throws -> String {
        let data = try Data(contentsOf: checkedDocumentURL(path))
        return Self.fileRevision(data: data, relativePath: path).fingerprint
    }

    private func recoverChange(_ original: VaultDocumentChange) -> VaultDocumentChange? {
        var record = original
        guard !record.failed else { return nil }
        if !record.applied {
            guard (try? diskFingerprint(record.path)) == record.after.fingerprint else { return nil }
            record.applied = true
            try? writeChange(record)
        }
        if let restoringAt = record.restoringAt, let before = record.before,
           (try? diskFingerprint(record.path)) == before.fingerprint {
            record.restoredAt = restoringAt
            record.reviewedAt = record.reviewedAt ?? restoringAt
            record.restoringAt = nil
            try? writeChange(record)
        }
        return record
    }

    public func documentChanges() throws -> [VaultDocumentChange] {
        // A read-only empty history must not initialize the sidecar and suppress legacy migration.
        guard fm.fileExists(atPath: documentChangesURL.path) else { return [] }
        return try withDocumentWriteLock {
            guard fm.fileExists(atPath: documentChangesURL.path) else { return [] }
            try ensurePrivateDirectory(documentChangesURL)
            let files = try fm.contentsOfDirectory(at: documentChangesURL, includingPropertiesForKeys: nil)
            return try files.filter { $0.pathExtension == "json" }.compactMap {
                recoverChange(try readChange($0.deletingPathExtension().lastPathComponent))
            }.sorted { $0.performedAt == $1.performedAt ? $0.id > $1.id : $0.performedAt > $1.performedAt }
        }
    }

    public func markDocumentChangeReviewed(id: String) throws {
        try withDocumentWriteLock {
            guard var record = recoverChange(try readChange(id)) else { throw VaultMutationError.operationNotFound(id) }
            if record.reviewedAt != nil { return }
            record.reviewedAt = Date()
            try writeChange(record)
        }
    }

    /// Restores exact prior bytes only while the document still matches this operation's after image.
    /// Creation has no deletion-based undo. Later external edits or path moves are never overwritten.
    public func restoreDocumentChange(id: String) throws -> VaultDocumentChangeRestoreResult {
        try withDocumentWriteLock {
            guard var record = recoverChange(try readChange(id)) else { throw VaultMutationError.operationNotFound(id) }
            guard record.restoredAt == nil else { throw VaultMutationError.alreadyUndone(id) }
            guard let before = record.before else { throw VaultMutationError.unsupportedUndo(id) }
            let url = try checkedDocumentURL(record.path)
            guard try diskFingerprint(record.path) == record.after.fingerprint else { throw VaultMutationError.conflict(record.path) }
            record.restoringAt = Date()
            try writeChange(record)
            // Recheck after recording intent, immediately before replacing document bytes.
            guard try diskFingerprint(record.path) == record.after.fingerprint else { throw VaultMutationError.conflict(record.path) }
            try AtomicFile.write(before.bytes, to: url, fileManager: fm)
            record.restoredAt = record.restoringAt
            record.reviewedAt = record.reviewedAt ?? record.restoringAt
            record.restoringAt = nil
            do { try writeChange(record); return VaultDocumentChangeRestoreResult(warning: nil) }
            catch { return VaultDocumentChangeRestoreResult(warning: "문서는 복원됐지만 기록의 완료 표시를 저장하지 못했다. 같은 복원을 반복하지 말고 다시 확인한다.") }
        }
    }
}
