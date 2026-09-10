import Foundation

public struct VaultWorkspace: Equatable {
    public let versioned: VersionedLoadResult
    public let folders: [String]
    public let trashEntries: [VaultTrashEntry]
    public var document: CueDocument { versioned.result.document }
    public var revision: VaultRevision { versioned.revision }
    public var paths: [String: String] { versioned.result.paths }
    public var entries: [VaultEntry] { revision.entries.values.sorted { $0.path < $1.path } }
}

public struct VaultMutationResult: Equatable {
    public let workspace: VaultWorkspace
    public let operation: VaultOperationRecord?
    public let linkImpacts: [VaultLinkImpact]
    /// 새 파일을 만든 조작이면 그 파일의 조각 id. 다른 조작에서는 `nil`이다.
    public let createdID: String?
    public init(workspace: VaultWorkspace, operation: VaultOperationRecord?,
                linkImpacts: [VaultLinkImpact], createdID: String? = nil) {
        self.workspace = workspace
        self.operation = operation
        self.linkImpacts = linkImpacts
        self.createdID = createdID
    }
    public var document: CueDocument { workspace.document }
    public var revision: VaultRevision { workspace.revision }
    public var paths: [String: String] { workspace.paths }
    public var folders: [String] { workspace.folders }
    public var trashEntries: [VaultTrashEntry] { workspace.trashEntries }
}

public struct VaultOperationPreview: Equatable, Sendable {
    public let sourcePath: String
    public let destinationPath: String
    public let kind: VaultPathKind
    public let linkImpacts: [VaultLinkImpact]
}

public enum VaultPathKind: String, Codable, Equatable, Sendable { case file, folder }

public struct VaultLinkImpact: Codable, Equatable, Sendable {
    public let markdownPath: String
    public let reference: String
    public let oldTargetPath: String
    public let targetAfterMove: String
    public let resolvedAfterMove: String?
}

public struct VaultTrashEntry: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: VaultPathKind
    public let originalPath: String?
    public let storedRelativePath: String
    public let trashedAt: Date
    public var restoredAt: Date?
    public let legacy: Bool
}

public struct VaultOperationRecord: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case folderCreate, fileMove, folderMove, trashFile, trashFolder, restore
    }
    public let id: String
    public let kind: Kind
    public let sourcePath: String
    public let destinationPath: String
    public let trashEntryID: String?
    public let performedAt: Date
    public var undoneAt: Date?
}

public enum VaultMutationError: Error, Equatable, Sendable, LocalizedError {
    case differentVault
    case invalidPath(String)
    case outsideVault(String)
    case hiddenPath(String)
    case sourceMissing(String)
    case wrongKind(String)
    case unknownFragment(String)
    case occupied(String)
    case conflict(String)
    case selfDescendant(String)
    case operationNotFound(String)
    case alreadyUndone(String)
    case unsupportedUndo(String)
    case trashEntryNotFound(String)
    case legacyTrashNeedsDestination(String)
    case recoveryRequired(String)
    case corruptRecord(String)

    public var errorDescription: String? {
        switch self {
        case .differentVault: return "다른 볼트에서 읽은 기준선이다"
        case .invalidPath(let p): return "경로가 올바르지 않다: \(p)"
        case .outsideVault(let p): return "경로가 볼트 밖을 가리킨다: \(p)"
        case .hiddenPath(let p): return "숨은 경로는 정리할 수 없다: \(p)"
        case .sourceMissing(let p): return "원본을 찾지 못했다: \(p)"
        case .wrongKind(let p): return "파일과 폴더 종류가 맞지 않는다: \(p)"
        case .unknownFragment(let id): return "문서 id를 찾지 못했다: \(id)"
        case .occupied(let p): return "목적지에 이미 항목이 있다: \(p)"
        case .conflict(let p): return "읽은 뒤 파일이 바뀌었다: \(p)"
        case .selfDescendant(let p): return "폴더를 자기 하위로 옮길 수 없다: \(p)"
        case .operationNotFound(let id): return "조작 기록을 찾지 못했다: \(id)"
        case .alreadyUndone(let id): return "이미 되돌린 조작이다: \(id)"
        case .unsupportedUndo(let id): return "이 조작은 경로 되돌리기를 지원하지 않는다: \(id)"
        case .trashEntryNotFound(let id): return "휴지통 항목을 찾지 못했다: \(id)"
        case .legacyTrashNeedsDestination(let id): return "원래 경로 기록이 없어 복구 위치가 필요하다: \(id)"
        case .recoveryRequired(let p): return "원상복구하지 못해 휴지통에 원본을 보존했다: \(p)"
        case .corruptRecord(let p): return "조작 기록을 읽지 못했다: \(p)"
        }
    }
}

private struct VaultOperationJournal: Codable { var operations: [VaultOperationRecord] }

extension VaultStore {
    public var operationJournalURL: URL { sidecarURL.appendingPathComponent("vault-operations.json") }

    public func loadWorkspace() throws -> VaultWorkspace {
        let loaded = try loadVersioned()
        return VaultWorkspace(versioned: loaded, folders: loaded.revision.entries.values.filter { $0.kind == "folder" }.map(\.path).sorted(),
                              trashEntries: try listTrash())
    }

