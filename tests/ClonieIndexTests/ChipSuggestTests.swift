import Foundation
import XCTest
@testable import ClonieCore
@testable import ClonieEmbedding
@testable import ClonieIndex

/// ★ **개념 제안이 Swift 쪽에서도 서나** — #33, ADR 0003 §3-② 의 Swift 절반.
///
/// ## 무엇을 잠그나 — 두 개다
///
/// | 시험 | 잠그는 것 |
/// |---|---|
/// | `test_01_indexTextMatchesFixture` | **글자가 같나.** 화면(`draftText`)·파이썬(fixture)·Swift(`indexText`) 셋이 같은 문자열을 임베딩하나 |
/// | `test_02_realModelReproducesTop3` | **수가 같나.** 앱이 실제로 쓰는 CoreML 경로가 fixture 성적(top-3 8/12)을 다시 내나 |
///
/// ## 왜 이 시험이 따로 필요한가 — `node --test` 로는 못 잡는 구멍
///
/// `tests/chip-suggest.test.mjs` 는 fixture 의 **구워진 벡터**로 화면 함수를 잰다. 그래서
/// **파이썬이 그 벡터를 어떤 글자에서 떴는지**와 **앱의 CoreML 이 같은 수를 내는지**는
/// 그 파일이 못 본다. 둘 중 하나가 어긋나면 `node --test` 는 **초록인 채로** 남고 앱에서만
/// 제안이 조용히 나빠진다. 여기가 그 두 자리다.
///
/// ⚠ 제안을 **고르는 것**(코사인·순위·기본 켜짐)은 여기서 안 잰다 — 그건 화면에 살고
/// (`ADR 0003 §4`) `tests/chip-suggest.test.mjs` 가 잠근다. 여기가 재는 것은 **벡터까지**다.
/// 그 갈림이 이 레포의 이식 경계이기도 하다.
///
/// ⚠ 모델이 없는 환경에서 **조용히 skip 하지 않는다** — 규칙의 정본은
/// `tests/ClonieEmbeddingTests/ScoreParityTests.swift` 머리글이고, 여기는
/// `IndexTestSupport` 로 그대로 쓴다.
final class ChipSuggestTests: XCTestCase {

    // ⚠ 값이 아니라 **하한**이다. 말뭉치를 줄여서 초록을 만드는 길을 막는다.
    static let minItems = 12
    static let minQuestions = 10
    /// ★ 판정선. `실측 2026-08-30`(#33 프로브): 출하 축·출하 기본에서 top-3 **8/12**.
    /// 우연은 3.6/12 다. **top-1 이 아니라 top-3 인 이유**가 이 티켓의 전부다 —
    /// top-1 은 3/12 라 「기계가 정하고 확인만 받기」가 안 선다.
    static let minTop3 = 8
    /// 화면에 띄우는 개수. `ChatHTML.swift` 의 `SUGGEST_N` 과 같아야 한다.
    static let suggestN = 3

    // MARK: - fixture

    struct Fixture: Decodable {
        struct Item: Decodable {
            let id: String, gold: String, title: String, body: String, index_text: String
        }
        struct Question: Decodable { let id: String, text: String; let variants: [String] }
        struct Vectors: Decodable {
            let items_titlebody: [String: String]
            let questions: [String: [String]]
        }
        let model_id: String, revision: String, dimensions: Int
        let shipped_axis: String
        let items: [Item], questions: [Question]
        let vectors: Vectors
    }

    /// 질문들을 점수 내림차순으로. **동점이면 id 순** — 화면(`suggestChips`)과 같은 규칙이라야
    /// 같은 셋이 나온다. ⚠ 타입을 다 적어 둔 이유는 추론이 터져서다(실측: 컴파일 불가).
    private func rankedQuestionIDs(draft: [Float], questions: [String: [Float]]) -> [String] {
        var scored: [(id: String, s: Double)] = []
        for (id, qv) in questions {
            scored.append((id: id, s: Double(TextEmbedder.cosine(draft, qv))))
        }
        scored.sort { (a: (id: String, s: Double), b: (id: String, s: Double)) -> Bool in
            a.s == b.s ? a.id < b.id : a.s > b.s
        }
        return scored.map { $0.id }
    }

