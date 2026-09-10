import Foundation
import GhostbarCore
import GhostbarEmbedding

/// 사이드카에 앉는 **두 파일의 규약** (#32, ADR 0003 §2·§3-①).
///
/// ```
/// <볼트>/.clonie/
/// ├── document.json      질문 목록 — #30 이 든다
/// ├── embeddings.json    ★ 조각 id → 벡터 + 원문 해시   (이 파일)
/// │                      ★ 질문 id → 물음꼴 벡터들      (이 파일, #34)
/// └── links.json         ★ 조각 id → 가까운 이웃들      (이 파일)
/// ```
///
/// ## ★ 한 파일에 **두 축**이 산다 — 조각과 질문 (#34)
///
/// - **조각 축** = 제목+본문. 찾는 쪽과 찾히는 쪽이 다른 **비대칭** 과제라
///   ``ContentIndexer/indexText(_:)`` 를 `embed(passage:)` 로 넣는다.
///   면접 중 검색(내용 직접)이 들린 질의를 이것에 대고 잰다.
/// - **질문 축** = 예상 질문의 물음꼴. **물음 대 물음이라 대칭** 과제이고,
///   그래서 `embed(query:)` 로 넣는다 — `embed(passage:)` 가 아니다.
///   근거 = 모델 카드(dragonkue/multilingual-e5-small-ko-v2) §FAQ: 대칭 과제는
///   **양쪽 다 `query: `** 를 쓴다.
///
/// ⚠ **질문 축을 쓰는 곳이 바뀌었다** (#53, ADR 0005). 예전엔 라이브 검색의 **개념 매개**
///   갈래가 이것을 읽어 「질의 ↔ 그 조각이 답하는 질문」으로 조각을 건너짚었다. 그 갈래는
///   걷혔다. 지금 이 축을 읽는 것은 **준비도 줄과 연습의 「준비된 답변이 없다」** 하나뿐이고,
///   그것도 「질문 벡터 ↔ 조각 벡터」로 쓴다 — **내용 직접 자와 같은 자**다.
///   ⚠ 그래서 변형(2번째 이후 벡터)은 지금 **아무도 안 읽는다.** 안 지우는 이유는
///   ADR 0005 「다시 열 조건」이 이 축을 되살릴 수 있어서다.
///
/// ⚠ 이 프리픽스가 조용히 갈리면 **아무것도 안 터지고 점수만 틀려진다.** 그래서
/// ``ModelIdentity/queryPrefix`` 가 파일에 같이 적히고, 시험이 저장된 벡터를
/// `embed(query:)` 것과 대조한다(양성 대조, 정관 6조).
///
/// 코사인·순위·색은 **화면(JS)이 낸다.** 이 파일이 하는 일은 셋뿐이다 — 계산 · 증분 저장 · 돌려주기.
///
/// ## ⚠ 이 둘은 **파생물**이다 — 지워도 아무것도 안 잃는다
///
/// 원본은 유저의 md 이고, 여기 있는 것은 그걸 다시 계산하면 나오는 것뿐이다. 그래서
/// **깨졌을 때 격리하지 않고 그냥 다시 만든다** (`FragmentStore` 는 격리한다 — 거긴 원본이라서).
/// 못 읽는 이유가 무엇이든 결론이 같다: `nil` 을 돌려주고, 부르는 쪽이 처음부터 채운다.
///
/// ## 모델이 바뀌면 통째로 버린다
///
/// 벡터는 **그 모델의 좌표계 안에서만** 뜻이 있다. 모델 id·리비전·차원 중 하나라도 다르면
/// 옛 벡터와 새 벡터의 코사인은 **숫자는 나오는데 뜻이 없다** — 아무것도 안 터지고 점수만
/// 조용히 틀려지는 모양이라, 여기서 끊는다.
///
/// ## 유저 md 에는 한 글자도 안 쓴다
///
/// 이 타입이 아는 경로는 `sidecarURL` 아래뿐이다. 승인 경계(#33)가 서기 전까지
/// **볼트 본문으로 나가는 길이 여기 없다.**
public struct ContentIndexStore {

