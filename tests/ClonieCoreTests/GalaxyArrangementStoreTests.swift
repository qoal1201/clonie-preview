import XCTest
@testable import ClonieCore

final class GalaxyArrangementStoreTests: XCTestCase {
    func testSavedViewSurvivesReopenWithoutChangingMarkdownAndRejectsStaleCorpus() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("a.md")
        try Data("# 원문\n그대로 남는다".utf8).write(to: source)
        let before = try Data(contentsOf: source)
        let record = GalaxyArrangement(fingerprint: "v1", model: "jev", anchorIDs: ["a"],
            assignments: [.init(documentID: "b", group: 0, probabilities: [0.8, 0.2], confidence: 0.6)])
        try GalaxyArrangementStore(root: root).save(record, documentIDs: ["a", "b"])
        let reopened = GalaxyArrangementStore(root: root)
        XCTAssertEqual(try reopened.load(fingerprint: "v1", model: "jev", documentIDs: ["a", "b"]), record)
        XCTAssertNil(try reopened.load(fingerprint: "v2", model: "jev", documentIDs: ["a", "b"]))
        XCTAssertNil(try reopened.load(fingerprint: "v1", model: "next", documentIDs: ["a", "b"]))
        XCTAssertThrowsError(try reopened.load(fingerprint: "v1", model: "jev", documentIDs: ["a", "c"]))
        XCTAssertEqual(try Data(contentsOf: source), before)
    }

    func testDuplicateMissingAndMalformedDecisionsCannotBeStored() {
        for row in [GalaxyAssignment(documentID: "a", group: 0, probabilities: [1, 0], confidence: 1),
                    .init(documentID: "b", group: 2, probabilities: [1, 0], confidence: 1),
                    .init(documentID: "b", group: 0, probabilities: [0.1, 0.9], confidence: 1),
                    .init(documentID: "b", group: -1, probabilities: [0, .nan], confidence: 1)] {
            let record = GalaxyArrangement(fingerprint: "v", model: "jev", anchorIDs: ["a"], assignments: [row])
            XCTAssertThrowsError(try record.validate(documentIDs: ["a", "b"]))
        }
    }

    func testSidecarSymlinkCannotRedirectArrangementWrites() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for url in [root, outside] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        defer { for url in [root, outside] { try? FileManager.default.removeItem(at: url) } }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(".clonie"), withDestinationURL: outside)
        let record = GalaxyArrangement(fingerprint: "v", model: "jev", anchorIDs: ["a"],
            assignments: [.init(documentID: "b", group: -1, probabilities: [0, 1], confidence: 1)])
        XCTAssertThrowsError(try GalaxyArrangementStore(root: root).save(record, documentIDs: ["a", "b"]))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }
}
