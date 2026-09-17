import Foundation

/// A user-created orbital group. The paths are derived from the current vault
/// entries; the group file also keeps each member's filesystem identity so a
/// rename or a folder move can be followed without changing the vault.
public struct OrbitGroup: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let paths: [String]

    public init(id: String, paths: [String]) {
        self.id = id
        self.paths = paths
    }
}

/// Persistent storage for manual orbital groups.
///
/// The file is deliberately separate from `CueDocument`: groups affect only
/// presentation and must never rewrite Markdown, questions, or the search
/// index. Loading refreshes known file identities after saves and renames,
/// but never drops missing members from disk. Undo can therefore bring an
/// earlier path back and recover the old relationship.
public final class OrbitGroupStore {
    public static let currentSchemaVersion = 1
    public static let sidecarFileName = "orbit-groups.json"

    /// The metadata file is small by design. These limits protect the app
    /// from accidentally treating an arbitrary large file as group metadata.
    public static let maxFileBytes = 4 * 1024 * 1024
    public static let maxGroups = 10_000
    public static let maxMembers = 100_000
    public static let maxIdentifierLength = 128
    public static let maxPathLength = 4_096

    public let rootURL: URL
    public let orbitGroupsURL: URL

    private let fm: FileManager

    public init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL.standardizedFileURL
        self.orbitGroupsURL = rootURL.standardizedFileURL
            .appendingPathComponent(".clonie", isDirectory: true)
            .appendingPathComponent(Self.sidecarFileName, isDirectory: false)
        self.fm = fileManager
    }

    /// Loads current, valid group membership and refreshes known references.
    ///
    /// A stored path wins over an inode match. This keeps membership attached
    /// to a path when an atomic document save replaces its inode. If the path
    /// is gone, an inode match is accepted only when it is unique.
    public func load(entries: [VaultEntry]) throws -> [OrbitGroup] {
        let records = try readRecords()
        let eligible = try eligibleEntries(entries)
        let refreshed = refreshedReferences(records, entries: eligible)
        if refreshed != records { try writeRecords(refreshed) }
        return visibleGroups(from: reconcile(refreshed, entries: eligible))
    }

    /// Moves the chosen file onto the target file's orbit. Other members of
    /// the source orbit stay together; a remaining singleton becomes ungrouped.
    @discardableResult
    public func join(path: String, targetPath: String,
                     entries: [VaultEntry]) throws -> [OrbitGroup] {
        let eligible = try eligibleEntries(entries)
        guard path != targetPath else { throw OrbitGroupStoreError.sameFile(path) }
        guard let source = eligible.first(where: { $0.path == path }) else {
            throw OrbitGroupStoreError.invalidMember(path)
        }
        guard let target = eligible.first(where: { $0.path == targetPath }) else {
            throw OrbitGroupStoreError.invalidMember(targetPath)
        }
        guard parentPath(source.path) == parentPath(target.path) else {
            throw OrbitGroupStoreError.differentParents(path, targetPath)
        }

        var records = reconcile(try readRecords(), entries: eligible)
        let sourceIndex = records.firstIndex { $0.members.contains { $0.path == source.path } }
        let targetIndex = records.firstIndex { $0.members.contains { $0.path == target.path } }

        if let sourceIndex, sourceIndex == targetIndex {
            return visibleGroups(from: records)
        }
        if let sourceIndex {
            records[sourceIndex].members.removeAll { $0.path == source.path }
        }
        let member = OrbitGroupMember(path: source.path, entryID: source.id)
        if let targetIndex {
            records[targetIndex].members.append(member)
        } else {
            records.append(OrbitGroupRecord(id: UUID().uuidString.lowercased(), members: [
                OrbitGroupMember(path: target.path, entryID: target.id), member
            ]))
        }
        records = reconcile(records, entries: eligible)
        try writeRecords(records)
        return visibleGroups(from: records)
    }

    /// Removes one file from its group. A resulting singleton becomes a
    /// normal, ungrouped file and is therefore omitted from the sidecar.
    @discardableResult
    public func split(path: String, entries: [VaultEntry]) throws -> [OrbitGroup] {
        let eligible = try eligibleEntries(entries)
        guard let entry = eligible.first(where: { $0.path == path }) else {
            throw OrbitGroupStoreError.invalidMember(path)
        }

        var records = reconcile(try readRecords(), entries: eligible)
        guard let index = records.firstIndex(where: { $0.members.contains { $0.path == entry.path } }) else {
            return visibleGroups(from: records)
        }

        records[index].members.removeAll { $0.path == entry.path }
        records = records.filter { $0.members.count >= 2 }
        try writeRecords(records)
        return visibleGroups(from: records)
    }
}

public enum OrbitGroupStoreError: Error, Equatable, Sendable, LocalizedError {
    case invalidMember(String)
    case sameFile(String)
    case differentParents(String, String)
    case sidecarSymlink(String)
    case invalidMetadata(String)
    case unknownSchemaVersion(Int)
    case metadataTooLarge
    case tooManyGroups
    case tooManyMembers
    case invalidIdentifier(String)
    case invalidPath(String)
    case ambiguousIdentity(String)