    public let sidecarURL: URL
    private let fm: FileManager

    public init(sidecarURL: URL, fileManager: FileManager = .default) {
        self.sidecarURL = sidecarURL
        self.fm = fileManager
    }

    public var embeddingsURL: URL { sidecarURL.appendingPathComponent("embeddings.json") }
    public var linksURL: URL { sidecarURL.appendingPathComponent("links.json") }

    // MARK: - 모델 신원

    /// 이 색인이 **어느 좌표계에서 만들어졌나.** 하나라도 다르면 색인을 버린다.
    public struct ModelIdentity: Codable, Equatable, Sendable {
        public var id: String
        public var revision: String
        public var dimensions: Int
        /// 조각을 어떤 프리픽스로 넣었나. e5 규약(#31)이 바뀌면 벡터도 갈린다.
        public var passagePrefix: String
        /// 질문의 물음꼴을 어떤 프리픽스로 넣었나 (#34). **파일에 두 축이 사는 순간 필요해진 것**이다 —
        /// 조각만 있을 땐 `passagePrefix` 하나가 좌표계를 다 설명했다.
        ///
        /// ⚠ **옵셔널로 안 둔다.** 그래서 이 필드가 없는 **옛 사이드카는 디코딩에서 떨어지고**,
        /// ``loadVectors(for:)`` 가 `nil` 을 돌려주고, 색인이 처음부터 다시 만들어진다.
        /// **그게 맞다** — 파일의 뜻이 바뀌었다(조각뿐 → 조각+질문). 옵셔널로 두고 기본값을 넣으면
        /// 질문 축이 없는 옛 파일을 「있다」고 읽게 되고, 그건 아무것도 안 터지면서 개념 매개가
        /// 통째로 빈 상태다. 파생물이라 다시 만드는 값이 싸다(위 「지워도 아무것도 안 잃는다」).
        public var queryPrefix: String

        public init(id: String, revision: String, dimensions: Int,
                    passagePrefix: String, queryPrefix: String) {
            self.id = id
            self.revision = revision
            self.dimensions = dimensions
            self.passagePrefix = passagePrefix
            self.queryPrefix = queryPrefix
        }

        public init(_ m: EmbeddingModelStore.Manifest) {
            self.init(id: m.modelID, revision: m.revision,
                      dimensions: m.dimensions,
                      passagePrefix: m.passagePrefix, queryPrefix: m.queryPrefix)
        }
    }

    // MARK: - embeddings.json

    /// v1 조각 하나의 자리. 장문 passage 색인(v2)에서는 ``PassageEntry`` 를 쓴다.
    ///
    /// 이 타입은 짧은 문서만 한 벡터로 건네던 기존 호출부의 호환용이다. v2에서 passage가
    /// 둘 이상인 파일은 ``loadVectors(for:)`` 에 절대 나타나지 않는다.
    public struct VectorEntry: Codable, Equatable, Sendable {
        /// 임베딩에 실제로 들어간 글자의 SHA-256. 같으면 벡터도 같다 —
        /// ⚠ **제목+본문만** 든다. `updatedAt` 이 흔들려도 재계산이 안 일어나는 이유다.
        public var hash: String
        /// float32 리틀엔디언을 base64 로. **JSON 실수 배열이 아니다** —
        /// 384칸을 십진수로 적으면 조각당 ~4KB 인데 base64 는 2KB 이고 **왕복에서 값이 안 변한다.**
        public var vector: String
    }

    /// 문서 안 passage 하나의 디스크 자리. range는 `Fragment.body`의 UTF-16 오프셋이다.
    /// `hash`는 제목·heading 문맥까지 포함해 실제로 임베딩한 문자열의 SHA-256이다.
    public struct PassageEntry: Codable, Equatable, Sendable {
        public var id: String
        public var startUTF16: Int
        public var endUTF16: Int
        public var hash: String
        public var vector: String