    /// 빈 폴더와 일반 dot 폴더를 포함한다. 도구 내부 경로·symlink·패키지는 내려가지 않는다.
    public func folderRelativePaths() throws -> [String] {
        try VaultEntryCatalog(rootURL: vaultURL, fileManager: fm).entries().filter { $0.kind == "folder" }.map(\.path)
    }
}

extension VaultStore {
    public func createFolder(at relativePath: String,
                             expecting revision: VaultRevision) throws -> VaultMutationResult {
        try validateRevisionVault(revision)
        let url = try checkedURL(relativePath, kind: .folder)
        try requireExistingFolder(url.deletingLastPathComponent(), relativePath: relativePath)
        try requireAvailable(url, excluding: nil, relativePath: relativePath)
        try fm.createDirectory(at: url, withIntermediateDirectories: false)
        do {
            let workspace = try loadWorkspace()
            let record = try recordOperation(kind: .folderCreate, source: "",
                                             destination: relativePath, trashEntryID: nil)
            return VaultMutationResult(workspace: workspace, operation: record, linkImpacts: [])
        } catch {
            try? removeDirectoryIfEmpty(url)
            _ = try? loadVersioned()
            throw error
        }
    }

    /// 기존 폴더 안에 빈 Markdown 문서를 create-only로 만든다.
    ///
    /// 문서 id는 경로와 독립적으로 만든다. 이동된 문서가 예전 경로 기반 id를 보존하므로
    /// 같은 경로를 다시 만들 때 id를 재사용하면 두 문서가 충돌한다. 기존 renderer가
    /// frontmatter에 id를 기록하므로 다시 읽어도 같은 id가 유지된다. 별도의 undo 기록은 만들지 않는다 — 사용자가 지우려는 경우 기존 휴지통
    /// 조작으로 되돌릴 수 있고, 새 조작 종류를 추가해 undo 의미를 넓힐 필요가 없다.
    public func createFile(at relativePath: String,
                           expecting revision: VaultRevision) throws -> VaultMutationResult {
        try validateRevisionVault(revision)
        guard ["md", "markdown"].contains((relativePath as NSString).pathExtension.lowercased())
        else { throw VaultMutationError.invalidPath(relativePath) }
        let url = try checkedURL(relativePath, kind: .file)
        try requireExistingFolder(url.deletingLastPathComponent(), relativePath: relativePath)
        try requireAvailable(url, excluding: nil, relativePath: relativePath)

        let id = UUID().uuidString.lowercased()
        let title = ((relativePath as NSString).deletingPathExtension as NSString).lastPathComponent
        let now = Date()
        let fragment = Fragment(id: id, title: title, body: "", questionIds: [],
                                createdAt: now, updatedAt: now)
        let text = MarkdownFragment.render(fragment)
        try writeNewAtomically(text, to: url, relativePath: relativePath)
        do {
            let workspace = try loadWorkspace()
            let createdID = workspace.paths.first(where: { $0.value == relativePath })?.key
            return VaultMutationResult(workspace: workspace, operation: nil,
                                       linkImpacts: [], createdID: createdID)
        } catch {
            // 우리가 쓴 바이트가 그대로일 때만 새 파일을 지운다. 다른 파일이나 사용자가
            // 같은 시각에 교체한 파일은 건드리지 않는다.
            if (try? Data(contentsOf: url)) == Data(text.utf8) {
                try? fm.removeItem(at: url)
            }
            _ = try? loadVersioned()
            throw error
        }
    }

    /// 이동과 같은 검사를 하지만 디스크를 바꾸지 않는다. 링크 확인창은 이 결과가 있을 때만 필요하다.
    public func previewMove(from sourcePath: String, to destinationPath: String,
                            expecting revision: VaultRevision) throws -> VaultOperationPreview {
        try validateRevisionVault(revision)
        let source = try existingVisibleURL(sourcePath)
        let kind = try pathKind(source)
        let destination = try checkedURL(destinationPath, kind: kind)
        if kind == .file {
            try guardFile(path: sourcePath, revision: revision)
        } else {
            try guardFolder(path: sourcePath, revision: revision)
            if destinationPath == sourcePath || destinationPath.hasPrefix(sourcePath + "/") {
                throw VaultMutationError.selfDescendant(destinationPath)
            }
        }
        try requireExistingFolder(destination.deletingLastPathComponent(), relativePath: destinationPath)
        try requireAvailable(destination, excluding: source, relativePath: destinationPath)
        return VaultOperationPreview(sourcePath: sourcePath, destinationPath: destinationPath,
            kind: kind, linkImpacts: linkImpactsMoving(from: sourcePath, to: destinationPath,
                                                       kind: kind, revision: revision))
    }

    public func renameFile(id: String, toFileName name: String,
                           expecting revision: VaultRevision) throws -> VaultMutationResult {
        guard !name.contains("/"), ["md", "markdown"].contains((name as NSString).pathExtension.lowercased())
        else { throw VaultMutationError.invalidPath(name) }
        let source = try fragmentPath(id, revision: revision)
        return try performMove(from: source, to: joined(parentPath(source), name), kind: .file,
                               expecting: revision, recordKind: .fileMove)
    }