    public var errorDescription: String? {
        switch self {
        case .invalidMember(let path): return "궤도 묶음에 넣을 수 없는 파일이다: \(path)"
        case .sameFile(let path): return "같은 파일은 묶을 수 없다: \(path)"
        case .differentParents(let path, let target):
            return "서로 다른 부모 폴더의 파일은 묶을 수 없다: \(path), \(target)"
        case .sidecarSymlink(let path): return "궤도 메타데이터 경로가 심볼릭 링크다: \(path)"
        case .invalidMetadata(let path): return "궤도 메타데이터가 올바르지 않다: \(path)"
        case .unknownSchemaVersion(let version): return "지원하지 않는 궤도 메타데이터 판이다: \(version)"
        case .metadataTooLarge: return "궤도 메타데이터가 너무 크다"
        case .tooManyGroups: return "궤도 묶음 수가 너무 많다"
        case .tooManyMembers: return "궤도 묶음 파일 수가 너무 많다"
        case .invalidIdentifier(let id): return "궤도 묶음 식별자가 올바르지 않다: \(id)"
        case .invalidPath(let path): return "궤도 묶음 경로가 올바르지 않다: \(path)"
        case .ambiguousIdentity(let id): return "파일 식별자가 여러 경로를 가리킨다: \(id)"
        }
    }
}

private struct OrbitGroupsFile: Codable {
    let schemaVersion: Int
    var groups: [OrbitGroupRecord]
}

private struct OrbitGroupRecord: Codable, Equatable {
    let id: String
    var members: [OrbitGroupMember]
}

private struct OrbitGroupMember: Codable, Equatable {
    let path: String
    let entryID: String
}

private extension OrbitGroupStore {
    func readRecords() throws -> [OrbitGroupRecord] {
        try checkSidecarPath()
        guard fm.fileExists(atPath: orbitGroupsURL.path) else { return [] }
        let attributes = try fm.attributesOfItem(atPath: orbitGroupsURL.path)
        if let size = attributes[.size] as? NSNumber,
           size.intValue > Self.maxFileBytes {
            throw OrbitGroupStoreError.metadataTooLarge
        }
        do {
            let data = try Data(contentsOf: orbitGroupsURL)
            let decoded = try FragmentStore.makeDecoder().decode(OrbitGroupsFile.self, from: data)
            guard decoded.schemaVersion == Self.currentSchemaVersion else {
                throw OrbitGroupStoreError.unknownSchemaVersion(decoded.schemaVersion)
            }
            guard decoded.groups.count <= Self.maxGroups else {
                throw OrbitGroupStoreError.tooManyGroups
            }
            let count = decoded.groups.reduce(0) { $0 + $1.members.count }
            guard count <= Self.maxMembers else { throw OrbitGroupStoreError.tooManyMembers }
            for group in decoded.groups {
                try validateIdentifier(group.id)
                for member in group.members {
                    try validatePersistedMember(member)
                }
            }
            return decoded.groups
        } catch let error as OrbitGroupStoreError {
            throw error
        } catch {
            throw OrbitGroupStoreError.invalidMetadata(orbitGroupsURL.path)
        }
    }

    func writeRecords(_ records: [OrbitGroupRecord]) throws {
        try checkSidecarPath()
        guard records.count <= Self.maxGroups else { throw OrbitGroupStoreError.tooManyGroups }
        let count = records.reduce(0) { $0 + $1.members.count }
        guard count <= Self.maxMembers else { throw OrbitGroupStoreError.tooManyMembers }
        for group in records {
            try validateIdentifier(group.id)
            for member in group.members { try validatePersistedMember(member) }
        }
        let data = try FragmentStore.makeEncoder().encode(
            OrbitGroupsFile(schemaVersion: Self.currentSchemaVersion, groups: records))
        guard data.count <= Self.maxFileBytes else {
            throw OrbitGroupStoreError.metadataTooLarge
        }
        try AtomicFile.write(data, to: orbitGroupsURL, fileManager: fm)
    }

    func checkSidecarPath() throws {
        let sidecar = orbitGroupsURL.deletingLastPathComponent()
        if isSymbolicLink(sidecar) { throw OrbitGroupStoreError.sidecarSymlink(sidecar.path) }
        if isSymbolicLink(orbitGroupsURL) { throw OrbitGroupStoreError.sidecarSymlink(orbitGroupsURL.path) }
    }

    func isSymbolicLink(_ url: URL) -> Bool {
        (try? fm.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    func validateIdentifier(_ value: String) throws {
        guard !value.isEmpty, value.utf8.count <= Self.maxIdentifierLength,
              !value.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7f }) else {
            throw OrbitGroupStoreError.invalidIdentifier(value)
        }
    }