    private func fixture() throws -> Fixture {
        // ⚠ `#filePath` 에서 올라간다 — 작업 디렉터리에 안 기댄다(`swift test` 는 어디서든 돈다).
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/chip_suggest.json")
        return try JSONDecoder().decode(Fixture.self, from: try Data(contentsOf: url))
    }

    /// fixture 가 실제로 있고 안 줄었나 — **0건은 결론이 아니다** (`정관 6조`).
    func test_00_fixtureIsPresentAndBigEnough() throws {
        let f = try fixture()
        XCTAssertGreaterThanOrEqual(f.items.count, Self.minItems, "말뭉치를 지워서 초록을 만들지 마라")
        XCTAssertGreaterThanOrEqual(f.questions.count, Self.minQuestions, "후보 질문이 하한 아래다")
        XCTAssertEqual(Set(f.items.map(\.gold)).count, f.questions.count,
                       "정답 칩이 질문 열을 전부 안 덮는다 — 안 쓰이는 후보가 생기면 과제가 쉬워진다")
        XCTAssertEqual(f.vectors.items_titlebody.count, f.items.count)
        XCTAssertEqual(f.shipped_axis, "titlebody", "출하 축이 갈렸다 — 아래 시험이 다른 것을 잰다")
    }

    // MARK: - 01 글자가 같나 (모델 없이 돈다)

    /// ★ **파이썬이 벡터를 뜬 글자 == `ContentIndexer.indexText` 가 만드는 글자.**
    ///
    /// 여기가 갈리면 저장 전 제안과 저장 후 색인이 **다른 문자열에서 나온 벡터**가 되는데,
    /// 아무것도 안 터진다 — 제안만 조용히 나빠진다. 그래서 글자 단위로 대조한다.
    func test_01_indexTextMatchesFixture() throws {
        let f = try fixture()
        for it in f.items {
            let fragment = Fragment(id: it.id, title: it.title, body: it.body,
                                    questionIds: [it.gold],
                                    createdAt: Date(timeIntervalSince1970: 0),
                                    updatedAt: Date(timeIntervalSince1970: 0))
            XCTAssertEqual(ContentIndexer.indexText(fragment), it.index_text,
                """
                「\(it.id)」 의 색인 글자가 fixture 와 갈렸다.
                  Swift  : \(ContentIndexer.indexText(fragment).debugDescription)
                  fixture: \(it.index_text.debugDescription)
                fixture 를 다시 구우려면: scripts/make_chip_suggest_fixture.py
                """)
        }
        // 양성 대조 — 대조가 무력하지 않나. 제목·본문이 **둘 다** 글자에 들어가야 한다.
        let sample = try XCTUnwrap(f.items.first { !$0.title.isEmpty && !$0.body.isEmpty })
        XCTAssertTrue(sample.index_text.contains(sample.title), "제목이 색인 글자에서 빠졌다")
        XCTAssertTrue(sample.index_text.contains(sample.body), "본문이 색인 글자에서 빠졌다")
    }

    // MARK: - 02 수가 같나 (모델이 있어야 돈다)