    /// Explorer operations preserve the original bytes, including Markdown without an id header.
    public func renameEntry(at path: String, toName name: String,
                            expecting revision: VaultRevision) throws -> VaultMutationResult {
        guard !name.isEmpty, !name.contains("/") else { throw VaultMutationError.invalidPath(name) }
        return try moveEntry(from: path, to: joined(parentPath(path), name), expecting: revision)
    }

    public func moveEntry(at path: String, toFolder folder: String,
                          expecting revision: VaultRevision) throws -> VaultMutationResult {
        try moveEntry(from: path, to: joined(folder, (path as NSString).lastPathComponent), expecting: revision)
    }

    private func moveEntry(from source: String, to destination: String,
                           expecting revision: VaultRevision) throws -> VaultMutationResult {
        let preview = try previewMove(from: source, to: destination, expecting: revision)
        return try performPreparedMove(preview, expecting: revision,
            recordKind: preview.kind == .file ? .fileMove : .folderMove, preserveIdentities: false)
    }

    public func moveFile(id: String, toFolder folder: String,
                         expecting revision: VaultRevision) throws -> VaultMutationResult {
        let source = try fragmentPath(id, revision: revision)
        return try performMove(from: source,
            to: joined(folder, (source as NSString).lastPathComponent), kind: .file,
            expecting: revision, recordKind: .fileMove)
    }

    /// 대상 문서와 같은 이름의 폴더를 필요하면 만들고 그 아래로 옮긴다.
    /// 폴더 생성과 이동 중 하나라도 실패하면 새로 만든 빈 폴더도 되돌린다.
    public func moveFile(id: String, underFile targetID: String,
                         expecting revision: VaultRevision) throws -> VaultMutationResult {
        let preview = try previewMoveFile(id: id, underFile: targetID, expecting: revision)
        let folderPath = parentPath(preview.destinationPath)
        let folderURL = try checkedURL(folderPath, kind: .folder)
        var isDirectory: ObjCBool = false
        let existed = fm.fileExists(atPath: folderURL.path, isDirectory: &isDirectory)
        if existed && !isDirectory.boolValue { throw VaultMutationError.wrongKind(folderPath) }
        if !existed { try fm.createDirectory(at: folderURL, withIntermediateDirectories: false) }
        do {
            return try performPreparedMove(preview, expecting: revision, recordKind: .fileMove)
        } catch {
            if !existed { try? removeDirectoryIfEmpty(folderURL) }
            throw error
        }
    }

    public func previewMoveFile(id: String, underFile targetID: String,
                                expecting revision: VaultRevision) throws -> VaultOperationPreview {
        try validateRevisionVault(revision)
        let sourcePath = try fragmentPath(id, revision: revision)
        let targetPath = try fragmentPath(targetID, revision: revision)
        guard sourcePath != targetPath else { throw VaultMutationError.invalidPath(targetPath) }
        try guardFile(path: sourcePath, revision: revision)
        try guardFile(path: targetPath, revision: revision)

        let targetStem = ((targetPath as NSString).deletingPathExtension as NSString).lastPathComponent
        let folderPath = joined(parentPath(targetPath), targetStem)
        let folderURL = try checkedURL(folderPath, kind: .folder)
        try requireExistingFolder(folderURL.deletingLastPathComponent(), relativePath: folderPath)
        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: folderURL.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { throw VaultMutationError.wrongKind(folderPath) }
            let values = try? folderURL.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values?.isSymbolicLink != true else { throw VaultMutationError.outsideVault(folderPath) }
        } else {
            try requireAvailable(folderURL, excluding: nil, relativePath: folderPath)
        }
        let destinationPath = joined(folderPath, (sourcePath as NSString).lastPathComponent)
        let destination = try checkedURL(destinationPath, kind: .file)
        if fm.fileExists(atPath: folderURL.path) {
            try requireAvailable(destination, excluding: try existingVisibleURL(sourcePath),
                                 relativePath: destinationPath)
        }
        return VaultOperationPreview(sourcePath: sourcePath, destinationPath: destinationPath,
            kind: .file, linkImpacts: linkImpactsMoving(from: sourcePath, to: destinationPath,
                                                        kind: .file, revision: revision))
    }

    public func renameFolder(at source: String, toName name: String,
                             expecting revision: VaultRevision) throws -> VaultMutationResult {
        guard !name.contains("/") else { throw VaultMutationError.invalidPath(name) }
        return try performMove(from: source, to: joined(parentPath(source), name), kind: .folder,
                               expecting: revision, recordKind: .folderMove)
    }

    public func moveFolder(at source: String, toFolder folder: String,
                           expecting revision: VaultRevision) throws -> VaultMutationResult {
        return try performMove(from: source,
            to: joined(folder, (source as NSString).lastPathComponent), kind: .folder,
            expecting: revision, recordKind: .folderMove)
    }

    private func performMove(from sourcePath: String, to destinationPath: String,
                             kind: VaultPathKind, expecting revision: VaultRevision,
                             recordKind: VaultOperationRecord.Kind) throws -> VaultMutationResult {
        let preview = try previewMove(from: sourcePath, to: destinationPath, expecting: revision)
        guard preview.kind == kind else { throw VaultMutationError.wrongKind(sourcePath) }
        return try performPreparedMove(preview, expecting: revision, recordKind: recordKind)
    }

    private func performPreparedMove(_ preview: VaultOperationPreview,
                                     expecting revision: VaultRevision,
                                     recordKind: VaultOperationRecord.Kind,
                                     preserveIdentities: Bool = true) throws -> VaultMutationResult {
        let sourcePath = preview.sourcePath
        let destinationPath = preview.destinationPath
        let kind = preview.kind
        let source = try existingVisibleURL(sourcePath)
        let destination = try checkedURL(destinationPath, kind: kind)
        if kind == .file { try guardFile(path: sourcePath, revision: revision) }
        else { try guardFolder(path: sourcePath, revision: revision) }
        try requireExistingFolder(destination.deletingLastPathComponent(), relativePath: destinationPath)
        try requireAvailable(destination, excluding: source, relativePath: destinationPath)
        let identities = preserveIdentities ? try identityPreparations(in: sourcePath, kind: kind, revision: revision) : []
        do {
            try applyIdentities(identities)
            try moveItem(source, to: destination)
        } catch {
            try? rollbackIdentities(identities)
            throw error
        }
        do {
            let workspace = try loadWorkspace()
            let record = try recordOperation(kind: recordKind, source: sourcePath,
                                             destination: destinationPath, trashEntryID: nil)
            return VaultMutationResult(workspace: workspace, operation: record,
                                       linkImpacts: preview.linkImpacts)
        } catch {
            try? moveItem(destination, to: source)
            try? rollbackIdentities(identities)
            _ = try? loadVersioned()
            throw error
        }
    }
}

