import XCTest
@testable import GhostbarCore

private final class MoveFaultFileManager: FileManager, @unchecked Sendable {
    var failMove: ((URL, URL) throws -> Bool)?

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        if try failMove?(srcURL, dstURL) == true {
            throw NSError(domain: "VaultOperationsTests.MoveFault", code: 1)
        }
        try super.moveItem(at: srcURL, to: dstURL)
    }
}

final class VaultOperationsTests: XCTestCase {
    private var dir: URL!
    private var store: VaultStore!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("clonie-ops-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store = VaultStore(vaultURL: dir)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func write(_ path: String, _ text: String) throws {
        let url = dir.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func read(_ path: String) throws -> String {
        try String(contentsOf: dir.appendingPathComponent(path), encoding: .utf8)
    }

    func testWorkspaceIncludesEmptyFoldersAndCreateFolderReturnsFreshState() throws {
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("empty"),
                                                withIntermediateDirectories: true)
        var workspace = try store.loadWorkspace()
        XCTAssertEqual(workspace.folders, ["empty"])

        let result = try store.createFolder(at: "empty/child", expecting: workspace.revision)
        workspace = result.workspace

        XCTAssertEqual(workspace.folders, ["empty", "empty/child"])
        let operation = try XCTUnwrap(result.operation)
        XCTAssertEqual(operation.kind, .folderCreate)
        XCTAssertEqual(operation.destinationPath, "empty/child")

        let undone = try store.undo(operationID: operation.id, expecting: workspace.revision)
        XCTAssertEqual(undone.folders, ["empty"])
        XCTAssertNotNil(undone.operation?.undoneAt)
    }