    /// ★ **앱이 실제로 쓰는 경로로 성적을 다시 낸다.**
    ///
    /// 조각은 `embed(passage:)`, 질문은 `embed(query:)` — `ContentIndexer` 가 두 축에 쓰는
    /// 그 프리픽스 그대로다. 여기서 `passage:` 대신 `query:` 를 쓰면 **아무것도 안 터지고
    /// 제안만 조용히 나빠진다.** 그래서 성적으로 잰다.
    ///
    /// ⚠ **fixture 벡터를 안 쓴다** — 여기서 모델을 직접 돌린다. fixture 를 쓰면 이 시험은
    /// `node --test` 가 이미 재는 것을 한 번 더 재는 것이 된다.
    /// ⚠ **출하 기본**으로 잰다: 질문의 물음꼴은 **본문 하나**뿐이다. `seed()` 가 심는
    /// 표준질문엔 변형이 없고, 변형을 적는 칸은 #34 가 걷었다.
    func test_02_realModelReproducesTop3() throws {
        let f = try fixture()
        let dir = try IndexTestSupport.makeTempDirectory("chipsuggest")
        defer { try? FileManager.default.removeItem(at: dir) }
        guard let indexer = IndexTestSupport.indexerOrAnnounceMissing(sidecarURL: dir) else { return }

        XCTAssertEqual(indexer.embedder.manifest.modelID, f.model_id, "fixture 와 다른 모델을 잰다")
        XCTAssertEqual(indexer.embedder.dimensions, f.dimensions)

        // 질문 축 — **대칭 과제라 `query:`** (모델카드 §FAQ · `ContentIndexer` 와 같은 규약)
        var questionVector: [String: [Float]] = [:]
        for q in f.questions { questionVector[q.id] = try indexer.embedder.embed(query: q.text) }

        var top1 = 0, top3 = 0, ranks: [Int] = []
        for it in f.items {
            // 조각 축 — **비대칭 과제라 `passage:`**
            let dv = try indexer.embedder.embed(passage: it.index_text)
            let scored = rankedQuestionIDs(draft: dv, questions: questionVector)
            let rank = (scored.firstIndex(of: it.gold) ?? scored.count) + 1
            ranks.append(rank)
            if rank == 1 { top1 += 1 }
            if rank <= Self.suggestN { top3 += 1 }
        }

        let report = "top-1 \(top1)/\(f.items.count) · top-3 \(top3)/\(f.items.count) · 순위 \(ranks)"
        XCTAssertGreaterThanOrEqual(top3, Self.minTop3,
            """
            ★ 앱의 CoreML 경로에서 top-3 이 줄었다 — \(report)
            제안 셋 중에 답이 없다는 뜻이고, 그러면 「셋 내고 고르게 한다」의 근거가 사라진다.
            프리픽스(passage:/query:)가 갈렸는지부터 봐라.
            """)
        // ★ **top-1 이 낮다는 것도 같이 잠근다.** 이게 「기계가 정하고 확인만 받기」를 안 하는
        //   근거다 — 어느 날 top-1 이 충분히 높아지면 이 줄이 빨개지고, 그때 설계를 다시 연다.
        XCTAssertLessThan(top1, Self.minTop3,
            """
            top-1 이 top-3 만큼 올라왔다 — \(report)
            그러면 「셋 제안」 대신 「하나 제안 + 확인」이 설 수 있다. ADR 0003 §3-② 를 다시 열어라.
            """)
        print("[#33] 앱 CoreML 경로 재현 — \(report) (fixture 파이썬: top-3 \(Self.minTop3)/12)")
    }

    /// ★ **이 자물쇠가 꺼졌는지 어떻게 아나** (`정관 10조`).
    /// 일부러 틀린 축(질문도 `passage:` 로)으로 같은 판정을 돌려 **빨개지는 것**을 확인한다.
    /// 이게 초록이면 위 시험은 무엇을 넣어도 통과하는 것이다.
    func test_03_wrongPrefixActuallyScoresWorse() throws {
        let f = try fixture()
        let dir = try IndexTestSupport.makeTempDirectory("chipsuggest-neg")
        defer { try? FileManager.default.removeItem(at: dir) }
        guard let indexer = IndexTestSupport.indexerOrAnnounceMissing(sidecarURL: dir) else { return }

        func top3(questionPrefixIsQuery: Bool) throws -> Int {
            var qv: [String: [Float]] = [:]
            for q in f.questions {
                qv[q.id] = questionPrefixIsQuery ? try indexer.embedder.embed(query: q.text)
                                                 : try indexer.embedder.embed(passage: q.text)
            }
            var hit = 0
            for it in f.items {
                let dv = try indexer.embedder.embed(passage: it.index_text)
                let scored = rankedQuestionIDs(draft: dv, questions: qv)
                if scored.prefix(Self.suggestN).contains(it.gold) { hit += 1 }
            }
            return hit
        }

        let right = try top3(questionPrefixIsQuery: true)
        let wrong = try top3(questionPrefixIsQuery: false)
        XCTAssertGreaterThan(right, wrong,
            """
            프리픽스를 일부러 틀리게 했는데 성적이 안 나빠졌다 (바른 축 \(right) · 틀린 축 \(wrong)).
            그러면 위 시험의 초록은 「프리픽스가 맞다」를 증명하지 않는다 — 자물쇠가 꺼진 것이다.
            """)
    }
}