extension VaultStore {
    public func previewTrash(at path: String,
                             expecting revision: VaultRevision) throws -> VaultOperationPreview {
        try validateRevisionVault(revision)
        let source = try existingVisibleURL(path)
        let kind = try pathKind(source)
        if kind == .file { try guardFile(path: path, revision: revision) }
        else { try guardFolder(path: path, revision: revision) }
        return VaultOperationPreview(sourcePath: path, destinationPath: ".clonie/trash",
            kind: kind, linkImpacts: linkImpactsTrashing(path, kind: kind, revision: revision))
    }

    public func trashFile(id: String,
                          expecting revision: VaultRevision) throws -> VaultMutationResult {
        let source = try fragmentPath(id, revision: revision)
        return try performTrash(path: source, kind: .file, expecting: revision)
    }

    public func trashFolder(at path: String,
                            expecting revision: VaultRevision) throws -> VaultMutationResult {
        try performTrash(path: path, kind: .folder, expecting: revision)
    }

    private func performTrash(path: String, kind: VaultPathKind,
                              expecting revision: VaultRevision) throws -> VaultMutationResult {
        let preview = try previewTrash(at: path, expecting: revision)
        guard preview.kind == kind else { throw VaultMutationError.wrongKind(path) }
        let source = try existingVisibleURL(path)
        let identities = try identityPreparations(in: path, kind: kind, revision: revision)
        let id = UUID().uuidString
        let entryFolder = trashURL.appendingPathComponent(id, isDirectory: true)
        let payload = entryFolder.appendingPathComponent(source.lastPathComponent,
                                                          isDirectory: kind == .folder)
        let stored = ".clonie/trash/\(id)/\(source.lastPathComponent)"
        let entry = VaultTrashEntry(id: id, kind: kind, originalPath: path,
            storedRelativePath: stored, trashedAt: Date(), restoredAt: nil, legacy: false)
        try fm.createDirectory(at: trashURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: entryFolder, withIntermediateDirectories: false)
        do {
            try writeTrashEntry(entry)
            try applyIdentities(identities)
            try moveItem(source, to: payload)
            let recordKind: VaultOperationRecord.Kind = kind == .file ? .trashFile : .trashFolder
            let workspace = try loadWorkspace()
            let record = try recordOperation(kind: recordKind, source: path,
                                             destination: stored, trashEntryID: id)
            return VaultMutationResult(workspace: workspace, operation: record,
                                       linkImpacts: preview.linkImpacts)
        } catch {
            if fm.fileExists(atPath: payload.path) {
                do {
                    try moveItem(payload, to: source)
                } catch {
                    // payload가 유일한 사본일 수 있다. metadata와 함께 그대로 두면 listTrash/복구 UI에서
                    // 다시 찾을 수 있다. 이 경우 entryFolder를 재귀 삭제해서는 안 된다.
                    _ = try? loadVersioned()
                    throw VaultMutationError.recoveryRequired(stored)
                }
            }
            try? rollbackIdentities(identities)
            try? fm.removeItem(at: trashEntryMetadataURL(id))
            try? removeDirectoryIfEmpty(entryFolder)
            _ = try? loadVersioned()
            throw error
        }
    }

