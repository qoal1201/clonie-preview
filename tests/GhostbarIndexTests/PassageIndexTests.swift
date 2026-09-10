import Foundation
import XCTest
@testable import GhostbarCore
@testable import GhostbarIndex

/// P3 장문 색인의 모델 없는 자물쇠.
///
/// 실제 CoreML 추론은 `ContentIndexerTests`가 별도로 잰다. 여기는 간단한 토큰 계수기를
/// 주입해 문서 경계·겹침·사이드카 판 올림을 모델 설치와 무관하게 고정한다.
final class PassageIndexTests: XCTestCase {

    private let date = Date(timeIntervalSince1970: 1_760_000_000)

    private func fragment(body: String) -> Fragment {
        Fragment(id: "notes/long", title: "장문 회고", body: body, questionIds: [],
                 createdAt: date, updatedAt: date)
    }

    /// 단어 수만 세는 가짜 토크나이저. 실제 색인은 manifest와 UnigramTokenizer를 쓴다.
    private func words(_ text: String) -> Int {
        text.split { $0.isWhitespace }.count
    }

    func test_passagesCoverBeginningMiddleAndEndWithinTheConfiguredBound() {
        let body = """
        # 타임라인

        BEGIN alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu.

        MIDDLE nu xi omicron pi rho sigma tau upsilon phi chi psi omega.

        END one two three four five six seven eight nine ten eleven twelve.
        """

        let passages = ContentIndexer.passages(for: fragment(body: body), maxTokens: 18,
                                                overlapTokens: 4, tokenCount: words)

        XCTAssertGreaterThanOrEqual(passages.count, 3)
        XCTAssertTrue(passages.contains { $0.sourceText.contains("BEGIN") })
        XCTAssertTrue(passages.contains { $0.sourceText.contains("MIDDLE") })
        XCTAssertTrue(passages.contains { $0.sourceText.contains("END") })
        XCTAssertTrue(passages.allSatisfy { words($0.text) <= 18 },
                      "한 passage가 모형 입력 한도를 넘었다")
        XCTAssertTrue(passages.allSatisfy { $0.text.contains("장문 회고") },
                      "어느 위치의 문장인지 알 수 있게 문서 제목을 함께 넣어야 한다")

        // 두 번째 passage는 직전 끝 문장을 다시 품어, 경계에 걸린 질의를 놓치지 않는다.
        XCTAssertTrue(passages.dropFirst().contains { $0.sourceText.contains("mu.") },
                      "겹침이 없어 문단 경계의 질의를 놓친다")
    }

    /// 기본 512 경로도 `encode`의 절단된 결과가 아니라 tokenizer 전체 길이로 계획해야 한다.
    /// 실제 CoreML 추론은 하지 않아도, 설치된 실제 tokenizer·prefix·manifest 조합을 그대로 잰다.
    func test_defaultTokenizerPlansLongBodyWithoutTruncationAndKeepsShortPlainBodyWhole() throws {
        let scratch = try IndexTestSupport.makeTempDirectory("passage-default-token-bound")
        defer { try? FileManager.default.removeItem(at: scratch) }
        guard let indexer = IndexTestSupport.indexerOrAnnounceMissing(
            sidecarURL: scratch.appendingPathComponent(".clonie", isDirectory: true)) else { return }

        let long = fragment(body: Array(repeating: "alpha", count: 600).joined(separator: " "))
        let planned = indexer.passages(for: long)
        XCTAssertGreaterThan(planned.count, 1,
                             "기본 512에서 긴 본문이 tokenizer 절단 때문에 한 passage로 남았다")
        for passage in planned {
            let actual = indexer.embedder.tokenizer
                .pieces(of: indexer.embedder.manifest.passagePrefix + passage.text).count + 2
            XCTAssertLessThanOrEqual(actual, indexer.embedder.manifest.maxSequenceLength,
                                     "계획한 passage가 실제 모델 입력 한도를 넘었다: \(actual)")
        }

        let short = fragment(body: "heading 없이도 충분히 짧은 일반 본문이다. 한 덩어리로 남아야 한다.")
        XCTAssertEqual(indexer.passages(for: short).count, 1,
                       "짧고 heading 없는 문서를 공백마다 여러 passage로 쪼갰다")
    }

    func test_oversizedTitleAndHeadingLeaveBoundedRoomForBodyPassages() {
        let longTitle = Array(repeating: "title", count: 80).joined(separator: " ")
        let longHeading = Array(repeating: "heading", count: 80).joined(separator: " ")
        let bodyWords = Array(repeating: "body", count: 36).joined(separator: " ")
        let f = Fragment(id: "notes/context", title: longTitle,
                         body: "# \(longHeading)\n\n\(bodyWords)", questionIds: [],
                         createdAt: date, updatedAt: date)

        let passages = ContentIndexer.passages(for: f, maxTokens: 16, overlapTokens: 0,
                                                tokenCount: words)
        XCTAssertGreaterThanOrEqual(passages.count, 3, "양성 대조 — 본문이 passage로 안 갈렸다")
        XCTAssertLessThan(passages.count, 10,
                          "긴 문맥 때문에 본문을 한 글자씩 쪼개고 있다")
        XCTAssertTrue(passages.allSatisfy { words($0.text) <= 16 },
                      "문맥 예산을 둬도 모델 입력 한도를 넘었다")
        XCTAssertTrue(passages.allSatisfy { $0.sourceText.contains("body") },
                      "문맥만 남고 본문 source 범위가 사라졌다")
    }