        public init(id: String, startUTF16: Int, endUTF16: Int, hash: String, vector: String) {
            self.id = id
            self.startUTF16 = startUTF16
            self.endUTF16 = endUTF16
            self.hash = hash
            self.vector = vector
        }
    }

    /// 질문 하나의 자리 (#34). **여러 벡터가 한 항목에 앉는다** — 같은 질문을 면접관이
    /// 다르게 말하는 모양(`Question.variants`, #23 갈래 ②)까지 같이 넣기 때문이다.
    ///
    /// - `vectors[0]` = 질문 자기 자신의 글자
    /// - `vectors[1...]` = ``ContentIndexer/questionText(_:)`` 가 돌려준 **그 순서 그대로**의 변형들
    ///
    /// ⚠ **순서가 규약이다.** 화면이 「어느 말투가 걸렸나」를 보여주려면 벡터와 글자가
    /// 같은 자리에 있어야 한다 — 순서를 흩으면 아무것도 안 터지고 라벨만 어긋난다.
    ///
    /// `hash` 는 조각과 같은 뜻이다: **글자가 같으면 벡터도 같다.** 다만 여기서 「글자」는
    /// 물음꼴 전부를 이은 것이라, 변형 하나만 고쳐도 해시가 갈린다.
    public struct QuestionEntry: Codable, Equatable, Sendable {
        public var hash: String
        /// base64 float32 리틀엔디언. ``VectorEntry/vector`` 와 **같은 부호 방식**이다.
        public var vectors: [String]

        public init(hash: String, vectors: [String]) {
            self.hash = hash
            self.vectors = vectors
        }
    }

    public struct IndexFile: Codable, Sendable {
        /// v2는 fragment 하나의 벡터를 passage 여러 개로 바꿨다. v1은 512 토큰에서 잘린
        /// 첫 부분을 문서 전체라고 주장하므로 이행하지 않고 반드시 콜드 재생성한다.
        public static let currentSchemaVersion = 2
        /// 벡터를 어떻게 적었나. 값이 하나뿐이지만 **적어둔다** — 안 적으면 바꾼 날 조용히 깨진다.
        public static let vectorEncoding = "float32-le-base64"

        public var schemaVersion: Int
        public var model: ModelIdentity
        public var encoding: String
        /// v1의 단일 벡터 자리. v2 파일에는 쓰지 않고, 구 파일을 알아본 뒤 버리는 데만 둔다.
        public var entries: [String: VectorEntry]?
        /// fragment id → 본문 passage들. 빈 문서도 `[:]`를 저장해 v2의 유효한 빈 색인과
        /// 파일 부재를 구별한다.
        public var passages: [String: [PassageEntry]]?
        /// 질문 축 (#34). **옵셔널인 것은 「없을 때 키를 아예 안 쓴다」는 뜻**이다 —
        /// 질문이 0개인 볼트의 파일에 `"questions": {}` 가 남으면, 그게 「질문 축이 있다」와
        /// 구분이 안 된다. `Question.variants` 가 옵셔널인 것과 같은 이유다(`CueDocument`).
        public var questions: [String: QuestionEntry]?
    }

    /// 쓸 수 있는 색인만 돌려준다. **없거나·깨졌거나·판이 다르거나·모델이 다르면 `nil`.**
    ///
    /// - Returns: 살아 있는 항목들. `nil` 은 「처음부터 채워라」다.
    public func loadVectors(for model: ModelIdentity) -> [String: VectorEntry]? {
        guard let passages = loadPassages(for: model) else { return nil }
        var single: [String: VectorEntry] = [:]
        for (fragmentID, values) in passages where values.count == 1 {
            let p = values[0]
            single[fragmentID] = VectorEntry(hash: p.hash, vector: p.vector)
        }
        return single
    }