    public func listTrash() throws -> [VaultTrashEntry] {
        guard fm.fileExists(atPath: trashURL.path) else { return [] }
        let urls = try fm.contentsOfDirectory(at: trashURL,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles])
        var out: [VaultTrashEntry] = []
        for url in urls {
            let metadata = url.appendingPathComponent("entry.json")
            if let data = try? Data(contentsOf: metadata),
               let entry = try? FragmentStore.makeDecoder().decode(VaultTrashEntry.self, from: data),
               entry.restoredAt == nil {
                out.append(entry)
                continue
            }
            // 옛 평면 휴지통은 원래 폴더 기록이 없다. UI가 복구 목적지를 받아야만 움직인다.
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            let attrs = try? fm.attributesOfItem(atPath: url.path)
            out.append(VaultTrashEntry(id: "legacy:" + url.lastPathComponent, kind: .file,
                originalPath: nil, storedRelativePath: ".clonie/trash/" + url.lastPathComponent,
                trashedAt: (attrs?[.modificationDate] as? Date) ?? Date(timeIntervalSince1970: 0),
                restoredAt: nil, legacy: true))
        }
        return out.sorted { $0.trashedAt > $1.trashedAt }
    }

    public func restoreTrash(id: String, to requestedPath: String? = nil,
                             expecting revision: VaultRevision) throws -> VaultMutationResult {
        try validateRevisionVault(revision)
        guard var entry = try listTrash().first(where: { $0.id == id }) else {
            throw VaultMutationError.trashEntryNotFound(id)
        }
        guard let destinationPath = requestedPath ?? entry.originalPath else {
            throw VaultMutationError.legacyTrashNeedsDestination(id)
        }
        let source = actualURL(forStoredRelativePath: entry.storedRelativePath)
        guard fm.fileExists(atPath: source.path) else { throw VaultMutationError.sourceMissing(entry.storedRelativePath) }
        let destination = try checkedURL(destinationPath, kind: entry.kind)
        try requireExistingFolder(destination.deletingLastPathComponent(), relativePath: destinationPath)
        try requireAvailable(destination, excluding: nil, relativePath: destinationPath)
        let originalEntry = entry
        try moveItem(source, to: destination)
        do {
            if !entry.legacy {
                entry.restoredAt = Date()
                try writeTrashEntry(entry)
            }
            let workspace = try loadWorkspace()
            let record = try recordOperation(kind: .restore, source: entry.storedRelativePath,
                                             destination: destinationPath, trashEntryID: id)
            return VaultMutationResult(workspace: workspace, operation: record, linkImpacts: [])
        } catch {
            try? moveItem(destination, to: source)
            if !originalEntry.legacy { try? writeTrashEntry(originalEntry) }
            _ = try? loadVersioned()
            throw error
        }
    }

    /// 이동/rename undo는 파일 내용을 과거판으로 쓰지 않고 현재 항목의 경로만 되돌린다.
    public func undo(operationID: String,
                     expecting revision: VaultRevision) throws -> VaultMutationResult {
        var journal = try readJournal()
        guard let index = journal.operations.firstIndex(where: { $0.id == operationID }) else {
            throw VaultMutationError.operationNotFound(operationID)
        }
        let record = journal.operations[index]
        guard record.undoneAt == nil else { throw VaultMutationError.alreadyUndone(operationID) }
        if record.kind == .folderCreate {
            try validateRevisionVault(revision)
            let folder = try existingVisibleURL(record.destinationPath)
            guard try pathKind(folder) == .folder else {
                throw VaultMutationError.wrongKind(record.destinationPath)
            }
            guard (try fm.contentsOfDirectory(at: folder,
                                              includingPropertiesForKeys: nil)).isEmpty else {
                throw VaultMutationError.conflict(record.destinationPath)
            }
            try fm.removeItem(at: folder)
            do {
                let workspace = try loadWorkspace()
                journal.operations[index].undoneAt = Date()
                try writeJournal(journal)
                return VaultMutationResult(workspace: workspace,
                                           operation: journal.operations[index], linkImpacts: [])
            } catch {
                try? fm.createDirectory(at: folder, withIntermediateDirectories: false)
                _ = try? loadVersioned()
                throw error
            }
        }
        guard record.kind == .fileMove || record.kind == .folderMove else {
            throw VaultMutationError.unsupportedUndo(operationID)
        }
        let kind: VaultPathKind = record.kind == .fileMove ? .file : .folder
        let preview = try previewMove(from: record.destinationPath, to: record.sourcePath,
                                     expecting: revision)
        guard preview.kind == kind else { throw VaultMutationError.wrongKind(record.destinationPath) }
        let source = try existingVisibleURL(record.destinationPath)
        let destination = try checkedURL(record.sourcePath, kind: kind)
        try moveItem(source, to: destination)
        do {
            let workspace = try loadWorkspace()
            journal.operations[index].undoneAt = Date()
            try writeJournal(journal)
            return VaultMutationResult(workspace: workspace, operation: journal.operations[index],
                                       linkImpacts: preview.linkImpacts)
        } catch {
            try? moveItem(destination, to: source)
            _ = try? loadVersioned()
            throw error
        }
    }
}

private struct VaultIdentityPreparation {
    let relativePath: String
    let original: Data
    let withIdentity: Data
}

extension VaultStore {
    private func validateRevisionVault(_ revision: VaultRevision) throws {
        guard revision.vaultPath == vaultURL.standardizedFileURL.path else {
            throw VaultMutationError.differentVault
        }
    }

    private func fragmentPath(_ id: String, revision: VaultRevision) throws -> String {
        guard let path = revision.baseline[id]?.relativePath else {
            throw VaultMutationError.unknownFragment(id)
        }
        return path
    }

