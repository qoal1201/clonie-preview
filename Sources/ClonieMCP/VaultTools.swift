import Foundation
import ClonieCore
import ClonieEmbedding
import ClonieIndex
import ClonieDocuments

// MARK: - 결과 타입 (Claude 가 받는 JSON 의 모양 — 키 이름이 곧 계약이다)

public struct FragmentSummary: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var path: String
    public var updatedAt: Date
}

public struct ListResult: Codable, Equatable, Sendable {
    public var total: Int
    public var fragments: [FragmentSummary]
}

public struct ReadResult: Codable, Equatable, Sendable {
    public var revision: String
    public var id: String
    public var title: String
    public var path: String
    public var body: String
    public var questionIds: [String]
    public var createdAt: Date
    public var updatedAt: Date
}

public struct SearchHit: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var path: String
    /// 초록선 눈금 (1.0 = 초록선). 글자 검색이면 `nil`.
    public var score: Double?
    /// `g` / `a` / `r`. 글자 검색이면 `nil`.
    public var light: String?
    public var snippet: String
}

public struct SearchResult: Codable, Equatable, Sendable {
    /// `meaning`(임베딩) 또는 `text`(모델이 없어 글자로).
    public var mode: String
    public var query: String
    public var hits: [SearchHit]
    public var note: String?
}

public struct WriteResult: Codable, Equatable, Sendable {
    public var written: Bool
    public var id: String
    public var path: String?
    /// 안 썼을 때 그 이유가 된 비슷한 조각들.
    public var duplicates: [SearchHit]
    public var note: String?
}

public enum VaultToolError: Error, CustomStringConvertible, Equatable {
    case notFound(String)
    case emptyQuery
    case emptyTitle
    case emptyBody
    case invalidRevision
    case invalidOutputPath
    case readOnlySource(String)

    public var description: String {
        switch self {
        case .notFound(let id): return "그런 조각이 없다: \(id)"
        case .emptyQuery: return "query 가 비었다"
        case .emptyTitle: return "title 이 비었다"
        case .emptyBody: return "body 가 비었다"
        case .invalidRevision: return "읽은 버전이 만료됐거나 다른 파일의 버전이다. vault_read로 다시 읽고 변경을 검토한다."
        case .invalidOutputPath: return "새 정리 문서의 path는 wiki/ 안의 Markdown 상대 경로여야 한다."
        case .readOnlySource(let path): return "원본은 읽기 전용이다: \(path). 해석은 wiki/ 정리 문서에 쓴다."
        }
    }
}

// MARK: - 도구 논리

