import Foundation
import GhostbarCloud

/// 원문 한 덩이 → **이야기 0~3장, 이번엔 사용자의 백엔드로** (#51).
///
/// ★ **새 기능이 아니라 잠든 스택의 배선이다.** 제공자·URL·키는 상류가 남긴
/// `Config/BackendConfig.swift` 가 이미 들고 있고(설정창이 채운다), 그것을 읽어 쓴다.
/// 우리가 더한 것은 「받기 화면에서 이 길을 켤 수 있다」는 **옵트인 한 칸**뿐이다.
///
/// ⚠ **지시문은 여기서 안 짓는다.** `FragmentDrafter.instructions`·`soloPrompt`·
/// `askPrompt`·`mergedPrompt` 를 **그대로** 부른다 — 두 벌이 되면 온디바이스와 클라우드가
/// 서로 다른 것을 시키게 되고, 그러면 두 길의 결과를 견줄 수가 없다. 더하는 것은
/// 아래 `jsonClause` 한 문단뿐이고, 그게 필요한 이유는 딱 하나다: `@Generable` 이 없어
/// **모양을 글자로 요구해야** 한다.
///
/// ⚠ **면접 모드와 무관하다.** 이 길을 여는 화면은 받기(`ingestRender`) 하나이고
/// 그것은 통째로 쌓기 모드 안, 판정선 검사가 선언한 경계(`stackRender`) 밖이다 —
/// `sendMessage` 가 네트워크를 타면서도 판정선이 초록인 것과 **같은 구조**다.
///
/// ⚠ **진짜 키로 잰 적이 없다.** 그건 사람만 할 수 있다(에이전트가 유저의 키로 호출하면
/// 유저가 과금된다). 여기서 잰 것은 파싱과 목 HTTP 뿐이다 — `tests/GhostbarCloudTests/`.
enum CloudDrafter {

    /// 화면에 「켤 수 있나」를 알려 주는 짐. **키 자체는 절대 안 나간다.**
    struct Readiness {
        let ready:    Bool
        let provider: String     // 사람에게 보일 이름 (OpenAI · Anthropic …)
        let model:    String
        let why:      String     // 못 켜는 이유 한 줄. 켤 수 있으면 빈 글자
    }

    /// 클라우드 한 번의 결과. `fallback` 의 한 줄은 **화면 띠에 그대로 뜬다.**
    enum Outcome {
        case ok([FragmentDrafter.Draft])
        case fallback(String)
    }

    /// 설정에 적힌 것으로 이 길을 켤 수 있나.
    ///
    /// ⚠ **네트워크를 안 탄다** — `UserDefaults` 만 읽는다. 「연결 시험」은 설정창의 일이고
    /// 여기서 한 번 더 하면 창이 뜰 때마다 남의 서버를 두드린다.
    static func cloudReadiness() -> Readiness {
        let cfg = BackendConfig.current
        let model = (UserDefaults.standard.string(forKey: "selectedModel") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name: String
        switch cfg.type {
        case .ollama:     name = "Ollama"
        case .openai:     name = "OpenAI 호환 백엔드"
        case .anthropic:  name = "Anthropic"
        case .openrouter: name = "OpenRouter"
        }
        // ⚠ Ollama 는 이 맥(또는 내 서버)에서 도는 것이라 키가 없다 — 키를 요구하면
        //   로컬 백엔드를 쓰는 사람이 영영 못 켠다.
        if cfg.type != .ollama, cfg.apiKey.isEmpty {
            return Readiness(ready: false, provider: name, model: model,
                             why: "설정(⚙)에서 API 키를 넣으면 「더 좋은 정리」를 켤 수 있어요")
        }
        if cfg.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Readiness(ready: false, provider: name, model: model,
                             why: "설정(⚙)에서 백엔드 주소를 넣으면 「더 좋은 정리」를 켤 수 있어요")
        }
        if model.isEmpty {
            return Readiness(ready: false, provider: name, model: model,
                             why: "설정(⚙)에서 모델을 고르면 「더 좋은 정리」를 켤 수 있어요")
        }
        return Readiness(ready: true, provider: name, model: model, why: "")
    }