    private func actualRoot() -> URL { vaultURL.resolvingSymlinksInPath().standardizedFileURL }

    private func checkedURL(_ path: String, kind: VaultPathKind) throws -> URL {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("~"), !path.contains("\\") else {
            throw VaultMutationError.invalidPath(path)
        }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            throw VaultMutationError.invalidPath(path)
        }
        guard !VaultEntryCatalog.isExcluded(relativePath: path) else {
            throw VaultMutationError.hiddenPath(path)
        }
        let root = actualRoot()
        let url = root.appendingPathComponent(path, isDirectory: kind == .folder).standardizedFileURL
        guard url.path.hasPrefix(root.path + "/") else { throw VaultMutationError.outsideVault(path) }
        var cursor = root
        for component in parts.dropLast() {
            cursor.appendPathComponent(component, isDirectory: true)
            if fm.fileExists(atPath: cursor.path) {
                let attributes = try fm.attributesOfItem(atPath: cursor.path)
                guard attributes[.type] as? FileAttributeType == .typeDirectory,
                      (try cursor.resourceValues(forKeys: [.isPackageKey])).isPackage != true
                else { throw VaultMutationError.outsideVault(path) }
                cursor = cursor.resolvingSymlinksInPath().standardizedFileURL
                guard cursor.path == root.path || cursor.path.hasPrefix(root.path + "/") else {
                    throw VaultMutationError.outsideVault(path)
                }
            }
        }
        return url
    }

    private func existingVisibleURL(_ path: String) throws -> URL {
        let candidate = try checkedURL(path, kind: .folder) // 파일 확장자를 강제하지 않고 공통 경로만 검사
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: candidate.path, isDirectory: &isDir) else {
            throw VaultMutationError.sourceMissing(path)
        }
        let values = try? candidate.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values?.isSymbolicLink != true else { throw VaultMutationError.outsideVault(path) }
        guard (try? candidate.resourceValues(forKeys: [.isPackageKey]).isPackage) != true
        else { throw VaultMutationError.wrongKind(path) }
        return candidate
    }

    private func pathKind(_ url: URL) throws -> VaultPathKind {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
        if values.isDirectory == true { return .folder }
        if values.isRegularFile == true { return .file }
        throw VaultMutationError.wrongKind(url.lastPathComponent)
    }

    private func requireExistingFolder(_ url: URL, relativePath: String) throws {
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw VaultMutationError.sourceMissing(parentPath(relativePath))
        }
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values?.isSymbolicLink != true else { throw VaultMutationError.outsideVault(relativePath) }
    }

    private func requireAvailable(_ url: URL, excluding source: URL?,
                                  relativePath: String) throws {
        let parent = url.deletingLastPathComponent()
        let wanted = collisionKey(url.lastPathComponent)
        let excluded = source?.standardizedFileURL.path
        for child in try fm.contentsOfDirectory(at: parent,
                                                includingPropertiesForKeys: nil) {
            if child.standardizedFileURL.path == excluded { continue }
            if collisionKey(child.lastPathComponent) == wanted {
                throw VaultMutationError.occupied(relativePath)
            }
        }
    }

    private func guardFile(path: String, revision: VaultRevision) throws {
        let url = try existingVisibleURL(path)
        guard try pathKind(url) == .file else { throw VaultMutationError.wrongKind(path) }
        if let pair = revision.baseline.first(where: { $0.value.relativePath == path }),
           let expected = revision.files[pair.key] {
            let data = try Data(contentsOf: url)
            guard Self.fileRevision(data: data, relativePath: path) == expected else {
                throw VaultMutationError.conflict(path)
            }
            return
        }
        guard let expected = revision.entries[path], expected.manageable,
              try VaultEntryCatalog(rootURL: vaultURL, fileManager: fm).entry(at: path) == expected else {
            throw VaultMutationError.conflict(path)
        }
    }

    private func guardFolder(path: String, revision: VaultRevision) throws {
        let prefix = path + "/"
        if !revision.entries.isEmpty {
            let expectedEntries = revision.entries.filter { $0.key == path || $0.key.hasPrefix(prefix) }
            let actualEntries = try VaultEntryCatalog(rootURL: vaultURL, fileManager: fm).entries().filter { $0.path == path || $0.path.hasPrefix(prefix) }
            guard !expectedEntries.isEmpty,
                  Dictionary(uniqueKeysWithValues: actualEntries.map { ($0.path, $0) }) == expectedEntries
            else { throw VaultMutationError.conflict(path) }
        }
        let expected = revision.baseline.filter { $0.value.relativePath.hasPrefix(prefix) }
        let current = Set(try markdownRelativePaths().filter { $0.hasPrefix(prefix) })
        let expectedPaths = Set(expected.values.map(\.relativePath))
        guard current == expectedPaths else {
            throw VaultMutationError.conflict(path)
        }
        for (_, parsed) in expected { try guardFile(path: parsed.relativePath, revision: revision) }
    }

    private func collisionKey(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive],
                     locale: Locale(identifier: "en_US_POSIX"))
    }

    private func parentPath(_ path: String) -> String {
        let parent = (path as NSString).deletingLastPathComponent
        return parent == "." ? "" : parent
    }

    private func joined(_ parent: String, _ child: String) -> String {
        parent.isEmpty ? child : parent + "/" + child
    }

    private func moveItem(_ source: URL, to destination: URL) throws {
        if source.deletingLastPathComponent() == destination.deletingLastPathComponent(),
           collisionKey(source.lastPathComponent) == collisionKey(destination.lastPathComponent) {
            let temporary = source.deletingLastPathComponent()
                .appendingPathComponent(".clonie-move-" + UUID().uuidString)
            try fm.moveItem(at: source, to: temporary)
            do { try fm.moveItem(at: temporary, to: destination) }
            catch { try? fm.moveItem(at: temporary, to: source); throw error }
        } else {
            try fm.moveItem(at: source, to: destination)
        }
    }

    private func removeDirectoryIfEmpty(_ url: URL) throws {
        guard (try fm.contentsOfDirectory(at: url,
                                         includingPropertiesForKeys: nil)).isEmpty else { return }
        try fm.removeItem(at: url)
    }
}

