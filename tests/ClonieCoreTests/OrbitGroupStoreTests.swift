import XCTest
@testable import ClonieCore

final class OrbitGroupStoreTests: XCTestCase {
    private var firstRoot: URL!

    override func setUpWithError() throws {
        firstRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("clonie-orbit-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: firstRoot)
    }

    private func entry(_ id: String, _ path: String,
                       kind: String = "file", manageable: Bool = true) -> VaultEntry {
        VaultEntry(id: id, path: path, kind: kind, byteCount: 1,
                   revision: "revision-" + id, manageable: manageable)
    }

    private func pair(_ prefix: String = "notes") -> [VaultEntry] {
        [entry("a", "\(prefix)/a.md"), entry("b", "\(prefix)/b.md")]
    }

    private func group(_ store: OrbitGroupStore,
                       entries: [VaultEntry] = [
                        VaultEntry(id: "a", path: "notes/a.md", kind: "file", byteCount: 1,
                                   revision: "a", manageable: true),
                        VaultEntry(id: "b", path: "notes/b.md", kind: "file", byteCount: 1,
                                   revision: "b", manageable: true)
                       ]) throws -> OrbitGroup {
        try XCTUnwrap(store.join(path: entries[0].path,
                                 targetPath: entries[1].path,
                                 entries: entries).first)
    }

    func testJoinRoundTripAndFreshStoreKeepOnlyPresentationMetadata() throws {
        let store = OrbitGroupStore(rootURL: firstRoot)
        let entries = pair()

        let created = try group(store, entries: entries)
        XCTAssertEqual(created.paths, ["notes/a.md", "notes/b.md"])
        XCTAssertEqual(try OrbitGroupStore(rootURL: firstRoot).load(entries: entries), [created])

        let raw = try Data(contentsOf: store.orbitGroupsURL)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: raw) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, OrbitGroupStore.currentSchemaVersion)
        let groups = try XCTUnwrap(object["groups"] as? [[String: Any]])
        let members = try XCTUnwrap(groups.first?["members"] as? [[String: Any]])
        XCTAssertEqual(Set(members.compactMap { $0["path"] as? String }), Set(created.paths))
        XCTAssertEqual(Set(members.compactMap { $0["entryID"] as? String }), ["a", "b"])
    }

    func testGroupsAreIsolatedByVaultRoot() throws {
        let secondRoot = firstRoot.deletingLastPathComponent()
            .appendingPathComponent("clonie-orbit-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: secondRoot) }

        let first = OrbitGroupStore(rootURL: firstRoot)
        let entries = pair()
        _ = try group(first, entries: entries)
        XCTAssertTrue(try OrbitGroupStore(rootURL: secondRoot).load(entries: entries).isEmpty)
    }

    func testJoinRejectsDifferentParentsFoldersAndUnmanageableFiles() throws {
        let store = OrbitGroupStore(rootURL: firstRoot)
        let entries = [
            entry("a", "notes/a.md"), entry("b", "notes/b.md"), entry("c", "other/c.md"),
            entry("folder", "notes/sub", kind: "folder"),
            entry("link", "notes/link", kind: "symlink", manageable: false)
        ]

        XCTAssertNoThrow(try store.join(path: "notes/a.md", targetPath: "notes/b.md", entries: entries))
        XCTAssertThrowsError(try store.join(path: "notes/a.md", targetPath: "other/c.md", entries: entries)) { error in
            XCTAssertEqual(error as? OrbitGroupStoreError,
                           .differentParents("notes/a.md", "other/c.md"))
        }
        XCTAssertThrowsError(try store.join(path: "notes/a.md", targetPath: "notes/sub", entries: entries)) { error in
            XCTAssertEqual(error as? OrbitGroupStoreError, .invalidMember("notes/sub"))
        }
        XCTAssertThrowsError(try store.join(path: "notes/a.md", targetPath: "notes/link", entries: entries)) { error in
            XCTAssertEqual(error as? OrbitGroupStoreError, .invalidMember("notes/link"))
        }
    }

    func testSplitDropsSingletonAndPreservesRemainingGroup() throws {
        let store = OrbitGroupStore(rootURL: firstRoot)
        let entries = [entry("a", "notes/a.md"), entry("b", "notes/b.md"), entry("c", "notes/c.md")]
        _ = try group(store, entries: Array(entries.prefix(2)))
        let joined = try store.join(path: "notes/c.md", targetPath: "notes/a.md", entries: entries)
        XCTAssertEqual(joined.first?.paths, ["notes/a.md", "notes/b.md", "notes/c.md"])

        XCTAssertEqual(try store.split(path: "notes/c.md", entries: entries).first?.paths,
                       ["notes/a.md", "notes/b.md"])
        XCTAssertTrue(try store.split(path: "notes/a.md", entries: entries).isEmpty)
        XCTAssertTrue(try store.load(entries: entries).isEmpty)
    }

    func testExactPathWinsWhenAtomicReplacementChangesInode() throws {
        let store = OrbitGroupStore(rootURL: firstRoot)
        let before = pair()
        let created = try group(store, entries: before)
        let replaced = [entry("new-a", "notes/a.md"), entry("b", "notes/b.md")]

        XCTAssertEqual(try store.load(entries: replaced), [created])
    }

    func testRenameAfterAtomicSaveRemainsGroupedAcrossFreshStores() throws {
        let store = OrbitGroupStore(rootURL: firstRoot)
        let created = try group(store, entries: pair())
        _ = try store.load(entries: [entry("new-a", "notes/a.md"), entry("b", "notes/b.md")])
        let renamed = [entry("new-a", "notes/renamed.md"), entry("b", "notes/b.md")]
        let expected = [OrbitGroup(id: created.id, paths: ["notes/b.md", "notes/renamed.md"])]
        XCTAssertEqual(try OrbitGroupStore(rootURL: firstRoot).load(entries: renamed), expected)
        XCTAssertEqual(try OrbitGroupStore(rootURL: firstRoot).load(entries: renamed), expected)
    }

    func testMovingOneMemberBetweenOrbitsPreservesBothOtherGroups() throws {
        let store = OrbitGroupStore(rootURL: firstRoot)
        let entries = ["a", "b", "c", "d", "e"].map { entry($0, "notes/\($0).md") }
        _ = try store.join(path: "notes/b.md", targetPath: "notes/a.md", entries: entries)
        _ = try store.join(path: "notes/c.md", targetPath: "notes/a.md", entries: entries)
        let before = try store.join(path: "notes/e.md", targetPath: "notes/d.md", entries: entries)
        let sourceID = try XCTUnwrap(before.first { $0.paths.contains("notes/a.md") }?.id)
        let targetID = try XCTUnwrap(before.first { $0.paths.contains("notes/d.md") }?.id)

        let moved = try store.join(path: "notes/c.md", targetPath: "notes/d.md", entries: entries)
        XCTAssertEqual(moved.first { $0.id == sourceID }?.paths, ["notes/a.md", "notes/b.md"])
        XCTAssertEqual(moved.first { $0.id == targetID }?.paths, ["notes/c.md", "notes/d.md", "notes/e.md"])
        XCTAssertEqual(try OrbitGroupStore(rootURL: firstRoot).load(entries: entries), moved)
    }

    func testMovingFromAPairToASingleFileDoesNotCarryTheOtherMember() throws {
        let store = OrbitGroupStore(rootURL: firstRoot)
        let entries = ["a", "b", "c"].map { entry($0, "notes/\($0).md") }
        _ = try store.join(path: "notes/a.md", targetPath: "notes/b.md", entries: entries)
        let moved = try store.join(path: "notes/a.md", targetPath: "notes/c.md", entries: entries)
        XCTAssertEqual(moved.count, 1)
        XCTAssertEqual(moved.first?.paths, ["notes/a.md", "notes/c.md"])
    }

    func testUniqueIdentityFollowsRenameAndWholeFolderMoveButPartialMoveKeepsOriginalParent() throws {
        let store = OrbitGroupStore(rootURL: firstRoot)
        let before = [entry("a", "old/a.md"), entry("b", "old/b.md"), entry("c", "old/c.md")]
        _ = try group(store, entries: Array(before.prefix(2)))
        _ = try store.join(path: "old/c.md", targetPath: "old/a.md", entries: before)

        let renamed = [entry("a", "old/renamed.md"), entry("b", "old/b.md"), entry("c", "old/c.md")]
        XCTAssertEqual(try store.load(entries: renamed).first?.paths,
                       ["old/b.md", "old/c.md", "old/renamed.md"])

        let movedFolder = [entry("a", "new/renamed.md"), entry("b", "new/b.md"), entry("c", "new/c.md")]
        XCTAssertEqual(try store.load(entries: movedFolder).first?.paths,
                       ["new/b.md", "new/c.md", "new/renamed.md"])

        let partiallyMoved = [entry("a", "new/renamed.md"), entry("b", "new/b.md"), entry("c", "other/c.md")]
        XCTAssertEqual(try store.load(entries: partiallyMoved).first?.paths,
                       ["new/b.md", "new/renamed.md"])
    }

    func testHardLinkIdentityAmbiguityDoesNotChooseAnArbitraryPath() throws {
        let store = OrbitGroupStore(rootURL: firstRoot)
        let before = [entry("same", "notes/a.md"), entry("other", "notes/b.md")]
        _ = try group(store, entries: before)
        let ambiguous = [
            entry("same", "new/a.md"), entry("same", "new/also-a.md"),
            entry("other", "notes/b.md")
        ]
        XCTAssertTrue(try store.load(entries: ambiguous).isEmpty)
    }

    func testLoadDoesNotRewriteWhenADeletedMemberReappearsForUndo() throws {
        let store = OrbitGroupStore(rootURL: firstRoot)
        let before = pair()
        let created = try group(store, entries: before)
        let deleted = [entry("a", "notes/a.md")]
        XCTAssertTrue(try store.load(entries: deleted).isEmpty)
        XCTAssertEqual(try store.load(entries: before), [created])
    }

    func testDuplicateMembersAreDeduplicatedWithoutRewritingTheSidecar() throws {
        let store = OrbitGroupStore(rootURL: firstRoot)
        let entries = pair()
        _ = try group(store, entries: entries)
        let original = try Data(contentsOf: store.orbitGroupsURL)
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: original) as? [String: Any])
        var groups = try XCTUnwrap(object["groups"] as? [[String: Any]])
        var members = try XCTUnwrap(groups[0]["members"] as? [[String: Any]])
        members.append(members[0])
        groups[0]["members"] = members
        object["groups"] = groups
        let duplicate = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try duplicate.write(to: store.orbitGroupsURL)

        XCTAssertEqual(try store.load(entries: entries).first?.paths, ["notes/a.md", "notes/b.md"])
        XCTAssertEqual(try Data(contentsOf: store.orbitGroupsURL), duplicate)
    }

    func testCorruptAndFutureMetadataAreThrownWithoutChangingTheOriginal() throws {
        let store = OrbitGroupStore(rootURL: firstRoot)
        try FileManager.default.createDirectory(at: store.orbitGroupsURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        let corrupt = Data("not json".utf8)
        try corrupt.write(to: store.orbitGroupsURL)
        XCTAssertThrowsError(try store.load(entries: pair()))
        XCTAssertEqual(try Data(contentsOf: store.orbitGroupsURL), corrupt)

        let future = Data("{\"schemaVersion\":2,\"groups\":[]}".utf8)
        try future.write(to: store.orbitGroupsURL)
        XCTAssertThrowsError(try store.load(entries: pair())) { error in
            XCTAssertEqual(error as? OrbitGroupStoreError, .unknownSchemaVersion(2))
        }
        XCTAssertEqual(try Data(contentsOf: store.orbitGroupsURL), future)
    }

    func testSidecarDirectoryAndFileSymlinksAreRejectedWithoutFollowingThem() throws {
        let sidecar = firstRoot.appendingPathComponent(".clonie", isDirectory: true)
        let target = firstRoot.deletingLastPathComponent()
            .appendingPathComponent("clonie-orbit-target-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: target) }
        try FileManager.default.createSymbolicLink(at: sidecar, withDestinationURL: target)
        let store = OrbitGroupStore(rootURL: firstRoot)
        XCTAssertThrowsError(try store.load(entries: pair())) { error in
            guard case .sidecarSymlink = error as? OrbitGroupStoreError else {
                return XCTFail("사이드카 디렉터리 심볼릭 링크를 허용했다: \(error)")
            }
        }

        try FileManager.default.removeItem(at: sidecar)
        try FileManager.default.createDirectory(at: sidecar, withIntermediateDirectories: true)
        let fileTarget = target.appendingPathComponent("orbit.json")
        try Data("{}".utf8).write(to: fileTarget)
        try FileManager.default.createSymbolicLink(at: store.orbitGroupsURL, withDestinationURL: fileTarget)
        XCTAssertThrowsError(try store.load(entries: pair())) { error in
            guard case .sidecarSymlink = error as? OrbitGroupStoreError else {
                return XCTFail("메타데이터 파일 심볼릭 링크를 허용했다: \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: fileTarget), Data("{}".utf8))
    }
}
