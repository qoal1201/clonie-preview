import Foundation

/// 입력이 온 자리. **실제로 온 것**만 있다 — 미리 써 둔 예상 질문은 여기 없다(그건 `Question`).
public enum AskedSource: String, Codable, Sendable {
    case sun          // 저장소 화면 태양에 친 것
    case interview    // 면접에서 상대가 말한 것 (확정된 발화만)
}

/// 입력 기록 한 줄 — **실제로 온 입력**만 여기 산다 (ADR 0006 §③). 태양에 친 것·면접에서 들린 것.
///
/// ★ 색(`color`)은 **그 입력이 온 순간** `rank()` 가 낸 것이다 — 저장소가 그때 얼마나 답했나.
///   나중에 다시 재지 않는다. 연습이 다시 물어 채점하면 `practiceColor`/`practicedAt` 에
///   따로 적는다(약한 것부터의 자).
/// ⚠ 글자 자(`how == "글자"`) 판정에는 색을 안 적는다(`nil`) — #53: 글자 자는 색을 못 낸다.
/// ⚠ 전부 옵셔널인 이유 = `Question.fromInterview` 와 같다. 키가 없는 옛 파일이 그대로 읽히고 판을 안 올린다.
public struct AskedEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var text: String
    public var source: AskedSource
    public var at: Date
    public var color: String?      // "g" | "a" | "r" — 온 순간의 신호등. 글자 자면 nil
    public var score: Double?
    public var how: String?        // "뜻" | "글자"
    public var count: Int?         // 같은 질문이 몇 번 왔나 (병합 시 +1)
    public var practiceColor: String?   // 연습에서 마지막으로 받은 색
    public var practicedAt: Date?       // 그 시각

    public init(id: String, text: String, source: AskedSource, at: Date,
                color: String? = nil, score: Double? = nil, how: String? = nil,
                count: Int? = nil, practiceColor: String? = nil, practicedAt: Date? = nil) {
        self.id = id; self.text = text; self.source = source; self.at = at
        self.color = color; self.score = score; self.how = how
        self.count = count; self.practiceColor = practiceColor; self.practicedAt = practicedAt
    }
}

/// `.clonie/asked.json` 의 모양. `document.json` 과 **다른 파일**이다 — 질문 목록(축)과 입력 기록(흐름)은
/// 바뀌는 박자가 달라서, 한 파일에 두면 면접 한 번에 질문 축 파일이 통째로 다시 쓰인다.
public struct AskedLog: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public var schemaVersion: Int
    public var entries: [AskedEntry]

    public init(schemaVersion: Int = AskedLog.currentSchemaVersion, entries: [AskedEntry] = []) {
        self.schemaVersion = schemaVersion
        self.entries = entries
    }
}