extension VaultStore {
    private func identityPreparations(in path: String, kind: VaultPathKind,
                                      revision: VaultRevision) throws -> [VaultIdentityPreparation] {
        let candidates: [(String, ParsedFile)]
        if kind == .file {
            guard let pair = revision.baseline.first(where: { $0.value.relativePath == path }) else { return [] }
            candidates = [(pair.key, pair.value)]
        } else {
            let prefix = path + "/"
            candidates = revision.baseline.compactMap { id, parsed in
                parsed.relativePath.hasPrefix(prefix) ? (id, parsed) : nil
            }
        }
        return try candidates.compactMap { id, parsed in
            guard !parsed.hadFrontmatterID else { return nil }
            let url = actualRoot().appendingPathComponent(parsed.relativePath)
            let original = try Data(contentsOf: url)
            return VaultIdentityPreparation(relativePath: parsed.relativePath, original: original,
                withIdentity: insertingIdentity(id, into: original))
        }
    }


    private func insertingIdentity(_ id: String, into data: Data) -> Data {
        let bomUTF8 = Data([0xEF, 0xBB, 0xBF])
        let bomLE = Data([0xFF, 0xFE])
        let bomBE = Data([0xFE, 0xFF])
        let encoding: String.Encoding
        let bom: Data
        let payload: Data
        if data.starts(with: bomUTF8) { encoding = .utf8; bom = bomUTF8; payload = data.dropFirst(3) }
        else if data.starts(with: bomLE) { encoding = .utf16LittleEndian; bom = bomLE; payload = data.dropFirst(2) }
        else if data.starts(with: bomBE) { encoding = .utf16BigEndian; bom = bomBE; payload = data.dropFirst(2) }
        else { encoding = .utf8; bom = Data(); payload = data }
        let original = String(data: payload, encoding: encoding)
        let newline = original?.contains("\r\n") == true ? "\r\n" : "\n"
        let emitted = Frontmatter.emit(id)
        let idLine = ("id: " + emitted + newline).data(using: encoding) ?? Data()
        if let original, let lineEnd = original.firstIndex(of: "\n") {
            let firstLine = original[..<lineEnd].trimmingCharacters(in: .whitespacesAndNewlines)
            if firstLine == "---" {
                let throughNewline = original.index(after: lineEnd)
                let prefix = String(original[..<throughNewline]).data(using: encoding) ?? Data()
                return bom + prefix + idLine + Data(payload.dropFirst(prefix.count))
            }
        }
        let header = ("---" + newline + "id: " + emitted + newline + "---" + newline)
            .data(using: encoding) ?? Data()
        // 본문을 다시 인코딩하지 않는다. 드문 잘못된 바이트가 있어도 이동이 내용을 고치지 않는다.
        return bom + header + payload
    }

    private func applyIdentities(_ changes: [VaultIdentityPreparation]) throws {
        for change in changes {
            let url = actualRoot().appendingPathComponent(change.relativePath)
            try AtomicFile.write(change.withIdentity, to: url, fileManager: fm)
        }
    }

    private func rollbackIdentities(_ changes: [VaultIdentityPreparation]) throws {
        for change in changes {
            let url = actualRoot().appendingPathComponent(change.relativePath)
            guard let current = try? Data(contentsOf: url), current == change.withIdentity else {
                // 원복 이동 실패로 old path에 새 파일이 생겼거나, 이동 뒤 누군가 내용을 고쳤다.
                // 우리가 쓴 바이트가 아니면 재생성하거나 과거판으로 덮지 않는다.
                continue
            }
            try AtomicFile.write(change.original, to: url, fileManager: fm)
        }
    }
}

extension VaultStore {
    private func mutationResult(operation: VaultOperationRecord?,
                                impacts: [VaultLinkImpact]) throws -> VaultMutationResult {
        VaultMutationResult(workspace: try loadWorkspace(), operation: operation,
                            linkImpacts: impacts)
    }

    private func readJournal() throws -> VaultOperationJournal {
        guard fm.fileExists(atPath: operationJournalURL.path) else {
            return VaultOperationJournal(operations: [])
        }
        do {
            return try FragmentStore.makeDecoder().decode(
                VaultOperationJournal.self, from: Data(contentsOf: operationJournalURL))
        } catch {
            throw VaultMutationError.corruptRecord(operationJournalURL.lastPathComponent)
        }
    }

