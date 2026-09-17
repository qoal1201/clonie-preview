import XCTest
@testable import ClonieCore

final class AskedMaintenanceTests: XCTestCase {
    private let timestamp = Date(timeIntervalSince1970: 1_757_000_000)

    private func retrieval() -> SessionRetrieval {
        SessionRetrieval(id: "retrieval-1", query: "예산이 얼마인가요?", scope: "회의",
                         requestedAt: 12, completedAt: 12.4,
                         candidates: [SessionCandidate(id: "budget", title: "예산",
                            path: "회의/예산.md", excerpt: "예산은 320만 원이다.", score: 0.83)],
                         status: "ready", displayedID: "budget", displayMode: "manual")
    }

    func testOldJSONKeepsPracticeFieldsWithoutRegisteringMaintenance() throws {
        let data = Data(#"{"schemaVersion":1,"entries":[{"id":"old","text":"예산은?","source":"sun","at":"2025-09-01T00:00:00Z","practiceColor":"g","practicedAt":"2025-09-02T00:00:00Z"}]}"#.utf8)
        let log = try FragmentStore.makeDecoder().decode(AskedLog.self, from: data)
        let entry = try XCTUnwrap(log.entries.first)
        XCTAssertEqual(entry.source, .sun)
        XCTAssertEqual(entry.practiceColor, "g")
        XCTAssertNotNil(entry.practicedAt)
        XCTAssertNil(entry.reviewStatus)
        XCTAssertNil(entry.reviewScope)
        XCTAssertNil(entry.reviewRetrieval)
        let encoded = try FragmentStore.makeEncoder().encode(log)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let entries = try XCTUnwrap(payload["entries"] as? [[String: Any]])
        XCTAssertNil(entries.first?["reviewStatus"])
        XCTAssertNil(entries.first?["reviewScope"])
        XCTAssertNil(entries.first?["reviewRetrieval"])
    }

    func testReviewStatusAndRetrievalSnapshotRoundTrip() throws {
        for status in ["open", "done"] {
            for scope in ["", "회의"] {
                let entry = AskedEntry(id: "asked-1", text: "예산이 얼마인가요?", source: .sun,
                                       at: timestamp, color: "a", score: 0.83, how: "뜻", count: 2,
                                       practiceColor: "g", practicedAt: timestamp,
                                       reviewStatus: status, reviewScope: scope,
                                       reviewRetrieval: retrieval())
                let data = try FragmentStore.makeEncoder().encode(entry)
                let restored = try FragmentStore.makeDecoder().decode(AskedEntry.self, from: data)
                XCTAssertEqual(restored, entry)
                XCTAssertEqual(restored.reviewRetrieval?.candidates.first?.excerpt, "예산은 320만 원이다.")
                XCTAssertEqual(restored.reviewRetrieval?.status, "ready")
            }
        }
    }

    func testMaintenanceMetadataSaveAndReloadLeavesMarkdownUntouched() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clonie-asked-maintenance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("예산.md")
        let original = Data("---\ntags: [예산, 회의]\n---\n# 예산\n\n예산은 320만 원이다.\n\n".utf8)
        try original.write(to: path)
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: path.path)
        let originalDate = try FileManager.default.attributesOfItem(atPath: path.path)[.modificationDate] as? Date
        let store = VaultStore(vaultURL: directory)
        var document = try store.load().document
        let fragments = document.fragments
        XCTAssertEqual(fragments.count, 1)
        document.asked = [AskedEntry(id: "asked-1", text: "예산이 얼마인가요?", source: .sun,
                                     at: timestamp, reviewStatus: "open", reviewScope: "",
                                     reviewRetrieval: retrieval())]
        try store.save(document)
        document.asked?[0].reviewStatus = "done"
        try store.save(document)

        let restored = try VaultStore(vaultURL: directory).load().document
        XCTAssertEqual(restored.asked, document.asked)
        XCTAssertEqual(restored.fragments, fragments)
        XCTAssertEqual(try store.markdownRelativePaths(), ["예산.md"])
        XCTAssertEqual(try Data(contentsOf: path), original)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: path.path)[.modificationDate] as? Date,
                       originalDate, "보완 상태만 저장하면 Markdown 파일을 다시 쓰지 않아야 한다")
    }
}
