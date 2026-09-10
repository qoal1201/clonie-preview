import Foundation
import XCTest
@testable import GhostbarEmbedding

/// ★ **점수 일치 자물쇠** — #31 의 인수 본체.
///
/// 파이썬(sentence-transformers)이 뜬 기준면과 **Swift 추론이 같은 수를 내나**를 잰다.
/// 기준면 = `tests/fixtures/embedding_reference.json`, 뜨는 법 = `scripts/make_embedding_fixture.py`.
///
/// ## 층을 갈라서 잠근다 — 빨개졌을 때 어디가 틀렸는지 알려고
///
/// | 빨개지는 곳 | 범인 |
/// |---|---|
/// | `test_02_tokenizer…` | 토크나이저(정규화기·Viterbi). 모델은 아직 안 돈다 |
/// | `test_03_embedding…` | CoreML 변환 또는 풀링. 토큰은 맞았다는 뜻이다 |
/// | `test_04_cosine…` | 위 둘이 초록인데 여기가 빨가면 점수 합성 쪽이다 |
///
/// ## ⚠ 모델이 없는 환경에서 **조용히 skip 하지 않는다**
///
/// `정관 6조` — *"0건은 결론이 아니다."* 모델은 git 에 안 드니까(ADR 0003 §5) CI 와 새 클론에는
/// 없다. 그때 `XCTSkip` 을 던지면 **초록인데 아무것도 안 잰 상태**가 되고, 그게 이 자물쇠가
/// 막으려는 바로 그 모양이다. 그래서 이렇게 한다:
///
/// - 모델이 **없으면**(`.missing`) — 통과시키되 **초록 출력에 「안 쟀다」를 대문짝만하게 박는다.**
///   어디를 봤는지와 받는 법까지 같이 낸다
/// - 모델이 **깨졌으면**(`.incomplete`·`.unreadable`) — **빨강.** 있는데 안 도는 것은 사고다
/// - `GHOSTBAR_REQUIRE_EMBEDDING_MODEL=1` 이면 없는 것도 **빨강**. 모델이 있어야 마땅한
///   기계(개발 맥·모델을 받아둔 CI)가 이걸 켠다 — 「없어서 안 쟀다」가 기본값이 되지 않게
///
/// ## 이 자물쇠가 꺼졌는지 어떻게 아나
///
/// 위의 것만으로는 **비교문 자체가 무력해진 경우**를 못 잡는다(늘 참을 돌려주는 비교).
/// 그래서 `test_05_…NotVacuous` 가 **일부러 틀린 벡터**를 같은 비교 함수에 먹여
/// **빨개지는 것을 확인**한다. 그게 초록이면 자물쇠가 꺼진 것이다.
/// 케이스 수 하한(`min…`)도 같은 취지 — 케이스를 지워서 초록을 만드는 길을 막는다.
final class ScoreParityTests: XCTestCase {

    // ⚠ 값이 아니라 **하한**이다. 늘리는 건 자유고 줄이는 것만 막는다.
    static let minTokenizerCases = 8
    static let minTexts = 5
    static let minCosinePairs = 10

    /// 모델이 없는 것을 **빨강으로 승격**하는 스위치.
    static let requireModelKey = "GHOSTBAR_REQUIRE_EMBEDDING_MODEL"

    // MARK: - 공통

    private func fixture() throws -> EmbeddingFixture { try EmbeddingFixture.load() }

