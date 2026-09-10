import XCTest
@testable import ClonieCore

/// 저장소가 **밖에서 보이는 것**만 검증한다 (#8 테스트 결정): 왕복 · 깨진 파일 · 원자성.
/// 내부 구조는 안 본다 — 임시 파일 이름 같은 것을 잠그면 구현을 못 바꾼다.
final class FragmentStoreTests: XCTestCase {
    private var dir: URL!
    private var store: FragmentStore!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cue-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store = FragmentStore(url: dir.appendingPathComponent("cue.json"))
    }

    override func tearDownWithError() throws {
        // 권한을 되돌려야 지워진다 — 원자성 시험이 폴더를 잠그고 끝난다.
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        try? FileManager.default.removeItem(at: dir)
    }

    private func sample() -> CueDocument {
        let t = Date(timeIntervalSince1970: 1_756_000_000)
        return CueDocument(
            questions: [Question(id: "q-1", text: "주도적으로 문제를 해결한 경험"),
                        Question(id: "q-2", text: "실패했던 경험과 거기서 배운 것")],
            fragments: [Fragment(id: "f-1", title: "배포 스크립트를 갈아엎었다",
                                 body: "매번 손으로 하던 것을 한 줄로 줄였다.",
                                 questionIds: ["q-1"], createdAt: t, updatedAt: t)]
        )
    }

    // MARK: - 왕복

    func testSaveThenLoadReturnsSameDocument() throws {
        let doc = sample()
        try store.save(doc)
        XCTAssertEqual(try store.load(), LoadResult(document: doc))
    }

    func testLoadWithNoFileReturnsEmptyDocument() throws {
        let result = try store.load()
        XCTAssertEqual(result.document, .empty)
        XCTAssertNil(result.quarantined)
        XCTAssertEqual(result.document.schemaVersion, CueDocument.currentSchemaVersion)
    }

    /// 사람이 읽을 수 있어야 한다 (#8 사용자 이야기 5). 줄바꿈이 있고 키가 정렬돼 있다.
    func testSavedFileIsHumanReadable() throws {
        try store.save(sample())
        let text = try String(contentsOf: store.url, encoding: .utf8)
        XCTAssertTrue(text.contains("\n"), "한 줄로 쓰면 눈으로도 git diff 로도 못 본다")
        XCTAssertTrue(text.contains("\"schemaVersion\" : 1"), "판 번호가 파일에 박혀 있어야 한다")
        XCTAssertLessThan(text.range(of: "\"fragments\"")!.lowerBound,
                          text.range(of: "\"questions\"")!.lowerBound,
                          "sortedKeys 가 안 걸렸다 — 키 순서가 흔들리면 diff 가 못 쓰게 된다")
        XCTAssertTrue(text.contains("2025-08-24T"), "날짜가 ISO8601 이 아니다")
    }

    /// 질문 연결이 **id** 다. 질문 목록을 뒤집어도 조각이 안 어긋난다 (#8: 인덱스가 아니라 id).
    func testQuestionLinkSurvivesReordering() throws {
        var doc = sample()
        try store.save(doc)
        doc.questions.reverse()
        try store.save(doc)
        let loaded = try store.load().document
        XCTAssertEqual(loaded.fragments[0].questionIds, ["q-1"])
        XCTAssertEqual(loaded.questions.first(where: { $0.id == "q-1" })?.text,
                       "주도적으로 문제를 해결한 경험")
    }

    // MARK: - 깨진 파일

    func testCorruptFileIsMovedAsideAndAppOpensEmpty() throws {
        let broken = "{ 이건 JSON 이 아니다 "
        try broken.write(to: store.url, atomically: true, encoding: .utf8)

        let result = try store.load()
        XCTAssertEqual(result.document, .empty, "깨진 파일을 만나면 빈 문서로 뜬다")
        let moved = try XCTUnwrap(result.quarantined, "치운 자리를 안 알려주면 사용자가 모른다")
        XCTAssertEqual(try String(contentsOf: moved, encoding: .utf8), broken,
                       "치운 파일의 내용이 그대로여야 복구를 시도할 수 있다")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path),
                       "원본 자리는 비어 있어야 한다 — 덮어쓴 게 아니라 옮긴 것이다")
    }

    /// 같은 초에 두 번 치워도 앞 것을 **안 덮어쓴다**.
    func testSecondCorruptFileDoesNotOverwriteTheFirst() throws {
        try "첫 번째 깨진 것".write(to: store.url, atomically: true, encoding: .utf8)
        let a = try XCTUnwrap(try store.load().quarantined)
        try "두 번째 깨진 것".write(to: store.url, atomically: true, encoding: .utf8)
        let b = try XCTUnwrap(try store.load().quarantined)

        XCTAssertNotEqual(a, b)
        XCTAssertEqual(try String(contentsOf: a, encoding: .utf8), "첫 번째 깨진 것")
        XCTAssertEqual(try String(contentsOf: b, encoding: .utf8), "두 번째 깨진 것")
    }

    /// 모르는 **미래 판**은 치우지도 열지도 않는다 — 옛 코드가 새 파일을 망치지 않게.
    func testFutureSchemaVersionIsRefusedNotQuarantined() throws {
        let future = #"{"schemaVersion": 99, "questions": [], "fragments": []}"#
        try future.write(to: store.url, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? FragmentStoreError,
                           .unknownSchemaVersion(found: 99, supported: CueDocument.currentSchemaVersion))
        }
        XCTAssertEqual(try String(contentsOf: store.url, encoding: .utf8), future,
                       "미래 판 파일은 건드리지 않는다")
    }

    /// 화면(JS)의 `toISOString()` 은 `.000Z` 를 붙인다. 그것도 읽혀야 한다 —
    /// 못 읽으면 조각이 저장은 되는데 **다시 안 열린다.**
    func testDecoderAcceptsFractionalSecondsFromTheScreen() throws {
        let fromJS = """
        {"schemaVersion":1,"questions":[],"fragments":[{"id":"f-1","title":"t","body":"b",
         "questionIds":[],"createdAt":"2026-08-28T11:00:00.000Z","updatedAt":"2026-08-28T11:00:00Z"}]}
        """
        try fromJS.write(to: store.url, atomically: true, encoding: .utf8)
        let doc = try store.load().document
        XCTAssertEqual(doc.fragments.count, 1)
        XCTAssertEqual(doc.fragments[0].createdAt, doc.fragments[0].updatedAt)
    }

    // MARK: - 원자성

    /// 쓰다 실패해도 **원본이 산다.** 폴더를 읽기 전용으로 잠가 쓰기를 실패시킨다 —
    /// 저장소에 시험용 구멍을 뚫지 않고 밖에서 만드는 실패다.
    func testFailedSaveLeavesPreviousFileIntact() throws {
        let first = sample()
        try store.save(first)
        let before = try Data(contentsOf: store.url)

        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700],
                                                       ofItemAtPath: dir.path) }

        var second = first
        second.fragments[0].title = "덮어쓰기를 시도한다"
        XCTAssertThrowsError(try store.save(second), "폴더가 잠겼는데 저장이 성공하면 시험이 헛돈다")

        XCTAssertEqual(try Data(contentsOf: store.url), before, "실패한 저장이 원본을 건드렸다")
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        XCTAssertEqual(try store.load().document, first)
    }

    /// 실패한 저장이 임시 파일을 흘리지 않는다 — 다음 로드가 그걸 정본으로 오해하진 않지만
    /// 폴더가 쓰레기로 찬다.
    func testSaveLeavesNoLeftoverFilesOnSuccess() throws {
        try store.save(sample())
        try store.save(sample())
        let left = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(left, ["cue.json"], "임시 파일이 남았다: \(left)")
    }
}

