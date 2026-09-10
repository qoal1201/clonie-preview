import XCTest
@testable import GhostbarDocuments

final class SourceCatalogTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("raw"), withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testListsOriginalsAndReadsFuturePlansWithSourceHash() throws {
        let source = root.appendingPathComponent("raw/plan.txt")
        try "다음에는 오디오 권한 안내를 개선한다.".write(to: source, atomically: true, encoding: .utf8)
        let catalog = SourceCatalog(vaultURL: root)
        let listed = try catalog.list()
        XCTAssertEqual(listed.map(\.path), ["raw/plan.txt"])
        let read = try catalog.read(path: "raw/plan.txt", offset: 0, limit: 8)
        XCTAssertEqual(read.hash, listed[0].hash)
        XCTAssertEqual(read.text, "다음에는 오디오")
        XCTAssertNotNil(read.nextOffset)
        let rest = try catalog.read(path: read.path, offset: read.nextOffset!, limit: 100)
        XCTAssertEqual(read.text + rest.text, "다음에는 오디오 권한 안내를 개선한다.")
    }

    func testRejectsTraversalAndSymlinkOutsideVault() throws {
        let catalog = SourceCatalog(vaultURL: root)
        XCTAssertThrowsError(try catalog.read(path: "../secrets.txt"))
        XCTAssertThrowsError(try catalog.read(path: "/etc/hosts"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("raw/escape.txt"), withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
        XCTAssertThrowsError(try catalog.read(path: "raw/escape.txt"))
        XCTAssertTrue(try catalog.list().isEmpty)
    }

    func testReplayUsesSameSourceIdentityAndDetectsChanges() throws {
        let source = root.appendingPathComponent("raw/memo.md")
        try "first".write(to: source, atomically: true, encoding: .utf8)
        let catalog = SourceCatalog(vaultURL: root)
        let first = try catalog.list()[0]
        XCTAssertEqual(try catalog.list()[0].hash, first.hash)
        try "revised".write(to: source, atomically: true, encoding: .utf8)
        XCTAssertNotEqual(try catalog.list()[0].hash, first.hash)
        XCTAssertEqual(try String(contentsOf: source), "revised")
    }
}