    /// v2 passage 색인. v1 단일 벡터는 **읽지 않는다** — 잘린 원래 벡터를 장문 전체의
    /// 뜻으로 다시 쓰는 것이 이 API가 막는 사고다.
    public func loadPassages(for model: ModelIdentity) -> [String: [PassageEntry]]? {
        usableFile(for: model)?.passages
    }

    /// 질문 축(#34). ``loadVectors(for:)`` 과 **같은 판정**을 지난다 — 한 파일이라 그래야 한다.
    ///
    /// - Returns: `nil` 은 「처음부터 채워라」다. **질문이 0개라 키가 없는 파일도 `nil`이 아니라
    ///   빈 사전**을 돌려준다 — 「없다」와 「비었다」를 부르는 쪽이 갈라야 하는 자리가 아니다.
    ///   (파일 자체가 못 쓰는 것일 때만 `nil`.)
    public func loadQuestions(for model: ModelIdentity) -> [String: QuestionEntry]? {
        guard let file = usableFile(for: model) else { return nil }
        return file.questions ?? [:]
    }

    /// 쓸 수 있는 파일 하나만 푼다. **두 loader 가 같은 판정을 쓰게** 하는 자리다 —
    /// 갈라 적으면 언젠가 한쪽만 고쳐지고, 그때 두 축의 좌표계가 달라진다.
    private func usableFile(for model: ModelIdentity) -> IndexFile? {
        guard let data = try? Data(contentsOf: embeddingsURL) else { return nil }
        guard let file = try? Self.decoder().decode(IndexFile.self, from: data) else { return nil }
        guard file.schemaVersion == IndexFile.currentSchemaVersion,
              file.encoding == IndexFile.vectorEncoding,
              file.model == model else { return nil }
        return file
    }

    /// 지금 디스크에 무엇이 있나 — **부작용 없이** 한 줄로. 진단·테스트가 쓴다.
    public func describeVectors() -> String {
        guard let data = try? Data(contentsOf: embeddingsURL) else { return "embeddings.json 없음" }
        guard let file = try? Self.decoder().decode(IndexFile.self, from: data) else {
            return "embeddings.json 못 읽음 (\(data.count)B)"
        }
        let passageCount = file.passages?.values.reduce(0) { $0 + $1.count } ?? 0
        return "embeddings.json v\(file.schemaVersion) · 조각 \(file.passages?.count ?? 0)건 · "
             + "passage \(passageCount)건 · "
             + "질문 \(file.questions?.count ?? 0)건 · "
             + "\(file.model.id)@\(file.model.revision.prefix(12)) \(file.model.dimensions)차"
    }

    /// passage와 질문 축을 **한 번에** 쓴다.
    ///
    /// ⚠ 조각과 질문을 따로 저장하는 API 를 안 둔다 — 한 파일이라 나중에 쓴 쪽이 앞엣것을
    /// 통째로 덮는다. 「한 번에」가 그 사고를 문법으로 막는다.
    ///
    /// - Parameter questions: 비었으면 **키를 아예 안 쓴다**(`IndexFile.questions` 주석).
    public func savePassages(_ passages: [String: [PassageEntry]],
                             questions: [String: QuestionEntry] = [:],
                             model: ModelIdentity) throws {
        let file = IndexFile(schemaVersion: IndexFile.currentSchemaVersion,
                             model: model,
                             encoding: IndexFile.vectorEncoding,
                             entries: nil,
                             passages: passages,
                             questions: questions.isEmpty ? nil : questions)
        try AtomicFile.write(try Self.encoder().encode(file), to: embeddingsURL, fileManager: fm)
    }

