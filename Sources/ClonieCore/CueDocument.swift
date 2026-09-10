import Foundation

/// 예상 질문 하나. 조각이 이걸 **id 로** 가리킨다.
///
/// ⚠ 인덱스가 아니라 id 인 이유 = #8: 질문 목록이 편집 가능해지는 순간 인덱스로 묶인
/// 조각이 통째로 어긋난다. 그때 데이터가 조용히 틀려지지 요란하게 깨지지 않는다.
public struct Question: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var text: String
    /// 면접 중에 들어온 질문인가 (#22). `nil`/`false` = 사람이 목록에서 고르거나 자소서에서 온 것.
    ///
    /// ⚠ **옵셔널인 것이 핵심이다.** 이 필드가 없는 옛 파일이 그대로 읽히고, `nil` 일 때는
    /// 인코더가 키를 아예 안 쓴다(`encodeIfPresent`). 그래서 **스키마 판을 안 올린다** —
    /// #22 의 *"새 저장 구조 금지"* 가 이 뜻이다. 자물쇠가 두 방향을 다 잰다.
    public var fromInterview: Bool?
    /// 같은 질문을 면접관이 **다르게 말하는 모양** (#23 갈래 ②). 사람이 적는다, 최대 3개.
    ///
    /// ⚠ **왜 조각이 아니라 질문에 붙나**: 색인의 단위가 질문 칩이다(`Fragment.questionIds`).
    /// 변형을 조각에 붙이면 같은 말투를 조각 수만큼 다시 적어야 한다.
    ///
    /// ⚠ `fromInterview` 와 **같은 이유로 옵셔널이다** — 이 필드가 없는 옛 파일이 그대로 읽히고,
    /// `nil` 이면 인코더가 키를 아예 안 쓴다. 그래서 **스키마 판을 안 올린다**.
    /// 개수·빈칸 다듬기는 **화면이 한다**(`setVariant`) — 여기는 나르기만 한다.
    public var variants: [String]?

    public init(id: String, text: String, fromInterview: Bool? = nil, variants: [String]? = nil) {
        self.id = id
        self.text = text
        self.fromInterview = fromInterview
        self.variants = variants
    }
}

/// 조각 하나 — 제목 + 본문 + 질문 칩.
///
/// ⚠ **「태그」 필드가 따로 없다.** Q9 의 태그가 이 레포에서 구현된 모양이 질문 칩이고,
/// 그게 `questionIds` 다 (#8 구현 결정). 이 등치가 틀리면 스키마가 아니라 필드 하나가 는다.
public struct Fragment: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var body: String
    public var questionIds: [String]
    public var createdAt: Date
    public var updatedAt: Date
    /// **예시다 — 사람이 쓴 것이 아니다.** 빈 문서에 화면이 넣는 placeholder 한 장에만 붙는다.
    ///
    /// ⚠ 이것이 없으면 *"여기에 내 경험을 한 줄로 쓴다"* 가 **실전 검색 1위**로 뜬다
    /// (`실측 2026-08-30`: 「성능 개선 경험」 질의에 1.042 초록 1위). 예시가 답으로 나오는 것은
    /// 빈 결과보다 나쁘다 — 화면은 그것을 「준비된 조각」으로 칠한다.
    ///
    /// ⚠ **화면이 글자로 판별하면 안 된다.** placeholder 문구를 그대로 둔 채 한 글자만 고쳐도
    /// 글자 비교는 틀리고, 반대로 사람이 우연히 같은 문장을 쓰면 그 조각이 죽는다.
    /// 그래서 **표식**이고, 표식은 디스크를 건너야 해서 여기 산다 — 화면에만 두면 재기동 한 번에
    /// 사라지고 씨앗이 보통 조각으로 되살아난다 (`실측`: QA 가 그 모양으로 잡았다).
    ///
    /// ⚠ `Question.fromInterview` 와 **같은 이유로 옵셔널이다** — 이 필드가 없는 옛 파일이
    /// 그대로 읽히고, `nil` 이면 인코더가 키를 아예 안 쓴다. 그래서 **스키마 판을 안 올린다**.
    /// 사람이 한 번이라도 고치면 화면이 이 표식을 뗀다(그때부터 보통 조각이다).
    public var seed: Bool?

    public init(id: String, title: String, body: String,
                questionIds: [String], createdAt: Date, updatedAt: Date,
                seed: Bool? = nil) {
        self.id = id
        self.title = title
        self.body = body
        self.questionIds = questionIds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.seed = seed
    }
}

/// 디스크에 사는 문서 하나. **이것이 정본이다** — 채팅 UI 의 `localStorage` 가 아니라.
///
/// ## 왜 빈 문서에 질문이 없나
///
/// 표준 예상 질문 목록은 **화면이 든다**(`ChatHTML.swift` 의 `STD`). 여기에도 두면
/// 한 사실이 두 곳에 살고 한쪽이 썩는다. 빈 문서를 받은 화면이 그 목록을 씨앗으로 넣고
/// 저장하며, **그 다음부터 정본은 이 파일**이다. Swift 쪽 검색은 파일을 읽지 화면을 안 읽는다.
public struct CueDocument: Codable, Equatable, Sendable {
    /// ⚠ 이 숫자를 올리는 것은 **옛 파일을 알아보고 옮기는 코드를 같이 넣는다는 뜻**이다.
    /// 지금은 1 이고, 읽을 때 모르는 판(더 큰 수)을 만나면 거부한다 — 조용히 덮어쓰지 않는다.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var questions: [Question]
    public var fragments: [Fragment]
    /// 입력 기록 (ADR 0006 §③). **통로를 안 늘리려고 여기 얹는다** — 화면은 문서 전체를 보내고 받으니
    /// 이 칸이 같이 오간다. ⚠ 디스크에서는 `asked.json` 에 따로 산다(`VaultStore`). `nil` = 「안 건드린다」 —
    /// `VaultStore.save` 가 그때 `asked.json` 을 **안 쓴다.** 이 칸을 모르는 인코더(옛 화면 판)가 보낸 문서를 위한 길이다.
    /// ⚠ 둘째 문(MCP)은 이 길이 **아니다** — `load()` 가 언제나 채워 주고 `write` 는 그것을 그대로 되쓴다. 거기서
    /// 기록을 지켜 주는 것은 `asked != lastAsked`(안 바뀌면 안 쓴다)이고, 자물쇠 = `VaultToolsTests.testWriteNeverErasesTheAskedLog`.
    ///
    /// ⚠ `Question.fromInterview` 와 **같은 이유로 옵셔널이다** — 이 칸이 없는 옛 파일이 그대로 읽히고,
    /// `nil` 이면 인코더가 키를 아예 안 쓴다. 그래서 **스키마 판을 안 올린다**.
    public var asked: [AskedEntry]?

    public init(schemaVersion: Int = CueDocument.currentSchemaVersion,
                questions: [Question] = [],
                fragments: [Fragment] = [],
                asked: [AskedEntry]? = nil) {
        self.schemaVersion = schemaVersion
        self.questions = questions
        self.fragments = fragments
        self.asked = asked
    }

    public static let empty = CueDocument()
}
