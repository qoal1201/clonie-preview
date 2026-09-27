import XCTest
@testable import ClonieCore

final class VaultRevisionRegistryTests: XCTestCase {
    private var root: URL!
    private var store: VaultStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("clonie-revision-registry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = VaultStore(vaultURL: root)
        try write("a", body: "A 처음")
        try write("b", body: "B 처음")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func write(_ id: String, body: String) throws {
        try "---\nid: \(id)\ntitle: \(id.uppercased())\n---\n\(body)\n"
            .write(to: root.appendingPathComponent("\(id).md"), atomically: true, encoding: .utf8)
    }

    private func contents(_ id: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent("\(id).md"), encoding: .utf8)
    }

    @discardableResult
    private func expire(_ token: String, in registry: inout VaultRevisionRegistry,
                        with revision: VaultRevision) -> String {
        var latest = ""
        for _ in 0..<32 { latest = registry.remember(revision) }
        XCTAssertNil(registry.revision(for: token))
        return latest
    }

    func testKeepsExactly32RecentOpaqueTokens() throws {
        var registry = VaultRevisionRegistry()
        let revision = try store.loadVersioned().revision
        let first = registry.remember(revision)
        let remaining = (0..<31).map { _ in registry.remember(revision) }
        XCTAssertNotNil(UUID(uuidString: first))
        XCTAssertEqual(Set(remaining + [first]).count, 32)
        XCTAssertEqual(registry.revision(for: first), revision)
        _ = registry.remember(revision)
        XCTAssertNil(registry.revision(for: first))
        for token in remaining { XCTAssertEqual(registry.revision(for: token), revision) }
    }

    func testPinnedExpiredTokenWorksOnlyAsAnOverride() throws {
        var registry = VaultRevisionRegistry()
        let editing = try store.loadVersioned().revision
        let token = registry.remember(editing)
        registry.pin([token: ["a"]])
        try write("a", body: "A 외부")
        try write("b", body: "B 외부")
        let latest = try store.loadVersioned().revision
        let base = expire(token, in: &registry, with: latest)

        let merged = try registry.resolveForSave(base: base, overrides: ["a": token])
        XCTAssertEqual(merged.files["a"], editing.files["a"])
        XCTAssertEqual(merged.files["b"], latest.files["b"])
        XCTAssertThrowsError(try registry.resolveForSave(base: token, overrides: ["a": token])) {
            XCTAssertEqual($0 as? VaultRevisionRegistry.ResolutionError, .expiredToken)
        }
    }

    func testReplacingPinsKeepsRequestedExpiredPinAndReleasesOthers() throws {
        var registry = VaultRevisionRegistry()
        let revision = try store.loadVersioned().revision
        let a = registry.remember(revision)
        let b = registry.remember(revision)
        registry.pin([a: ["a"], b: ["b"]])
        let base = expire(b, in: &registry, with: revision)
        registry.pin([a: ["a"], "unknown": ["b"]])

        XCTAssertNoThrow(try registry.resolveForSave(base: base, overrides: ["a": a]))
        XCTAssertThrowsError(try registry.resolveForSave(base: base, overrides: ["b": b]))
        registry.pin([a: []])
        XCTAssertThrowsError(try registry.resolveForSave(base: base, overrides: ["a": a]))
    }

    func testPinRetainsOnlySelectedFileBaselinesIncludingAnAbsentNewFile() throws {
        var registry = VaultRevisionRegistry()
        let editing = try store.loadVersioned().revision
        let token = registry.remember(editing)
        registry.pin([token: ["a", "new"]])
        try write("new", body: "외부에서 같은 id 생성")
        let latest = try store.loadVersioned().revision
        let base = expire(token, in: &registry, with: latest)
        // Re-pinning an expired token uses its retained subset, never the old full vault.
        registry.pin([token: ["new"]])
        let merged = try registry.resolveForSave(base: base, overrides: ["new": token])
        XCTAssertNil(merged.files["new"])
        XCTAssertNil(merged.baseline["new"])
        XCTAssertEqual(merged.files["a"], latest.files["a"])
        XCTAssertEqual(merged.files["b"], latest.files["b"])
    }

