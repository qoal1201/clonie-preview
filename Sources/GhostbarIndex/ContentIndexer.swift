import CryptoKit
import Foundation
import GhostbarCore
import GhostbarEmbedding

/// ★ **내용 그래프가 자라는 자리** — ADR 0003 §3-① 집행 (#32).
///
/// 조각이 저장/변경될 때마다 제목+본문을 임베딩해 사이드카에 쌓고, 그 벡터로 **유사 조각을
/// 자동 상호참조**한다. 사람이 아무것도 안 눌러도 자란다는 것이 "전자동"의 뜻이다.
///
/// ```swift
/// switch ContentIndexer.open(sidecarURL: store.sidecarURL) {
/// case .unavailable(let status): print(status.explanation)   // 모델 없음 — 앱은 그대로 돈다
/// case .ready(let indexer):
///     let report = try indexer.reindex(fragments: doc.fragments, questions: doc.questions)
///     print(report.summary)
/// }
/// ```
///
/// ## ★ 축이 둘이다 — 조각과 질문 (#34)
///
/// | 축 | 무엇을 넣나 | 과제 | 그래서 넣는 법 |
/// |---|---|---|---|
/// | **조각** | 제목+본문 | **비대칭** (찾는 쪽 ≠ 찾히는 쪽) | `embed(passage:)` |
/// | **질문** | 예상 질문의 물음꼴 | **대칭** (물음 대 물음) | `embed(query:)` |
///
/// 그래서 이 타입은 조각을 `passage:` 로, 질문을 **`query:` 로** 넣는다. 근거 = 모델 카드
/// (dragonkue/multilingual-e5-small-ko-v2) §FAQ — 대칭 과제는 **양쪽 다 `query: `** 를 쓴다.
///
/// ⚠ 여기서 `passage:` 를 쓰면 **아무것도 안 터지고 점수만 조용히 틀려진다.**
/// 그래서 시험이 저장된 질문 벡터를 `embed(query:)` 것과 대조한다(양성 대조, 정관 6조).
///
/// ⚠ **두 축을 쓰는 법이 #53(ADR 0005)에서 바뀌었다.** 면접 중 검색은 이제
/// **조각 축 하나**로만 점수를 낸다(`max(내용 직접, 개념 매개)` 가 아니다). 질문 축은
/// 준비도·연습이 「그 질문에 내용으로 가장 가까운 조각」을 잴 때만 쓴다.
/// ⚠ 그 자리는 **물음꼴 첫 개만** 읽는다 — 변형 벡터는 지금 아무도 안 읽는다.
/// 안 지우는 이유는 ADR 0005 「다시 열 조건」이 이 축을 되살릴 수 있어서다.
///
/// ⚠ **코사인·순위·색은 여기가 안 낸다 — 화면(JS)이 낸다.** 이 타입의 몫은 셋뿐이다:
/// 계산 · 증분 저장 · 돌려주기(``Report/vectors``·``Report/questionVectors``).
///
/// ## 증분 — 해시가 같으면 모델을 안 부른다
///
/// 조각마다 **임베딩에 실제로 들어간 글자**의 SHA-256 을 같이 저장한다. 다음 번에 그 해시가
/// 같으면 벡터를 그대로 재사용한다. 그래서 볼트를 열 때 도는 것은 **없는 것과 낡은 것뿐**이다.
/// ⚠ `updatedAt` 으로 안 가른다 — 파일을 만지기만 해도 시각이 바뀌는데 알맹이는 같다.
///
/// ## 모델이 없으면 — 조용히 죽지 않고, 앱도 안 죽는다
///
/// `EmbeddingModelStore` 의 판정을 그대로 물려받는다(#31): 여기서 하는 일은 **왜 못 하는지를
/// 말로 들고 나오는 것**뿐이고, 그 위에서 앱은 색인 없이 그대로 돈다. 빈 벡터나 0 점수를
/// 지어내지 않는다 — 그러면 검색이 「그냥 안 맞는 제품」이 된다.
///
/// ## 유저 md 에는 아무것도 안 쓴다
///
/// 이 타입이 여는 경로는 `.clonie/` 아래 둘뿐이다. 승인 경계는 #33 몫이고, 그전까지
/// 제안이 유저 파일로 나가는 길은 **여기 없다.**
public final class ContentIndexer {

    // MARK: - ★ 문턱 — `실측 2026-08-30`, 근거 분포가 아래 표다

    /// 한 조각에 매달 이웃 수. **순위로 자른다.**
    ///
    /// ⚠ 절대값으로 「관련 있음」을 판정하지 않는 이유 = `memory/feedback-measure-threshold-overlap-first`:
    /// 이 레포에서 문턱 셋 중 둘이 겹쳤고, 겹치는데 숫자를 고르면 **고른 자리가 근거처럼 보인다.**
    public static let topK = 5

