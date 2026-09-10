import Foundation

/// 클라우드 초안의 **전선**(#51) — 요청 한 벌을 짓고, 온 답에서 이야기를 꺼낸다.
///
/// ★ **지시문은 여기 없다.** 무엇을 시킬지는 `FragmentDrafter` 하나가 든다(온디바이스와
/// 같은 글자여야 두 길의 결과를 견줄 수 있다). 여기 사는 것은 **어느 제공자에 어떤 모양으로
/// 실어 보내고, 온 것을 어떻게 뜯나**뿐이다.
///
/// ⚠ **왜 앱 타깃이 아니라 라이브러리인가.** `Sources/Clonie/` 는 executable 이라
/// `swift test` 가 못 부른다 — `ClonieCore`(#8)·`ClonieEmbedding`(#31)·
/// `ClonieIndex`(#32) 를 뽑은 것과 **똑같은 이유**다. 걷으면 무슨 일이 다시 일어나나:
/// **클라우드 답 파싱이 검사 밖으로 나가고**, 제공자가 답 모양을 바꿔도 아무것도 안 빨개진다.
/// 파싱은 남의 서버가 흔드는 자리라 그 자리가 제일 조용히 낡는다.
///
/// ⚠ **키를 로그·URL 에 절대 안 싣는다.** 키가 가는 곳은 헤더 하나뿐이고,
/// 실패 사유(`Outcome.fallback`)는 사용자에게 그대로 보이는 글자라 거기에도 안 넣는다.
public enum CloudDraftWire {

    /// 뽑아낸 이야기 한 장. **`FragmentDrafter.Draft` 와 짝이지만 타입은 따로다** —
    /// 저쪽은 FoundationModels 를 들어 이 타깃이 못 든다. 옮기는 것은 앱 층 한 줄이다.
    public struct Draft: Equatable {
        public let title: String
        public let body:  String
        public init(title: String, body: String) {
            self.title = title
            self.body  = body
        }
    }

    /// 어느 제공자인가.
    ///
    /// ⚠ **`BackendType` 의 rawValue 를 그대로 받는다** (`Config/BackendConfig.swift`).
    /// 저쪽은 앱 타깃이라 여기서 못 든다 — 그래서 낱말이 두 곳에 산다. 갈리면
    /// `init?(rawValue:)` 가 `nil` 이고, 그때 클라우드는 **안 켜진다**(온디바이스로 그냥 간다).
    /// 조용히 틀린 곳으로 보내는 것보다 안 켜지는 쪽이 싸다.
    public enum Provider: String {
        case ollama
        case openai
        case anthropic
        case openrouter
    }

    /// 클라우드 한 번의 결과 **둘뿐이다.**
    /// - `ok`: 답이 왔고 뜯었다. **빈 목록도 `ok`** 다 — 「이 덩이엔 이야기가 없다」는 판정이다
    /// - `fallback`: 이 길로는 못 갔다. 딸린 한국어 한 줄이 **사용자에게 그대로 보인다**
    ///
    /// ⚠ 여기서 재시도하지 않는다. 무엇을 다시 할지는 부르는 쪽(앱 층)이 정한다 —
    /// 지금 그 답은 「온디바이스로 물러선다」 하나다.
    public enum Outcome: Equatable {
        case ok([Draft])
        case fallback(String)
    }

    /// 한 덩이에서 받을 이야기 상한의 **기본값**. 부르는 쪽이 `FragmentDrafter.maxDrafts` 를
    /// 실어 보내므로 여기 값은 그때 안 쓰인다 — 두 자가 갈릴 자리를 안 만들려고 인자로 뺐다.
    public static let defaultLimit = 3

    // MARK: - 보내기