    /// 덩이 하나 → 이야기 0~3장. **던지지 않는다.**
    ///
    /// ⚠ 자(길이 바닥·입력 상한)와 지시문·물음은 **`OutsideDraft.plan` 하나가 짓는다**
    /// (#55 이 사다리에 CLI 층을 더하면서 뽑았다). 여기서 다른 수를 쓰면 같은 글이
    /// 켠 사람과 끈 사람에게, 또 키를 쓰는 사람과 CLI 를 쓰는 사람에게 다르게 잘린다.
    /// ⚠ **문지기(`StoryPresence`)를 따로 안 부른다.** 그 갈림은 4,096 토큰 문맥 창에서
    /// 「빠짐없이 뽑아라」와 「없으면 빈 목록」이 한 손잡이가 되던 것을 가른 장치다
    /// (`FragmentDrafter.StoryPresence` 머리글). 클라우드는 창이 넓어 한 번에 물어보고,
    /// 대신 `jsonClause` 가 「없으면 빈 목록」을 한 줄로 말한다.
    static func draftViaCloud(text: String,
                              parts: Int = 1,
                              ask: Bool = false,
                              session: URLSession = .shared) async -> Outcome {
        let ready = cloudReadiness()
        guard ready.ready else { return .fallback(ready.why) }

        let cfg = BackendConfig.current
        guard let provider = CloudDraftWire.Provider(rawValue: cfg.type.rawValue) else {
            return .fallback("이 백엔드로는 「더 좋은 정리」를 아직 못 보내요")
        }
        let instructions: String, prompt: String
        switch OutsideDraft.plan(text: text, parts: parts, ask: ask) {
        case .stop(let why):     return .fallback(why)
        case .none:              return .ok([])
        case .go(let i, let p):  instructions = i; prompt = p
        }
        guard let req = CloudDraftWire.cloudRequest(
                provider: provider,
                base: cfg.url,
                key: cfg.apiKey,
                model: ready.model,
                instructions: instructions,
                prompt: prompt) else {
            return .fallback("설정의 주소나 모델이 이상해요 — 설정(⚙)을 확인해 주세요")
        }
        switch await CloudDraftWire.cloudFetch(request: req,
                                               provider: provider,
                                               limit: FragmentDrafter.maxDrafts,
                                               session: session) {
        case .ok(let drafts):
            return .ok(drafts.map { FragmentDrafter.Draft(title: $0.title, body: $0.body) })
        case .fallback(let why):
            return .fallback(why)
        }
    }

    /// 지시문 한 벌 = **온디바이스 것 그대로 + 모양 요구 한 문단.**
    ///
    /// ⚠ 앞부분을 여기서 다시 쓰지 않는다(`FragmentDrafter.instructions`). 그것이
    /// 실측으로 조여 온 글자라, 베끼는 순간 한쪽만 고쳐지고 두 길이 갈린다.
    /// ⚠ **예시 문장을 안 적는다** — 안내문의 예시는 원문과 구별되지 않아 그대로
    /// 조각으로 나온다(`ExtractedStory` 머리글의 실측). 그래서 칸 이름만 적는다.
    static func cloudInstructions(parts: Int, ask: Bool) -> String {
        FragmentDrafter.instructions(parts: parts, ask: ask) + "\n\n" + jsonClause
    }

    /// `@Generable` 이 없는 자리를 메우는 문단. **여기가 클라우드에만 있는 유일한 글자다.**
    private static let jsonClause = """
        답은 **JSON 하나로만** 낸다. 설명·머리말·코드펜스를 붙이지 않는다.
        모양: {"drafts":[{"title":"제목 한 줄","body":"2~5문장"}]}
        - `drafts` 는 최대 \(FragmentDrafter.maxDrafts)개다.
        - 겪은 일이 하나도 서술돼 있지 않은 글이면 {"drafts":[]} 로 답한다. \
        목차·연락처·서류 안내·제목 나열이 그렇다.
        """
}

/// **바깥 층 둘이 같은 것을 시키게** 하는 한 자리 (#55 의 공급자 사다리).
///
/// 사다리는 위에서 아래로 셋이다 — ① 본인 키 클라우드(`CloudDrafter`, #51) ·
/// ② 설치된 공식 CLI(`CliDrafter`, #54) · ③ 온디바이스(`FragmentDrafter`).
/// ①과 ②는 **모양만 다르고 시키는 것은 같아야 한다**: 자(길이 바닥·입력 상한·장 수)도,
/// 지시문도, 물음도. 갈리면 「키를 넣은 사람」과 「CLI 를 깐 사람」이 서로 다른 앱을 쓰게 되고,
/// 그때부터 두 길의 결과를 견줄 수가 없다 — 그게 #51 부터 지켜 온 규율이다.
///
/// ⚠ **지시문을 여기서 짓지 않는다.** `CloudDrafter.cloudInstructions` 를 그대로 부르고,
/// 그것은 다시 `FragmentDrafter.instructions` 를 부른다. 정본은 언제나 온디바이스 쪽이다.
enum OutsideDraft {