    /// ★ **근거 분포** — `실측 2026-08-30`, 조각 25장 · 300쌍 · `multilingual-e5-small-ko-v2`.
    /// 재는 코드 = `tests/GhostbarIndexTests` 의 `test_04_thresholdSeparatesTheTwoGroups`
    /// (**아래 두 상수를 그 시험이 다시 재서 검증한다** — 모델을 바꾸면 여기가 먼저 빨개진다).
    ///
    /// ```
    ///   같은 사연을 다시 쓴 쌍 (6쌍)    최소 0.717 · 중앙 0.813 · 최대 0.835
    ///   서로 다른 조각        (294쌍)   중앙 0.561 · 90분위 0.620 · 최대 0.680
    ///   간격 (정답최소 − 오답최대)      +0.037  → 갈린다 (겹치지는 않는다)
    ///   가장 높은 오답 쌍  갈등 이야기 ↔ 마감 이야기 0.680
    ///   가장 낮은 정답 쌍  같은 실패담을 다르게 쓴 것 0.717
    /// ```
    ///
    /// ⚠ **e5 는 아무 상관 없는 한국어 두 줄도 0.55 를 준다.** 0.62 를 「많이 닮았다」로
    /// 읽으면 안 된다 — 이 모델의 0 점은 0 이 아니라 **0.55 근처**다.
    ///
    /// ⚠ **간격이 0.037 밖에 안 된다.** 갈리기는 갈리지만 말뭉치 하나 · 정답 6쌍으로 잰
    /// 것이고, 그래서 아래 둘 중 어느 것도 **되돌릴 수 없는 일을 안 한다**
    /// (`memory/feedback-measure-threshold-overlap-first`).

    /// 이웃으로 **적기라도 할** 최소 점수. 판정이 아니라 **바닥**이다 —
    /// 오답 90분위(0.620)에 둔다. 이 아래는 관계보다 우연이 많다.
    /// **무엇이 이웃이 되는지는 이 값이 아니라 ``topK`` 순위가 정한다.**
    public static let linkFloor: Double = 0.62

    /// **「이미 비슷한 걸 썼다」 알림이 뜨는 자리.** 위 두 무리 사이 (0.680 < 0.70 < 0.717).
    ///
    /// ⚠ **이 값은 결과를 안 정한다.** 뜨는 것은 한 줄짜리 알림이고, 지울지 합칠지는 사람이
    /// 정한다 — 틀렸을 때의 대가가 「한 줄 읽고 무시」가 되게 두는 것이 이 문턱의 설계다.
    /// 간격이 좁으니 **문턱을 올려 놓치는 쪽보다 낮춰 한 번 더 묻는 쪽**에 가깝게 뒀다.
    public static let nearDuplicate: Double = 0.70

    // MARK: - 열기

    public enum Availability {
        case ready(ContentIndexer)
        /// 왜 못 하는지. `explanation` 이 사람이 읽고 다음에 뭘 할지 아는 한 덩어리다.
        case unavailable(EmbeddingModelStore.Status)
    }

    /// 모델이 준비됐을 때만 색인기를 만든다.
    ///
    /// ⚠ **반쯤 살아 있는 색인기를 안 만든다** — `TextEmbedder` 와 같은 규칙이다.
    /// 살아 있으면 부르는 쪽이 점수를 믿어도 된다.
    public static func open(sidecarURL: URL,
                            environment: [String: String] = ProcessInfo.processInfo.environment,
                            fileManager: FileManager = .default) -> Availability {
        let status = EmbeddingModelStore.status(environment: environment)
        guard let manifest = status.manifest else { return .unavailable(status) }
        do {
            let embedder = try TextEmbedder(manifest: manifest)
            return .ready(ContentIndexer(sidecarURL: sidecarURL, embedder: embedder,
                                         fileManager: fileManager))
        } catch {
            // 있는데 못 연다 — 「없음」과 섞지 않는다. 같은 낱말표로 낸다.
            return .unavailable(.unreadable(directory: manifest.directory, reason: "\(error)"))
        }
    }

    public let store: ContentIndexStore
    public let embedder: TextEmbedder
    private let model: ContentIndexStore.ModelIdentity
    private let passageMaxTokens: Int
    private let passageOverlapTokens: Int

    public init(sidecarURL: URL, embedder: TextEmbedder, fileManager: FileManager = .default,
                passageMaxTokens: Int? = nil, passageOverlapTokens: Int = 64) {
        self.store = ContentIndexStore(sidecarURL: sidecarURL, fileManager: fileManager)
        self.embedder = embedder
        self.model = ContentIndexStore.ModelIdentity(embedder.manifest)
        self.passageMaxTokens = min(embedder.manifest.maxSequenceLength,
                                    max(1, passageMaxTokens ?? embedder.manifest.maxSequenceLength))
        self.passageOverlapTokens = max(0, passageOverlapTokens)
    }

    // MARK: - 색인에 들어가는 글자

    /// 장문 한 파일에서 만든 passage 하나. `startUTF16`/`endUTF16`은 `Fragment.body` 안의
    /// 위치라 화면·MCP가 원문을 다시 찾을 수 있고, `hash`는 실제 모델 입력(`text`)을 가리킨다.
    public struct Passage: Codable, Equatable, Sendable {
        public var id: String
        public var fragmentID: String
        public var startUTF16: Int
        public var endUTF16: Int
        /// 제목과 현재 Markdown heading 문맥을 포함한 실제 임베딩 입력(프리픽스 제외).
        public var text: String
        /// 본문에서 온 원문 부분. 검색 결과의 snippet/source로 쓴다.
        public var sourceText: String
        public var hash: String

        public init(id: String, fragmentID: String, startUTF16: Int, endUTF16: Int,
                    text: String, sourceText: String, hash: String) {
            self.id = id
            self.fragmentID = fragmentID
            self.startUTF16 = startUTF16
            self.endUTF16 = endUTF16
            self.text = text
            self.sourceText = sourceText
            self.hash = hash
        }
    }