    /// 요청 한 벌. 못 지으면 `nil` 이고, 그때 부르는 쪽이 온디바이스로 간다.
    ///
    /// - Parameter base: 설정에 적힌 그 URL. 꼬리 `/` 는 여기서 걷는다.
    /// - Parameter instructions: **역할·규칙**(`FragmentDrafter.instructions` + JSON 요구).
    /// - Parameter prompt: 이번 글 한 덩이(`soloPrompt`/`askPrompt`/`mergedPrompt`).
    ///
    /// 조각은 완성된 응답을 파싱한 뒤 한 번에 화면에 전달한다.
    /// ⚠ **`response_format`(JSON 모드)을 안 건다.** 제공자·모델마다 받는 이름이 달라
    /// 안 받는 조합에서 400 이 나고, 그러면 **되는 모델도 통째로 못 쓰게** 된다.
    /// 대신 지시문이 JSON 을 요구하고 `cloudDrafts` 가 너그럽게 뜯는다.
    /// (예외: Ollama 의 `format` 은 서버 기능이라 모델과 무관하다 — 그것만 건다.)
    public static func cloudRequest(provider: Provider,
                                    base: String,
                                    key: String,
                                    model: String,
                                    instructions: String,
                                    prompt: String,
                                    maxTokens: Int = 4_096) -> URLRequest? {
        let root = base.trimmingCharacters(in: .whitespacesAndNewlines)
                       .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !root.isEmpty, !model.isEmpty else { return nil }
        let path: String
        switch provider {
        case .ollama:                 path = "/api/chat"
        case .anthropic:              path = "/messages"
        case .openai, .openrouter:    path = "/chat/completions"
        }
        guard let url = URL(string: root + path) else { return nil }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any]
        switch provider {
        case .anthropic:
            // 상류 `streamAnthropic` 과 같은 헤더 규약. 다른 것은 `stream` 이 꺼진 것뿐이다.
            req.setValue(key, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = ["model": model,
                    "max_tokens": maxTokens,
                    "system": instructions,
                    "messages": [["role": "user", "content": prompt]]]
        case .openai, .openrouter:
            if !key.isEmpty { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
            body = ["model": model,
                    "stream": false,
                    "messages": [["role": "system", "content": instructions],
                                 ["role": "user",   "content": prompt]]]
        case .ollama:
            if !key.isEmpty { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
            body = ["model": model,
                    "stream": false,
                    "format": "json",
                    "messages": [["role": "system", "content": instructions],
                                 ["role": "user",   "content": prompt]]]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        req.httpBody = data
        return req
    }

    /// 한 번 다녀온다. **던지지 않는다** — 실패도 `Outcome` 이다.
    ///
    /// ⚠ `session` 을 받는 이유는 하나다: **목으로 시험하려고.** 진짜 키로 잰 적이 없는
    /// 코드라(사람만 그걸 할 수 있다) 최소한 이 길이 도는지는 `URLProtocol` 목이 잰다.
    public static func cloudFetch(request: URLRequest,
                                  provider: Provider,
                                  limit: Int = defaultLimit,
                                  session: URLSession = .shared) async -> Outcome {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            return .fallback("클라우드에 못 닿았어요 — \((error as NSError).localizedDescription)")
        }
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let detail = cloudErrorMessage(from: data).map { " — \($0)" } ?? ""
            return .fallback("클라우드가 거절했어요 (HTTP \(http.statusCode))\(detail)")
        }
        guard let text = cloudText(from: data, provider: provider) else {
            return .fallback("클라우드 답의 모양을 못 읽었어요")
        }
        guard let drafts = cloudDrafts(fromText: text, limit: limit) else {
            return .fallback("클라우드가 JSON 이 아닌 답을 냈어요")
        }
        return .ok(drafts)
    }

    // MARK: - 뜯기

    /// 답 꾸러미에서 **모델이 쓴 글자**를 꺼낸다. 제공자마다 자리가 다르다.
    ///
    /// ⚠ OpenAI 호환 게이트웨이 일부는 `content` 를 **조각 목록**으로 준다 — 문자열만
    /// 기대하면 그 게이트웨이에서 통째로 실패한다. 둘 다 받는다.
    public static func cloudText(from data: Data, provider: Provider) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        switch provider {
        case .anthropic:
            guard let blocks = json["content"] as? [[String: Any]] else { return nil }
            let text = blocks.compactMap { b -> String? in
                guard (b["type"] as? String) == "text" else { return nil }
                return b["text"] as? String
            }.joined()
            return text.isEmpty ? nil : text
        case .openai, .openrouter:
            guard let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any] else { return nil }
            if let s = message["content"] as? String, !s.isEmpty { return s }
            if let parts = message["content"] as? [[String: Any]] {
                let text = parts.compactMap { $0["text"] as? String }.joined()
                return text.isEmpty ? nil : text
            }
            return nil
        case .ollama:
            if let m = json["message"] as? [String: Any],
               let s = m["content"] as? String, !s.isEmpty { return s }
            if let s = json["response"] as? String, !s.isEmpty { return s }
            return nil
        }
    }

    /// 사고 꾸러미에서 사람이 읽을 한 줄. **키·본문은 안 싣는다** — 이 글자는 화면에 뜬다.
    public static func cloudErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let e = json["error"] as? [String: Any], let m = e["message"] as? String, !m.isEmpty {
            return String(m.prefix(140))
        }
        if let s = json["error"] as? String, !s.isEmpty { return String(s.prefix(140)) }
        if let s = json["message"] as? String, !s.isEmpty { return String(s.prefix(140)) }
        return nil
    }

    /// 모델이 쓴 글자 → **이야기 목록**. 못 뜯으면 `nil` (= 온디바이스로 물러설 신호).
    ///
    /// ★ **너그럽게 뜯는다.** 지시문이 「JSON 만」이라고 말해도 모델은 코드펜스를 두르거나
    /// 앞뒤에 한 줄을 붙인다. 그때마다 온디바이스로 물러서면 옵트인이 켜져 있어도 대개
    /// 안 쓰이게 된다 — 그래서 **첫 번째로 파싱되는 JSON 덩이**를 찾아 쓴다.
    /// ⚠ **받는 모양 셋**: `{"drafts":[…]}` · 벌거벗은 배열 `[…]` · 한 장짜리 `{"title":…}`.
    ///   목록이 비면 **빈 배열이지 `nil` 이 아니다** — 「이야기 없음」은 판정이다.
    /// ⚠ 제목·본문이 **둘 다** 빈 장은 버린다. 하나만 비는 것은 화면(`draftList`)이 메운다 —
    ///   그 자가 두 벌이 되면 온디바이스와 클라우드가 다른 규칙으로 메우게 된다.
    public static func cloudDrafts(fromText text: String, limit: Int = defaultLimit) -> [Draft]? {
        guard let any = cloudJSON(inText: text) else { return nil }
        let rows: [[String: Any]]
        if let obj = any as? [String: Any] {
            if let list = obj["drafts"] as? [[String: Any]] {
                rows = list
            } else if obj["title"] != nil || obj["body"] != nil {
                rows = [obj]
            } else {
                return nil
            }
        } else if let list = any as? [[String: Any]] {
            rows = list
        } else if any is [Any] {
            rows = []            // 벌거벗은 빈 배열 — 「이야기 없음」이다
        } else {
            return nil
        }
        let drafts = rows.map { row -> Draft in
            Draft(title: (row["title"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  body:  (row["body"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines))
        }.filter { !($0.title.isEmpty && $0.body.isEmpty) }
        return Array(drafts.prefix(max(0, limit)))
    }

    /// 글자 안에서 **처음으로 파싱되는 JSON 덩이**를 찾는다. 코드펜스·잡문을 건너뛴다.
    ///
    /// ⚠ 여는 괄호를 찾을 때마다 짝을 세어 잘라 보고, 안 되면 **다음 여는 괄호**로 간다.
    /// 문자열 안의 괄호와 `\"` 를 세면 안 되므로 따옴표 상태를 들고 센다.
    public static func cloudJSON(inText text: String) -> Any? {
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            guard c == "{" || c == "[" else { i += 1; continue }
            if let end = cloudMatch(chars, from: i),
               let data = String(chars[i...end]).data(using: .utf8),
               let any = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                return any
            }
            i += 1
        }
        return nil
    }

    /// 여는 괄호의 짝 자리. 없으면 `nil`.
    private static func cloudMatch(_ chars: [Character], from start: Int) -> Int? {
        var depth = 0
        var inString = false
        var escaped = false
        var i = start
        while i < chars.count {
            let c = chars[i]
            if inString {
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
            } else {
                switch c {
                case "\"": inString = true
                case "{", "[": depth += 1
                case "}", "]":
                    depth -= 1
                    if depth == 0 { return i }
                    if depth < 0 { return nil }
                default: break
                }
            }
            i += 1
        }
        return nil
    }
}