// MARK: - 면접에서 온 질문 표식 (#22)

/// ⚠ 이 자물쇠가 재는 것은 **스키마 판을 안 올리고도 되는가**다.
/// 한 방향만 재면 안 된다 — 옛 파일이 읽히는 것과 새 표식이 살아남는 것은 서로 다른 실패다.
final class QuestionFromInterviewTests: XCTestCase {

    func testOldFileWithoutTheFieldStillLoads() throws {
        let json = """
        {"schemaVersion":1,
         "questions":[{"id":"q-1","text":"실패했던 경험과 거기서 배운 것"}],
         "fragments":[]}
        """
        let doc = try FragmentStore.makeDecoder().decode(CueDocument.self, from: Data(json.utf8))
        XCTAssertEqual(doc.questions.count, 1)
        XCTAssertNil(doc.questions[0].fromInterview, "없던 필드가 nil 이 아니다")
    }

    func testMarkSurvivesRoundTrip() throws {
        let doc = CueDocument(questions: [
            Question(id: "q-1", text: "사람이 고른 것"),
            Question(id: "q-2", text: "면접에서 온 것", fromInterview: true),
        ])
        let data = try FragmentStore.makeEncoder().encode(doc)
        let back = try FragmentStore.makeDecoder().decode(CueDocument.self, from: data)
        XCTAssertNil(back.questions[0].fromInterview)
        XCTAssertEqual(back.questions[1].fromInterview, true)
    }

    /// nil 이면 키가 **아예 안 나가야** 한다 — 그래야 옛 판과 파일이 같은 모양이다.
    func testNilIsNotWrittenToDisk() throws {
        let doc = CueDocument(questions: [Question(id: "q-1", text: "사람이 고른 것")])
        let json = String(data: try FragmentStore.makeEncoder().encode(doc), encoding: .utf8)!
        XCTAssertFalse(json.contains("fromInterview"), "nil 인데 키가 파일에 쓰였다:\n\(json)")
    }