    /// passage의 출처와 실제 벡터를 같이 나르는 모양. 파일별 점수는 이 벡터들 중 질의와
    /// 가장 가까운 하나(max passage cosine)로 계산한다.
    public struct PassageVector: Equatable, Sendable {
        public var passage: Passage
        public var vector: [Float]

        public init(passage: Passage, vector: [Float]) {
            self.passage = passage
            self.vector = vector
        }
    }

    /// 파일별 최고 passage 검색 결과. `passage`가 그대로 source/snippet의 근거다.
    public struct PassageHit: Equatable, Sendable {
        public var fragmentID: String
        public var passage: Passage
        public var score: Double

        public init(fragmentID: String, passage: Passage, score: Double) {
            self.fragmentID = fragmentID
            self.passage = passage
            self.score = score
        }
    }

    /// 문서를 heading 단위로 보존하면서 입력 길이 안에서 겹치는 passage를 만든다.
    ///
    /// `tokenCount`는 **프리픽스를 붙인 뒤의 실제 모델 토큰 수**를 세는 함수여야 한다.
    /// 테스트는 간단한 계수기를 넣고, `reindex`는 `UnigramTokenizer`와 manifest 한도를 쓴다.
    public static func passages(for fragment: Fragment, maxTokens: Int,
                                overlapTokens: Int = 64,
                                tokenCount: (String) -> Int) -> [Passage] {
        let title = fragment.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = fragment.body
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            guard !title.isEmpty else { return [] }
            let text = fittingText(context: "", source: title, maxTokens: maxTokens,
                                   tokenCount: tokenCount)
            guard !text.isEmpty else { return [] }
            return [Passage(id: fragment.id + "#0-0", fragmentID: fragment.id,
                            startUTF16: 0, endUTF16: 0, text: text, sourceText: title,
                            hash: hash(text))]
        }