/// 둘째 문의 알맹이 — **MCP 를 모른다.** `VaultStore` 위에서 네 가지 일을 한다.
///
/// ## 규칙 (ADR 0007)
///
/// - **md 만 쓴다.** `.clonie/embeddings.json`·`links.json` 은 읽기만. 벡터는 이 actor 안 메모리에만 산다.
/// - 씨앗(`seed == true`)은 사람이 쓴 것이 아니다 — 목록·검색에 안 낸다.
/// - 임베더는 **첫 검색 때** 연다(모델 로드는 초 단위) — 목록·읽기는 그 값을 안 문다.
///
/// actor 인 이유: MCP 핸들러가 동시에 들어오고, 벡터 캐시·임베더가 공유 상태다.
public actor VaultTools {
    private let store: VaultStore
    private let environment: [String: String]

    private enum EmbedderState { case unknown, ready(TextEmbedder), missing(String) }
    private var embedderState: EmbedderState = .unknown
    /// 해시 → 벡터. 프로세스 수명 동안만 산다 — 디스크에 안 내린다 (ADR 0007).
    private var vectorCache: [String: [Float]] = [:]
    private var readVersions: [String: (id: String, load: VersionedLoadResult)] = [:]
    private var readOrder: [String] = []
    private var lastRead: [String: String] = [:]

    public init(vaultURL: URL, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.store = VaultStore(vaultURL: vaultURL)
        self.environment = environment
    }

    public struct SourceListResult: Codable {
        public let total: Int
        public let sources: [SourceCatalog.Source]
        public let nextOffset: Int?
    }

    public func listSources(offset: Int = 0, limit: Int = 50) throws -> SourceListResult {
        let all = try SourceCatalog(vaultURL: store.vaultURL).list()
        let start = min(max(0, offset), all.count)
        let end = min(start + min(max(1, limit), 500), all.count)
        return SourceListResult(total: all.count, sources: Array(all[start..<end]), nextOffset: end < all.count ? end : nil)
    }

    public func readSource(path: String, offset: Int = 0, limit: Int = 20_000) throws -> SourceCatalog.Page {
        try SourceCatalog(vaultURL: store.vaultURL).read(path: path, offset: offset, limit: limit)
    }

    // MARK: list

    public func list(limit: Int = 50) throws -> ListResult {
        let lim = max(1, min(limit, 500))
        let load = try store.load()
        let frags = Self.humanFragments(load.document)
            .sorted { $0.updatedAt == $1.updatedAt ? $0.id < $1.id : $0.updatedAt > $1.updatedAt }
        return ListResult(total: frags.count,
                          fragments: frags.prefix(lim).map {
                              FragmentSummary(id: $0.id, title: $0.title,
                                              path: load.paths[$0.id] ?? "", updatedAt: $0.updatedAt)
                          })
    }

    // MARK: read

    public func read(id: String) throws -> ReadResult {
        let versioned = try store.loadVersioned()
        let load = versioned.result
        guard let f = load.document.fragments.first(where: { $0.id == id }) else {
            throw VaultToolError.notFound(id)
        }
        let token = UUID().uuidString
        readVersions[token] = (id, versioned)
        readOrder.append(token)
        lastRead[id] = token
        if readOrder.count > 32 {
            let expired = readOrder.removeFirst()
            if let entry = readVersions.removeValue(forKey: expired), lastRead[entry.id] == expired {
                lastRead.removeValue(forKey: entry.id)
            }
        }
        return ReadResult(revision: token, id: f.id, title: f.title, path: load.paths[f.id] ?? "", body: f.body,
                          questionIds: f.questionIds, createdAt: f.createdAt, updatedAt: f.updatedAt)
    }

    // MARK: search

    public func search(query: String, limit: Int = 5) throws -> SearchResult {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { throw VaultToolError.emptyQuery }
        let lim = max(1, min(limit, 20))
        let load = try store.load()
        let frags = Self.humanFragments(load.document)

        guard let embedder = embedderIfAvailable() else {
            // ★ 글자 폴백 — 모델이 없어도 둘째 문은 닫히지 않는다. 다만 **무엇으로 찾았는지** 말한다.
            let needle = q.lowercased()
            let hits = frags
                .filter { ($0.title + "\n" + $0.body).lowercased().contains(needle) }
                .prefix(lim)
                .map { Self.makeHit($0, cosine: nil, paths: load.paths, withLight: false) }
            return SearchResult(mode: "text", query: q, hits: hits, note: embedderNote)
        }

        let indexer = ContentIndexer(sidecarURL: store.sidecarURL, embedder: embedder)
        let ranked = try indexer.search(query: q, fragments: frags, limit: lim)
        let byID = Dictionary(uniqueKeysWithValues: frags.map { ($0.id, $0) })
        let hits = ranked.compactMap { hit -> SearchHit? in
            guard let fragment = byID[hit.fragmentID] else { return nil }
            var result = Self.makeHit(fragment, cosine: hit.score, paths: load.paths, withLight: true)
            result.snippet = Self.snippet(hit.passage.sourceText)
            return result
        }
        return SearchResult(mode: "meaning", query: q, hits: hits, note: nil)
    }

    /// 코사인 내림차순으로 조각 전부. `asQuery` 면 `query: ` 프리픽스(찾는 쪽), 아니면 `passage: `(조각끼리 — 중복 문지기).
    ///
    /// 조각 벡터는 ① 메모리 캐시 → ② 사이드카 `embeddings.json` 의 **해시가 같은** 항목 → ③ 지금 계산.
    /// ③ 도 캐시에만 앉는다 — **디스크에 안 쓴다** (ADR 0007).
    func rankByMeaning(text: String, asQuery: Bool, embedder: TextEmbedder,
                       fragments: [Fragment]) throws -> [(Fragment, Double)] {
        let qv = asQuery ? try embedder.embed(query: text) : try embedder.embed(passage: text)
        let sidecar = ContentIndexStore(sidecarURL: store.sidecarURL)
        let stored = sidecar.loadVectors(for: ContentIndexStore.ModelIdentity(embedder.manifest)) ?? [:]
        var scored: [(Fragment, Double)] = []
        for f in fragments {
            let passage = ContentIndexer.indexText(f)
            let h = ContentIndexer.hash(passage)
            let v: [Float]
            if let c = vectorCache[h] {
                v = c
            } else if let e = stored[f.id], e.hash == h,
                      let d = ContentIndexStore.decode(vector: e.vector, dimensions: embedder.dimensions) {
                v = d; vectorCache[h] = d
            } else {
                v = try embedder.embed(passage: passage); vectorCache[h] = v
            }
            scored.append((f, Double(TextEmbedder.cosine(qv, v))))
        }
        return scored.sorted { $0.1 > $1.1 }
    }

    /// 임베더 — 첫 호출에 한 번만 연다. 못 열면 그 이유를 `embedderNote` 에 남기고 `nil`.
    func embedderIfAvailable() -> TextEmbedder? {
        switch embedderState {
        case .ready(let e): return e
        case .missing: return nil
        case .unknown:
            let status = EmbeddingModelStore.status(environment: environment)
            guard let manifest = status.manifest else {
                embedderState = .missing(status.explanation); return nil
            }
            do {
                let e = try TextEmbedder(manifest: manifest)
                embedderState = .ready(e); return e
            } catch {
                embedderState = .missing("모델이 있는데 못 열었다: \(error)"); return nil
            }
        }
    }

    /// 뜻 검색이 안 되는 이유(있으면). `search` 가 글자 폴백에 실어 보낸다.
    var embedderNote: String? {
        if case .missing(let why) = embedderState { return "뜻 검색 불가 — 글자로 찾았다. " + why }
        return nil
    }

    // MARK: write

    /// 새 조각을 쓰거나(`id` 없음) 있는 조각을 고친다(`id` 있음). `id` 가 있는데 그 조각이 없으면
    /// `notFound` 를 던진다. **md 만 쓴다** — `VaultStore.save` 를 그대로 타고, 그 저장은 질문이
    /// 그대로면 `document.json` 을 안 건드린다(ADR 0007).
    ///
    /// 중복 문지기: 새 조각이고 모델이 있으면 **조각끼리의 코사인**(`passage:` ↔ `passage:`)이
    /// `ContentIndexer.nearDuplicate`(0.70) 이상인 것이 있을 때 안 쓰고 그것들을 돌려준다.
    /// `force: true` 면 쓴다. 나무의 실측(brain#56 「안 읽은 것을 새 발견으로 센다 — 7번」)이 이 자리다:
    /// 신호등은 읽을 때만이 아니라 **쓸 때도** 켜져야 한다.
    ///
    /// ⚠ 이때 돌려주는 `duplicates` 의 `light` 는 언제나 `nil` 이다 — 신호등은 그 순간의 측정인데,
    /// `nearDuplicate/simGreenDirect ≈ 1.29` 는 문턱을 통과했다는 사실 자체가 언제나 `g`라
    /// 「신호」가 아니라 상수를 돌려주는 꼴이 된다. `score`(정규화·3자리)는 그대로 남긴다.
    public func write(title: String, body: String, questionIds: [String] = [],
                      id: String? = nil, force: Bool = false,
                      path: String? = nil, revision: String? = nil) throws -> WriteResult {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw VaultToolError.emptyTitle }
        guard !b.isEmpty else { throw VaultToolError.emptyBody }

        let baseline: VersionedLoadResult
        if let token = revision ?? id.flatMap({ lastRead[$0] }) {
            guard let entry = readVersions[token], entry.id == id else { throw VaultToolError.invalidRevision }
            baseline = entry.load
        } else {
            baseline = try store.loadVersioned()
        }
        let load = baseline.result
        var doc = load.document
        let known = Set(doc.questions.map(\.id))
        let chips = questionIds.filter { known.contains($0) }
        let now = Date()

        if let id = id, let i = doc.fragments.firstIndex(where: { $0.id == id }) {
            let existingPath = load.paths[id] ?? ""
            if existingPath.hasPrefix("wiki/"), revision == nil, lastRead[id] == nil {
                throw VaultToolError.invalidRevision
            }
            if existingPath.lowercased().hasPrefix("raw/") { throw VaultToolError.readOnlySource(existingPath) }
            if let path, path != existingPath { throw VaultToolError.invalidOutputPath }
            doc.fragments[i].title = t
            doc.fragments[i].body = b
            // 빈 목록이거나 전부 모르는 id 면 칩은 그대로 둔다 — 지우는 통로가 아니다.
            if !chips.isEmpty { doc.fragments[i].questionIds = chips }
            doc.fragments[i].updatedAt = now
            doc.fragments[i].seed = nil      // 사람이(Claude 가) 고쳤다 — 이제 보통 조각이다
            let saved = try store.saveFragments(doc, expecting: baseline.revision)
            lastRead.removeValue(forKey: id)
            return WriteResult(written: true, id: id, path: saved.paths[id],
                               duplicates: [], note: "updated")
        }

        // ⚠ id 를 줬는데 없다 — 조용히 새로 만들지 않는다. `read` 와 같은 낱말로 거절하고,
        //   부르는 쪽(Claude)이 id 없이 다시 부르게 한다. 새 조각의 id 는 언제나 우리가 찍는다.
        if let id = id { throw VaultToolError.notFound(id) }

        if let path {
            guard path.hasPrefix("wiki/"), path.lowercased().hasSuffix(".md"),
                  !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0.isEmpty || $0.hasPrefix(".") })
            else { throw VaultToolError.invalidOutputPath }
        }

        // 정리본은 원본과 의도적으로 내용이 겹친다. wiki 출력의 중복 후보는 기존 wiki 문서다.
        let duplicateCandidates = Self.humanFragments(doc).filter { fragment in
            guard path?.hasPrefix("wiki/") == true else { return true }
            return load.paths[fragment.id]?.hasPrefix("wiki/") == true
        }
        if !force, !duplicateCandidates.isEmpty, let embedder = embedderIfAvailable() {
            let probe = Fragment(id: "_probe", title: t, body: b, questionIds: [], createdAt: now, updatedAt: now)
            let ranked = try rankByMeaning(text: ContentIndexer.indexText(probe), asQuery: false,
                                           embedder: embedder, fragments: duplicateCandidates)
            let dups = ranked.prefix(3).filter { $0.1 >= ContentIndexer.nearDuplicate }
            if !dups.isEmpty {
                let hits = dups.map { Self.makeHit($0.0, cosine: $0.1, paths: load.paths, withLight: false) }
                return WriteResult(written: false, id: "", path: nil, duplicates: hits,
                                   note: "이미 비슷한 조각이 있다. 그것을 고치려면 id 를 주고, 그래도 새로 쓰려면 force: true.")
            }
        }

        let newID = Self.mintID()
        doc.fragments.append(Fragment(id: newID, title: t, body: b, questionIds: chips,
                                      createdAt: now, updatedAt: now))
        let saved = try store.saveFragments(doc, expecting: baseline.revision, newPaths: path.map { [newID: $0] } ?? [:])
        return WriteResult(written: true, id: newID, path: saved.paths[newID],
                           duplicates: [], note: "created")
    }

    /// `mcp-<밀리초 base36>-<4자>`. 화면의 `uid()` 와 같은 결을 — 시각이 앞이라 정렬이 되고, 꼬리가 충돌을 막는다.
    static func mintID() -> String {
        let ms = String(Int(Date().timeIntervalSince1970 * 1000), radix: 36)
        let tail = String((0..<4).map { _ in "abcdefghijklmnopqrstuvwxyz0123456789".randomElement()! })
        return "mcp-\(ms)-\(tail)"
    }

    // MARK: - 공통

    /// `SearchHit` 을 짓는 자리 하나 — 글자 검색·뜻 검색·`write` 의 중복 알림, 셋이 같은 모양을 썼다.
    /// `cosine` 이 `nil` 이면(글자 검색) `score`·`light` 도 `nil`. `withLight` 가 `false` 면
    /// 코사인이 있어도 `light` 는 안 낸다 — **중복 알림이 그 경우다**(F6): 신호등은 순간의 측정인데
    /// 중복 문턱을 넘었다는 것 자체가 언제나 초록이라 신호가 아니게 된다.
    /// ⚠ `light` 는 **반올림 전(3자리로 안 자른) 정규화 값**으로 잰다 — `score` 표시용 반올림이
    ///   문턱 바로 위·아래를 흔들면 안 된다.
    private static func makeHit(_ f: Fragment, cosine: Double?, paths: [String: String],
                                withLight: Bool) -> SearchHit {
        let n = cosine.map { Thresholds.normalized(cosine: $0) }
        let score = n.map { ($0 * 1000).rounded() / 1000 }
        let light = withLight ? n.map { Thresholds.light(normalized: $0) } : nil
        return SearchHit(id: f.id, title: f.title, path: paths[f.id] ?? "",
                         score: score, light: light, snippet: Self.snippet(f.body))
    }

    /// 사람이 쓴 조각만. 씨앗은 화면이 빈 문서에 넣는 예시 한 장이다 (`Fragment.seed` 머리글).
    static func humanFragments(_ doc: CueDocument) -> [Fragment] {
        doc.fragments.filter { $0.seed != true }
    }

    /// 본문 앞 160자 — 줄바꿈은 공백으로.
    static func snippet(_ body: String) -> String {
        let flat = body.replacingOccurrences(of: "\n", with: " ")
        return flat.count <= 160 ? flat : String(flat.prefix(160)) + "…"
    }
}