    /// 이 덩이를 바깥 층으로 보낼 수 있나.
    /// - `go`: 보낸다. 딸린 둘이 **제공자 무관한 글자**다
    /// - `none`: 바닥 미만이라 안 보낸다 — 「이야기 없음」은 **판정이지 사고가 아니다**
    /// - `stop`: 아예 못 간다. 딸린 한 줄이 화면 띠에 그대로 뜬다
    enum Plan {
        case go(instructions: String, prompt: String)
        case none
        case stop(String)
    }

    static func plan(text: String, parts: Int, ask: Bool) -> Plan {
        let parts = min(max(parts, 1), FragmentDrafter.maxDrafts)
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return .stop("빈 글이라 만들 것이 없다") }
        let input = cleaned.count > FragmentDrafter.inputLimit
            ? String(cleaned.prefix(FragmentDrafter.inputLimit))
            : cleaned
        if input.count < FragmentDrafter.storyFloor { return .none }
        let prompt = parts > 1
            ? FragmentDrafter.mergedPrompt(parts: parts, input: input)
            : (ask ? FragmentDrafter.askPrompt(input: input)
                   : FragmentDrafter.soloPrompt(input: input))
        return .go(instructions: CloudDrafter.cloudInstructions(parts: parts, ask: ask),
                   prompt: prompt)
    }
}

/// ★ **사다리가 강제가 아니라 선택이 됐다** (박선호 2026-09-01: *"사디리를 해당순서로
/// 강제하는게 아니라 구독제가 있으면 구독제로 쓰는거고 api키가 있으면 api로 꼳아서 쓰는거고,
/// 연결을 해두고 따라 모델 선택 창이나 추론 선택창을 만들어서 유저가 원하는 모델을 물려서
/// 쓸수 있게 하는거지"*. 그가 답하던 질문 = 「구독 경로를 시험하려면 키를 먼저 지워야 한다」).
///
/// 위 `OutsideDraft` 머리글의 사다리(①키 → ②CLI → ③온디바이스)는 **`auto` 일 때의 내부
/// 순서로만** 남는다. 사람이 두뇌를 고르면 그 층 하나만 두드린다.
///
/// ⚠ **명시 선택은 조용히 안 샌다.** 고른 층이 죽어 있으면 다음 층으로 내려가지 않고
/// 화면이 정직하게 말한다 — 다른 데로 새는 것은 사람이 내린 결정을 뒤집는 것이다.
///
/// ★ **그럼 온디바이스는 언제 받나** (2026-09-02 정정 — 전 판은 *「`auto` 에서뿐」* 이라고
/// 적었고 그건 거짓이었다). 둘이다:
/// - **`auto` 의 사다리 끝** — 위 둘이 다 안 되면 그대로 내려온다. 이때만 화면도 토글을 끈다
///   (`cloudArmed`: `auto` 는 「아무 데도 안 걸렸다」가 곧 온디바이스라 헛왕복만 는다)
/// - 끄기를 사람이 직접 골랐을 때
///
/// ⚠ **명시 선택은 「죽어 보인다」로 안 내려온다** (2026-09-02, 리뷰 발견 ① 정정). 전 판은
/// *「고른 층이 죽어 있으면 `ready` 가 거짓이라 화면이 토글을 끄고 `cloud:false` 로 보낸다」*
/// 였는데, 그 `ready` 는 **`shownLane` — 마지막에 잰 로그인 자국**이 짓는 값이고 그 자국은
/// 낡는다. 그래서 터미널에서 방금 로그인하고 돌아온 사람이 `lane`(자국을 안 믿고 진짜로
/// 두드려 보는 쪽)에 **닿지도 못했다** — `lastLoggedIn` 머리글이 배려한다고 적어 둔 바로 그
/// 사람이다. 지금은 명시 선택이면 토글이 살아 있고, 진짜로 죽어 있으면 아래 `unavailable` 로
/// 떨어진다. **온디바이스가 몰래 받는 자리가 하나 줄었다.**
///
/// ⚠ **살아 있다고 보고 두드렸다 실패한 것은 온디바이스가 안 받는다.** 그건 `error:"unavailable"`
/// 로 나가고 화면이 **기계 자르기**로 채운다(`draftFragment` 머리글) — 고른 두뇌의 결과를
/// 다른 모델의 결과로 조용히 바꿔치지 않으려는 것이다.
enum DrafterChoice: String, CaseIterable {
    case auto, claude, codex, key