        let sections = markdownSections(in: body)
        var result: [Passage] = []
        for section in sections {
            let rawContext = [title, section.heading].filter { !$0.isEmpty }.joined(separator: "\n")
            // 제목·heading은 위치 문맥이지 본문보다 우선하는 입력이 아니다. 그것만으로 한도를
            // 넘으면 본문을 한 글자씩 쪼개며 문맥을 매번 걷게 된다. 문맥에는 입력의 1/4,
            // 최대 64토큰만 주고 나머지는 실제 본문 passage에 남긴다.
            let context = boundedContext(rawContext, maxTokens: maxTokens, tokenCount: tokenCount)
            var start = section.range.lowerBound
            while start < section.range.upperBound {
                start = skipLeadingWhitespace(in: body, from: start, upperBound: section.range.upperBound)
                guard start < section.range.upperBound else { break }
                let end = fittingEnd(in: body, start: start, upperBound: section.range.upperBound,
                                     context: context, maxTokens: maxTokens, tokenCount: tokenCount)
                guard end > start else { break }
                var sourceEnd = end
                while sourceEnd > start, body[body.index(before: sourceEnd)].isWhitespace {
                    sourceEnd = body.index(before: sourceEnd)
                }
                let source = String(body[start..<sourceEnd])
                guard !source.isEmpty else { break }
                let text = fittingText(context: context, source: source, maxTokens: maxTokens,
                                       tokenCount: tokenCount)
                guard !text.isEmpty else { break }
                let startUTF16 = body[..<start].utf16.count
                let endUTF16 = body[..<sourceEnd].utf16.count
                result.append(Passage(id: "\(fragment.id)#\(startUTF16)-\(endUTF16)",
                                      fragmentID: fragment.id, startUTF16: startUTF16,
                                      endUTF16: endUTF16, text: text, sourceText: source,
                                      hash: hash(text)))
                guard end < section.range.upperBound else { break }
                let next = overlappingStart(in: body, start: start, end: end, context: context,
                                            overlapTokens: overlapTokens, tokenCount: tokenCount)
                start = next > start ? next : end
            }
        }
        return result
    }

    /// 디스크의 새 passage 벡터 또는 현재 문서에서 즉석 계산한 벡터로 검색한다. 이 함수는
    /// sidecar를 쓰지 않아 MCP의 읽기 경계를 지킨다.
    public func search(query: String, fragments: [Fragment], limit: Int = 5) throws -> [PassageHit] {
        let q = try embedder.embed(query: query)
        let plans = Dictionary(uniqueKeysWithValues: fragments.map { ($0.id, passages(for: $0)) })
        let stored = store.loadPassages(for: model) ?? [:]
        var values: [String: [PassageVector]] = [:]
        for (fragmentID, passages) in plans {
            let byID = Dictionary(uniqueKeysWithValues: (stored[fragmentID] ?? []).map { ($0.id, $0) })
            values[fragmentID] = try passages.map { passage in
                if let old = byID[passage.id], old.hash == passage.hash,
                   let vector = ContentIndexStore.decode(vector: old.vector, dimensions: model.dimensions) {
                    return PassageVector(passage: passage, vector: vector)
                }
                return PassageVector(passage: passage, vector: try embedder.embed(passage: passage.text))
            }
        }
        return Self.rank(queryVector: q, passageVectors: values, limit: limit)
    }

    /// 순수 집계 함수. 호출자는 저장된 passage·즉석 passage 어느 쪽이든 넣을 수 있다.
    public static func rank(queryVector: [Float], passageVectors: [String: [PassageVector]],
                            limit: Int = 5) -> [PassageHit] {
        let hits = passageVectors.compactMap { fragmentID, values -> PassageHit? in
            values.compactMap { value -> PassageHit? in
                let score = Double(TextEmbedder.cosine(queryVector, value.vector))
                guard score.isFinite else { return nil }
                return PassageHit(fragmentID: fragmentID, passage: value.passage, score: score)
            }.max { a, b in
                a.score == b.score ? a.passage.id > b.passage.id : a.score < b.score
            }
        }
        return Array(hits.sorted {
            $0.score == $1.score ? $0.fragmentID < $1.fragmentID : $0.score > $1.score
        }.prefix(max(0, limit)))
    }

    /// 실제 모델의 tokenizer·prefix·한도를 쓰는 인스턴스 입구.
    public func passages(for fragment: Fragment) -> [Passage] {
        Self.passages(for: fragment, maxTokens: passageMaxTokens, overlapTokens: passageOverlapTokens,
                      tokenCount: { [embedder] text in
                          // `encode`는 model maxSequenceLength에서 잘라 실제보다 긴 입력도
                          // 항상 512개처럼 보인다. 경계를 찾을 때는 특수 토큰까지 포함한
                          // **잘리지 않은** 개수를 세야 한다.
                          embedder.tokenizer.pieces(of: embedder.manifest.passagePrefix + text).count + 2
                      })
    }

    private struct MarkdownSection {
        var heading: String
        var range: Range<String.Index>
    }

    /// heading은 다음 heading 전까지의 문맥이다. heading 자체만 있는 문서는 heading을 본문으로
    /// 남겨 잃지 않고, 빈 구역은 만들지 않는다.
    private static func markdownSections(in body: String) -> [MarkdownSection] {
        var headings: [(range: Range<String.Index>, text: String)] = []
        var lineStart = body.startIndex
        while lineStart < body.endIndex {
            let lineEnd = body[lineStart...].firstIndex(of: "\n") ?? body.endIndex
            let line = body[lineStart..<lineEnd]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let heading = markdownHeading(String(trimmed)) {
                headings.append((lineStart..<lineEnd, heading))
            }
            lineStart = lineEnd < body.endIndex ? body.index(after: lineEnd) : body.endIndex
        }
        guard !headings.isEmpty else {
            return [MarkdownSection(heading: "", range: body.startIndex..<body.endIndex)]
        }

        var sections: [MarkdownSection] = []
        let first = headings[0]
        if body.startIndex < first.range.lowerBound {
            sections.append(MarkdownSection(heading: "", range: body.startIndex..<first.range.lowerBound))
        }
        for i in headings.indices {
            let here = headings[i]
            let contentStart = here.range.upperBound < body.endIndex
                ? body.index(after: here.range.upperBound) : body.endIndex
            let contentEnd = i + 1 < headings.count ? headings[i + 1].range.lowerBound : body.endIndex
            if contentStart < contentEnd {
                sections.append(MarkdownSection(heading: here.text, range: contentStart..<contentEnd))
            } else {
                sections.append(MarkdownSection(heading: "", range: here.range))
            }
        }
        return sections
    }

    private static func markdownHeading(_ line: String) -> String? {
        guard line.hasPrefix("#") else { return nil }
        let hashes = line.prefix { $0 == "#" }
        guard hashes.count <= 6 else { return nil }
        let rest = line.dropFirst(hashes.count)
        guard rest.first?.isWhitespace == true else { return nil }
        let text = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func skipLeadingWhitespace(in text: String, from start: String.Index,
                                              upperBound: String.Index) -> String.Index {
        var index = start
        while index < upperBound, text[index].isWhitespace { index = text.index(after: index) }
        return index
    }

    /// 문서 문맥이 본문 입력을 밀어내지 않게 작은 고정 예산 안으로 자른다. 본문 range는
    /// 여기에 의존하지 않으므로 source/snippet 좌표는 그대로다.
    private static func boundedContext(_ context: String, maxTokens: Int,
                                       tokenCount: (String) -> Int) -> String {
        let budget = min(64, maxTokens / 4)
        guard budget > 0, tokenCount(context) > budget else { return budget > 0 ? context : "" }

        var low = 0
        var high = context.count
        while low < high {
            let middle = (low + high + 1) / 2
            let end = context.index(context.startIndex, offsetBy: middle)
            if tokenCount(String(context[..<end])) <= budget { low = middle }
            else { high = middle - 1 }
        }
        return String(context.prefix(low)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// tokenizer offset API가 없으므로, 이분 탐색으로 가장 긴 유효 prefix를 먼저 찾고 그 근처의
    /// paragraph/공백 경계를 고른다. 결과는 항상 `maxTokens` 이하다.
    private static func fittingEnd(in body: String, start: String.Index, upperBound: String.Index,
                                   context: String, maxTokens: Int,
                                   tokenCount: (String) -> Int) -> String.Index {
        // 이미 한 passage에 들어가는 짧은 본문을 뒤의 공백까지 거슬러 올라가 자르면 안 된다.
        // 이 빠른 경로가 없으면 binary search의 `low == 전체 길이` 다음 경계 탐색이 첫 공백을
        // 골라 평범한 짧은 문서를 수백 passage로 쪼갠다.
        if tokenCount(render(context: context, source: String(body[start..<upperBound]))) <= maxTokens {
            return upperBound
        }
        var low = body.distance(from: start, to: start)
        var high = body.distance(from: start, to: upperBound)
        while low < high {
            let middle = (low + high + 1) / 2
            let end = body.index(start, offsetBy: middle)
            let source = String(body[start..<end])
            if tokenCount(render(context: context, source: source)) <= maxTokens { low = middle }
            else { high = middle - 1 }
        }
        guard low > 0 else {
            // 제목/heading이 긴 특수 경우도 한 글자만큼은 진행해 무한 루프를 피한다.
            return body.index(after: start)
        }
        let hardEnd = body.index(start, offsetBy: low)
        var cursor = hardEnd
        let floor = max(0, low - 320)
        while cursor > start, body.distance(from: start, to: cursor) >= floor {
            let before = body.index(before: cursor)
            if body[before].isWhitespace {
                // hardEnd에 가장 가까운 단어/문단 경계 하나만 고른다. 계속 갱신하면 320자
                // 앞의 첫 공백으로 밀려 short passage를 대량 생성한다.
                return cursor
            }
            cursor = before
        }
        return hardEnd
    }

    private static func overlappingStart(in body: String, start: String.Index, end: String.Index,
                                         context: String, overlapTokens: Int,
                                         tokenCount: (String) -> Int) -> String.Index {
        guard overlapTokens > 0 else { return end }
        var candidate = end
        var best = end
        while candidate > start {
            let before = body.index(before: candidate)
            if body[before].isWhitespace {
                let suffix = String(body[before..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                if tokenCount(suffix) <= overlapTokens { best = before }
                else { break }
            }
            candidate = before
        }
        return skipLeadingWhitespace(in: body, from: best, upperBound: end)
    }

    private static func fittingText(context: String, source: String, maxTokens: Int,
                                    tokenCount: (String) -> Int) -> String {
        let full = render(context: context, source: source)
        guard tokenCount(full) > maxTokens else { return full }
        // 아주 긴 제목/heading이어도 input bound를 깨지 않는다. source를 우선해 가장 긴 앞부분의
        // 문맥만 남긴다. 보통 경로에서는 `fittingEnd`이 이 분기에 오기 전에 이미 잘랐다.
        var keptContext = context
        while !keptContext.isEmpty && tokenCount(render(context: keptContext, source: source)) > maxTokens {
            keptContext.removeLast()
        }
        let withContext = render(context: keptContext, source: source)
        if tokenCount(withContext) <= maxTokens { return withContext }
        var end = source.endIndex
        while end > source.startIndex {
            let attempt = String(source[..<end])
            if tokenCount(attempt) <= maxTokens { return attempt }
            end = source.index(before: end)
        }
        return ""
    }

    private static func render(context: String, source: String) -> String {
        guard !context.isEmpty else { return source }
        guard !source.isEmpty else { return context }
        return context + "\n" + source
    }

    /// 임베딩에 실제로 들어가는 문자열. **제목과 본문 둘 다** (ADR 0003 §3-①).
    ///
    /// ⚠ 프리픽스(`passage: `)는 여기 안 붙인다 — 그건 `embed(passage:)` 가 규약대로 붙인다(#31).
    /// 여기 붙이면 두 번 붙는다.
    public static func indexText(_ f: Fragment) -> String {
        let t = f.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = f.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return b }
        if b.isEmpty { return t }
        return t + "\n" + b
    }

    /// 재계산을 안 하는 근거. **글자가 같으면 벡터가 같다**는 것 하나만 걸고 있다.
    public static func hash(_ text: String) -> String {
        "sha256:" + SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// 질문 하나가 임베딩되는 **물음꼴들** — 자기 글자 + 변형들 (#34, #23 갈래 ②).
    ///
    /// ⚠ **짝이던 화면 쪽 규칙(`qforms`)은 #53 이 걷었다** — 화면의 글자 자는 이제 조각의
    /// 제목+본문만 본다. 여기가 남은 이유는 **저장 형식**이라서다: 벡터 자리가
    /// ``ContentIndexStore/QuestionEntry/vectors`` 에 이 순서로 앉고, 지금 읽히는 것은
    /// **첫 개뿐**이다(준비도·연습). 변형을 여기서 빼면 옛 사이드카와 자리가 어긋난다.
    ///
    /// - 빈 `text` 는 뺀다 — 빈 글자를 임베딩하면 서로 전부 쌍둥이가 된다(조각의 `skippedEmpty` 와 같은 이유).
    /// - 변형은 **앞뒤 공백을 털고**, 털어서 비면 뺀다.
    /// - **순서를 지킨다.** ``ContentIndexStore/QuestionEntry/vectors`` 가 이 순서에 앉는다.
    ///
    /// ⚠ 프리픽스(`query: `)는 여기 안 붙인다 — `embed(query:)` 가 규약대로 붙인다(#31).
    public static func questionText(_ q: Question) -> [String] {
        var forms: [String] = []
        let t = q.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { forms.append(t) }
        for v in q.variants ?? [] {
            let s = v.trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { forms.append(s) }
        }
        return forms
    }

    /// 질문 축의 재계산을 안 하는 근거. **물음꼴 전부를 이어서** 잰다 —
    /// 그래서 `text` 를 고쳐도, 변형 하나를 고치거나 더하거나 빼도 해시가 갈린다.
    ///
    /// ⚠ `"\n"` 으로 잇는다: 변형을 나누는 자리가 글자 안에 우연히 생기지 않게.
    public static func questionHash(_ q: Question) -> String {
        hash(questionText(q).joined(separator: "\n"))
    }

    // MARK: - 보고

    public struct DuplicateHit: Equatable, Sendable {
        /// 이번에 새로 들어오거나 바뀐 조각.
        public var id: String
        /// 그것과 아주 가까운, **이미 있던** 조각.
        public var otherID: String
        public var score: Double
    }

    public struct Report: Sendable {
        public var total: Int
        /// 모델을 실제로 부른 횟수.
        public var embedded: Int
        /// 해시가 같아 **안 부른** 횟수. 증분이 도는지 이 수로 잰다.
        public var reused: Int
        /// 사라진 조각의 벡터를 걷어낸 수.
        public var dropped: Int
        /// 제목도 본문도 빈 조각. 임베딩하면 **서로 전부 쌍둥이가 된다** — 안 넣는다.
        public var skippedEmpty: Int
        /// 색인 파일이 없거나 못 써서 처음부터 채웠나. **알림을 띄울지 말지가 여기 걸린다.**
        public var coldBuild: Bool
        public var elapsed: TimeInterval
        public var neighbors: [String: [ContentIndexStore.Neighbor]]
        /// 문턱을 넘은 것만, 점수 내림차순.
        public var duplicates: [DuplicateHit]

        /// 질문의 물음꼴을 실제로 임베딩한 횟수 (#34). **질문 하나가 아니라 「질문 항목」 수**다 —
        /// 변형이 셋이어도 그 질문은 1로 센다(모델은 4번 돌지만, 증분이 사는 단위가 질문이라서).
        public var questionsEmbedded: Int
        /// 해시가 같아 **안 부른** 질문 수.
        public var questionsReused: Int

        /// ★ **화면으로 넘어가는 것** — 조각 id → 벡터 (#34).
        ///
        /// 앱 층이 이걸 그대로 화면에 건넨다. 파일에서 다시 읽어 풀지 않는 이유:
        /// 방금 계산한 것을 부호화했다 되풀면 **한 번 더 도는 일**이고, 그 사이에 파일이
        /// 밖에서 바뀌면 화면이 방금 색인한 것과 다른 것을 본다.
        public var vectors: [String: [Float]]
        /// ★ P3 — 조각 id → 실제 passage들의 출처·벡터. 장문 검색은 이 값으로 파일마다
        /// 최고 passage cosine을 고르고, 결과에는 그 passage의 `sourceText`를 붙인다.
        public var passageVectors: [String: [PassageVector]]
        /// ★ 질문 id → **물음꼴들의 벡터**, ``questionText(_:)`` 와 **같은 순서** (#34).
        public var questionVectors: [String: [[Float]]]

        public var summary: String {
            String(format: "색인 %d건 — 새로 계산 %d · 재사용 %d · 걷어냄 %d · 빈 조각 %d · "
                         + "질문 %d건(새로 %d · 재사용 %d) · %@ %.0fms",
                   total, embedded, reused, dropped, skippedEmpty,
                   questionVectors.count, questionsEmbedded, questionsReused,
                   coldBuild ? "콜드" : "웜", elapsed * 1000)
        }
    }

    // MARK: - 사람이 읽는 한 줄

    /// 중복 알림을 **띠 하나에 들어갈 한 줄**로 만든다 (#32).
    ///
    /// ⚠ 이 함수가 여기 있는 이유는 **`swift test` 가 잴 수 있는 자리**여서다. 앱 층에
    /// 두면 문자열을 잠글 방법이 `.app` 을 띄우는 것밖에 없다.
    ///
    /// 규칙 셋:
    /// - **id 가 아니라 제목으로 부른다.** `f-1750…` 을 보여주면 사람은 그게 뭔지 모른다.
    /// - **여러 건이면 가장 가까운 것 하나만 이름을 대고 나머지는 수로 센다.** 띠는 한 줄이다.
    /// - **명령하지 않는다.** 「합쳐라」가 아니라 「있다」 — 지울지 합칠지는 사람이 정한다
    ///   (문턱 간격이 0.037 뿐이라 이 알림은 **틀릴 수 있다**).
    ///
    /// - Returns: 알릴 것이 없으면 `nil`. **빈 문자열을 안 돌려준다** — 부르는 쪽이
    ///   빈 띠를 띄우게 된다.
    public static func duplicateNotice(_ hits: [DuplicateHit],
                                       fragments: [Fragment]) -> String? {
        guard let top = hits.first else { return nil }
        var titles: [String: String] = [:]
        for f in fragments {
            let t = f.title.trimmingCharacters(in: .whitespacesAndNewlines)
            titles[f.id] = t.isEmpty ? "제목 없는 조각" : t
        }
        let other = titles[top.otherID] ?? "이름을 잃은 조각"
        let percent = Int((top.score * 100).rounded())
        var line = "이미 비슷한 조각이 있다 — 「\(other)」 와 \(percent)% 닮았다"
        // 같은 조각을 가리키는 여러 쌍을 다 부르지 않는다. **몇 건 더 있다**까지만.
        let more = hits.count - 1
        if more > 0 { line += " (그 밖에 \(more)건 더)" }
        return line + ". 겹치면 하나로 합치는 편이 낫다"
    }

    // MARK: - ★ 증분 색인

    /// 질문 없이 조각만. **#32 때의 입구**이고, 지금은 아래 것에 넘긴다.
    ///
    /// ⚠ `questions: []` 는 「질문이 없다」가 아니라 **「이번엔 질문 축을 안 쟀다」**로 읽히면 안 된다 —
    /// 실제로 질문 벡터가 **통째로 걷힌다**(문서에서 사라진 것과 구분하지 않는다).
    /// 앱 층은 ``reindex(fragments:questions:)`` 를 쓴다.
    @discardableResult
    public func reindex(fragments: [Fragment]) throws -> Report {
        try reindex(fragments: fragments, questions: [])
    }

    /// 없는 것과 낡은 것만 채우고, 이웃을 다시 잇고, 사이드카 두 파일을 쓴다.
    ///
    /// **두 축이 같은 규칙으로 증분한다**: 해시가 같고 저장된 벡터가 성하면 모델을 안 부른다.
    /// 사라진 것(조각이든 질문이든)은 벡터도 같이 걷는다.
    @discardableResult
    public func reindex(fragments: [Fragment], questions: [Question]) throws -> Report {
        let t0 = DispatchTime.now().uptimeNanoseconds

        let previous = store.loadPassages(for: model)
        let coldBuild = previous == nil
        let old = previous ?? [:]
        let oldQuestions = store.loadQuestions(for: model) ?? [:]

        var entries: [String: [ContentIndexStore.PassageEntry]] = [:]
        var passageVectors: [String: [PassageVector]] = [:]
        var changed: Set<String> = []
        var embedded = 0, reused = 0, skippedEmpty = 0

        for f in fragments {
            let plans = passages(for: f)
            guard !plans.isEmpty else { skippedEmpty += 1; continue }
            let oldByHash = Dictionary(grouping: old[f.id] ?? [], by: \.hash)
            var currentEntries: [ContentIndexStore.PassageEntry] = []
            var currentVectors: [PassageVector] = []
            var fileChanged = (old[f.id]?.count ?? 0) != plans.count

            for plan in plans {
                // 위치가 밀려도 제목·heading을 포함한 실제 입력이 같으면 같은 벡터를 재사용한다.
                // 반대로 v1은 `loadPassages`에서 이미 끊겨 여기로 올 수 없다.
                if let oldEntry = oldByHash[plan.hash]?.first,
                   let vector = ContentIndexStore.decode(vector: oldEntry.vector,
                                                          dimensions: model.dimensions) {
                    currentEntries.append(.init(id: plan.id, startUTF16: plan.startUTF16,
                                                endUTF16: plan.endUTF16, hash: plan.hash,
                                                vector: oldEntry.vector))
                    currentVectors.append(PassageVector(passage: plan, vector: vector))
                    reused += 1
                } else {
                    let vector = try embedder.embed(passage: plan.text)
                    currentEntries.append(.init(id: plan.id, startUTF16: plan.startUTF16,
                                                endUTF16: plan.endUTF16, hash: plan.hash,
                                                vector: ContentIndexStore.encode(vector: vector)))
                    currentVectors.append(PassageVector(passage: plan, vector: vector))
                    embedded += 1
                    fileChanged = true
                }
            }
            entries[f.id] = currentEntries
            passageVectors[f.id] = currentVectors
            if fileChanged { changed.insert(f.id) }
        }

        // ── 질문 축 (#34) — 같은 증분 규칙, **다른 프리픽스** ──
        var questionEntries: [String: ContentIndexStore.QuestionEntry] = [:]
        var questionVectors: [String: [[Float]]] = [:]
        var questionsEmbedded = 0, questionsReused = 0

        for q in questions {
            let forms = Self.questionText(q)
            // 글자가 하나도 안 남은 질문(빈 text + 빈 변형)은 안 넣는다 — 빈 조각과 같은 이유다.
            guard !forms.isEmpty else { continue }
            let h = Self.questionHash(q)

            // 재사용의 조건이 조각보다 하나 많다: **개수까지 맞아야 한다.**
            // 해시가 같으면 개수도 같아야 정상이지만, 파일이 반쯤 상했을 때 개수만 어긋난
            // 항목을 믿으면 변형 하나가 조용히 사라진 채로 검색이 돈다.
            if let e = oldQuestions[q.id], e.hash == h, e.vectors.count == forms.count {
                let decoded = e.vectors.compactMap {
                    ContentIndexStore.decode(vector: $0, dimensions: model.dimensions)
                }
                if decoded.count == forms.count {
                    questionEntries[q.id] = e
                    questionVectors[q.id] = decoded
                    questionsReused += 1
                    continue
                }
            }

            // ★ `embed(query:)` 다 — `embed(passage:)` 가 아니다.
            //   물음 대 물음은 **대칭** 과제라 양쪽 다 `query: ` 를 쓴다
            //   (모델 카드 dragonkue/multilingual-e5-small-ko-v2 §FAQ).
            //   여기가 갈리면 아무것도 안 터지고 개념 매개 점수만 틀려진다.
            let vs = try forms.map { try embedder.embed(query: $0) }
            questionEntries[q.id] = ContentIndexStore.QuestionEntry(
                hash: h, vectors: vs.map { ContentIndexStore.encode(vector: $0) })
            questionVectors[q.id] = vs
            questionsEmbedded += 1
        }

        // 사라진 조각 — 벡터도 같이 걷는다. **유저 파일은 안 건드린다** (그건 `VaultStore` 몫).
        let oldIDs = Set(old.flatMap { fragmentID, values in values.map { fragmentID + "/" + $0.id } })
        let newIDs = Set(entries.flatMap { fragmentID, values in values.map { fragmentID + "/" + $0.id } })
        let dropped = oldIDs.subtracting(newIDs).count

        // ⚠ **질문은 이웃 잇기에 안 들어간다.** 링크는 조각↔조각이다(ADR 0003 §3-①) —
        //   「이 조각과 비슷한 조각」이 사람이 보는 것이고, 중복 알림도 조각 쌍에 대해 뜬다.
        //   질문은 **다른 축**이다: 조각을 찾는 열쇠이지 서로 이어지는 마디가 아니다.
        //   섞으면 links.json 의 id 가 두 종류가 되고, 그걸 읽는 화면이 조각인 줄 알고 연다.
        let (neighbors, duplicates) = Self.link(passageVectors: passageVectors, changed: changed)

        try store.savePassages(entries, questions: questionEntries, model: model)
        try store.saveLinks(neighbors, model: model,
                            policy: .init(topK: Self.topK,
                                          linkFloor: Self.linkFloor,
                                          nearDuplicate: Self.nearDuplicate))

        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e9
        return Report(total: entries.count, embedded: embedded, reused: reused,
                      dropped: dropped, skippedEmpty: skippedEmpty, coldBuild: coldBuild,
                      elapsed: elapsed, neighbors: neighbors, duplicates: duplicates,
                      questionsEmbedded: questionsEmbedded, questionsReused: questionsReused,
                      vectors: Self.singlePassageVectors(passageVectors),
                      passageVectors: passageVectors, questionVectors: questionVectors)
    }

    // MARK: - 이웃 잇기

    /// 모든 문서 쌍에서 passage끼리의 최고 코사인을 재서 조각마다 상위 ``topK`` 를 남긴다.
    ///
    /// ⚠ **조각만 들어온다 — 질문은 안 들어온다** (#34). 위 호출 자리의 주석이 이유다:
    /// 링크는 조각↔조각이고(ADR 0003 §3-①), 질문은 조각을 찾는 **다른 축**이다.
    ///
    /// ⚠ **쌍의 수가 N² 로 는다.** `실측 2026-08-30`: 조각 50장(1,225쌍)에서 잇는 비용이
    /// 임베딩 한 건보다 작다 — 지금 규모에선 이게 문제가 아니다. 조각이 수천 장이 되면
    /// 여기가 먼저 아프고, 그때 근사 이웃 탐색으로 가는 자리가 이 함수 하나다.
    static func link(passageVectors: [String: [PassageVector]], changed: Set<String>)
        -> ([String: [ContentIndexStore.Neighbor]], [DuplicateHit]) {

        let ids = passageVectors.keys.sorted()
        var neighbors: [String: [ContentIndexStore.Neighbor]] = [:]
        var duplicates: [DuplicateHit] = []

        // 점수는 한 번만 잰다 — 아래 두 쓰임(이웃 목록·중복 알림)이 같은 수를 본다.
        var scores: [String: [ContentIndexStore.Neighbor]] = [:]
        for i in 0..<ids.count {
            for j in (i + 1)..<ids.count {
                let a = ids[i], b = ids[j]
                guard let va = passageVectors[a], let vb = passageVectors[b] else { continue }
                let s = va.flatMap { left in vb.map { Double(TextEmbedder.cosine(left.vector, $0.vector)) } }
                    .filter(\.isFinite).max()
                guard let s else { continue }   // NaN 을 이웃으로 앉히지 않는다 (#31 의 자국)
                scores[a, default: []].append(.init(id: b, score: s))
                scores[b, default: []].append(.init(id: a, score: s))
            }
        }

        for id in ids {
            let sorted = (scores[id] ?? [])
                .filter { $0.score >= ContentIndexer.linkFloor }
                // 점수가 같으면 id 순 — **순서가 실행마다 안 바뀌게.** 안 그러면 파일이 매번 달라진다.
                .sorted { $0.score == $1.score ? $0.id < $1.id : $0.score > $1.score }
            let kept = Array(sorted.prefix(ContentIndexer.topK))
            if !kept.isEmpty { neighbors[id] = kept }

            // 중복 알림은 **이번에 바뀐 것**에 대해서만 낸다.
            guard changed.contains(id) else { continue }
            for n in sorted where n.score >= ContentIndexer.nearDuplicate {
                // 둘 다 이번에 바뀐 쌍은 한 방향만 — 같은 쌍을 두 번 알리지 않는다.
                if changed.contains(n.id) && n.id < id { continue }
                duplicates.append(DuplicateHit(id: id, otherID: n.id, score: n.score))
            }
        }
        duplicates.sort { $0.score == $1.score ? $0.id < $1.id : $0.score > $1.score }
        return (neighbors, duplicates)
    }

    /// 이전 단일-벡터 소비자는 짧은 문서에 한해서만 계속 쓸 수 있다. passage가 둘 이상인
    /// 문서는 의도적으로 빼서, 512토큰에서 잘린 한 passage를 전체 내용으로 오인하지 않는다.
    private static func singlePassageVectors(_ values: [String: [PassageVector]]) -> [String: [Float]] {
        values.compactMapValues { $0.count == 1 ? $0[0].vector : nil }
    }
}