    private func writeJournal(_ journal: VaultOperationJournal) throws {
        let data = try FragmentStore.makeEncoder().encode(journal)
        try AtomicFile.write(data, to: operationJournalURL, fileManager: fm)
    }

    private func recordOperation(kind: VaultOperationRecord.Kind, source: String,
                                 destination: String, trashEntryID: String?) throws -> VaultOperationRecord {
        var journal = try readJournal()
        let record = VaultOperationRecord(id: UUID().uuidString, kind: kind, sourcePath: source,
            destinationPath: destination, trashEntryID: trashEntryID, performedAt: Date(), undoneAt: nil)
        journal.operations.append(record)
        if journal.operations.count > 200 {
            journal.operations.removeFirst(journal.operations.count - 200)
        }
        try writeJournal(journal)
        return record
    }

    private func actualURL(forStoredRelativePath path: String) -> URL {
        actualRoot().appendingPathComponent(path).standardizedFileURL
    }

    private func trashEntryMetadataURL(_ id: String) -> URL {
        trashURL.appendingPathComponent(id, isDirectory: true).appendingPathComponent("entry.json")
    }

    private func writeTrashEntry(_ entry: VaultTrashEntry) throws {
        let data = try FragmentStore.makeEncoder().encode(entry)
        try AtomicFile.write(data, to: trashEntryMetadataURL(entry.id), fileManager: fm)
    }
}

extension VaultStore {
    private func linkImpactsTrashing(_ source: String, kind: VaultPathKind,
                                     revision: VaultRevision) -> [VaultLinkImpact] {
        let prefix = source + "/"
        let removedDocuments = Set(revision.baseline.values.compactMap { parsed in
            parsed.relativePath == source || (kind == .folder && parsed.relativePath.hasPrefix(prefix))
                ? parsed.relativePath : nil
        })
        var impacts: [VaultLinkImpact] = []
        for parsed in revision.baseline.values where !removedDocuments.contains(parsed.relativePath) {
            for reference in markdownReferences(parsed.fragment.body) {
                guard let oldTarget = resolveReference(reference, from: parsed.relativePath),
                      oldTarget == source || (kind == .folder && oldTarget.hasPrefix(prefix))
                else { continue }
                impacts.append(VaultLinkImpact(markdownPath: parsed.relativePath,
                    reference: reference, oldTargetPath: oldTarget,
                    targetAfterMove: ".clonie/trash", resolvedAfterMove: nil))
            }
        }
        return impacts.sorted { ($0.markdownPath, $0.reference) < ($1.markdownPath, $1.reference) }
    }

    private func linkImpactsMoving(from source: String, to destination: String,
                                   kind: VaultPathKind,
                                   revision: VaultRevision) -> [VaultLinkImpact] {
        func mapped(_ path: String) -> String {
            if path == source { return destination }
            if kind == .folder && path.hasPrefix(source + "/") {
                return destination + String(path.dropFirst(source.count))
            }
            return path
        }
        var impacts: [VaultLinkImpact] = []
        for parsed in revision.baseline.values {
            let markdownPath = parsed.relativePath
            for reference in markdownReferences(parsed.fragment.body) {
                guard let oldTarget = resolveReference(reference, from: markdownPath) else { continue }
                let newDocumentPath = mapped(markdownPath)
                let intendedTarget = mapped(oldTarget)
                let actualTarget = resolveReference(reference, from: newDocumentPath)
                if actualTarget != intendedTarget {
                    impacts.append(VaultLinkImpact(markdownPath: markdownPath, reference: reference,
                        oldTargetPath: oldTarget, targetAfterMove: intendedTarget,
                        resolvedAfterMove: actualTarget))
                }
            }
        }
        return impacts.sorted {
            ($0.markdownPath, $0.reference) < ($1.markdownPath, $1.reference)
        }
    }

    private func markdownReferences(_ body: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"(?<!!)\[[^\]\n]+\]\(([^)\n]+)\)"#) else {
            return []
        }
        let ns = body as NSString
        return regex.matches(in: body, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            var raw = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            if raw.hasPrefix("<"), let end = raw.firstIndex(of: ">") {
                raw = String(raw[raw.index(after: raw.startIndex)..<end])
            } else if let title = raw.range(of: #"\s+[\"']"#, options: .regularExpression) {
                raw = String(raw[..<title.lowerBound])
            }
            return raw
        }
    }

    private func resolveReference(_ raw: String, from markdownPath: String) -> String? {
        var reference = String(raw.prefix { $0 != "#" && $0 != "?" })
        reference = reference.removingPercentEncoding ?? ""
        guard !reference.isEmpty, !reference.hasPrefix("/"), !reference.hasPrefix("~"),
              !reference.contains("\\"),
              reference.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*:"#,
                              options: .regularExpression) == nil else { return nil }
        var parts = markdownPath.split(separator: "/").dropLast().map(String.init)
        for part in reference.split(separator: "/", omittingEmptySubsequences: false).map(String.init) {
            if part.isEmpty { return nil }
            if part == "." { continue }
            if part == ".." { guard !parts.isEmpty else { return nil }; parts.removeLast() }
            else { guard !part.hasPrefix(".") else { return nil }; parts.append(part) }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "/")
    }
}