    /// `UserDefaults` 의 칸 하나. **네 값 밖은 안 앉는다**(`save`).
    static let storageKey = "drafterChoice"

    /// 화면에 뜨는 이름. ★ **정본이 여기 하나다** — 화면은 이 표를 `detectCli` 의 답에
    /// 실어 받는다(모델 목록·터미널 두 줄이 이미 그 길이다, #61 리뷰 발견 ④).
    var label: String {
        switch self {
        case .auto:   return "자동"
        case .claude: return "Claude 구독"
        case .codex:  return "Codex 구독"
        case .key:    return "API 키"
        }
    }

    /// 이 선택이 가리키는 CLI 벤더. `auto`·`key` 는 없다.
    /// ⚠ **`rawValue` 가 벤더 id 와 같아야 한다** — 그래서 이름을 박지 않고 **표를 찾아서**
    /// 답한다. 갈리면 여기가 `nil` 이 되고, 그러면 그 선택은 「연결 안 됨」으로 정직하게
    /// 떨어진다(조용히 다른 벤더로 새지 않는다).
    var vendor: CliDrafter.Vendor? { CliDrafter.vendors.first { $0.id == rawValue } }

    /// 지금 저장돼 있는 선택. **모르는 글자는 `auto` 다** — 옛 값·손으로 넣은 값이
    /// 앱을 세우지 않는다.
    static var current: DrafterChoice {
        DrafterChoice(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .auto
    }

    /// 화면이 고른 것을 저장한다. **네 값 밖은 그냥 안 저장한다** —
    /// `CliDrafter.saveTuning` 과 같은 규율이다(사고를 내지도, 기본값으로 덮지도 않는다).
    @discardableResult
    static func save(_ raw: String) -> Bool {
        guard let c = DrafterChoice(rawValue: raw) else { return false }
        UserDefaults.standard.set(c.rawValue, forKey: storageKey)
        return true
    }

    /// 지금 이 선택이 **실제로 두드릴 층**.
    ///
    /// ⚠ **로그인은 안 본다.** 그걸 알려면 남의 프로세스를 띄워야 하고 이 함수는 창이
    /// 뜰 때마다·저장할 때마다 돈다(`CliDrafter.cliReadiness` 와 같은 규율). 보는 것은
    /// 파일이 있나(`findBin`)와 `UserDefaults`(`cloudReadiness`)뿐이다.
    /// ★ **화면에 말할 때는 `shownLane` 이다** — 그쪽은 마지막에 잰 로그인 자국까지 본다.
    /// 이 갈림이 뜻하는 것: **두드리는 판정과 말하는 판정이 다르다.** 두드릴 때는 자국을
    /// 안 믿고 진짜로 두드려 보고, 말할 때는 아는 것을 다 쓴다.
    /// ⚠ `.device` 의 뜻이 **고른 것에 따라 다르다**: `auto` 면 「온디바이스로 내려간다」,
    /// 명시 선택이면 「고른 두뇌가 연결 안 됐다」다. 가르는 것은 부르는 쪽이다.
    enum Lane {
        case key
        case cli(CliDrafter.Vendor)
        case device
    }

    var lane: Lane { lane(loginAware: false) }

    /// **화면에 말할 때의 층.** `lane` 과 갈림이 같고, CLI 층에서 **마지막에 잰 로그인**까지 본다.
    ///
    /// ⚠ **왜 갈랐나** (2026-09-02, matt 2축 리뷰 P1): `lane` 이 로그인을 안 봐서, codex 를
    /// 골라 두고 로그아웃이면 받기 화면은 「Codex CLI 가 만들어요」(거짓)라 하고 설정 화면은
    /// 「로그인이 필요해요」(참)라 했다. **한 화면이 거짓말하는 것보다 두 화면이 갈리는 것이
    /// 나쁘다** — 어느 쪽을 믿을지 사람이 정할 수 없다.
    /// ⚠ **여기서 로그인을 재지 않는다.** 읽는 것은 `CliDrafter.lastLoggedIn` 의 자국뿐이고,
    /// **안 재 봤으면 안 깎는다**(`nil ≠ false`) — 모르는 것을 「로그아웃」으로 읽으면 설정
    /// 화면을 한 번도 안 연 사람에게 늘 「연결 안 됨」이라고 말하게 된다.
    /// ⚠ **두드리는 쪽은 `lane` 이다.** 자국은 낡을 수 있고, 터미널에서 방금 로그인하고 돌아온
    /// 사람의 층을 자국 하나로 지우면 안 된다 — 두드릴 때는 진짜로 두드려 본다.
    var shownLane: Lane { lane(loginAware: true) }

    private func lane(loginAware: Bool) -> Lane {
        /// 이 벤더가 지금 살아 있나. `loginAware` 면 **모르는 것은 산 것으로** 친다.
        func alive(_ v: CliDrafter.Vendor) -> Bool {
            guard CliDrafter.findBin(v) != nil else { return false }
            return loginAware ? CliDrafter.lastLoggedIn(v.id) != false : true
        }
        switch self {
        case .key:
            return CloudDrafter.cloudReadiness().ready ? .key : .device
        case .claude, .codex:
            if let v = vendor, alive(v) { return .cli(v) }
            return .device
        case .auto:
            if CloudDrafter.cloudReadiness().ready { return .key }
            for v in CliDrafter.vendors where alive(v) { return .cli(v) }
            return .device
        }
    }

    /// 「자동」이 **지금** 해석되는 곳의 이름표. 아무 데도 안 걸리면 **빈 글자**다.
    ///
    /// ★ **정본이 여기 하나다** (2026-09-02, matt 2축 리뷰 P1·H2). 전엔 화면(JS `autoWho`)이
    /// 이 판정을 **한 벌 더** 들었고, 둘이 갈려 있었다 — 저쪽은 「로그인된 첫 CLI」, 이쪽은
    /// 「깔린 첫 CLI」. 게다가 `"API 키(…)"` 라는 이름표를 화면이 **손으로 박고** 있었다
    /// (이름표의 집은 `label` 이다). 그래서 판정도 글자도 여기서 지어 화면에 실어 보낸다.
    /// ⚠ **`shownLane` 을 쓴다** — 화면에 말하는 글자라 로그인까지 본 쪽이 맞다.
    static var autoLabel: String {
        switch DrafterChoice.auto.shownLane {
        case .key:        return "\(DrafterChoice.key.label)(\(CloudDrafter.cloudReadiness().provider))"
        case .cli(let v): return v.name
        case .device:     return ""
        }
    }

    /// 고른 두뇌가 아예 연결 안 됐다. **화면 띠에 그대로 뜬다.**
    /// ⚠ 글자가 두 집에 있으면 한쪽만 고쳐진다 — 받기 화면의 안내(`sendCloudReady` 의 `why`)와
    /// 뽑기 실패(`draftFragment`)가 **같은 문장**을 쓴다.
    /// ⚠ **두 자리의 도달 빈도가 다르다.** 받기 화면 쪽이 늘 뜨는 자리고, `draftFragment` 쪽은
    /// **뽑는 도중에 설정이 바뀐 경우의 방어**다 — 평소엔 그 화면이 이 문장을 이미 띄우고
    /// 토글을 꺼서 뽑기가 `cloud:false` 로 온다. 그래도 안 지운다: 큐가 직렬이라 한 판이 분 단위고
    /// (`CliDrafter.timeout` 머리글), 그 사이에 사람이 설정을 여는 것은 **실제로 일어난다.**
    var notConnected: String {
        "선택한 두뇌(\(label))가 아직 연결 안 됐어요 — 설정(⚙)에서 확인해 주세요"
    }

    /// 연결은 됐는데 답을 못 냈다. 뒤에 그 층이 준 사유가 그대로 붙는다.
    func noAnswer(_ why: String) -> String {
        let tail = why.trimmingCharacters(in: .whitespacesAndNewlines)
        return "선택한 두뇌(\(label))가 답하지 않아요" + (tail.isEmpty ? "" : " — \(tail)")
    }
}
