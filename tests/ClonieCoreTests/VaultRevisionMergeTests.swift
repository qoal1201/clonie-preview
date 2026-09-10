import XCTest
@testable import ClonieCore

/// 화면이 외부 reload를 받아도 **로컬에서 손댄 파일만** 옛 기준선을 유지하는가 (#84).
final class VaultRevisionMergeTests: XCTestCase {
    private var dir: URL!
    private var store: VaultStore!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("clonie-revision-merge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store = VaultStore(vaultURL: dir)
        try write("a.md", id: "a", body: "A 처음")
        try write("b.md", id: "b", body: "B 처음")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func write(_ name: String, id: String, body: String) throws {
        try "---\nid: \(id)\ntitle: \(id.uppercased())\n---\n\(body)\n"
            .write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private func body(_ name: String) throws -> String {
        try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
    }

    func testPreservedFileBaselineConflictsWhileUnrelatedExternalFileUsesLatestBaseline() throws {
        let editing = try store.loadVersioned()
        try write("a.md", id: "a", body: "A 외부")
        try write("b.md", id: "b", body: "B 외부")
        let latest = try store.loadVersioned()
        var attempted = latest.result.document
        attempted.fragments[attempted.fragments.firstIndex { $0.id == "a" }!].body = "A 앱"

        let hybrid = try latest.revision.preservingFileBaselines(
            for: ["a"], from: editing.revision)

        XCTAssertThrowsError(try store.save(attempted, expecting: hybrid)) { error in
            let conflicts = (error as? VaultConflictError)?.conflicts
            XCTAssertEqual(conflicts?.map(\.fragmentID), ["a"],
                           "최신으로 받아들인 다른 파일까지 거짓 충돌로 막았다")
        }
        XCTAssertTrue(try body("a.md").contains("A 외부"))
        XCTAssertTrue(try body("b.md").contains("B 외부"))
    }

    func testPreservedLocalFileSavesWhileAnUnrelatedExternalEditSurvives() throws {
        let editing = try store.loadVersioned()
        try write("b.md", id: "b", body: "B 외부")
        let latest = try store.loadVersioned()
        var attempted = latest.result.document
        attempted.fragments[attempted.fragments.firstIndex { $0.id == "a" }!].body = "A 앱"
        let hybrid = try latest.revision.preservingFileBaselines(
            for: ["a"], from: editing.revision)

        _ = try store.save(attempted, expecting: hybrid)

        XCTAssertTrue(try body("a.md").contains("A 앱"))
        XCTAssertTrue(try body("b.md").contains("B 외부"))
    }

    func testCannotSpliceABaselineFromAnotherVault() throws {
        let editing = try store.loadVersioned()
        let otherURL = dir.deletingLastPathComponent()
            .appendingPathComponent("clonie-other-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: otherURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: otherURL) }
        let other = try VaultStore(vaultURL: otherURL).loadVersioned()

        XCTAssertThrowsError(try editing.revision.preservingFileBaselines(
            for: ["a"], from: other.revision)) { error in
            XCTAssertNotNil(error as? VaultRevisionError)
        }
    }

    func testPinnedRevisionKeepsOnlyTheRequestedFileBaselines() throws {
        let loaded = try store.loadVersioned()
        let pinned = loaded.revision.selectingFileBaselines(for: ["a"])
        try write("a.md", id: "a", body: "A 외부")
        let latest = try store.loadVersioned()
        var attempted = latest.result.document
        attempted.fragments[attempted.fragments.firstIndex { $0.id == "a" }!].body = "A 앱"

        let hybrid = try latest.revision.preservingFileBaselines(for: ["a"], from: pinned)

        XCTAssertThrowsError(try store.save(attempted, expecting: hybrid)) { error in
            XCTAssertEqual((error as? VaultConflictError)?.conflicts.map(\.fragmentID), ["a"])
        }
        XCTAssertEqual(pinned.files.count, 1)
        XCTAssertEqual(pinned.files["a"]?.relativePath, "a.md")
    }
}