    /// 두 벡터의 최대 성분 편차. **실제 판정과 음성 대조가 같은 함수를 쓴다** —
    /// 그래야 음성 대조가 판정 경로를 진짜로 시험한 것이 된다.
    ///
    /// ⚠ **NaN 을 반드시 무한대로 올린다.** `max(0, .nan)` 은 Swift 에서 **0 을 돌려준다** —
    ///   비교가 `y >= x ? y : x` 이고 NaN 과의 비교는 전부 거짓이기 때문이다. 그래서 예전 판은
    ///   **벡터 384칸이 전부 NaN 인데 편차 0 으로 초록**이었다 (`실측 2026-08-30`, #31).
    ///   자물쇠가 자기 자신에게 당한 자리라 여기 적어둔다.
    static func maxAbsDiff(_ a: [Double], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return .infinity }
        var worst = 0.0
        for i in 0..<a.count {
            let d = abs(a[i] - Double(b[i]))
            if d.isNaN { return .infinity }
            if d > worst { worst = d }
        }
        return worst
    }

    /// 모델을 열어본다. **열 수 없는 이유에 따라 빨강인지 아닌지가 갈린다.**
    /// 돌려주는 값이 `nil` 이면 「없어서 못 쟀다」이고, 그건 부르는 쪽이 출력에 박아야 한다.
    private func embedderOrAnnounceMissing(_ function: String = #function) throws -> TextEmbedder? {
        let status = EmbeddingModelStore.status()
        switch status {
        case .ready:
            return try TextEmbedder()

        case .incomplete, .unreadable:
            // 있는데 못 쓴다 — 이건 사고다. 넘어가지 않는다.
            XCTFail("""
                모델이 있는데 못 읽는다. 이건 skip 이 아니라 빨강이다.
                \(status.explanation)
                """)
            return nil

        case .missing(let searched):
            let required = ProcessInfo.processInfo.environment[Self.requireModelKey] == "1"
            if required {
                XCTFail("""
                    \(Self.requireModelKey)=1 인데 모델이 없다.
                    \(status.explanation)
                    """)
                return nil
            }
            // ★ 초록이지만 **안 쟀다는 사실을 크게 박는다.** 이 문구가 「조용한 초록」을 막는다.
            print("""

                ┌──────────────────────────────────────────────────────────────────────┐
                │ ⚠ 점수 일치 자물쇠가 \(function) 에서 **안 돌았다** — 모델이 없다.
                │   이 초록은 「일치한다」가 아니라 「재지 못했다」는 뜻이다.
                ├──────────────────────────────────────────────────────────────────────┤
                \(searched.map { "│   본 자리: \($0.path)" }.joined(separator: "\n"))
                │   받는 법: ./scripts/fetch-model.sh
                │   없는 것을 빨강으로 올리려면: \(Self.requireModelKey)=1 swift test
                └──────────────────────────────────────────────────────────────────────┘

                """)
            return nil
        }
    }

    // MARK: - 00 기준면이 살아 있나 (모델 없이 돈다)

    func test_00_fixtureIsPresentAndBigEnough() throws {
        let f = try fixture()

        // 양성 대조 — 파일은 읽혔는데 알맹이가 0건이면 그건 결론이 아니라 고장이다
        XCTAssertGreaterThanOrEqual(f.tokenizerCases.count, Self.minTokenizerCases,
            "토크나이저 케이스가 하한 아래다 — 케이스를 지워서 초록을 만들지 마라")
        XCTAssertGreaterThanOrEqual(f.texts.count, Self.minTexts, "기준 문장이 하한 아래다")
        XCTAssertGreaterThanOrEqual(f.cosines.count, Self.minCosinePairs, "코사인 쌍이 하한 아래다")

        XCTAssertEqual(f.dimensions, 384, "차원이 바뀌었다 — 모델이 바뀐 것이다")
        XCTAssertEqual(f.queryPrefix, "query: ")
        XCTAssertEqual(f.passagePrefix, "passage: ")

        for t in f.texts {
            XCTAssertEqual(t.embedding.count, f.dimensions, "\(t.key) 벡터 길이가 다르다")
            XCTAssertFalse(t.tokens.isEmpty, "\(t.key) 토큰이 비었다")
            // 기준 벡터가 정규화돼 있나 — 파이썬 쪽 Normalize 가 실제로 돌았다는 증거
            let norm = (t.embedding.reduce(0) { $0 + $1 * $1 }).squareRoot()
            XCTAssertEqual(norm, 1.0, accuracy: 1e-4, "\(t.key) 기준 벡터가 정규화 안 됐다")
        }

        // ⚠ 허용 오차를 키워서 빨강을 끄는 길을 막는다. 근거 문구도 비면 안 된다.
        XCTAssertGreaterThan(f.cosineTolerance, 0, "허용 오차가 0 이하다")
        XCTAssertLessThanOrEqual(f.cosineTolerance, 0.01,
            "허용 오차가 1e-2 를 넘는다 — 그 정도면 자물쇠가 아무것도 안 잠근다")
        XCTAssertFalse(f.toleranceWhy.isEmpty, "허용 오차의 근거가 비었다")

        print("기준면 OK — \(f.modelID)@\(f.revision.prefix(12)) · 문장 \(f.texts.count) · "
            + "토크나이저 케이스 \(f.tokenizerCases.count) · 코사인 쌍 \(f.cosines.count) · "
            + "허용 오차 \(f.cosineTolerance)")
    }

    // MARK: - 01 모델 상태를 말로 낸다 (늘 돈다)

    func test_01_modelAvailabilityIsAnnounced() throws {
        let status = EmbeddingModelStore.status()
        print("임베딩 모델 상태 — \(status.explanation)")

        switch status {
        case .ready(let m):
            XCTAssertEqual(m.dimensions, 384)
            XCTAssertFalse(m.enumeratedShapes.isEmpty, "열거된 길이가 비었다")
            let f = try fixture()
            XCTAssertEqual(m.modelID, f.modelID, "디스크의 모델이 기준면과 다른 모델이다")
            XCTAssertEqual(m.revision, f.revision,
                "디스크의 모델 리비전이 기준면과 다르다 — 점수가 갈릴 자리다")
        case .incomplete, .unreadable:
            XCTFail("모델이 깨졌다:\n\(status.explanation)")
        case .missing:
            if ProcessInfo.processInfo.environment[Self.requireModelKey] == "1" {
                XCTFail("\(Self.requireModelKey)=1 인데 모델이 없다:\n\(status.explanation)")
            }
        }
    }

    // MARK: - 02 토크나이저가 파이썬과 같은 id 를 내나

    func test_02_tokenizerMatchesPython() throws {
        let f = try fixture()
        guard let embedder = try embedderOrAnnounceMissing() else { return }
        let tok = embedder.tokenizer

        var checked = 0
        for c in f.tokenizerCases {
            let got = tok.encode(c.text)
            XCTAssertEqual(got, c.tokens, """
                토크나이저가 갈렸다 — 케이스 '\(c.key)'
                  입력   \(c.text.debugDescription)
                  파이썬 \(c.tokens)
                  Swift  \(got)
                  조각   \(tok.pieces(of: c.text))
                """)
            checked += 1
        }
        // 실제 임베딩 대상 문장도 같은 잣대로
        for t in f.texts {
            XCTAssertEqual(tok.encode(t.text), t.tokens,
                           "토크나이저가 갈렸다 — 문장 '\(t.key)'")
            checked += 1
        }

        XCTAssertGreaterThanOrEqual(checked, Self.minTokenizerCases + Self.minTexts,
            "0건은 결론이 아니다 — 케이스를 하나도 안 돌렸다")
        print("토크나이저 일치 \(checked)건 (어휘 \(tok.vocabularySize)개)")
    }

    // MARK: - 03 벡터가 파이썬과 같나

    func test_03_embeddingMatchesPython() throws {
        let f = try fixture()
        guard let embedder = try embedderOrAnnounceMissing() else { return }

        var worst = 0.0
        var worstKey = "-"
        var rows: [String] = []
        for t in f.texts {
            // ⚠ 기준면의 `text` 는 프리픽스가 **이미 붙은** 문자열이다. 그래서 raw 로 넣는다 —
            //   여기서 embed(query:) 를 쓰면 프리픽스가 두 번 붙는다.
            let got = try embedder.embed(raw: t.text)
            XCTAssertEqual(got.count, f.dimensions, "\(t.key) 차원이 다르다")

            let diff = Self.maxAbsDiff(t.embedding, got)
            if diff > worst { worst = diff; worstKey = t.key }
            rows.append(String(format: "  %-12@  최대성분편차 %.6f", t.key as NSString, diff))

            XCTAssertLessThanOrEqual(diff, f.componentTolerance, """
                벡터가 허용 오차를 넘었다 — '\(t.key)'
                  최대 성분 편차 \(diff) > 허용 \(f.componentTolerance)
                  \(f.toleranceWhy)
                """)
        }
        print("벡터 일치 (파이썬 fp32 ↔ Swift CoreML fp16)\n" + rows.joined(separator: "\n")
            + String(format: "\n  → 전체 최대 %.6f (%@), 허용 %.6f",
                     worst, worstKey as NSString, f.componentTolerance))
    }

    // MARK: - 04 코사인이 파이썬과 같나 — 제품이 실제로 쓰는 수

    func test_04_cosineMatchesPython() throws {
        let f = try fixture()
        guard let embedder = try embedderOrAnnounceMissing() else { return }

        var vectors: [String: [Float]] = [:]
        for t in f.texts { vectors[t.key] = try embedder.embed(raw: t.text) }

        var worst = 0.0
        var rows: [String] = []
        for p in f.cosines {
            guard let a = vectors[p.a], let b = vectors[p.b] else {
                XCTFail("코사인 쌍이 가리키는 문장이 기준면에 없다: \(p.a)/\(p.b)"); continue
            }
            let got = Double(TextEmbedder.cosine(a, b))
            let diff = abs(got - p.cosine)
            worst = max(worst, diff)
            rows.append(String(format: "  %-12@ %-12@  py %.6f  swift %.6f  차 %.6f",
                               p.a as NSString, p.b as NSString, p.cosine, got, diff))
            XCTAssertEqual(got, p.cosine, accuracy: f.cosineTolerance, """
                코사인이 갈렸다 — \(p.a) ↔ \(p.b)
                  파이썬 \(p.cosine) · Swift \(got) · 차 \(diff) > 허용 \(f.cosineTolerance)
                """)
        }
        print("코사인 일치 \(f.cosines.count)쌍\n" + rows.joined(separator: "\n")
            + String(format: "\n  → 최대 차 %.6f, 허용 %.6f", worst, f.cosineTolerance))
    }

    // MARK: - 05 ★ 자물쇠가 실제로 빨개지나 (모델 없이 돈다)

    func test_05_parityCheckIsNotVacuous() throws {
        let f = try fixture()
        guard let ref = f.texts.first else { return XCTFail("기준면에 문장이 없다") }

        // ① 자기 자신과는 편차 ~0 — 비교 함수가 살아 있다는 양성 대조.
        //   ⚠ 정확히 0 이 아니다: 기준면은 Double 이고 Swift 추론은 Float 라 왕복에서
        //   1e-8 급이 남는다. 그것까지 빨강으로 삼으면 헛빨강이 난다
        let same = ref.embedding.map { Float($0) }
        XCTAssertEqual(Self.maxAbsDiff(ref.embedding, same), 0, accuracy: 1e-6,
                       "같은 벡터인데 편차가 났다 — 비교 함수가 고장났다")

        // ② 성분 하나를 허용 오차의 10배만큼 흔들면 **반드시** 걸려야 한다
        var nudged = same
        nudged[0] += Float(f.componentTolerance * 10)
        let diff = Self.maxAbsDiff(ref.embedding, nudged)
        XCTAssertGreaterThan(diff, f.componentTolerance, """
            일부러 틀린 벡터가 허용 오차를 안 넘었다 — 이 자물쇠는 아무것도 안 잠그고 있다.
            (편차 \(diff), 허용 \(f.componentTolerance))
            """)

        // ③ 길이가 다르면 통과시키면 안 된다 — 빈 벡터가 조용히 초록이 되는 자리
        XCTAssertGreaterThan(Self.maxAbsDiff(ref.embedding, []), f.componentTolerance,
                             "빈 벡터가 통과했다 — 모델이 죽어도 초록이 된다")

        // ③' ★ **NaN 벡터가 통과하면 안 된다.** 실제로 통과했었다 (`실측 2026-08-30`) —
        //     fp16 으로 구운 CoreML 이 어텐션 마스크에서 NaN 을 뱉었는데 `max(0, .nan) == 0`
        //     이라 편차 0 으로 초록이 났다. 그 구멍을 여기가 막는다
        let allNaN = [Float](repeating: .nan, count: ref.embedding.count)
        XCTAssertEqual(Self.maxAbsDiff(ref.embedding, allNaN), .infinity,
                       "NaN 벡터가 통과했다 — 모델이 NaN 을 뱉어도 초록이 된다")
        XCTAssertTrue(TextEmbedder.cosine(allNaN, allNaN).isNaN,
                      "NaN 끼리의 코사인이 NaN 이 아니다 — 어딘가가 삼키고 있다")

        // ④ 서로 다른 두 문장의 코사인이 1.0 이 아니어야 한다 — 기준면이 전부 같은 값이면 무의미
        if let pair = f.cosines.first {
            XCTAssertLessThan(pair.cosine, 0.999,
                "기준면의 코사인이 전부 1 에 붙어 있다 — 문장이 서로 안 다르다")
        }
        print("음성 대조 OK — 틀린 벡터는 걸리고, 빈 벡터도 걸린다")
    }

    // MARK: - 06 프리픽스 규약이 실제로 걸리나

    /// e5 는 질의와 문서를 **다르게** 인코딩한다. 프리픽스를 빼먹으면 아무것도 안 터지고
    /// **점수만 조용히 나빠진다** — 그래서 API 가 규약을 강제하고, 여기가 그걸 잠근다.
    func test_06_prefixConventionIsApplied() throws {
        guard let embedder = try embedderOrAnnounceMissing() else { return }
        let body = "팀에서 갈등이 있었던 경험을 말해주세요"

        // ① 규약대로 부른 것 == 손으로 프리픽스를 붙여 raw 로 부른 것
        let viaAPI = try embedder.embed(query: body)
        let viaRaw = try embedder.embed(raw: "query: " + body)
        XCTAssertEqual(Self.maxAbsDiff(viaRaw.map(Double.init), viaAPI), 0, accuracy: 1e-6,
                       "embed(query:) 가 'query: ' 를 안 붙였다")

        let passageAPI = try embedder.embed(passage: body)
        let passageRaw = try embedder.embed(raw: "passage: " + body)
        XCTAssertEqual(Self.maxAbsDiff(passageRaw.map(Double.init), passageAPI), 0, accuracy: 1e-6,
                       "embed(passage:) 가 'passage: ' 를 안 붙였다")

        // ② ★ 음성 대조 — 프리픽스가 **실제로 벡터를 바꾸나.**
        //    안 바뀌면 위의 ①은 「둘 다 아무것도 안 붙인다」여도 초록이다
        let noPrefix = try embedder.embed(raw: body)
        let d = Self.maxAbsDiff(noPrefix.map(Double.init), viaAPI)
        XCTAssertGreaterThan(d, 1e-3,
            "프리픽스를 붙인 것과 안 붙인 것의 벡터가 사실상 같다 — 규약이 안 걸리고 있다")

        // ③ query 와 passage 도 서로 달라야 한다
        XCTAssertGreaterThan(Self.maxAbsDiff(passageAPI.map(Double.init), viaAPI), 1e-3,
                             "query 와 passage 프리픽스가 같은 벡터를 낸다")

        print(String(format: "프리픽스 규약 OK — 붙인 것과 안 붙인 것의 최대 성분차 %.4f", d))
    }

    // MARK: - 07 지연 실측

    func test_07_latency() throws {
        let f = try fixture()
        guard let embedder = try embedderOrAnnounceMissing() else { return }
        let query = "팀에서 갈등이 있었던 경험을 말해주세요"

        for _ in 0..<3 { _ = try embedder.embed(query: query) }   // 예열

        var ms: [Double] = []
        for _ in 0..<30 {
            let t0 = DispatchTime.now().uptimeNanoseconds
            _ = try embedder.embed(query: query)
            ms.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
        }
        ms.sort()
        let median = ms[ms.count / 2]
        let ids = embedder.tokenizer.encode(f.queryPrefix + query)
        print(String(format: """
            질의 1건 지연 (Swift/CoreML) — 중앙값 %.2fms  p10 %.2f  p90 %.2f  (30회)
              토큰 %d개 → 패딩 길이 %d · 파이썬 기준면 %.2fms
            """, median, ms[3], ms[26], ids.count,
            embedder.paddedLength(for: ids.count), f.pythonMedianMs))

        // 상한은 안 건다 — 기계마다 다르고, 걸면 남의 맥에서 헛빨강이 난다.
        // 대신 **터무니없으면** 잡는다: 1초는 뭔가 잘못된 것이다(모델이 CPU 로 떨어졌다든지).
        XCTAssertLessThan(median, 1000.0, "질의 하나에 1초가 넘는다 — 계산 경로를 확인해라")
    }
}
