import XCTest
@testable import ClonieCore

private final class ChangeFaultFileManager: FileManager, @unchecked Sendable {
    var failJournalCommit = false
    var failDocumentWrite = false
    override func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool,
                                  attributes: [FileAttributeKey: Any]? = nil) throws {
        let journal = url.lastPathComponent == "document-changes"
            ? url : url.appendingPathComponent(".clonie/document-changes")
        let hasPrepared = ((try? contentsOfDirectory(atPath: journal.path)) ?? []).contains { $0.hasSuffix(".json") }
        if hasPrepared && ((failJournalCommit && url.lastPathComponent == "document-changes")
                           || (failDocumentWrite && url.lastPathComponent != "document-changes")) {
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: attributes)
    }
}

final class VaultDocumentChangesTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("clonie-changes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func existingStore(fileManager: FileManager = .default) throws -> VaultStore {
        // Deliberately retain original formatting and metadata that the app does not own.
        let original = "---\nid: stable-id\ntitle: Original\ntags: [keep, custom]\ncustom: 'exact spacing'\n---\n\n# Original\n\nOriginal body.\n"
        try Data(original.utf8).write(to: root.appendingPathComponent("original.md"))
        return VaultStore(vaultURL: root, fileManager: fileManager)
    }

    private func update(_ store: VaultStore, body: String = "Updated body.") throws -> VaultSaveResult {
        let loaded = try store.loadVersioned()
        var document = loaded.result.document
        document.fragments[0].body = body
        document.fragments[0].title = "Updated"
        return try store.saveFragments(document, expecting: loaded.revision)
    }

    func testReadingEmptyHistoryDoesNotInitializeSidecar() throws {
        let store = VaultStore(vaultURL: root)
        XCTAssertEqual(try store.documentChanges().count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.sidecarURL.path))
    }

    func testUpdateRecordsExactBeforeAfterAndReviewSurvivesReload() throws {
        let store = try existingStore()
        let original = try Data(contentsOf: root.appendingPathComponent("original.md"))
        _ = try update(store)
        let record = try XCTUnwrap(store.documentChanges().first)
        XCTAssertEqual(record.source, "mcp")
        XCTAssertEqual(record.operation, .update)
        XCTAssertEqual(record.fragmentID, "stable-id")
        XCTAssertEqual(record.path, "original.md")
        XCTAssertEqual(record.before?.bytes, original)
        XCTAssertEqual(record.after.bytes, try Data(contentsOf: root.appendingPathComponent("original.md")))
        XCTAssertTrue(record.after.markdown.contains("custom: 'exact spacing'"))
        XCTAssertNil(record.reviewedAt)
        try store.markDocumentChangeReviewed(id: record.id)
        let restarted = VaultStore(vaultURL: root)
        XCTAssertNotNil(try restarted.documentChanges().first?.reviewedAt)
        XCTAssertEqual(try restarted.restoreDocumentChange(id: record.id).warning, nil)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("original.md")), original)
        XCTAssertNotNil(try restarted.documentChanges().first?.restoredAt)
        XCTAssertThrowsError(try restarted.restoreDocumentChange(id: record.id))
    }

    func testLaterEditingOrDeletionPreventsRestore() throws {
        let store = try existingStore()
        _ = try update(store)
        let record = try XCTUnwrap(store.documentChanges().first)
        let later = Data("Later editor's work".utf8)
        let path = root.appendingPathComponent("original.md")
        try later.write(to: path)
        XCTAssertThrowsError(try store.restoreDocumentChange(id: record.id))
        XCTAssertEqual(try Data(contentsOf: path), later)
        try FileManager.default.removeItem(at: path)
        XCTAssertThrowsError(try store.restoreDocumentChange(id: record.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
    }

    func testCreationRecordedButNotDeletedByRestoreAndNoOpIsExcluded() throws {
        let store = VaultStore(vaultURL: root)
        let initial = try store.loadVersioned()
        let fragment = Fragment(id: "new-id", title: "New", body: "New body", questionIds: [], createdAt: Date(), updatedAt: Date())
        let saved = try store.saveFragments(CueDocument(fragments: [fragment]), expecting: initial.revision)
        let record = try XCTUnwrap(store.documentChanges().first)
        XCTAssertEqual(record.operation, .create)
        XCTAssertNil(record.before)
        XCTAssertThrowsError(try store.restoreDocumentChange(id: record.id))
        XCTAssertNotNil(saved.paths[fragment.id])
        let next = try store.loadVersioned()
        _ = try store.saveFragments(next.result.document, expecting: next.revision)
        XCTAssertEqual(try store.documentChanges().count, 1)
    }

    func testFailedDocumentWriteIsNotListedAsApplied() throws {
        let fm = ChangeFaultFileManager()
        let store = try existingStore(fileManager: fm)
        let original = try Data(contentsOf: root.appendingPathComponent("original.md"))
        fm.failDocumentWrite = true
        XCTAssertThrowsError(try update(store))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("original.md")), original)
        XCTAssertEqual(try store.documentChanges().count, 0)
        // Even if an external editor later supplies those bytes, an explicitly failed write stays failed.
        let journalFile = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: store.documentChangesURL, includingPropertiesForKeys: nil).first)
        let failed = try VaultStore.documentChangeDecoder().decode(VaultDocumentChange.self, from: Data(contentsOf: journalFile))
        XCTAssertTrue(failed.failed)
        try failed.after.bytes.write(to: root.appendingPathComponent("original.md"))
        XCTAssertEqual(try VaultStore(vaultURL: root).documentChanges().count, 0)
    }

    func testJournalCommitFailureReturnsSuccessWarningAndRecoversFromBytes() throws {
        let fm = ChangeFaultFileManager()
        let store = try existingStore(fileManager: fm)
        fm.failJournalCommit = true
        let saved = try update(store)
        XCTAssertNotNil(saved.changeWarning)
        XCTAssertEqual(try store.load().document.fragments.first?.body, "Updated body.")
        // A new process can verify a prepared transaction's actual after image.
        let restarted = VaultStore(vaultURL: root)
        let record = try XCTUnwrap(restarted.documentChanges().first)
        XCTAssertEqual(record.after.body, "Updated body.")
        XCTAssertTrue(record.applied)
        XCTAssertNil(try restarted.restoreDocumentChange(id: record.id).warning)
    }

    func testJournalPreparationFailurePreventsDocumentWrite() throws {
        let store = try existingStore()
        _ = try store.load()
        let original = try Data(contentsOf: root.appendingPathComponent("original.md"))
        try Data("occupied".utf8).write(to: store.documentChangesURL)
        XCTAssertThrowsError(try update(store))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("original.md")), original)
    }

    func testRestoreRefusesSymlinkEvenWhenTargetMatchesAfterBytes() throws {
        let store = try existingStore()
        _ = try update(store)
        let record = try XCTUnwrap(store.documentChanges().first)
        let path = root.appendingPathComponent(record.path)
        let other = root.appendingPathComponent("other.md")
        try record.after.bytes.write(to: other)
        try FileManager.default.removeItem(at: path)
        try FileManager.default.createSymbolicLink(at: path, withDestinationURL: other)
        XCTAssertThrowsError(try store.restoreDocumentChange(id: record.id))
        XCTAssertEqual(try Data(contentsOf: other), record.after.bytes)
    }

    func testConcurrentStoresCannotBothOverwriteSameRevision() throws {
        let first = try existingStore()
        let second = VaultStore(vaultURL: root)
        let a = try first.loadVersioned()
        let b = try second.loadVersioned()
        var one = a.result.document
        var two = b.result.document
        one.fragments[0].body = "First writer"
        two.fragments[0].body = "Second writer"
        let group = DispatchGroup()
        let outcomes = ChangeOutcomes()
        for (store, document, revision) in [(first, one, a.revision), (second, two, b.revision)] {
            group.enter()
            DispatchQueue.global().async {
                do { _ = try store.saveFragments(document, expecting: revision); outcomes.add(success: true) }
                catch { outcomes.add(success: false) }
                group.leave()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(outcomes.successes, 1)
        XCTAssertEqual(try first.documentChanges().count, 1)
    }
}

private final class ChangeOutcomes: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var successes: Int { lock.lock(); defer { lock.unlock() }; return count }
    func add(success: Bool) { lock.lock(); defer { lock.unlock() }; if success { count += 1 } }
}