    func validatePersistedMember(_ member: OrbitGroupMember) throws {
        try validatePath(member.path)
        guard !member.entryID.isEmpty, member.entryID.utf8.count <= Self.maxIdentifierLength,
              !member.entryID.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7f }) else {
            throw OrbitGroupStoreError.invalidIdentifier(member.entryID)
        }
    }

    func validatePath(_ path: String) throws {
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !path.isEmpty, path.utf8.count <= Self.maxPathLength,
              !path.hasPrefix("/"), !path.hasPrefix("~"), !path.contains("\\"),
              !path.contains("\0"),
              !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
              !VaultEntryCatalog.isExcluded(relativePath: path) else {
            throw OrbitGroupStoreError.invalidPath(path)
        }
    }

    func eligibleEntries(_ entries: [VaultEntry]) throws -> [VaultEntry] {
        var seenPaths = Set<String>()
        var out: [VaultEntry] = []
        for entry in entries where entry.kind == "file" && entry.manageable {
            try validatePath(entry.path)
            guard seenPaths.insert(entry.path).inserted else {
                throw OrbitGroupStoreError.invalidMember(entry.path)
            }
            out.append(entry)
        }
        return out
    }

    /// An atomic Markdown save replaces its inode. Refresh that identity
    /// while its path still exists, so a later rename remains traceable.
    /// Keep unavailable references intact for file-operation undo.
    func refreshedReferences(_ records: [OrbitGroupRecord],
                             entries: [VaultEntry]) -> [OrbitGroupRecord] {
        let byPath = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0) })
        let byID = Dictionary(grouping: entries, by: \.id)
        return records.map { record in
            OrbitGroupRecord(id: record.id, members: record.members.map { member in
                let matches = byID[member.entryID] ?? []
                guard let current = byPath[member.path] ?? (matches.count == 1 ? matches[0] : nil) else {
                    return member
                }
                return OrbitGroupMember(path: current.path, entryID: current.id)
            })
        }
    }

    /// Reconciles persisted members against current filesystem entries. This
    /// is intentionally an in-memory operation. Only explicit join/split
    /// writes a normalized result that discards old or invalid memberships.
    func reconcile(_ input: [OrbitGroupRecord], entries: [VaultEntry]) -> [OrbitGroupRecord] {
        let eligible = entries.filter { $0.kind == "file" && $0.manageable }
        let byPath = Dictionary(uniqueKeysWithValues: eligible.map { ($0.path, $0) })
        let byID = Dictionary(grouping: eligible, by: \.id)
        var claimedPaths = Set<String>(), claimedIDs = Set<String>()
        var output: [OrbitGroupRecord] = []

        for group in input {
            guard !claimedIDs.contains(group.id) else { continue }
            var members: [OrbitGroupMember] = []
            var seenStored = Set<String>()
            for stored in group.members {
                let storedKey = stored.path + "\u{0}" + stored.entryID
                guard seenStored.insert(storedKey).inserted else { continue }

                let current: VaultEntry?
                if let exact = byPath[stored.path] {
                    // Path wins, even when an atomic replacement changed its inode.
                    current = exact
                } else {
                    let matches = byID[stored.entryID] ?? []
                    current = matches.count == 1 ? matches[0] : nil
                }
                guard let current, !claimedPaths.contains(current.path) else { continue }
                members.append(OrbitGroupMember(path: current.path, entryID: current.id))
            }

            members = keepOneParentGroup(members, originalMembers: group.members)
            guard members.count >= 2 else { continue }
            claimedPaths.formUnion(members.map(\.path))
            claimedIDs.insert(group.id)
            output.append(OrbitGroupRecord(id: group.id, members: uniqueMembers(members)))
        }
        return output
    }

    func keepOneParentGroup(_ members: [OrbitGroupMember],
                            originalMembers: [OrbitGroupMember]) -> [OrbitGroupMember] {
        let currentParents = Dictionary(grouping: members, by: { parentPath($0.path) })
        guard currentParents.count > 1 else { return members }

        // Prefer the original parent when at least two files remain there.
        let originalParents = Dictionary(grouping: originalMembers, by: { parentPath($0.path) })
        if let originalParent = originalParents.max(by: { $0.value.count < $1.value.count })?.key,
           let retained = currentParents[originalParent], retained.count >= 2 {
            return retained
        }

        let largest = currentParents.values.sorted { $0.count > $1.count }
        guard let first = largest.first, first.count >= 2,
              largest.dropFirst().first?.count != first.count else {
            // A tie has no safe identity-based answer. Drop the group rather
            // than inventing a new cross-folder relationship.
            return []
        }
        return first
    }

    func uniqueMembers(_ members: [OrbitGroupMember]) -> [OrbitGroupMember] {
        var seen = Set<String>()
        return members
            .sorted { $0.path < $1.path }
            .filter { seen.insert($0.path).inserted }
    }

    func visibleGroups(from records: [OrbitGroupRecord]) -> [OrbitGroup] {
        records.compactMap { group in
            let paths = uniqueMembers(group.members).map(\.path)
            return paths.count >= 2 ? OrbitGroup(id: group.id, paths: paths) : nil
        }
    }

    func parentPath(_ path: String) -> String {
        let parent = (path as NSString).deletingLastPathComponent
        return parent == "." ? "" : parent
    }
}
