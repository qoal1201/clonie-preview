import XCTest
@testable import GhostbarCore

final class VaultConnectionIOTests: XCTestCase {
    func testMissingSelectedRootIsReportedAndNeverRecreated() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let io = VaultIO(store: VaultStore(vaultURL: root), requireExistingRoot: true)
        let finished = expectation(description: "missing folder")
        var trouble: VaultIO.Trouble?
        io.loadVersioned(onTrouble: { trouble = $0 }) { loaded in
            XCTAssertNil(loaded)
            XCTAssertNotNil(trouble)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
            finished.fulfill()
        }
        wait(for: [finished], timeout: 3)
    }

    func testSaveDoesNotRecreateASelectedRootThatDisappeared() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = VaultStore(vaultURL: root)
        let loaded = try store.loadVersioned()
        let io = VaultIO(store: store, requireExistingRoot: true)
        try FileManager.default.removeItem(at: root)
        let finished = expectation(description: "save refused")
        io.save(.empty, expecting: loaded.revision) { result in
            guard case .failure = result else { XCTFail("missing folder became a successful save");finished.fulfill();return }
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
            finished.fulfill()
        }
        wait(for: [finished], timeout: 3)
    }
}
