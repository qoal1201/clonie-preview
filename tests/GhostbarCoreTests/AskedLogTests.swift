import XCTest
@testable import GhostbarCore

/// 입력 기록 (ADR 0006 §③ · #79) — **판을 안 올리고** 새 칸을 얹었는가, 그리고
/// `.clonie/asked.json` 이 `document.json` 과 **따로** 사는가.
final class AskedLogTests: XCTestCase {
    private let t = Date(timeIntervalSince1970: 1_757_000_000)

    /// ⚠ 옵셔널이 핵심이다 — `nil` 이면 키가 아예 안 나가서 옛 판 파일과 같은 글자다.
    func testDocumentWithoutAskedEncodesNoKey() throws {
        let doc = CueDocument(questions: [], fragments: [])
        let data = try FragmentStore.makeEncoder().encode(doc)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("\"asked\""))
    }

    func testOldDocumentJSONWithoutAskedStillDecodes() throws {
        let json = #"{"schemaVersion":1,"questions":[],"fragments":[]}"#
        let doc = try FragmentStore.makeDecoder().decode(CueDocument.self, from: Data(json.utf8))
        XCTAssertNil(doc.asked)
    }

    func testAskedLogRoundTrip() throws {
        let e = AskedEntry(id: "a-1", text: "주도적으로 문제를 해결한 경험", source: .interview,
                           at: t, color: "r", score: 0.31, how: "뜻", count: 2)
        let log = AskedLog(entries: [e])
        let data = try FragmentStore.makeEncoder().encode(log)
        let back = try FragmentStore.makeDecoder().decode(AskedLog.self, from: data)
        XCTAssertEqual(back, log)
        XCTAssertEqual(back.schemaVersion, 1)
    }

    /// 연습이 다시 재서 준 색. ⚠ **이 두 칸의 이름이 곧 디스크 키다** — 화면(JS)이 쓰는 글자와
    /// 갈리면 Swift 가 그 줄을 조용히 못 읽고 「연습에서 받은 색」이 매번 없는 것이 된다.
    func testPracticeColorRoundTripsUnderItsOwnKeys() throws {
        let e = AskedEntry(id: "a-3", text: "왜 우리 회사인가", source: .sun, at: t,
                           color: "r", practiceColor: "g", practicedAt: t)
        let data = try FragmentStore.makeEncoder().encode(e)
        let s = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(s.contains("\"practiceColor\""), s)
        XCTAssertTrue(s.contains("\"practicedAt\""), s)
        XCTAssertEqual(try FragmentStore.makeDecoder().decode(AskedEntry.self, from: data), e)
    }

    /// 색이 없는 줄(글자 자 판정)은 `color` 키가 안 나간다 — 옵셔널 규율 그대로.
    func testEntryWithoutColorOmitsKey() throws {
        let e = AskedEntry(id: "a-2", text: "왜 우리 회사인가", source: .sun, at: t)
        let s = String(decoding: try FragmentStore.makeEncoder().encode(e), as: UTF8.self)
        XCTAssertFalse(s.contains("\"color\""))
        XCTAssertTrue(s.contains("\"source\":\"sun\"") || s.contains("\"source\" : \"sun\""))
    }

    // MARK: - 볼트 왕복 (VaultStoreTests 의 setUp 과 같은 임시 볼트)

    private var dir: URL!
    private var store: VaultStore!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("asked-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store = VaultStore(vaultURL: dir)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func entry(_ id: String, _ text: String) -> AskedEntry {
        AskedEntry(id: id, text: text, source: .sun, at: t, color: "g", score: 1.02, how: "뜻", count: 1)
    }

    func testAskedRoundTripsThroughVault() throws {
        let doc = CueDocument(questions: [], fragments: [], asked: [entry("a-1", "왜 우리 회사인가")])
        try store.save(doc)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.askedJSONURL.path))
        let back = try store.load()
        XCTAssertEqual(back.document.asked, doc.asked)
    }

    /// `nil` 은 「안 건드린다」 — MCP 처럼 이 칸을 모르는 저장이 기록을 안 지운다.
    func testSavingNilAskedLeavesFileAlone() throws {
        try store.save(CueDocument(asked: [entry("a-1", "왜 우리 회사인가")]))
        try store.save(CueDocument(asked: nil))
        XCTAssertEqual(try store.load().document.asked?.count, 1)
    }

    /// 기록은 `document.json` 에 섞이지 않는다 — 두 파일의 박자가 다르다.
    func testDocumentJSONHasNoAskedKey() throws {
        try store.save(CueDocument(asked: [entry("a-1", "왜 우리 회사인가")]))
        let s = try String(contentsOf: store.documentJSONURL, encoding: .utf8)
        XCTAssertFalse(s.contains("\"asked\""))
    }

    /// 없는 파일 = 빈 기록. 옛 볼트가 그대로 열린다.
    func testMissingAskedFileLoadsAsEmpty() throws {
        try store.save(CueDocument())
        XCTAssertEqual(try store.load().document.asked, [])
    }

    /// 깨진 파일은 옆으로 치우고 빈 기록으로 연다 — 볼트 전체를 막지 않는다.
    func testCorruptAskedFileIsQuarantined() throws {
        try store.save(CueDocument())
        try FileManager.default.createDirectory(at: store.sidecarURL, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: store.askedJSONURL)
        let r = try store.load()
        XCTAssertEqual(r.document.asked, [])
        let names = try FileManager.default.contentsOfDirectory(atPath: store.sidecarURL.path)
        XCTAssertTrue(names.contains { $0.hasPrefix("asked.json.bad-") }, "\(names)")
        // ★ 조용히 치우지 않는다 — 화면 띠가 말할 수 있게 치운 자리를 올린다 (리뷰 H3, 정관 10조)
        XCTAssertEqual(r.quarantined?.lastPathComponent.hasPrefix("asked.json.bad-"), true, "\(String(describing: r.quarantined))")
    }

    /// 안 바뀌면 안 쓴다 — 머리글 규율이 이 파일에도 걸린다.
    func testUnchangedAskedDoesNotRewrite() throws {
        let doc = CueDocument(asked: [entry("a-1", "왜 우리 회사인가")])
        try store.save(doc)
        let m1 = try FileManager.default.attributesOfItem(atPath: store.askedJSONURL.path)[.modificationDate] as! Date
        Thread.sleep(forTimeInterval: 0.05)
        try store.save(doc)
        let m2 = try FileManager.default.attributesOfItem(atPath: store.askedJSONURL.path)[.modificationDate] as! Date
        XCTAssertEqual(m1, m2)
    }
}
