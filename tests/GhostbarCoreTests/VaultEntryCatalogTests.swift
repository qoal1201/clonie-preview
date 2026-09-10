import XCTest
@testable import GhostbarCore

final class VaultEntryCatalogTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("clonie-entries-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func write(_ path: String, _ text: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
    func testCatalogShowsOrdinaryFilesAndHiddenConfigurationWithoutTraversingInternals() throws {
        for path in ["README.md", "Sources/App.swift", "scripts/build.sh", ".gitignore", ".github/workflows/test.yml", ".git/config", ".build/file.swift", "node_modules/lib/index.js", ".venv/lib/tool.py", "__pycache__/cache.pyc", ".pytest_cache/state"] { try write(path, "content") }
        let rows = try VaultEntryCatalog(rootURL: root).entries()
        XCTAssertEqual(Set(rows.filter { $0.kind == "file" }.map(\.path)), Set(["README.md", "Sources/App.swift", "scripts/build.sh", ".gitignore", ".github/workflows/test.yml"]))
        XCTAssertTrue(rows.contains { $0.path == ".github" && $0.kind == "folder" })
    }
    func testSymlinkIsLeafAndCannotBeUsedAsTraversalOrMoveTarget() throws {
        try write("actual/inside.swift", "code")
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("shortcut"), withDestinationURL: root.appendingPathComponent("actual"))
        let catalog = VaultEntryCatalog(rootURL: root)
        XCTAssertEqual(try catalog.entry(at: "shortcut").kind, "symlink")
        XCTAssertFalse(try catalog.entry(at: "shortcut").manageable)
        XCTAssertFalse(try catalog.entries().contains { $0.path == "shortcut/inside.swift" })
        XCTAssertThrowsError(try catalog.entry(at: "shortcut/inside.swift"))
        XCTAssertThrowsError(try catalog.entry(at: "../outside"))
    }
    func testGenericMoveAndUndoPreserveBytesAndIdentity() throws {
        try write("code.swift", "let value = 3\n")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("target"), withIntermediateDirectories: false)
        let store = VaultStore(vaultURL: root)
        let before = try store.loadWorkspace()
        let moved = try store.moveEntry(at: "code.swift", toFolder: "target", expecting: before.revision)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("target/code.swift")), Data("let value = 3\n".utf8))
        XCTAssertEqual(before.entries.first { $0.path == "code.swift" }?.id, moved.workspace.entries.first { $0.path == "target/code.swift" }?.id)
        let undone = try store.undo(operationID: XCTUnwrap(moved.operation).id, expecting: moved.revision)
        XCTAssertTrue(undone.workspace.entries.contains { $0.path == "code.swift" })
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("target/code.swift").path))
    }
    func testExplorerMarkdownMoveDoesNotInsertFrontmatter() throws {
        let original = "# Context\n\nA document without metadata.\n"
        try write("README.md", original)
        let store = VaultStore(vaultURL: root), before = try store.loadWorkspace()
        let moved = try store.renameEntry(at: "README.md", toName: "Overview.md", expecting: before.revision)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Overview.md")), Data(original.utf8))
        XCTAssertEqual(moved.workspace.document.fragments.count, 1)
    }
    func testGenericExternalChangesAndFolderChangesRejectStaleMoves() throws {
        try write("src/main.swift", "let a = 1")
        let store = VaultStore(vaultURL: root), before = try store.loadWorkspace()
        try write("src/main.swift", "let a = 12345")
        XCTAssertThrowsError(try store.renameEntry(at: "src/main.swift", toName: "changed.swift", expecting: before.revision))
        XCTAssertThrowsError(try store.renameEntry(at: "src", toName: "other", expecting: before.revision))
        let latest = try store.loadWorkspace()
        try write("src/new.txt", "new")
        XCTAssertThrowsError(try store.renameEntry(at: "src", toName: "other", expecting: latest.revision))
    }
    func testMixedFolderMoveAndUndoPreserveEveryFile() throws {
        try write("src/note.md", "# Original\n")
        try write("src/code.swift", "let a = 1")
        try write("src/.gitignore", "tmp/")
        let store = VaultStore(vaultURL: root), before = try store.loadWorkspace()
        let moved = try store.renameEntry(at: "src", toName: "renamed", expecting: before.revision)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("renamed/note.md")), "# Original\n")
        let undone = try store.undo(operationID: XCTUnwrap(moved.operation).id, expecting: moved.revision)
        XCTAssertEqual(Set(undone.workspace.entries.filter { $0.kind == "file" }.map(\.path)), Set(["src/note.md", "src/code.swift", "src/.gitignore"]))
    }
    func testConflictingAndDescendantTargetsAreRejected() throws {
        try write("a/code.swift", "a"); try write("b/code.swift", "b")
        let store = VaultStore(vaultURL: root), before = try store.loadWorkspace()
        XCTAssertThrowsError(try store.moveEntry(at: "a/code.swift", toFolder: "b", expecting: before.revision))
        XCTAssertThrowsError(try store.moveEntry(at: "a", toFolder: "a", expecting: before.revision))
        XCTAssertThrowsError(try store.renameEntry(at: "a/code.swift", toName: "../oops", expecting: before.revision))
    }
    func testWatcherIncludesGenericFilesAndExcludesInternalChanges() {
        XCTAssertTrue(VaultWatcher.isInteresting(root.path + "/src/app.swift", vaultPath: root.path))
        XCTAssertTrue(VaultWatcher.isInteresting(root.path + "/.gitignore", vaultPath: root.path))
        XCTAssertFalse(VaultWatcher.isInteresting(root.path + "/.git/index", vaultPath: root.path))
        XCTAssertFalse(VaultWatcher.isInteresting(root.path + "/node_modules/x.js", vaultPath: root.path))
    }
    func testLiteralBackslashDoesNotBlockTheRestOfTheCatalog() throws {
        try write("normal.txt", "ordinary")
        try write("a\\b/file.txt", "unusual")
        let rows = try VaultEntryCatalog(rootURL: root).entries()
        XCTAssertEqual(rows.count, 3)
        XCTAssertTrue(try XCTUnwrap(rows.first { $0.path == "normal.txt" }).manageable)
        XCTAssertFalse(try XCTUnwrap(rows.first { $0.path == "a\\b/file.txt" }).manageable)
    }
}
