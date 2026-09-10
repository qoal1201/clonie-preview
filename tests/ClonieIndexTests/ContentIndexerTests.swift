import Foundation
import XCTest
@testable import ClonieCore
@testable import ClonieEmbedding
@testable import ClonieIndex

/// ★ **내용 그래프 자물쇠** — #32 의 인수 본체.
///
/// | 빨개지는 곳 | 범인 |
/// |---|---|
/// | `test_02_incremental…` | 증분이 죽었다 — 해시가 같은데 모델을 또 불렀다 |
/// | `test_04_threshold…` | 문턱이 두 무리를 못 가른다. **모델을 바꿨으면 여기가 먼저 빨개진다** |
/// | `test_05_degrades…` | 모델 없는 환경에서 색인이 앱을 끌고 넘어진다 |
/// | `test_06_userMarkdown…` | 승인 경계가 뚫렸다 — 유저 md 를 건드렸다 |
final class ContentIndexerTests: XCTestCase {

    // ⚠ 값이 아니라 **하한**이다. 말뭉치를 지워서 초록을 만드는 길을 막는다.
    static let minFragments = 20
    static let minDuplicatePairs = 5
    /// 질문 축(#34)의 하한. **물음꼴 수를 따로 세는 이유**: 변형이 통째로 빠져도
    /// 질문 개수는 그대로라 안 빨개진다.
    static let minQuestions = 6
    static let minQuestionForms = 12

    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = try IndexTestSupport.makeTempDirectory("case")
    }

    override func tearDownWithError() throws {
        if let s = scratch { try? FileManager.default.removeItem(at: s) }
    }

    private var sidecar: URL { scratch.appendingPathComponent(".clonie", isDirectory: true) }

    // MARK: - 00 말뭉치가 살아 있나 (모델 없이 돈다)

    func test_00_corpusIsPresentAndHasBothGroups() throws {
        let frs = NeighborCorpus.fragments()
        XCTAssertGreaterThanOrEqual(frs.count, Self.minFragments,
            "말뭉치가 하한 아래다 — 조각을 지워서 초록을 만들지 마라")
        XCTAssertGreaterThanOrEqual(NeighborCorpus.duplicatePairs.count, Self.minDuplicatePairs,
            "정답 쌍이 하한 아래다")

        let ids = Set(frs.map(\.id))
        XCTAssertEqual(ids.count, frs.count, "말뭉치에 id 가 겹친다")
        for (a, b) in NeighborCorpus.duplicatePairs {
            XCTAssertTrue(ids.contains(a) && ids.contains(b), "정답 쌍이 가리키는 조각이 없다: \(a)/\(b)")
        }
        for f in frs {
            XCTAssertFalse(ContentIndexer.indexText(f).isEmpty, "\(f.id) 의 색인 글자가 비었다")
        }
        let pairs = frs.count * (frs.count - 1) / 2
        print("말뭉치 OK — 조각 \(frs.count)장 · 전체 \(pairs)쌍 · "
            + "정답(같은 사연) \(NeighborCorpus.duplicatePairs.count)쌍 · "
            + "나머지 \(pairs - NeighborCorpus.duplicatePairs.count)쌍")
    }

    // MARK: - 01 색인 글자와 해시 (모델 없이 돈다)

    func test_01_indexTextAndHash() throws {
        let t = Date(timeIntervalSince1970: 1_750_000_000)
        let f = Fragment(id: "x", title: " 제목 ", body: " 본문 ", questionIds: ["q-1"],
                         createdAt: t, updatedAt: t)
        XCTAssertEqual(ContentIndexer.indexText(f), "제목\n본문", "제목과 본문 둘 다 들어가야 한다")

        // ⚠ 칩·시각은 색인 글자에 **안 든다** — 들면 칩 하나 눌렀다고 384차를 다시 계산한다.
        var moved = f
        moved.questionIds = ["q-9"]
        moved.updatedAt = t.addingTimeInterval(10_000)
        XCTAssertEqual(ContentIndexer.hash(ContentIndexer.indexText(moved)),
                       ContentIndexer.hash(ContentIndexer.indexText(f)),
                       "칩/시각만 바뀌었는데 해시가 달라졌다 — 재계산이 헛돈다")

        var edited = f
        edited.body = " 본문이 달라졌다 "
        XCTAssertNotEqual(ContentIndexer.hash(ContentIndexer.indexText(edited)),
                          ContentIndexer.hash(ContentIndexer.indexText(f)),
                          "본문이 바뀌었는데 해시가 같다 — 증분이 낡은 벡터를 붙든다")

        // 벡터 왕복이 **비트 단위로** 같나. 여기가 깨지면 재사용한 벡터가 조용히 틀려진다
        let v: [Float] = (0..<384).map { Float($0) * 0.001 - 0.19 }
        let round = ContentIndexStore.decode(vector: ContentIndexStore.encode(vector: v),
                                             dimensions: 384)
        XCTAssertEqual(round, v, "벡터 왕복에서 값이 변했다")
        XCTAssertNil(ContentIndexStore.decode(vector: ContentIndexStore.encode(vector: v),
                                              dimensions: 383),
                     "길이가 다른 벡터를 통과시켰다 — 0 벡터가 조용히 앉는 자리다")
    }

    // MARK: - 02 ★ 증분 — 해시가 같으면 모델을 안 부른다

    func test_02_incrementalReusesUnchangedVectors() throws {
        guard let indexer = IndexTestSupport.indexerOrAnnounceMissing(sidecarURL: sidecar) else { return }
        let frs = NeighborCorpus.fragments()
        func plans(_ values: [Fragment]) -> [ContentIndexer.Passage] {
            values.flatMap { indexer.passages(for: $0) }
        }

        let cold = try indexer.reindex(fragments: frs)
        XCTAssertTrue(cold.coldBuild, "첫 색인인데 콜드가 아니다")
        XCTAssertEqual(cold.embedded, plans(frs).count, "첫 색인에서 passage를 전부 계산해야 한다")
        XCTAssertEqual(cold.reused, 0)
        print("콜드 — " + cold.summary)

        // ★ 같은 것을 다시 — **모델을 한 번도 안 불러야 한다**
        let warm = try indexer.reindex(fragments: frs)
        XCTAssertFalse(warm.coldBuild, "두 번째인데 색인 파일을 못 읽었다")
        XCTAssertEqual(warm.embedded, 0, "해시가 같은데 다시 계산했다 — 증분이 죽었다")
        XCTAssertEqual(warm.reused, plans(frs).count)
        XCTAssertTrue(warm.duplicates.isEmpty, "바뀐 것이 없는데 중복 알림이 났다")
        print("웜   — " + warm.summary)

        // 한 장만 고치면 그 한 장만
        var edited = frs
        edited[3].body += " 그리고 그 뒤에 회고를 한 번 더 돌렸다."
        let partial = try indexer.reindex(fragments: edited)
        let oldHashes = Set(plans(frs).map(\.hash))
        let editedPlans = plans(edited)
        let editedEmbedded = editedPlans.filter { !oldHashes.contains($0.hash) }.count
        XCTAssertEqual(partial.embedded, editedEmbedded,
                       "바뀐 passage 외에 \(partial.embedded - editedEmbedded)개를 다시 계산했다")
        XCTAssertEqual(partial.reused, editedPlans.count - editedEmbedded)

        // 새 조각 한 장 → 하나만 늘고
        let t = Date(timeIntervalSince1970: 1_750_000_000)
        let added = edited + [Fragment(id: "brand-new", title: "완전히 다른 이야기",
                                       body: "주말에 텃밭에 상추를 심었다. 물을 얼마나 줘야 하는지 몰랐다.",
                                       questionIds: [], createdAt: t, updatedAt: t)]
        let grown = try indexer.reindex(fragments: added)
        let editedHashes = Set(editedPlans.map(\.hash))
        XCTAssertEqual(grown.embedded, plans(added).filter { !editedHashes.contains($0.hash) }.count)
        XCTAssertEqual(grown.total, frs.count + 1)

        // 지우면 벡터도 걷힌다
        let shrunk = try indexer.reindex(fragments: Array(added.dropLast()))
        XCTAssertEqual(shrunk.dropped, plans(added).count - plans(edited).count,
                       "사라진 조각의 passage 벡터를 안 걷었다")
        XCTAssertEqual(shrunk.embedded, 0)
        XCTAssertEqual(shrunk.total, frs.count)
    }

    // MARK: - 03 색인 파일 규약

    func test_03_sidecarFilesAreWellFormed() throws {
        guard let indexer = IndexTestSupport.indexerOrAnnounceMissing(sidecarURL: sidecar) else { return }
        let frs = NeighborCorpus.fragments()
        let report = try indexer.reindex(fragments: frs)

        let store = ContentIndexStore(sidecarURL: sidecar)
        let model = ContentIndexStore.ModelIdentity(indexer.embedder.manifest)

        let passages = try XCTUnwrap(store.loadPassages(for: model), "embeddings.json 을 못 읽었다")
        XCTAssertEqual(Set(passages.keys), Set(frs.map(\.id)), "색인 파일의 파일 id 가 문서와 다르다")
        XCTAssertEqual(passages.values.reduce(0) { $0 + $1.count }, report.embedded,
                       "콜드 보고의 passage 수와 파일의 passage 수가 다르다")
        XCTAssertEqual(report.passageVectors.values.reduce(0) { $0 + $1.count }, report.embedded,
                       "보고가 passage 벡터를 전부 화면에 넘기지 않았다")
        for fragment in frs {
            let stored = try XCTUnwrap(passages[fragment.id])
            let planned = indexer.passages(for: fragment)
            XCTAssertEqual(stored.count, planned.count, "\(fragment.id) passage 수가 계획과 다르다")
            for (entry, plan) in zip(stored, planned) {
                XCTAssertEqual(entry.id, plan.id)
                XCTAssertEqual(entry.startUTF16, plan.startUTF16)
                XCTAssertEqual(entry.endUTF16, plan.endUTF16)
                XCTAssertEqual(entry.hash, plan.hash)
                XCTAssertTrue(entry.hash.hasPrefix("sha256:"), "\(entry.id) 해시 모양이 다르다")
                let decoded = try XCTUnwrap(
                    ContentIndexStore.decode(vector: entry.vector, dimensions: model.dimensions),
                    "\(entry.id) 벡터를 못 푼다")
                let reported = try XCTUnwrap(report.passageVectors[fragment.id]?
                    .first { $0.passage.id == entry.id })
                XCTAssertEqual(reported.vector, decoded, "\(entry.id) 파일과 보고 벡터가 다르다")
            }
        }

        // 이전 단일-벡터 소비자는 **정확히 한 passage인 파일만** 받는다. 여러 passage를
        // 첫 조각 벡터로 축약하면 장문의 뒤쪽이 조용히 사라진다.
        let legacy = try XCTUnwrap(store.loadVectors(for: model))
        let singleIDs = Set(passages.compactMap { $0.value.count == 1 ? $0.key : nil })
        XCTAssertEqual(Set(legacy.keys), singleIDs)
        XCTAssertEqual(Set(report.vectors.keys), singleIDs)
        for id in singleIDs {
            let sole = try XCTUnwrap(passages[id]?.first)
            XCTAssertEqual(legacy[id]?.hash, sole.hash)
            XCTAssertEqual(legacy[id]?.vector, sole.vector)
        }

        let links = try XCTUnwrap(store.loadLinks(), "links.json 을 못 읽었다")
        XCTAssertEqual(links.policy.topK, ContentIndexer.topK)
        XCTAssertEqual(links.policy.linkFloor, ContentIndexer.linkFloor)
        XCTAssertEqual(links.policy.nearDuplicate, ContentIndexer.nearDuplicate)
        XCTAssertFalse(links.links.isEmpty, "이웃이 한 건도 안 잡혔다 — 0건은 결론이 아니다")
        for (id, ns) in links.links {
            XCTAssertLessThanOrEqual(ns.count, ContentIndexer.topK, "\(id) 이웃이 topK 를 넘었다")
            XCTAssertFalse(ns.contains { $0.id == id }, "\(id) 가 자기 자신을 이웃으로 들었다")
            XCTAssertEqual(ns, ns.sorted { $0.score == $1.score ? $0.id < $1.id : $0.score > $1.score },
                           "\(id) 이웃이 점수순이 아니다")
            for n in ns {
                XCTAssertGreaterThanOrEqual(n.score, ContentIndexer.linkFloor)
                XCTAssertNotNil(passages[n.id], "\(id) 가 색인에 없는 조각을 가리킨다")
            }
        }

        // ★ 두 번 돌려도 **글자 단위로 같은 파일**이어야 한다 — 안 그러면 남의 옵시디언
        //   동기화가 열 때마다 깨어난다
        let first = try Data(contentsOf: store.embeddingsURL)
        _ = try indexer.reindex(fragments: frs)
        XCTAssertEqual(try Data(contentsOf: store.embeddingsURL), first,
                       "같은 입력인데 embeddings.json 이 달라졌다")
        XCTAssertEqual(try XCTUnwrap(store.loadLinks()).links, links.links,
                       "같은 입력인데 이웃이 달라졌다")

        print(store.describeVectors() + " · 이웃을 가진 조각 \(links.links.count)장")
    }

    // MARK: - 04 ★ 문턱 — 두 무리가 겹치나

    /// `memory/feedback-measure-threshold-overlap-first` — 분포 표로 끝내지 않는다.
    /// **넘어야 하는 것의 최소**와 **못 넘어야 하는 것의 최대**를 나란히 놓고 간격을 낸다.
    func test_04_thresholdSeparatesTheTwoGroups() throws {
        guard let indexer = IndexTestSupport.indexerOrAnnounceMissing(sidecarURL: sidecar) else { return }
        let frs = NeighborCorpus.fragments()

        var vec: [String: [Float]] = [:]
        for f in frs { vec[f.id] = try indexer.embedder.embed(passage: ContentIndexer.indexText(f)) }

        let goldPairs = Set(NeighborCorpus.duplicatePairs.map { [$0.0, $0.1].sorted().joined(separator: "|") })
        var near: [(Double, String)] = []
        var far: [(Double, String)] = []
        let ids = frs.map(\.id).sorted()
        for i in 0..<ids.count {
            for j in (i + 1)..<ids.count {
                let key = [ids[i], ids[j]].sorted().joined(separator: "|")
                let s = Double(TextEmbedder.cosine(vec[ids[i]]!, vec[ids[j]]!))
                (goldPairs.contains(key) ? { near.append(($0, key)) } : { far.append(($0, key)) })(s)
            }
        }
        XCTAssertEqual(near.count, NeighborCorpus.duplicatePairs.count, "정답 쌍을 다 못 쟀다")
        XCTAssertGreaterThan(far.count, 100, "음성 쌍이 너무 적다 — 간격이 거짓으로 벌어진다")

        let nearS = near.map(\.0).sorted(), farS = far.map(\.0).sorted()
        let nearMin = nearS.first!, farMax = farS.last!
        let gap = nearMin - farMax

        print(String(format: """

            ── 이웃 문턱 근거 분포 (`실측`) — 조각 %d장 · %d쌍 ─────────────────
              같은 사연을 다시 쓴 쌍 (%d쌍)  최소 %.3f  중앙 %.3f  최대 %.3f
              서로 다른 조각        (%d쌍)  중앙 %.3f  90분위 %.3f  최대 %.3f
              간격 (정답최소 − 오답최대)      %+.3f  → %@
              가장 높은 오답 쌍               %@ (%.3f)
              가장 낮은 정답 쌍               %@ (%.3f)
              현재 상수: linkFloor %.2f · nearDuplicate %.2f
            ─────────────────────────────────────────────────────────────

            """,
            frs.count, near.count + far.count,
            nearS.count, nearMin, IndexTestSupport.percentile(nearS, 0.5), nearS.last!,
            farS.count, IndexTestSupport.percentile(farS, 0.5),
            IndexTestSupport.percentile(farS, 0.9), farMax,
            gap, (gap > 0 ? "갈린다" : "**겹친다 — 이 문턱은 판정을 못 한다**") as NSString,
            far.max(by: { $0.0 < $1.0 })!.1 as NSString, farMax,
            near.min(by: { $0.0 < $1.0 })!.1 as NSString, nearMin,
            ContentIndexer.linkFloor, ContentIndexer.nearDuplicate))

        print("  정답 쌍 하나하나:")
        for (s, key) in near.sorted(by: { $0.0 < $1.0 }) {
            print(String(format: "    %-28@ %.3f  %@", key as NSString, s,
                         (s >= ContentIndexer.nearDuplicate ? "알림 뜬다" : "**놓친다**") as NSString))
        }

        // ★ 상수가 실제로 두 무리 사이에 있나. **선언한 값과 잰 값이 갈리면 빨강이다.**
        XCTAssertGreaterThan(gap, 0, """
            두 무리가 겹친다 — 이 문턱은 판정을 못 한다.
            정답 최소 \(nearMin), 오답 최대 \(farMax).
            겹치면 갈래는 둘이다: ① 기본값으로 물러선다 ② 절대값을 안 쓰고 순위만 쓴다.
            """)
        XCTAssertLessThanOrEqual(ContentIndexer.nearDuplicate, nearMin,
            "nearDuplicate 가 정답 최소(\(nearMin))보다 높다 — 정답을 놓친다")
        XCTAssertGreaterThan(ContentIndexer.nearDuplicate, farMax,
            "nearDuplicate 가 오답 최대(\(farMax))보다 낮다 — 남의 이야기를 중복이라 부른다")
        XCTAssertLessThan(ContentIndexer.linkFloor, ContentIndexer.nearDuplicate,
            "링크 바닥이 중복 문턱보다 높다 — 중복인데 링크가 안 걸린다")
    }

    // MARK: - 04' 문턱이 실제로 뭔가를 거르나 (음성 대조)

    func test_04b_duplicateNoticeIsNotVacuous() throws {
        guard let indexer = IndexTestSupport.indexerOrAnnounceMissing(sidecarURL: sidecar) else { return }
        let frs = NeighborCorpus.fragments()
        let (a, b) = NeighborCorpus.duplicatePairs[0]

        // ① 한쪽만 먼저 넣고 색인한 뒤, 짝을 나중에 넣으면 **알림이 나야 한다**
        let others = frs.filter { $0.id != b }
        _ = try indexer.reindex(fragments: others)
        let hit = try indexer.reindex(fragments: frs)
        XCTAssertEqual(hit.embedded, 1)
        XCTAssertTrue(hit.duplicates.contains { ($0.id == b && $0.otherID == a) },
                      "같은 사연을 다시 넣었는데 알림이 안 났다 — 알림이 죽었다. \(hit.duplicates)")

        // ② ★ 양성 대조의 반대편 — **아무 관계 없는 조각**은 알림이 나면 안 된다
        let t = Date(timeIntervalSince1970: 1_750_000_000)
        let unrelated = Fragment(id: "unrelated",
                                 title: "고양이가 새벽에 우는 이유를 찾아봤다",
                                 body: "밤마다 우는 통에 검색을 했다. 사료 시간을 당기니 조용해졌다.",
                                 questionIds: [], createdAt: t, updatedAt: t)
        let quiet = try indexer.reindex(fragments: frs + [unrelated])
        XCTAssertEqual(quiet.embedded, 1)
        XCTAssertFalse(quiet.duplicates.contains { $0.id == "unrelated" },
                       "관계없는 조각에 중복 알림이 났다 — 문턱이 아무것도 안 거른다")

        // ③ 콜드 빌드는 **전부가 바뀐 것**이라 알림을 그대로 쓰면 안 된다. 보고가 그걸 밝히나
        let fresh = try IndexTestSupport.makeTempDirectory("cold")
        defer { try? FileManager.default.removeItem(at: fresh) }
        guard let i2 = IndexTestSupport.indexerOrAnnounceMissing(
            sidecarURL: fresh.appendingPathComponent(".clonie")) else { return }
        let cold = try i2.reindex(fragments: frs)
        XCTAssertTrue(cold.coldBuild, "콜드 빌드라고 안 밝힌다 — 앱이 알림을 무더기로 띄운다")
        print("중복 알림 — 정답 쌍은 잡히고, 관계없는 조각은 안 잡힌다 "
            + "(콜드 빌드에서 잡힌 쌍 \(cold.duplicates.count)건, 이건 앱이 안 띄운다)")
    }

    // MARK: - 05 ★ 모델이 없을 때 — 앱은 그대로 돈다

    func test_05_degradesWithoutModel() throws {
        let empty = try IndexTestSupport.makeTempDirectory("nomodel")
        defer { try? FileManager.default.removeItem(at: empty) }

        switch ContentIndexer.open(sidecarURL: sidecar,
                                   environment: [EmbeddingModelStore.directoryOverrideKey: empty.path]) {
        case .ready:
            XCTFail("빈 폴더를 가리켰는데 색인기가 만들어졌다 — 어딘가에서 기본 자리로 물러섰다")
        case .unavailable(let status):
            XCTAssertFalse(status.isReady)
            guard case .missing(let searched) = status else {
                return XCTFail("없음이 아니라 \(status.explanation)")
            }
            XCTAssertEqual(searched.map(\.path), [empty.path], "본 자리를 안 밝힌다")
            // 사람이 읽고 다음에 뭘 할지 아는가
            XCTAssertTrue(status.explanation.contains("fetch-model.sh"), "받는 법을 안 알려준다")
            print("모델 부재 저하 OK —\n\(status.explanation)")
        }

        // ★ 사이드카에 **아무것도 안 쓴다.** 빈 색인 파일을 남기면 다음 실행이 그걸 믿는다
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecar.path),
                       "모델이 없는데 사이드카를 만들었다")
        let store = ContentIndexStore(sidecarURL: sidecar)
        XCTAssertNil(store.loadLinks())
        XCTAssertEqual(store.describeVectors(), "embeddings.json 없음")
    }

    // MARK: - 05' 모델이 바뀌면 색인을 버린다

    func test_05b_indexIsDroppedWhenModelChanges() throws {
        guard let indexer = IndexTestSupport.indexerOrAnnounceMissing(sidecarURL: sidecar) else { return }
        _ = try indexer.reindex(fragments: NeighborCorpus.fragments())

        let store = ContentIndexStore(sidecarURL: sidecar)
        let real = ContentIndexStore.ModelIdentity(indexer.embedder.manifest)
        XCTAssertNotNil(store.loadPassages(for: real))

        for other in [
            ContentIndexStore.ModelIdentity(id: "다른/모델", revision: real.revision,
                                            dimensions: real.dimensions,
                                            passagePrefix: real.passagePrefix,
                                            queryPrefix: real.queryPrefix),
            ContentIndexStore.ModelIdentity(id: real.id, revision: "0000deadbeef",
                                            dimensions: real.dimensions,
                                            passagePrefix: real.passagePrefix,
                                            queryPrefix: real.queryPrefix),
            ContentIndexStore.ModelIdentity(id: real.id, revision: real.revision,
                                            dimensions: 768,
                                            passagePrefix: real.passagePrefix,
                                            queryPrefix: real.queryPrefix),
            ContentIndexStore.ModelIdentity(id: real.id, revision: real.revision,
                                            dimensions: real.dimensions,
                                            passagePrefix: "query: ",
                                            queryPrefix: real.queryPrefix),
            // ★ #34 가 더한 축 — 질문을 어떤 프리픽스로 넣었나도 좌표계다
            ContentIndexStore.ModelIdentity(id: real.id, revision: real.revision,
                                            dimensions: real.dimensions,
                                            passagePrefix: real.passagePrefix,
                                            queryPrefix: "passage: "),
        ] {
            XCTAssertNil(store.loadPassages(for: other),
                         "좌표계가 다른데 옛 passage를 돌려줬다 — 점수가 조용히 틀려지는 자리다: \(other)")
            XCTAssertNil(store.loadQuestions(for: other),
                         "좌표계가 다른데 옛 질문 벡터를 돌려줬다: \(other)")
        }

        // ⚠ **옛 사이드카**(질문 축이 생기기 전, `queryPrefix` 키가 없는 파일)는 못 읽어야 한다.
        //    읽히면 개념 매개가 통째로 빈 채로 검색이 돈다 — 아무것도 안 터지는 모양이다.
        let legacy = """
            {"schemaVersion":1,"encoding":"\(ContentIndexStore.IndexFile.vectorEncoding)",\
            "model":{"id":"\(real.id)","revision":"\(real.revision)",\
            "dimensions":\(real.dimensions),"passagePrefix":"\(real.passagePrefix)"},"entries":{}}
            """
        try Data(legacy.utf8).write(to: store.embeddingsURL)
        XCTAssertNil(store.loadPassages(for: real),
                     "queryPrefix 가 없는 옛 파일을 그대로 읽었다 — 파일의 뜻이 바뀌었는데 안 버렸다")

        // 깨진 파일도 같은 결론 — **격리하지 않고 다시 만든다** (파생물이라서)
        try Data("{ 이건 JSON 이 아니다".utf8).write(to: store.embeddingsURL)
        XCTAssertNil(store.loadPassages(for: real))
        let rebuilt = try indexer.reindex(fragments: NeighborCorpus.fragments())
        XCTAssertTrue(rebuilt.coldBuild, "깨진 색인 위에서 콜드로 안 갔다")
        XCTAssertEqual(rebuilt.embedded,
                       NeighborCorpus.fragments().reduce(0) { $0 + indexer.passages(for: $1).count })
    }

    // MARK: - 06 ★ 승인 경계 — 유저 md 에는 한 글자도 안 쓴다

    func test_06_userMarkdownIsNeverTouched() throws {
        let vault = try IndexTestSupport.makeTempDirectory("vault")
        defer { try? FileManager.default.removeItem(at: vault) }

        let store = VaultStore(vaultURL: vault)
        let t = Date(timeIntervalSince1970: 1_750_000_000)
        let frs = Array(NeighborCorpus.fragments().prefix(6))
        _ = try store.load()
        try store.save(CueDocument(questions: [], fragments: frs))

        // 사람이 손으로 넣어둔 md 한 장도 같이 — frontmatter 가 없는, 앱이 안 만든 파일
        let handmade = vault.appendingPathComponent("옛날 회고.md")
        try Data("# 옛날 회고\n\n앱이 만들지 않은 파일이다.\n".utf8).write(to: handmade)

        func snapshot() throws -> [String: (Data, Date)] {
            var out: [String: (Data, Date)] = [:]
            for rel in try store.markdownRelativePaths() {
                let u = vault.appendingPathComponent(rel)
                let a = try FileManager.default.attributesOfItem(atPath: u.path)
                out[rel] = (try Data(contentsOf: u), a[.modificationDate] as! Date)
            }
            return out
        }
        let before = try snapshot()
        XCTAssertGreaterThanOrEqual(before.count, 7, "양성 대조 — 볼트에 md 가 안 깔렸다")

        guard let indexer = IndexTestSupport.indexerOrAnnounceMissing(
            sidecarURL: store.sidecarURL) else { return }
        _ = try indexer.reindex(fragments: try store.load().document.fragments)

        let after = try snapshot()
        XCTAssertEqual(after.count, before.count, "색인이 md 를 늘리거나 줄였다")
        for (rel, b) in before {
            let a = try XCTUnwrap(after[rel], "\(rel) 이 사라졌다")
            XCTAssertEqual(a.0, b.0, "\(rel) 의 알맹이가 바뀌었다 — 승인 경계가 뚫렸다")
            XCTAssertEqual(a.1, b.1, "\(rel) 의 수정 시각이 바뀌었다 — 안 바뀐 파일을 다시 썼다")
        }

        // 새로 생긴 것은 사이드카 안뿐인가
        let sidecarFiles = try FileManager.default
            .contentsOfDirectory(atPath: store.sidecarURL.path).sorted()
        XCTAssertTrue(sidecarFiles.contains("embeddings.json"))
        XCTAssertTrue(sidecarFiles.contains("links.json"))
        print("승인 경계 OK — md \(before.count)장 그대로, 새로 생긴 것은 .clonie/ 안뿐 "
            + "(\(sidecarFiles.joined(separator: ", ")))")
        _ = t
    }

    // MARK: - 06' 사람이 읽는 한 줄 (모델 없이 돈다)

    /// 띠에 뜨는 글자. **모델 없이 도는 순수 함수라** 여기서 잠근다 —
    /// 앱 층에 두면 잴 방법이 `.app` 을 띄우는 것밖에 없다.
    func test_06b_duplicateNoticeReadsLikeASentence() throws {
        let frs = NeighborCorpus.fragments()
        XCTAssertNil(ContentIndexer.duplicateNotice([], fragments: frs),
                     "알릴 것이 없는데 글자를 만들었다 — 빈 띠가 뜨는 자리다")

        let (a, b) = NeighborCorpus.duplicatePairs[0]
        let one = try XCTUnwrap(ContentIndexer.duplicateNotice(
            [.init(id: b, otherID: a, score: 0.835)], fragments: frs))
        // ★ **id 가 아니라 제목으로 부른다.** `deploy-1` 을 보여주면 사람은 그게 뭔지 모른다.
        XCTAssertTrue(one.contains(NeighborCorpus.fragment(a).title), "짝의 제목을 안 불렀다: \(one)")
        XCTAssertFalse(one.contains(a), "id 가 그대로 새어나왔다: \(one)")
        XCTAssertTrue(one.contains("84%"), "닮은 정도를 안 말한다: \(one)")
        XCTAssertFalse(one.contains("그 밖에"), "한 건인데 나머지를 셌다: \(one)")
        print("알림 한 줄 — \(one)")

        // 여러 건이면 **가장 가까운 것 하나만 이름을 대고** 나머지는 센다. 띠는 한 줄이다.
        let many = try XCTUnwrap(ContentIndexer.duplicateNotice(
            [.init(id: b, otherID: a, score: 0.835),
             .init(id: b, otherID: "conflict-1", score: 0.71)], fragments: frs))
        XCTAssertTrue(many.contains("그 밖에 1건"), "나머지를 안 셌다: \(many)")
        XCTAssertFalse(many.contains(NeighborCorpus.fragment("conflict-1").title),
                       "두 번째 제목까지 띠에 넣었다 — 한 줄을 넘긴다: \(many)")

        // 색인에 없는 짝 · 제목 없는 조각에서 **안 죽는다** (볼트는 밖에서도 바뀐다)
        XCTAssertNotNil(ContentIndexer.duplicateNotice(
            [.init(id: "x", otherID: "사라진-조각", score: 0.9)], fragments: frs))
        let t = Date(timeIntervalSince1970: 1_750_000_000)
        let untitled = Fragment(id: "u", title: "   ", body: "본문만 있다",
                                questionIds: [], createdAt: t, updatedAt: t)
        let blank = try XCTUnwrap(ContentIndexer.duplicateNotice(
            [.init(id: "x", otherID: "u", score: 0.9)], fragments: [untitled]))
        XCTAssertTrue(blank.contains("제목 없는 조각"), "빈 제목이 「」 로 새어나왔다: \(blank)")
    }

    // MARK: - 07 색인 시간 실측 — 콜드/웜

    func test_07_indexingLatency() throws {
        guard let indexer = IndexTestSupport.indexerOrAnnounceMissing(sidecarURL: sidecar) else { return }

        // 조각 50장 규모. 말뭉치를 밑돌면 **꼬리표만 다른 조각**으로 채운다 —
        // 지연은 토큰 수가 정하므로 길이를 비슷하게 유지한다.
        var frs = NeighborCorpus.fragments()
        let base = frs
        var n = 0
        while frs.count < 50 {
            let src = base[n % base.count]
            n += 1
            frs.append(Fragment(id: "pad-\(n)", title: src.title + " (\(n)번째 판)",
                                body: src.body + "\n덧붙임 \(n): 그때 남긴 메모를 다시 읽었다.",
                                questionIds: [], createdAt: src.createdAt, updatedAt: src.updatedAt))
        }

        let cold = try indexer.reindex(fragments: frs)
        let warm = try indexer.reindex(fragments: frs)
        var edited = frs
        edited[0].body += " 한 줄 더 적었다."
        let single = try indexer.reindex(fragments: edited)

        print(String(format: """

            ── 볼트 열기 색인 지연 (`실측`) — 조각 %d장 ─────────────────
              콜드(색인 없음, 전부 계산)   %7.0f ms   (%d건 계산)
              웜  (해시 전부 일치)         %7.0f ms   (%d건 재사용, 계산 0)
              한 장 고쳤을 때              %7.0f ms   (%d건 계산)
              ⚠ 앱에서는 이게 **주 스레드 밖**에서 돈다 — 창은 이만큼 안 기다린다
            ────────────────────────────────────────────────────────

            """, frs.count,
            cold.elapsed * 1000, cold.embedded,
            warm.elapsed * 1000, warm.reused,
            single.elapsed * 1000, single.embedded))

        XCTAssertEqual(warm.embedded, 0)
        // 상한은 안 건다 — 기계마다 다르다. **터무니없으면** 잡는다
        XCTAssertLessThan(warm.elapsed, 5.0, "재계산이 0인데 5초가 넘는다 — 어딘가가 다시 돌고 있다")
    }

    // MARK: - 08 ★ 질문의 물음꼴과 해시 (모델 없이 돈다)

    /// #34. **화면의 `qforms` 와 같은 규칙인가** — 갈리면 브라우저에서 걸리던 말투가
    /// 앱에선 안 걸리는데 아무것도 안 터진다.
    func test_08_questionFormsAndHash() throws {
        let qs = NeighborCorpus.questions()
        XCTAssertGreaterThanOrEqual(qs.count, Self.minQuestions,
            "질문 말뭉치가 하한 아래다 — 질문을 지워서 초록을 만들지 마라")
        let formCount = qs.reduce(0) { $0 + ContentIndexer.questionText($1).count }
        XCTAssertGreaterThanOrEqual(formCount, Self.minQuestionForms,
            "물음꼴이 하한 아래다 — 변형이 통째로 빠져도 안 빨개지는 자리다")
        XCTAssertTrue(qs.contains { ($0.variants ?? []).isEmpty },
            "변형 없는 질문이 하나도 없다 — `variants == nil` 갈래가 안 돈다")
        XCTAssertTrue(qs.contains { ($0.variants ?? []).count >= 2 },
            "변형이 여럿인 질문이 없다 — 순서 규약이 안 돈다")

        // ① 자기 글자가 먼저, 변형이 **적힌 순서 그대로** 뒤에
        let q = Question(id: "q", text: " 강점이 무엇인가요 ",
                         variants: ["잘하는 것은", "  자신 있는 일은  "])
        XCTAssertEqual(ContentIndexer.questionText(q),
                       ["강점이 무엇인가요", "잘하는 것은", "자신 있는 일은"],
                       "물음꼴의 순서/공백 다듬기가 화면(`qforms`)과 다르다")

        // ② 빈 변형은 빠진다. **자리를 남기지 않는다** — 남기면 빈 글자를 임베딩하고,
        //    빈 글자끼리는 서로 전부 쌍둥이가 된다
        var blanks = q
        blanks.variants = ["", "   ", "\n\t", "쓸모 있는 변형"]
        XCTAssertEqual(ContentIndexer.questionText(blanks),
                       ["강점이 무엇인가요", "쓸모 있는 변형"])

        // ③ 글자가 하나도 안 남는 질문 — 색인에서 통째로 빠져야 한다
        XCTAssertEqual(ContentIndexer.questionText(
            Question(id: "q", text: "   ", variants: ["  "])), [])
        XCTAssertEqual(ContentIndexer.questionText(Question(id: "q", text: "  ", variants: ["살아남는다"])),
                       ["살아남는다"], "빈 text 만 빼고 변형은 살려야 한다")

        // ④ ★ 해시 — text 든 변형이든 **하나만 바뀌어도** 갈린다
        let base = ContentIndexer.questionHash(q)
        XCTAssertTrue(base.hasPrefix("sha256:"), "해시 모양이 조각과 다르다: \(base)")
        XCTAssertEqual(base.count, "sha256:".count + 64)

        var textEdited = q; textEdited.text = "강점이 뭐라고 생각하나요"
        XCTAssertNotEqual(ContentIndexer.questionHash(textEdited), base, "text 를 고쳤는데 해시가 같다")

        var variantEdited = q; variantEdited.variants = ["잘하는 것은", "자신 있는 일은 뭔가요"]
        XCTAssertNotEqual(ContentIndexer.questionHash(variantEdited), base,
                          "변형을 고쳤는데 해시가 같다 — 증분이 낡은 벡터를 붙든다")

        var variantAdded = q; variantAdded.variants = (q.variants ?? []) + ["하나 더"]
        XCTAssertNotEqual(ContentIndexer.questionHash(variantAdded), base, "변형을 더했는데 해시가 같다")

        var variantRemoved = q; variantRemoved.variants = ["잘하는 것은"]
        XCTAssertNotEqual(ContentIndexer.questionHash(variantRemoved), base, "변형을 뺐는데 해시가 같다")

        var reordered = q; reordered.variants = ["자신 있는 일은", "잘하는 것은"]
        XCTAssertNotEqual(ContentIndexer.questionHash(reordered), base,
                          "변형 순서가 바뀌었는데 해시가 같다 — 벡터 자리와 글자가 어긋난다")

        // ⑤ 공백만 다듬어진 것·색인에 안 드는 필드는 **해시를 안 흔든다**
        var respaced = q
        respaced.text = "강점이 무엇인가요"
        respaced.variants = ["  잘하는 것은  ", "자신 있는 일은"]
        XCTAssertEqual(ContentIndexer.questionHash(respaced), base, "공백만 다른데 재계산이 헛돈다")
        var flagged = q; flagged.fromInterview = true
        XCTAssertEqual(ContentIndexer.questionHash(flagged), base,
                       "`fromInterview` 만 바뀌었는데 384차를 다시 계산한다")

        // 빈 질문의 해시는 **빈 글자의 해시**다 — 색인에 안 들어가므로 부딪칠 일이 없다
        XCTAssertEqual(ContentIndexer.questionHash(Question(id: "q", text: " ")),
                       ContentIndexer.hash(""))
        print("물음꼴 OK — 질문 \(qs.count)개 · 물음꼴 \(formCount)개")
    }

    // MARK: - 09 ★ 질문 벡터가 파일에 앉고, 증분이 돈다

    func test_09_questionVectorsAreStoredIncrementally() throws {
        guard let indexer = IndexTestSupport.indexerOrAnnounceMissing(sidecarURL: sidecar) else { return }
        let frs = NeighborCorpus.fragments()
        let qs = NeighborCorpus.questions()
        let store = ContentIndexStore(sidecarURL: sidecar)
        let model = ContentIndexStore.ModelIdentity(indexer.embedder.manifest)

        // ── 콜드 ──
        let cold = try indexer.reindex(fragments: frs, questions: qs)
        XCTAssertEqual(cold.questionsEmbedded, qs.count, "첫 색인에서 질문을 다 안 계산했다")
        XCTAssertEqual(cold.questionsReused, 0)
        XCTAssertEqual(Set(cold.passageVectors.keys), Set(frs.map(\.id)),
                       "보고가 파일별 passage 벡터를 안 들고 나온다 — 화면에 넘길 것이다")
        XCTAssertEqual(cold.passageVectors.values.reduce(0) { $0 + $1.count }, cold.embedded,
                       "보고의 passage 벡터 수가 실제 모델 호출 수와 다르다")
        XCTAssertEqual(cold.questionVectors.count, qs.count, "보고가 질문 벡터를 안 들고 나온다")
        print("콜드(질문 포함) — " + cold.summary)

        // ── 파일이 성한가 ──
        let stored = try XCTUnwrap(store.loadQuestions(for: model), "질문 축을 못 읽었다")
        XCTAssertEqual(Set(stored.keys), Set(qs.map(\.id)), "파일의 질문 id 가 문서와 다르다")
        for q in qs {
            let forms = ContentIndexer.questionText(q)
            let e = try XCTUnwrap(stored[q.id])
            XCTAssertTrue(e.hash.hasPrefix("sha256:"), "\(q.id) 해시 모양이 다르다")
            XCTAssertEqual(e.hash, ContentIndexer.questionHash(q))
            XCTAssertEqual(e.vectors.count, forms.count,
                           "\(q.id) 의 벡터 수가 물음꼴 수와 다르다 — 변형 하나가 조용히 빠졌다")
            let fromReport = try XCTUnwrap(cold.questionVectors[q.id])
            XCTAssertEqual(fromReport.count, forms.count)
            for (i, text) in e.vectors.enumerated() {
                let v = try XCTUnwrap(
                    ContentIndexStore.decode(vector: text, dimensions: model.dimensions),
                    "\(q.id)[\(i)] 벡터를 못 푼다")
                // 왕복이 **비트 단위로** 같나 — 보고로 넘긴 것과 파일에 앉은 것이 같아야 한다
                XCTAssertEqual(v, fromReport[i], "\(q.id)[\(i)] 파일과 보고의 벡터가 다르다")
                XCTAssertEqual(Double(TextEmbedder.cosine(v, v)), 1.0, accuracy: 1e-3,
                               "\(q.id)[\(i)] 벡터가 정규화 안 됐다")
            }
        }
        XCTAssertTrue(store.describeVectors().contains("질문 \(qs.count)건"),
                      "한 줄 진단이 질문 수를 안 센다: \(store.describeVectors())")

        // ── 웜: 그대로 다시 → 모델을 한 번도 안 부른다 ──
        let warm = try indexer.reindex(fragments: frs, questions: qs)
        XCTAssertEqual(warm.questionsEmbedded, 0, "물음꼴이 그대로인데 다시 계산했다 — 질문 증분이 죽었다")
        XCTAssertEqual(warm.questionsReused, qs.count)
        XCTAssertEqual(warm.embedded, 0, "질문을 같이 넣었다고 조각까지 다시 돌았다")
        XCTAssertEqual(warm.questionVectors.count, qs.count, "재사용한 것도 보고에 들고 나와야 한다")
        for q in qs {
            XCTAssertEqual(warm.questionVectors[q.id], cold.questionVectors[q.id],
                           "\(q.id) 재사용한 벡터가 처음 것과 다르다")
        }
        print("웜(질문 포함)   — " + warm.summary)

        // ── text 한 줄만 고치면 그 질문 하나만 ──
        var edited = qs
        edited[0].text += " 구체적으로요."
        let byText = try indexer.reindex(fragments: frs, questions: edited)
        XCTAssertEqual(byText.questionsEmbedded, 1, "text 를 고쳤는데 \(byText.questionsEmbedded)개를 계산했다")
        XCTAssertEqual(byText.questionsReused, qs.count - 1)
        XCTAssertEqual(byText.embedded, 0, "질문만 고쳤는데 조각이 다시 돌았다")

        // ── ★ 변형 하나만 고쳐도 다시 계산한다 ──
        var vEdited = edited
        let target = try XCTUnwrap(vEdited.firstIndex { ($0.variants ?? []).count >= 2 })
        vEdited[target].variants?[1] = "그 일을 다시 한다면 어떻게 하시겠어요"
        let byVariant = try indexer.reindex(fragments: frs, questions: vEdited)
        XCTAssertEqual(byVariant.questionsEmbedded, 1,
                       "변형만 고쳤는데 \(byVariant.questionsEmbedded)개를 계산했다 — 해시가 변형을 안 본다")
        XCTAssertEqual(byVariant.questionsReused, qs.count - 1)

        // ── 변형을 **더하면** 벡터도 는다 ──
        var grown = vEdited
        grown[target].variants = (grown[target].variants ?? []) + ["그때 무엇을 배우셨나요"]
        let after = try indexer.reindex(fragments: frs, questions: grown)
        XCTAssertEqual(after.questionsEmbedded, 1)
        XCTAssertEqual(after.questionVectors[grown[target].id]?.count,
                       ContentIndexer.questionText(grown[target]).count,
                       "변형을 더했는데 벡터가 안 늘었다")

        // ── 사라진 질문은 벡터도 걷힌다 ──
        let gone = grown[0].id
        let shrunk = try indexer.reindex(fragments: frs, questions: Array(grown.dropFirst()))
        XCTAssertEqual(shrunk.questionsEmbedded, 0)
        XCTAssertNil(shrunk.questionVectors[gone], "지운 질문이 보고에 남아 있다")
        let afterDrop = try XCTUnwrap(store.loadQuestions(for: model))
        XCTAssertNil(afterDrop[gone], "지운 질문의 벡터가 파일에 남았다")
        XCTAssertEqual(afterDrop.count, qs.count - 1)

        // ── 질문이 0개면 **키를 아예 안 쓴다** (「없다」와 「비었다」를 안 섞는다) ──
        let none = try indexer.reindex(fragments: frs, questions: [])
        XCTAssertEqual(none.questionVectors.count, 0)
        XCTAssertEqual(store.loadQuestions(for: model), [:],
                       "질문이 0개인데 「못 읽음」이 됐다 — 빈 것과 없는 것을 섞었다")
        let raw = try XCTUnwrap(
            String(data: try Data(contentsOf: store.embeddingsURL), encoding: .utf8))
        XCTAssertFalse(raw.contains("\"questions\""),
                       "질문이 0개인데 questions 키가 남았다 — 빈 축이 있는 축처럼 보인다")

        // 옛 입구(#32)는 그대로 돈다 — 다만 질문 축을 **안 남긴다**
        let legacy = try indexer.reindex(fragments: frs)
        XCTAssertEqual(legacy.total, frs.count)
        XCTAssertEqual(legacy.questionVectors.count, 0)
    }

    // MARK: - 10 ★★ 양성 대조 — 질문은 `query:` 로 들어갔나 (정관 6조)

    /// #34 에서 **조용히 틀려지는 단 하나의 자리.** `embed(passage:)` 로 바꿔도 컴파일되고,
    /// 파일도 성하고, 개수도 맞고, 벡터도 정규화돼 있다 — **점수만 틀려진다.**
    /// 그래서 같은 글자를 두 규약으로 직접 넣어보고, 저장된 것이 **어느 쪽인지 짚는다.**
    ///
    /// 왜 `query:` 인가: 개념 매개는 **물음 대 물음**이라 대칭 과제이고, 모델 카드
    /// (dragonkue/multilingual-e5-small-ko-v2) §FAQ 가 대칭 과제는 양쪽 다 `query: ` 라고 못 박는다.
    func test_10_questionVectorsUseTheQueryPrefix() throws {
        guard let indexer = IndexTestSupport.indexerOrAnnounceMissing(sidecarURL: sidecar) else { return }
        let qs = NeighborCorpus.questions()
        let store = ContentIndexStore(sidecarURL: sidecar)
        let model = ContentIndexStore.ModelIdentity(indexer.embedder.manifest)

        _ = try indexer.reindex(fragments: Array(NeighborCorpus.fragments().prefix(4)), questions: qs)
        let stored = try XCTUnwrap(store.loadQuestions(for: model))

        // 프리픽스 둘이 실제로 다른가 — **양성 대조의 대조군이 진짜인지 먼저 본다**
        XCTAssertNotEqual(indexer.embedder.manifest.queryPrefix,
                          indexer.embedder.manifest.passagePrefix,
                          "두 프리픽스가 같다 — 이 시험은 아무것도 못 가른다")
        XCTAssertEqual(model.queryPrefix, indexer.embedder.manifest.queryPrefix,
                       "파일에 적힌 queryPrefix 가 모델이 쓰는 것과 다르다")

        var worstToQuery: Float = 0
        var closestToPassage: Float = .greatestFiniteMagnitude
        var checked = 0

        for q in qs {
            let forms = ContentIndexer.questionText(q)
            let e = try XCTUnwrap(stored[q.id])
            for (i, form) in forms.enumerated() {
                let got = try XCTUnwrap(
                    ContentIndexStore.decode(vector: e.vectors[i], dimensions: model.dimensions))
                let asQuery = try indexer.embedder.embed(query: form)
                let asPassage = try indexer.embedder.embed(passage: form)

                let dq = Self.maxAbsDiff(got, asQuery)
                let dp = Self.maxAbsDiff(got, asPassage)
                worstToQuery = max(worstToQuery, dq)
                closestToPassage = min(closestToPassage, dp)
                checked += 1

                XCTAssertLessThanOrEqual(Double(dq), Self.vectorTolerance, """
                    \(q.id)[\(i)] 저장된 벡터가 `embed(query:)` 것과 다르다 (성분 최대차 \(dq)).
                    질문은 `query: ` 로 들어가야 한다 — 물음 대 물음은 대칭 과제다
                    (모델 카드 §FAQ). 여기가 갈리면 아무것도 안 터지고 점수만 틀려진다.
                    """)
                XCTAssertGreaterThan(Double(dp), Self.vectorTolerance * 10, """
                    \(q.id)[\(i)] 저장된 벡터가 `embed(passage:)` 것과도 구분이 안 된다
                    (성분 최대차 \(dp)) — 이 시험이 두 규약을 못 가른다.
                    """)
            }
        }
        XCTAssertGreaterThanOrEqual(checked, Self.minQuestionForms, "물음꼴을 다 안 쟀다")

        print(String(format: """

            ── 질문 프리픽스 양성 대조 (`실측`) — 물음꼴 %d개 ──────────────
              저장된 것 ↔ embed(query:)    성분 최대차 %.2e   (허용 %.0e)
              저장된 것 ↔ embed(passage:)  성분 최소차 %.2e   ← 이만큼 벌어져야 갈린다
              queryPrefix "%@" · passagePrefix "%@"
            ────────────────────────────────────────────────────────

            """, checked, Double(worstToQuery), Self.vectorTolerance, Double(closestToPassage),
            indexer.embedder.manifest.queryPrefix as NSString,
            indexer.embedder.manifest.passagePrefix as NSString))
    }

    // MARK: - 11 ★ 질문이 **뒤늦게** 와도 굽는다 — `실측 2026-08-31` 사고의 자물쇠

    /// ## 무엇이 있었나
    ///
    /// 볼트를 밖에서 갈면서 `.clonie/document.json` 이 사라졌다. 기동 색인 패스는 남은 조각
    /// 6장만 들고 돌았고(질문 0개), `embeddings.json` 은 **조각만 있고 질문 축이 아예 없는**
    /// 모양으로 앉았다 — `실측`: `entries` 6건 · `questions` 키 없음. 화면이 표준 질문을
    /// 다시 앉혔지만 저장이 안 나서 그 다음 색인 패스에도 질문이 0개였고, 구멍 판정이
    /// 질문마다 「못 잼」으로 물러섰다.
    ///
    /// 뿌리는 화면 쪽(`seedNeedsSave`, `tests/seed.test.mjs`)이었고 **여기는 그 뒤 반쪽**이다:
    /// 질문이 뒤늦게 문서에 앉았을 때 **질문 축이 없는 파일 위에서** 색인 패스가 실제로 굽는가.
    /// 안 구우면(예: 질문 축 없음을 「전부 재사용」으로 읽으면) 아무것도 안 터지고 화면만
    /// 영영 물러선다.
    func test_11_questionsArrivingLaterAreBakedOntoAQuestionlessIndex() throws {
        guard let indexer = IndexTestSupport.indexerOrAnnounceMissing(sidecarURL: sidecar) else { return }
        let frs = Array(NeighborCorpus.fragments().prefix(4))
        let qs = NeighborCorpus.questions()
        let store = ContentIndexStore(sidecarURL: sidecar)
        let model = ContentIndexStore.ModelIdentity(indexer.embedder.manifest)

        // ── ① 사고 당시의 파일을 그대로 만든다: 조각만 있고 질문 축이 없다 ──
        let questionless = try indexer.reindex(fragments: frs, questions: [])
        XCTAssertEqual(questionless.total, frs.count)
        XCTAssertEqual(questionless.questionVectors.count, 0)
        let raw = try XCTUnwrap(
            String(data: try Data(contentsOf: store.embeddingsURL), encoding: .utf8))
        XCTAssertFalse(raw.contains("\"questions\""),
                       "이 시험의 전제가 안 섰다 — 질문 축이 없는 파일을 만들려던 것이다")

        // ── ② 질문이 뒤늦게 앉는다 (document.json 이 다시 쓰인 순간) ──
        let recovered = try indexer.reindex(fragments: frs, questions: qs)
        XCTAssertEqual(recovered.questionsEmbedded, qs.count, """
            질문 축이 없는 파일 위에서 질문을 \(recovered.questionsEmbedded)개만 구웠다 —
            벡터 없는 질문은 **전부** 구워야 한다. 여기가 죽으면 구멍 판정이 영영 「못 잼」이다.
            """)
        XCTAssertEqual(recovered.questionsReused, 0, "없던 벡터를 재사용했다고 셌다")
        XCTAssertEqual(recovered.embedded, 0,
                       "질문이 늦게 왔다고 조각까지 다시 돌았다 — 증분이 축을 섞는다")
        XCTAssertEqual(recovered.questionVectors.count, qs.count,
                       "보고가 질문 벡터를 안 들고 나온다 — 화면(`receiveVectors`)이 이걸 먹는다")

        // ── ③ 디스크에도 앉았나 — 화면이 다음 기동에 이걸 읽는다 ──
        let stored = try XCTUnwrap(store.loadQuestions(for: model), "질문 축을 못 읽었다")
        XCTAssertEqual(Set(stored.keys), Set(qs.map(\.id)))
        XCTAssertTrue(store.describeVectors().contains("질문 \(qs.count)건"),
                      "한 줄 진단: \(store.describeVectors())")
        print("뒤늦은 질문 회복 — " + recovered.summary)
    }

    /// `tests/fixtures/embedding_reference.json` 의 `embedding_component_abs` 와 **같은 값**이다.
    /// 근거는 그 파일의 `why` 가 든다 — 여기서 다시 고르지 않는다.
    static let vectorTolerance = 1e-3

    static func maxAbsDiff(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return .greatestFiniteMagnitude }
        var m: Float = 0
        for i in 0..<a.count { m = max(m, abs(a[i] - b[i])) }
        return m
    }
}
