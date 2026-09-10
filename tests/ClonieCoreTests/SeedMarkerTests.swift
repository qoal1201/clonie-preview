import XCTest
@testable import ClonieCore

/// 씨앗 표식이 **디스크를 건너나** — QA 2026-08-30 블로커 F2 의 Swift 쪽 절반.
///
/// ## 왜 이 다리를 재나
///
/// 화면이 예시 조각에 `seed:true` 를 박아도, 그것이 md 를 못 건너면 **재기동 한 번에
/// 사라진다** — 그리고 씨앗이 보통 조각으로 되살아나 실전 검색 1위로 뜬다.
/// QA 가 잡은 것이 정확히 그 모양이라, 표식이 살아 돌아오는 것을 여기서 잠근다.
///
/// ⚠ **스키마 판을 안 올렸다.** `Question.fromInterview` 와 같은 모양의 옵셔널이고,
/// 그래서 이 파일은 **두 방향을 다 잰다**: 표식 있는 것이 살아 돌아오나 ·
/// 표식 **없던 옛 파일**이 그대로 읽히나.
final class SeedMarkerTests: XCTestCase {

    private func tempVault() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("seed-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private let t = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - md 한 장

    func testRenderWritesSeedLineOnlyWhenTrue() {
        let seeded = Fragment(id: "f-1", title: "예시", body: "본문", questionIds: [],
                              createdAt: t, updatedAt: t, seed: true)
        XCTAssertTrue(MarkdownFragment.render(seeded).contains("\nseed: true\n"))

        // ⚠ 거짓·nil 은 **줄을 안 쓴다** — 남의 볼트에 우리 전용 키가 영영 남으면 안 된다.
        for f in [Fragment(id: "f-1", title: "예시", body: "본문", questionIds: [],
                           createdAt: t, updatedAt: t, seed: false),
                  Fragment(id: "f-1", title: "예시", body: "본문", questionIds: [],
                           createdAt: t, updatedAt: t)] {
            XCTAssertFalse(MarkdownFragment.render(f).contains("seed:"),
                           "표식을 뗀 조각의 md 에 우리 키가 남았다")
        }
    }

    func testParseReadsSeedMarkerBack() {
        let f = Fragment(id: "f-1", title: "예시", body: "본문", questionIds: [],
                         createdAt: t, updatedAt: t, seed: true)
        let back = MarkdownFragment.parse(text: MarkdownFragment.render(f),
                                          relativePath: "예시.md",
                                          fallbackDates: (t, t)).fragment
        XCTAssertEqual(back.seed, true, "왕복에서 표식이 죽으면 재기동마다 씨앗이 되살아난다")
    }

    func testParseIsLenientAboutTruthAndAbsence() {
        func seedOf(_ line: String) -> Bool? {
            let text = "---\nid: f-1\ntitle: 예시\n\(line)\n---\n\n본문\n"
            return MarkdownFragment.parse(text: text, relativePath: "a.md",
                                          fallbackDates: (t, t)).fragment.seed
        }
        // 읽기는 너그럽다 — YAML 1.1 의 참들
        for l in ["seed: true", "seed: yes", "seed: on", "seed: 1", "seed: \"true\"", "seed: TRUE"] {
            XCTAssertEqual(seedOf(l), true, l)
        }
        // 거짓·헛것은 **nil** 이다 (`false` 가 아니라) — 인코더가 키를 아예 안 쓰게
        for l in ["seed: false", "seed: no", "seed:", "seed: 아무말"] {
            XCTAssertNil(seedOf(l), l)
        }
    }

    /// ★ **표식이 없던 옛 파일**이 그대로 읽힌다 — 스키마 판을 안 올린 것의 뜻이다.
    func testOldFileWithoutMarkerStillReads() {
        let text = "---\nid: f-old\ntitle: 옛 조각\n---\n\n본문\n"
        let p = MarkdownFragment.parse(text: text, relativePath: "옛.md", fallbackDates: (t, t))
        XCTAssertNil(p.fragment.seed)
        XCTAssertEqual(p.fragment.title, "옛 조각")
    }

    /// ⚠ `seed` 는 **우리 키**라 보존 목록에 안 든다 — 안 그러면 뗀 표식이 되돌아온다.
    func testSeedIsOwnedNotPreserved() {
        XCTAssertTrue(MarkdownFragment.ownedKeys.contains("seed"))
        let text = "---\nid: f-1\ntitle: 예시\nseed: true\ntags: [메모]\n---\n\n본문\n"
        let p = MarkdownFragment.parse(text: text, relativePath: "a.md", fallbackDates: (t, t))
        XCTAssertFalse(p.preservedFrontmatter.contains { $0.contains("seed") })
        XCTAssertTrue(p.preservedFrontmatter.contains { $0.contains("tags") },
                      "남의 키는 그대로 보존한다 — 그 성질은 안 건드렸다")
    }

    // MARK: - 볼트 한 폴더

    /// 표식을 **떼면 파일이 실제로 다시 쓰인다.** `sameOnDisk` 가 표식을 안 보면
    /// 「알맹이가 같다」로 읽혀 안 쓰이고, 재기동하면 표식이 되살아난다.
    func testDroppingMarkerRewritesTheFile() throws {
        let vault = try tempVault()
        let store = VaultStore(vaultURL: vault)
        _ = try store.load()

        let seeded = Fragment(id: "f-1", title: "예시", body: "본문", questionIds: [],
                              createdAt: t, updatedAt: t, seed: true)
        try store.save(CueDocument(questions: [], fragments: [seeded]))
        let path = try XCTUnwrap(store.markdownRelativePaths().first)
        XCTAssertTrue(try String(contentsOf: vault.appendingPathComponent(path), encoding: .utf8)
                        .contains("seed: true"))

        // 사람이 손댔다 = 표식을 뗀다. 알맹이는 그대로 두고 표식만 바꿔 본다.
        var edited = seeded
        edited.seed = nil
        XCTAssertFalse(VaultStore.sameOnDisk(seeded, edited),
                       "표식이 `sameOnDisk` 에서 빠지면 이 저장이 조용히 건너뛰어진다")
        try store.save(CueDocument(questions: [], fragments: [edited]))
        XCTAssertFalse(try String(contentsOf: vault.appendingPathComponent(path), encoding: .utf8)
                        .contains("seed:"))

        // 다시 읽어도 안 되살아난다
        let reloaded = try VaultStore(vaultURL: vault).load()
        XCTAssertNil(reloaded.document.fragments.first?.seed)
    }

    func testMarkerSurvivesSaveLoadRoundTrip() throws {
        let vault = try tempVault()
        let store = VaultStore(vaultURL: vault)
        _ = try store.load()
        try store.save(CueDocument(questions: [], fragments: [
            Fragment(id: "f-1", title: "예시", body: "본문", questionIds: [],
                     createdAt: t, updatedAt: t, seed: true),
            Fragment(id: "f-2", title: "진짜", body: "본문", questionIds: [],
                     createdAt: t, updatedAt: t),
        ]))
        // **새 저장소**로 읽는다 — 재기동을 흉내내는 자리다(스냅샷을 안 물려받는다).
        let back = try VaultStore(vaultURL: vault).load().document.fragments
        XCTAssertEqual(back.first(where: { $0.id == "f-1" })?.seed, true)
        XCTAssertNil(back.first(where: { $0.id == "f-2" })?.seed)
    }
}
