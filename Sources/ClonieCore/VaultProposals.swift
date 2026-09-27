import Foundation

public struct VaultProposal: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let taskID: String
    public let taskTitle: String
    public let createdAt: Date
    public let fragment: Fragment
    public let before: Fragment?
    public let base: VaultFileRevision?
    public let path: String?
    public var draftTitle: String?
    public var draftBody: String?
    public var applying: Bool = false
}

extension VaultStore {
    public var proposalsURL: URL { sidecarURL.appendingPathComponent("proposals", isDirectory: true) }

    private func proposalDirectory() throws {
        for url in [sidecarURL, proposalsURL] {
            if let attrs = try? fm.attributesOfItem(atPath: url.path) {
                guard attrs[.type] as? FileAttributeType == .typeDirectory else { throw VaultMutationError.outsideVault(url.path) }
            } else { try fm.createDirectory(at: url, withIntermediateDirectories: true) }
        }
    }
    private func proposalURL(_ id: String) throws -> URL {
        guard UUID(uuidString: id) != nil else { throw VaultMutationError.operationNotFound(id) }
        try proposalDirectory()
        let url = proposalsURL.appendingPathComponent(id + ".json")
        if let attrs = try? fm.attributesOfItem(atPath: url.path), attrs[.type] as? FileAttributeType != .typeRegular {
            throw VaultMutationError.outsideVault(id)
        }
        return url
    }
    private func readProposal(_ id: String) throws -> VaultProposal {
        let value = try JSONDecoder().decode(VaultProposal.self, from: Data(contentsOf: proposalURL(id)))
        guard value.id == id, UUID(uuidString: value.taskID) != nil else { throw VaultMutationError.corruptRecord(id) }
        return value
    }
    private func writeProposal(_ proposal: VaultProposal) throws {
        try AtomicFile.write(try JSONEncoder().encode(proposal), to: proposalURL(proposal.id), fileManager: fm)
    }
    public func proposals() throws -> [VaultProposal] {
        guard fm.fileExists(atPath: proposalsURL.path) else { return [] }
        return try withDocumentWriteLock {
            try proposalDirectory()
            return try fm.contentsOfDirectory(at: proposalsURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }.map { try readProposal($0.deletingPathExtension().lastPathComponent) }
                .sorted { $0.createdAt < $1.createdAt }
        }
    }
    public func propose(fragment: Fragment, before: Fragment?, base: VaultFileRevision?, path: String?,
                        taskID: String?, taskTitle: String) throws -> VaultProposal {
        try withDocumentWriteLock {
            let task = taskID ?? UUID().uuidString
            guard UUID(uuidString: task) != nil else { throw VaultMutationError.corruptRecord(task) }
            let existingTaskTitle: String?
            if taskID != nil {
                try proposalDirectory()
                existingTaskTitle = try fm.contentsOfDirectory(at: proposalsURL, includingPropertiesForKeys: nil)
                    .filter { $0.pathExtension == "json" }
                    .map { try readProposal($0.deletingPathExtension().lastPathComponent) }
                    .filter { $0.taskID == task }
                    .min { $0.createdAt < $1.createdAt }?.taskTitle
            } else {
                existingTaskTitle = nil
            }
            if let path {
                guard path.split(separator: "/").first?.lowercased() != "raw", !path.split(separator: "/").dropLast().contains("원본"), ["md", "markdown"].contains((path as NSString).pathExtension.lowercased()),
                      !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0.isEmpty || $0.hasPrefix(".") })
                else { throw VaultMutationError.outsideVault(path) }
                guard !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0") else { throw VaultMutationError.outsideVault(path) }
                var cursor = vaultURL
                for part in path.split(separator: "/").dropLast() {
                    cursor.appendPathComponent(String(part))
                    if let attrs = try? fm.attributesOfItem(atPath: cursor.path), attrs[.type] as? FileAttributeType != .typeDirectory {
                        throw VaultMutationError.outsideVault(path)
                    }
                }
            }
            let p = VaultProposal(id: UUID().uuidString, taskID: task,
                taskTitle: existingTaskTitle ?? (taskTitle.isEmpty ? fragment.title : taskTitle), createdAt: Date(),
                fragment: fragment, before: before, base: base, path: path)
            try writeProposal(p)
            return p
        }
    }
    public func saveProposalDraft(id: String, title: String, body: String) throws {
        try withDocumentWriteLock {
            var proposal = try readProposal(id)
            guard !proposal.applying else { throw VaultMutationError.conflict(id) }
            proposal.draftTitle = title
            proposal.draftBody = body
            try writeProposal(proposal)
        }
    }
    public func rejectProposal(id: String) throws {
        try withDocumentWriteLock { try fm.removeItem(at: proposalURL(id)) }
    }
    /// Only the app calls this. The MCP surface cannot approve its own proposals.
    @discardableResult public func approveProposal(id: String, title: String? = nil, body: String? = nil) throws -> String {
        try withDocumentWriteLock {
            var p = try readProposal(id)
            let current = try loadVersioned()
            let existing = current.result.document.fragments.first { $0.id == p.fragment.id }
            // Recover a crash between the document save and removal of the pending item.
            if p.applying, let existing, existing.title == p.fragment.title, existing.body == p.fragment.body,
               existing.questionIds == p.fragment.questionIds {
                try fm.removeItem(at: proposalURL(id)); return existing.id
            }
            if let base = p.base {
                guard current.revision.files[p.fragment.id] == base else { throw VaultMutationError.conflict(base.relativePath) }
            } else if existing != nil { throw VaultMutationError.conflict(p.path ?? p.fragment.id) }
            var fragment = p.fragment
            if let title = title ?? p.draftTitle { fragment.title = title.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let body = body ?? p.draftBody { fragment.body = body }
            guard !fragment.title.isEmpty, !fragment.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw VaultMutationError.incompleteProposal
            }
            fragment.updatedAt = Date()
            p = VaultProposal(id: p.id, taskID: p.taskID, taskTitle: p.taskTitle, createdAt: p.createdAt,
                fragment: fragment, before: p.before, base: p.base, path: p.path, applying: true)
            try writeProposal(p)
            var document = current.result.document
            if let i = document.fragments.firstIndex(where: { $0.id == fragment.id }) { document.fragments[i] = fragment }
            else { document.fragments.append(fragment) }
            _ = try performSaveLocked(document, expecting: current.revision,
                newPaths: p.base == nil ? p.path.map { [fragment.id: $0] } ?? [:] : [:],
                writeMetadata: false, recordDocumentChanges: false)
            try fm.removeItem(at: proposalURL(id))
            return fragment.id
        }
    }
}