    func test_legacySingleVectorFileIsNotAcceptedAsAPassageIndex() throws {
        let scratch = try IndexTestSupport.makeTempDirectory("passage-migration")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let sidecar = scratch.appendingPathComponent(".clonie", isDirectory: true)
        let store = ContentIndexStore(sidecarURL: sidecar)
        let model = ContentIndexStore.ModelIdentity(id: "test", revision: "r", dimensions: 2,
                                                    passagePrefix: "passage: ", queryPrefix: "query: ")
        let legacy = """
        {"schemaVersion":1,"encoding":"float32-le-base64","model":{"id":"test","revision":"r","dimensions":2,"passagePrefix":"passage: ","queryPrefix":"query: "},"entries":{"notes/long":{"hash":"sha256:old","vector":"AAAAAA=="}}}
        """
        try FileManager.default.createDirectory(at: sidecar, withIntermediateDirectories: true)
        try Data(legacy.utf8).write(to: store.embeddingsURL)

        XCTAssertNil(store.loadPassages(for: model),
                     "v1 단일 벡터는 장문의 전체 내용을 대표하는 passage로 읽으면 안 된다")
    }

    func test_longDocumentReusesUnchangedPassagesAndDropsDeletedDocument() throws {
        let scratch = try IndexTestSupport.makeTempDirectory("passage-incremental")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let sidecar = scratch.appendingPathComponent(".clonie", isDirectory: true)
        guard let real = IndexTestSupport.indexerOrAnnounceMissing(sidecarURL: sidecar) else { return }
        // 실제 모델은 그대로 쓰되 작은 한도로 장문 passage 증분을 빠르고 결정적으로 잰다.
        let indexer = ContentIndexer(sidecarURL: sidecar, embedder: real.embedder,
                                     passageMaxTokens: 24, passageOverlapTokens: 4)
        var document = fragment(body: """
        # 경험

        처음에는 고객 요청을 수집하고 우선순위를 정해 팀과 공유했습니다. 매주 결과를 검토했습니다.

        중간에는 실패 원인을 재현하고 지표를 나눠 실험했습니다. 담당자와 판단 근거를 기록했습니다.

        마지막에는 배포 뒤 오류율을 확인하고 회고를 남겼습니다. 다음 작업의 기준도 바꿨습니다.
        """)

        let cold = try indexer.reindex(fragments: [document])
        XCTAssertGreaterThanOrEqual(cold.embedded, 3, "양성 대조 — 장문이 passage로 안 갈렸다")
        XCTAssertEqual(cold.vectors[document.id], nil,
                       "여러 passage 파일을 단일 문서 벡터로 다시 내보내면 안 된다")
        XCTAssertGreaterThanOrEqual(cold.passageVectors[document.id]?.count ?? 0, 3)

        let warm = try indexer.reindex(fragments: [document])
        XCTAssertEqual(warm.embedded, 0, "같은 passage를 다시 모델에 넣었다")
        XCTAssertEqual(warm.reused, cold.embedded)

        document.body += "\n\n추가로 마지막 지표를 한 번 더 확인했습니다."
        let changed = try indexer.reindex(fragments: [document])
        XCTAssertGreaterThan(changed.embedded, 0, "끝 passage를 고쳤는데 낡은 벡터를 재사용했다")
        XCTAssertLessThan(changed.embedded, cold.embedded,
                          "문서 끝만 고쳤는데 처음부터 전부 다시 계산했다")
        XCTAssertGreaterThan(changed.reused, 0)

        let dropped = try indexer.reindex(fragments: [])
        XCTAssertEqual(dropped.total, 0)
        XCTAssertGreaterThanOrEqual(dropped.dropped, cold.embedded,
                                    "지운 문서의 passage가 sidecar에 남았다")
        let model = ContentIndexStore.ModelIdentity(indexer.embedder.manifest)
        XCTAssertEqual(indexer.store.loadPassages(for: model), [:])
    }

    func test_rankUsesTheBestPassagePerFileAndReturnsItsSource() {
        func passage(_ id: String, _ source: String) -> ContentIndexer.Passage {
            ContentIndexer.Passage(id: id, fragmentID: "notes/\(id.prefix(1))",
                                   startUTF16: 0, endUTF16: source.utf16.count,
                                   text: source, sourceText: source,
                                   hash: ContentIndexer.hash(source))
        }
        let weak = passage("a-early", "파일 A 앞부분")
        let decisive = passage("a-late", "파일 A 결정적 뒷부분")
        let other = passage("b-only", "파일 B 본문")
        let ranked = ContentIndexer.rank(queryVector: [1, 0], passageVectors: [
            "notes/a": [.init(passage: weak, vector: [0.1, 0]),
                        .init(passage: decisive, vector: [0.95, 0])],
            "notes/b": [.init(passage: other, vector: [0.7, 0])],
        ])

        XCTAssertEqual(ranked.map(\.fragmentID), ["notes/a", "notes/b"])
        XCTAssertEqual(ranked.first?.passage.id, "a-late",
                       "파일 점수는 평균이나 첫 passage가 아니라 최고 cosine이어야 한다")
        XCTAssertEqual(ranked.first?.passage.sourceText, "파일 A 결정적 뒷부분",
                       "검색 결과는 파일 전체 대신 실제로 맞은 passage를 출처로 내야 한다")
    }
}
