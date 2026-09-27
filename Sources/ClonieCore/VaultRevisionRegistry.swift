import Foundation

/// Owns the opaque revision tokens exchanged with an editor.
///
/// Recent full snapshots expire after 32 deliveries. Unsaved edits may retain only their
/// file baselines beyond that limit; those pins are usable only as save overrides, never
/// as a full snapshot for another operation. The owner serializes access and resets the
/// registry when switching vaults.
public struct VaultRevisionRegistry {
    public enum ResolutionError: Error, Equatable {
        case expiredToken
    }

    private var recent: [String: VaultRevision] = [:]
    private var order: [String] = []
    private var pinned: [String: VaultRevision] = [:]

    public init() {}

    public mutating func remember(_ revision: VaultRevision) -> String {
        let token = UUID().uuidString
        recent[token] = revision
        order.append(token)
        while order.count > 32 {
            recent.removeValue(forKey: order.removeFirst())
        }
        return token
    }

    /// Only a recent full snapshot can authorize a new operation.
    public func revision(for token: String) -> VaultRevision? { recent[token] }

    /// Replaces the complete set of unsaved-edit pins, releasing saved/cancelled edits.
    /// Unknown tokens and empty file sets are ignored, as in the editor bridge.
    public mutating func pin(_ requested: [String: Set<String>]) {
        var next: [String: VaultRevision] = [:]
        for (token, ids) in requested {
            guard !ids.isEmpty, let source = recent[token] ?? pinned[token] else { continue }
            next[token] = source.selectingFileBaselines(for: ids)
        }
        pinned = next
    }

    /// Uses the current full snapshot for untouched files and the editing baseline for
    /// each overridden file. An expired base cannot be revived by an edit pin.
    public func resolveForSave(base token: String,
                               overrides: [String: String]) throws -> VaultRevision {
        guard var revision = recent[token] else { throw ResolutionError.expiredToken }
        let grouped = Dictionary(grouping: overrides, by: \.value)
        for (editingToken, rows) in grouped {
            guard let editing = recent[editingToken] ?? pinned[editingToken] else {
                throw ResolutionError.expiredToken
            }
            revision = try revision.preservingFileBaselines(for: Set(rows.map(\.key)), from: editing)
        }
        return revision
    }

    public mutating func reset() {
        recent.removeAll()
        order.removeAll()
        pinned.removeAll()
    }
}
