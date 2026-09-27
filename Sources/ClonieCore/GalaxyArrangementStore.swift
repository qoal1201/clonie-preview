import Foundation

/// A derived view of Markdown documents. This never changes their paths or contents.
public struct GalaxyAssignment: Codable, Equatable, Sendable {
    public let documentID: String
    /// Anchor index, or -1 when none of the proposed subjects fits.
    public let group: Int
    /// Anchor probabilities in order, followed by the no-match probability.
    public let probabilities: [Double]
    public let confidence: Double

    public init(documentID: String, group: Int, probabilities: [Double], confidence: Double) {
        self.documentID = documentID
        self.group = group
        self.probabilities = probabilities
        self.confidence = confidence
    }
}

public struct GalaxyArrangement: Codable, Equatable, Sendable {
    public static let policy = "representative-subject-choice-v1"
    public static let maximumDocuments = 64
    public let schemaVersion: Int
    public let policy: String
    public let fingerprint: String
    public let model: String
    public let anchorIDs: [String]
    public let assignments: [GalaxyAssignment]

    public init(fingerprint: String, model: String, anchorIDs: [String], assignments: [GalaxyAssignment]) {
        self.schemaVersion = 1
        self.policy = Self.policy
        self.fingerprint = fingerprint
        self.model = model
        self.anchorIDs = anchorIDs
        self.assignments = assignments
    }

    public func validate(documentIDs: Set<String>) throws {
        guard schemaVersion == 1, policy == Self.policy,
              !fingerprint.isEmpty, !model.isEmpty,
              (2...Self.maximumDocuments).contains(documentIDs.count),
              (1...6).contains(anchorIDs.count),
              anchorIDs.count < documentIDs.count,
              Set(anchorIDs).count == anchorIDs.count,
              Set(anchorIDs).isSubset(of: documentIDs),
              Set(assignments.map(\.documentID)).count == assignments.count,
              Set(anchorIDs).isDisjoint(with: assignments.map(\.documentID)),
              Set(anchorIDs + assignments.map(\.documentID)) == documentIDs else {
            throw GalaxyArrangementError.invalidData
        }
        for row in assignments {
            let selected = row.group < 0 ? anchorIDs.count : row.group
            guard (-1..<anchorIDs.count).contains(row.group),
                  row.probabilities.count == anchorIDs.count + 1,
                  row.probabilities.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
                  abs(row.probabilities.reduce(0, +) - 1) <= 0.001,
                  row.probabilities[selected] >= (row.probabilities.max() ?? 1),
                  row.confidence.isFinite, (0...1).contains(row.confidence) else {
                throw GalaxyArrangementError.invalidData
            }
        }
    }
}

public enum GalaxyArrangementError: Error {
    case invalidData, unsafePath, tooLarge
}

/// Access on the vault's serial I/O queue. A stale view stays on disk but is not restored.
public struct GalaxyArrangementStore {
    public let root: URL
    public var url: URL { root.appendingPathComponent(".clonie/galaxy-arrangement.json") }
    private static let maximumBytes = 256_000

    public init(root: URL) { self.root = root.standardizedFileURL }

    public func load(fingerprint: String, model: String, documentIDs: Set<String>) throws -> GalaxyArrangement? {
        try checkPaths()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let size = (try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
        guard size <= Self.maximumBytes else { throw GalaxyArrangementError.tooLarge }
        let data = try Data(contentsOf: url)
        guard data.count <= Self.maximumBytes else { throw GalaxyArrangementError.tooLarge }
        let record = try JSONDecoder().decode(GalaxyArrangement.self, from: data)
        guard record.fingerprint == fingerprint, record.model == model,
              record.policy == GalaxyArrangement.policy, record.schemaVersion == 1 else { return nil }
        try record.validate(documentIDs: documentIDs)
        return record
    }

    public func save(_ record: GalaxyArrangement, documentIDs: Set<String>) throws {
        try record.validate(documentIDs: documentIDs)
        try checkPaths()
        let data = try JSONEncoder().encode(record)
        guard data.count <= Self.maximumBytes else { throw GalaxyArrangementError.tooLarge }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try checkPaths()
        try AtomicFile.write(data, to: url, fileManager: .default)
    }

    private func checkPaths() throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw GalaxyArrangementError.unsafePath
        }
        for path in [root.appendingPathComponent(".clonie"), url] {
            if let attributes = try? FileManager.default.attributesOfItem(atPath: path.path),
               attributes[.type] as? FileAttributeType == .typeSymbolicLink {
                throw GalaxyArrangementError.unsafePath
            }
        }
    }
}