    func testResetDropsRecentAndPinnedTokens() throws {
        var registry = VaultRevisionRegistry()
        let revision = try store.loadVersioned().revision
        let token = registry.remember(revision)
        registry.pin([token: ["a"]])
        registry.reset()
        let base = registry.remember(revision)
        XCTAssertNil(registry.revision(for: token))
        XCTAssertThrowsError(try registry.resolveForSave(base: token, overrides: [:]))
        XCTAssertThrowsError(try registry.resolveForSave(base: base, overrides: ["a": token]))
        XCTAssertEqual(try registry.resolveForSave(base: base, overrides: [:]), revision)
    }

    func testRejectsUnknownOrUnpinnedExpiredOverride() throws {
        var registry = VaultRevisionRegistry()
        let revision = try store.loadVersioned().revision
        let token = registry.remember(revision)
        let base = expire(token, in: &registry, with: revision)
        for invalid in [token, "unknown"] {
            XCTAssertThrowsError(try registry.resolveForSave(base: base, overrides: ["a": invalid])) {
                XCTAssertEqual($0 as? VaultRevisionRegistry.ResolutionError, .expiredToken)
            }
        }
    }

    func testRejectsPinnedBaselineFromAnotherVault() throws {
        var registry = VaultRevisionRegistry()
        let revision = try store.loadVersioned().revision
        let token = registry.remember(revision)
        registry.pin([token: ["a"]])
        let other = VaultRevision(vaultPath: root.path + "-other", files: [:], baseline: [:])
        let base = expire(token, in: &registry, with: other)
        XCTAssertThrowsError(try registry.resolveForSave(base: base, overrides: ["a": token])) {
            XCTAssertNotNil($0 as? VaultRevisionError)
        }
    }

    func testExpiredPinnedEditStillConflictsWithoutChangingExternalMarkdown() throws {
        var registry = VaultRevisionRegistry()
        let token = registry.remember(try store.loadVersioned().revision)
        registry.pin([token: ["a"]])
        try write("a", body: "A 외부")
        try write("b", body: "B 외부")
        let latest = try store.loadVersioned()
        let base = expire(token, in: &registry, with: latest.revision)
        var attempted = latest.result.document
        attempted.fragments[attempted.fragments.firstIndex { $0.id == "a" }!].body = "A 앱"
        let beforeA = try contents("a"), beforeB = try contents("b")
        let expected = try registry.resolveForSave(base: base, overrides: ["a": token])

        XCTAssertThrowsError(try store.save(attempted, expecting: expected)) {
            XCTAssertEqual(($0 as? VaultConflictError)?.conflicts.map(\.fragmentID), ["a"])
        }
        XCTAssertEqual(try contents("a"), beforeA)
        XCTAssertEqual(try contents("b"), beforeB)
    }

    func testExpiredPinnedEditSavesAlongsideUnrelatedExternalChange() throws {
        var registry = VaultRevisionRegistry()
        let token = registry.remember(try store.loadVersioned().revision)
        registry.pin([token: ["a"]])
        try write("b", body: "B 외부")
        let latest = try store.loadVersioned()
        let base = expire(token, in: &registry, with: latest.revision)
        var attempted = latest.result.document
        attempted.fragments[attempted.fragments.firstIndex { $0.id == "a" }!].body = "A 앱"
        let beforeB = try contents("b")
        let expected = try registry.resolveForSave(base: base, overrides: ["a": token])

        _ = try store.save(attempted, expecting: expected)
        XCTAssertTrue(try contents("a").contains("A 앱"))
        XCTAssertEqual(try contents("b"), beforeB)
    }
}