    /// 짧은 문서 벡터를 쓰던 호출부의 임시 호환 API. 새 색인은 이 입구를 사용하지 않는다.
    @available(*, deprecated, message: "Use savePassages(_:questions:model:) for passage indexing.")
    public func saveVectors(_ entries: [String: VectorEntry],
                            questions: [String: QuestionEntry] = [:],
                            model: ModelIdentity) throws {
        let passages = entries.mapValues { entry in
            [PassageEntry(id: "legacy-single", startUTF16: 0, endUTF16: 0,
                          hash: entry.hash, vector: entry.vector)]
        }
        try savePassages(passages, questions: questions, model: model)
    }

    // MARK: - links.json

    /// 「이 조각과 가까운 조각」 하나.
    public struct Neighbor: Codable, Equatable, Sendable {
        public var id: String
        /// 코사인. **화면이 색을 칠할 수 있게 점수를 같이 남긴다** — 순위만 남기면
        /// 「가깝다」가 얼마나 가까운지를 읽는 쪽이 영영 모른다.
        public var score: Double
    }

    public struct LinksFile: Codable, Sendable {
        public static let currentSchemaVersion = 1

        public var schemaVersion: Int
        public var model: ModelIdentity
        public var generatedAt: Date
        /// 이 파일을 만들 때 쓴 값들. **파일이 자기가 어떤 잣대로 만들어졌는지 안다** —
        /// 상수를 고치고 색인을 안 다시 돌리면 여기가 옛 값을 들고 있어서 티가 난다.
        public var policy: Policy
        public var links: [String: [Neighbor]]

        public struct Policy: Codable, Equatable, Sendable {
            public var topK: Int
            public var linkFloor: Double
            public var nearDuplicate: Double
        }
    }

    public func loadLinks() -> LinksFile? {
        guard let data = try? Data(contentsOf: linksURL) else { return nil }
        return try? Self.decoder().decode(LinksFile.self, from: data)
    }

    public func saveLinks(_ links: [String: [Neighbor]],
                          model: ModelIdentity,
                          policy: LinksFile.Policy,
                          now: Date = Date()) throws {
        let file = LinksFile(schemaVersion: LinksFile.currentSchemaVersion,
                             model: model, generatedAt: now, policy: policy, links: links)
        try AtomicFile.write(try Self.encoder().encode(file), to: linksURL, fileManager: fm)
    }

    // MARK: - 벡터 ↔ 글자

    /// float32 리틀엔디언 base64. **왕복이 비트 단위로 같다** — 십진수로 적으면 안 그렇다.
    public static func encode(vector: [Float]) -> String {
        var data = Data(capacity: vector.count * 4)
        for v in vector {
            var le = v.bitPattern.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        return data.base64EncodedString()
    }

    /// - Returns: 길이가 `dimensions` 와 다르면 `nil` — **길이가 맞지 않는 벡터를 안 돌려준다.**
    ///   0 으로 채운 벡터를 돌려주면 코사인이 조용히 0 이 되고 아무도 못 알아챈다.
    public static func decode(vector text: String, dimensions: Int) -> [Float]? {
        guard let data = Data(base64Encoded: text), data.count == dimensions * 4 else { return nil }
        var out = [Float](repeating: 0, count: dimensions)
        data.withUnsafeBytes { raw in
            for i in 0..<dimensions {
                var bits: UInt32 = 0
                withUnsafeMutableBytes(of: &bits) { dst in
                    dst.copyMemory(from: UnsafeRawBufferPointer(rebasing: raw[(i * 4)..<(i * 4 + 4)]))
                }
                out[i] = Float(bitPattern: UInt32(littleEndian: bits))
            }
        }
        return out
    }

    // MARK: - 부호기

    /// ⚠ `FragmentStore` 와 **같은 모양**을 쓴다 (`sortedKeys` — 안 그러면 알맹이가 같아도
    /// 파일이 매번 달라져 옵시디언 동기화가 계속 깨어난다).
    static func encoder() -> JSONEncoder { FragmentStore.makeEncoder() }
    static func decoder() -> JSONDecoder { FragmentStore.makeDecoder() }
}