    func testFolderCreateRollsBackWhenWorkspaceReloadFails() throws {
        let loaded = try store.loadWorkspace()
        try FileManager.default.createDirectory(at: store.sidecarURL, withIntermediateDirectories: true)
        try Data("not a directory".utf8).write(to: store.trashURL)

        XCTAssertThrowsError(try store.createFolder(at: "rolled-back",
                                                    expecting: loaded.revision))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("rolled-back").path))
    }

    func testFolderCreateUndoRefusesFolderThatGainedContent() throws {
        let loaded = try store.loadWorkspace()
        let created = try store.createFolder(at: "new-folder", expecting: loaded.revision)
        let operation = try XCTUnwrap(created.operation)
        try write("new-folder/added.txt", "keep")

        XCTAssertThrowsError(try store.undo(operationID: operation.id,
                                            expecting: created.revision)) { error in
            XCTAssertEqual(error as? VaultMutationError, .conflict("new-folder"))
        }
        XCTAssertEqual(try read("new-folder/added.txt"), "keep")
    }

    func testCreateFileInSelectedFolderKeepsIDAfterReload() throws {
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("notes"),
                                                withIntermediateDirectories: true)
        let loaded = try store.loadWorkspace()

        let created = try store.createFile(at: "notes/new-document.md", expecting: loaded.revision)
        let id = try XCTUnwrap(created.createdID)
        XCTAssertEqual(created.paths[id], "notes/new-document.md")
        XCTAssertEqual(created.document.fragments.first(where: { $0.id == id })?.title,
                       "new-document")
        XCTAssertEqual(created.document.fragments.first(where: { $0.id == id })?.body, "")
        XCTAssertNil(created.operation)

        let reloaded = try store.loadWorkspace()
        XCTAssertEqual(reloaded.paths[id], "notes/new-document.md")
        XCTAssertEqual(reloaded.document.fragments.first(where: { $0.id == id })?.title,
                       "new-document")
        XCTAssertEqual(reloaded.document.fragments.first(where: { $0.id == id })?.body, "")
    }

    func testCreateFileAfterMoveDoesNotReuseTheMovedDocumentsID() throws {
        try write("notes/original.md", "# Original\n\nKeep this body\n")
        let before = try store.loadWorkspace()
        let originalID = try XCTUnwrap(before.document.fragments.first?.id)
        let moved = try store.renameFile(id: originalID, toFileName: "moved.md", expecting: before.revision)
        let created = try store.createFile(at: "notes/original.md", expecting: moved.revision)
        let createdID = try XCTUnwrap(created.createdID)
        XCTAssertNotEqual(createdID, originalID)
        XCTAssertEqual(created.paths[originalID], "notes/moved.md")
        XCTAssertEqual(created.paths[createdID], "notes/original.md")
        XCTAssertTrue(created.document.fragments.first(where: { $0.id == originalID })?.body.contains("Keep this body") == true)
    }

    func testCreateFileDoesNotOverwriteExistingFile() throws {
        try write("notes/existing.md", "원래 파일\n")
        let loaded = try store.loadWorkspace()

        XCTAssertThrowsError(try store.createFile(at: "notes/existing.md",
                                                  expecting: loaded.revision)) { error in
            XCTAssertEqual(error as? VaultMutationError, .occupied("notes/existing.md"))
        }
        XCTAssertEqual(try read("notes/existing.md"), "원래 파일\n")
    }

    func testCreateFileRejectsTraversalPath() throws {
        let loaded = try store.loadWorkspace()

        XCTAssertThrowsError(try store.createFile(at: "../outside.md",
                                                  expecting: loaded.revision)) { error in
            XCTAssertEqual(error as? VaultMutationError, .invalidPath("../outside.md"))
        }
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: dir.deletingLastPathComponent().appendingPathComponent("outside.md").path))
    }

    func testFileRenameKeepsDocumentTitleBodyUnknownFrontmatterAndPathDerivedID() throws {
        try write("notes/original.md", "---   \ntitle: 화면 제목\ncustom: keep-me\n---\n\n본문 그대로\n")
        let before = try store.loadWorkspace()
        let id = try XCTUnwrap(before.document.fragments.first?.id)

        let result = try store.renameFile(id: id, toFileName: "renamed.md",
                                          expecting: before.revision)

        XCTAssertEqual(result.paths[id], "notes/renamed.md")
        XCTAssertEqual(result.document.fragments.first?.title, "화면 제목")
        XCTAssertEqual(result.document.fragments.first?.id, id)
        let raw = try read("notes/renamed.md")
        XCTAssertTrue(raw.hasPrefix("---   \nid: notes/original\n"))
        XCTAssertTrue(raw.contains("custom: keep-me"))
        XCTAssertTrue(raw.contains("본문 그대로"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("notes/original.md").path))
        XCTAssertEqual(result.operation?.sourcePath, "notes/original.md")
        XCTAssertEqual(result.operation?.destinationPath, "notes/renamed.md")
    }

    func testFileMoveRejectsExternalExternalEditAndKeepsBothPathsUntouched() throws {
        try write("from/a.md", "---\nid: a\ntitle: A\n---\n처음\n")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("to"),
                                                withIntermediateDirectories: true)
        let loaded = try store.loadWorkspace()
        try write("from/a.md", "---\nid: a\ntitle: A\n---\n외부 수정\n")

        XCTAssertThrowsError(try store.moveFile(id: "a", toFolder: "to",
                                                expecting: loaded.revision)) { error in
            XCTAssertEqual(error as? VaultMutationError, .conflict("from/a.md"))
        }
        XCTAssertTrue(try read("from/a.md").contains("외부 수정"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("to/a.md").path))
    }

    func testFolderMovePreservesNestedFilesAndIDsAndRejectsSelfDescendant() throws {
        try write("alpha/a.md", "# A\n\n본문\n")
        try write("alpha/nested/raw.txt", "raw bytes")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("target"),
                                                withIntermediateDirectories: true)
        let loaded = try store.loadWorkspace()
        let id = try XCTUnwrap(loaded.document.fragments.first?.id)

        XCTAssertThrowsError(try store.moveFolder(at: "alpha", toFolder: "alpha/nested",
                                                  expecting: loaded.revision)) { error in
            XCTAssertEqual(error as? VaultMutationError, .selfDescendant("alpha/nested/alpha"))
        }
        let result = try store.moveFolder(at: "alpha", toFolder: "target",
                                          expecting: loaded.revision)

        XCTAssertEqual(result.paths[id], "target/alpha/a.md")
        XCTAssertEqual(result.document.fragments.first?.id, id)
        XCTAssertEqual(try read("target/alpha/nested/raw.txt"), "raw bytes")
    }

    func testDestinationCasefoldAndSymlinkEscapeAreRejected() throws {
        try write("a.md", "---\nid: a\n---\nA\n")
        try write("Topic.md", "---\nid: topic\n---\nT\n")
        let loaded = try store.loadWorkspace()
        XCTAssertThrowsError(try store.renameFile(id: "a", toFileName: "topic.md",
                                                  expecting: loaded.revision)) { error in
            XCTAssertEqual(error as? VaultMutationError, .occupied("topic.md"))
        }

        let outside = dir.deletingLastPathComponent().appendingPathComponent("outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("escape"),
                                                   withDestinationURL: outside)
        XCTAssertThrowsError(try store.moveFile(id: "a", toFolder: "escape",
                                                expecting: loaded.revision)) { error in
            XCTAssertEqual(error as? VaultMutationError, .outsideVault("escape/a.md"))
        }
    }

    func testPreviewReportsOnlyRelativeLinksThatWouldBreak() throws {
        try write("docs/a.md", "---\nid: a\n---\n[같이 이동](b.md)\n[밖](../refs/c.md)\n")
        try write("docs/b.md", "---\nid: b\n---\nB\n")
        try write("refs/c.md", "---\nid: c\n---\n[들어옴](../docs/a.md)\n")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("archive"),
                                                withIntermediateDirectories: true)
        let loaded = try store.loadWorkspace()

        let preview = try store.previewMove(from: "docs", to: "archive/docs",
                                            expecting: loaded.revision)

        XCTAssertEqual(preview.linkImpacts.map(\.reference).sorted(), ["../docs/a.md", "../refs/c.md"])
        XCTAssertFalse(preview.linkImpacts.contains { $0.reference == "b.md" })
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("docs/a.md").path),
                      "preview가 실제 파일을 움직였다")
    }

    func testMoveUnderFileCreatesBasenameFolderAtomicallyAndKeepsTitleSeparate() throws {
        try write("ideas/source.md", "# 옮길 문서\n\n본문\n")
        try write("map/target-file.md", "---\nid: target\ntitle: 화면 제목은 다름\n---\n대상\n")
        let loaded = try store.loadWorkspace()
        let sourceID = try XCTUnwrap(loaded.document.fragments.first { $0.title == "옮길 문서" }?.id)

        let preview = try store.previewMoveFile(id: sourceID, underFile: "target",
                                                expecting: loaded.revision)
        XCTAssertEqual(preview.destinationPath, "map/target-file/source.md")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("map/target-file").path), "preview가 폴더를 만들었다")

        let result = try store.moveFile(id: sourceID, underFile: "target",
                                        expecting: loaded.revision)
        XCTAssertEqual(result.paths[sourceID], "map/target-file/source.md")
        XCTAssertTrue(result.folders.contains("map/target-file"))
        XCTAssertEqual(result.document.fragments.first { $0.id == sourceID }?.title, "옮길 문서")
    }

    func testMoveUnderFileFailureNeverDeletesContentAddedToItsNewFolder() throws {
        try write("source.md", "---\nid: source\n---\n원본\n")
        try write("target.md", "---\nid: target\n---\n대상\n")
        let faulty = MoveFaultFileManager()
        let faultStore = VaultStore(vaultURL: dir, fileManager: faulty)
        let loaded = try faultStore.loadWorkspace()
        let vault = try XCTUnwrap(dir)
        faulty.failMove = { source, destination in
            guard source.lastPathComponent == "source.md",
                  destination.path.hasSuffix("/target/source.md") else { return false }
            try "외부에서 추가".write(to: vault.appendingPathComponent("target/added.txt"),
                                      atomically: true, encoding: .utf8)
            return true
        }

        XCTAssertThrowsError(try faultStore.moveFile(id: "source", underFile: "target",
                                                     expecting: loaded.revision))
        XCTAssertEqual(try read("target/added.txt"), "외부에서 추가")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("source.md").path))
    }

    func testFailedMoveDoesNotRollIdentityBackOverAConcurrentEdit() throws {
        try write("source.md", "본문 원본\n")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("destination"),
                                                withIntermediateDirectories: true)
        let faulty = MoveFaultFileManager()
        let faultStore = VaultStore(vaultURL: dir, fileManager: faulty)
        let loaded = try faultStore.loadWorkspace()
        let sourceID = try XCTUnwrap(loaded.document.fragments.first?.id)
        let vault = try XCTUnwrap(dir)
        faulty.failMove = { source, destination in
            guard source.lastPathComponent == "source.md",
                  destination.path.hasSuffix("/destination/source.md") else { return false }
            try "동시에 생긴 새 내용".write(to: vault.appendingPathComponent("source.md"),
                                           atomically: true, encoding: .utf8)
            return true
        }

        XCTAssertThrowsError(try faultStore.moveFile(id: sourceID, toFolder: "destination",
                                                     expecting: loaded.revision))
        XCTAssertEqual(try read("source.md"), "동시에 생긴 새 내용")
    }

    func testTrashPreviewAndResultReportInboundLinksWithoutMutatingDuringPreview() throws {
        try write("docs/a.md", "---\nid: a\n---\n[같이 사라짐](b.md)\n")
        try write("docs/b.md", "---\nid: b\n---\nB\n")
        try write("outside.md", "---\nid: outside\n---\n[참조](docs/a.md)\n")
        let loaded = try store.loadWorkspace()

        let preview = try store.previewTrash(at: "docs", expecting: loaded.revision)
        XCTAssertEqual(preview.linkImpacts.map(\.reference), ["docs/a.md"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("docs/a.md").path))

        let result = try store.trashFolder(at: "docs", expecting: loaded.revision)
        XCTAssertEqual(result.linkImpacts, preview.linkImpacts)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("docs").path))
    }

    func testTrashRestorePersistsOriginalPathAndNeverOverwritesCollision() throws {
        try write("notes/a.md", "---\nid: a\ncustom: keep\n---\n본문\n")
        let loaded = try store.loadWorkspace()
        let trashed = try store.trashFile(id: "a", expecting: loaded.revision)
        let entry = try XCTUnwrap(trashed.workspace.trashEntries.first)
        XCTAssertEqual(entry.originalPath, "notes/a.md")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("notes/a.md").path))

        try write("notes/a.md", "다른 파일")
        XCTAssertThrowsError(try store.restoreTrash(id: entry.id, expecting: trashed.workspace.revision)) { error in
            XCTAssertEqual(error as? VaultMutationError, .occupied("notes/a.md"))
        }
        XCTAssertEqual(try read("notes/a.md"), "다른 파일")
        try FileManager.default.removeItem(at: dir.appendingPathComponent("notes/a.md"))
        let refreshed = try store.loadWorkspace()
        let restored = try store.restoreTrash(id: entry.id, expecting: refreshed.revision)
        XCTAssertEqual(restored.paths["a"], "notes/a.md")
        XCTAssertTrue(try read("notes/a.md").contains("custom: keep"))
        XCTAssertTrue(restored.workspace.trashEntries.isEmpty)
    }

    func testTrashRollbackFailureKeepsPayloadAndMetadataAsARecoverableEntry() throws {
        try write("notes/a.md", "---\nid: a\n---\n유일한 원본\n")
        let faulty = MoveFaultFileManager()
        let faultStore = VaultStore(vaultURL: dir, fileManager: faulty)
        let loaded = try faultStore.loadWorkspace()
        try FileManager.default.createDirectory(at: faultStore.operationJournalURL,
                                                withIntermediateDirectories: true)
        let vault = try XCTUnwrap(dir)
        faulty.failMove = { source, destination in
            guard source.path.contains("/.clonie/trash/"),
                  destination.path.hasSuffix("/notes/a.md") else { return false }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try "외부 파일".write(to: vault.appendingPathComponent("notes/a.md"),
                                  atomically: true, encoding: .utf8)
            return true
        }

        var recoveryPath: String?
        XCTAssertThrowsError(try faultStore.trashFile(id: "a", expecting: loaded.revision)) { error in
            guard case .recoveryRequired(let path) = error as? VaultMutationError else {
                return XCTFail("복구 경로 오류가 아니다: \(error)")
            }
            recoveryPath = path
        }
        XCTAssertEqual(try read("notes/a.md"), "외부 파일")
        let path = try XCTUnwrap(recoveryPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent(path).path))
        XCTAssertTrue(try read(path).contains("유일한 원본"))
        XCTAssertEqual(try faultStore.listTrash().first?.storedRelativePath, path)
    }

    func testLegacyTrashRequiresChosenDestinationAndUndoMovesCurrentBytesOnly() throws {
        try FileManager.default.createDirectory(at: store.trashURL, withIntermediateDirectories: true)
        try "legacy".write(to: store.trashURL.appendingPathComponent("old.md"),
                           atomically: true, encoding: .utf8)
        var workspace = try store.loadWorkspace()
        let legacy = try XCTUnwrap(workspace.trashEntries.first { $0.legacy })
        XCTAssertThrowsError(try store.restoreTrash(id: legacy.id, expecting: workspace.revision)) { error in
            XCTAssertEqual(error as? VaultMutationError, .legacyTrashNeedsDestination(legacy.id))
        }

        try write("one.md", "---\nid: one\n---\n처음\n")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("moved"),
                                                withIntermediateDirectories: true)
        workspace = try store.loadWorkspace()
        let moved = try store.moveFile(id: "one", toFolder: "moved", expecting: workspace.revision)
        let operation = try XCTUnwrap(moved.operation)
        try write("moved/one.md", "---\nid: one\n---\n나중 수정\n")

        XCTAssertThrowsError(try store.undo(operationID: operation.id,
                                            expecting: moved.workspace.revision)) { error in
            XCTAssertEqual(error as? VaultMutationError, .conflict("moved/one.md"))
        }
        let current = try store.loadWorkspace()
        let undone = try store.undo(operationID: operation.id, expecting: current.revision)
        XCTAssertEqual(undone.paths["one"], "one.md")
        XCTAssertTrue(try read("one.md").contains("나중 수정"), "undo가 이후 본문을 과거판으로 되감았다")
    }
}