    func testSchemaVersionDidNotMove() {
        XCTAssertEqual(CueDocument.currentSchemaVersion, 1, "#22 는 스키마 판을 올리지 않는다")
    }
}

// MARK: - 말투 변형 (#23 갈래 ②)

/// ⚠ `fromInterview` 와 **똑같은 두 방향**을 잰다 — 옛 파일이 읽히는 것과 새 필드가 살아남는 것.
/// 한 방향만 재면 반쪽이다. 여기가 빨개지면 사용자 파일이 조용히 못 읽히거나 변형이 사라진 것이다.
final class QuestionVariantsTests: XCTestCase {

    /// 변형이 세상에 없던 때 쓰인 파일. **글자 하나 안 고치고** 열려야 한다.
    func testOldFileWithoutVariantsStillLoads() throws {
        let json = """
        {"schemaVersion":1,
         "questions":[{"id":"q-1","text":"실패했던 경험과 거기서 배운 것"},
                      {"id":"q-2","text":"면접에서 온 것","fromInterview":true}],
         "fragments":[{"id":"f-1","title":"제목","body":"본문","questionIds":["q-1"],
                       "createdAt":"2026-08-29T00:00:00Z","updatedAt":"2026-08-29T00:00:00Z"}]}
        """
        let doc = try FragmentStore.makeDecoder().decode(CueDocument.self, from: Data(json.utf8))
        XCTAssertEqual(doc.questions.count, 2)
        XCTAssertNil(doc.questions[0].variants, "없던 필드가 nil 이 아니다")
        XCTAssertEqual(doc.questions[1].fromInterview, true, "옆 필드가 같이 죽었다")
        XCTAssertEqual(doc.fragments.count, 1)
    }

    /// 옛 파일을 **읽고 그대로 다시 쓰면** 옛 파일과 같은 모양이어야 한다 —
    /// 옛 판 앱과 새 판 앱이 같은 파일을 번갈아 열어도 diff 가 안 생기게.
    func testOldFileRoundTripsUnchanged() throws {
        let json = """
        {"schemaVersion":1,
         "questions":[{"id":"q-1","text":"실패했던 경험과 거기서 배운 것"}],
         "fragments":[]}
        """
        let doc = try FragmentStore.makeDecoder().decode(CueDocument.self, from: Data(json.utf8))
        let out = String(data: try FragmentStore.makeEncoder().encode(doc), encoding: .utf8)!
        XCTAssertFalse(out.contains("variants"), "안 쓴 필드가 파일에 나타났다:\n\(out)")
        XCTAssertFalse(out.contains("fromInterview"))
    }

    func testVariantsSurviveRoundTripInOrder() throws {
        let v = ["생각대로 안 됐던 일이 있으면 말씀해 주세요",
                 "결과가 기대에 못 미친 프로젝트가 있었나요",
                 "크게 실수했던 순간과 그 뒤에 바뀐 점을 알려주세요"]
        let doc = CueDocument(questions: [
            Question(id: "q-1", text: "변형 없는 질문"),
            Question(id: "q-2", text: "실패했던 경험과 거기서 배운 것", variants: v),
        ])
        let back = try FragmentStore.makeDecoder()
            .decode(CueDocument.self, from: FragmentStore.makeEncoder().encode(doc))
        XCTAssertNil(back.questions[0].variants)
        // 순서가 곧 화면의 칸 순서다 — 섞이면 사용자가 적은 자리가 옮겨간다
        XCTAssertEqual(back.questions[1].variants, v)
    }

    /// nil 이면 키가 **아예 안 나가야** 한다 — 그래야 옛 판과 파일이 같은 모양이다.
    func testNilVariantsIsNotWrittenToDisk() throws {
        let doc = CueDocument(questions: [Question(id: "q-1", text: "사람이 고른 것")])
        let json = String(data: try FragmentStore.makeEncoder().encode(doc), encoding: .utf8)!
        XCTAssertFalse(json.contains("variants"), "nil 인데 키가 파일에 쓰였다:\n\(json)")
    }

    /// 디스크를 실제로 한 번 왕복한다 — 인코더/디코더만 재면 저장 경로가 빠진다.
    func testVariantsSurviveDisk() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cue-variants-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FragmentStore(url: dir.appendingPathComponent("cue.json"))
        try store.save(CueDocument(questions: [
            Question(id: "q-1", text: "실패했던 경험과 거기서 배운 것",
                     variants: ["결과가 기대에 못 미친 프로젝트가 있었나요"]),
        ]))
        let back = try store.load()
        XCTAssertNil(back.quarantined, "멀쩡한 파일이 치워졌다")
        XCTAssertEqual(back.document.questions[0].variants, ["결과가 기대에 못 미친 프로젝트가 있었나요"])
    }

    func testSchemaVersionDidNotMove() {
        XCTAssertEqual(CueDocument.currentSchemaVersion, 1, "#23 도 스키마 판을 올리지 않는다")
    }
}
