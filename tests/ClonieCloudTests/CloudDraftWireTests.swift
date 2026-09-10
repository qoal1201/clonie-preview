import XCTest
@testable import ClonieCloud

/// 클라우드 전선 자물쇠 (#51) — **답 뜯기**와 **다녀오는 길**.
///
/// ⚠ **진짜 키로 안 잰다.** 유저의 키로 호출하면 유저가 과금되고, 그 판단은 사람의 것이다.
/// 그래서 여기서 재는 것은 둘뿐이다: ① 캔드 픽스처(제공자가 실제로 주는 모양)를 뜯나 ·
/// ② `URLProtocol` 목으로 요청→응답→뜯기가 한 줄로 도나. **살아 있는 API 와의 대조는
/// 사람이 하는 것이 남아 있다** — 이 초록은 「모양이 맞다」이지 「그 백엔드에서 된다」가 아니다.
///
/// ⚠ 자물쇠가 이름에 기대는 것은 **함수 이름까지**다 — 줄 번호·인자 개수에 안 기댄다
/// (`memory/feedback-selftest-cases-must-name-what-stays-unreal.md`).
final class CloudDraftWireTests: XCTestCase {

    // MARK: - 양성 대조

    /// 0건이 결론이 되지 않게: **되는 것 하나**를 같은 방법으로 먼저 통과시킨다.
    func testPlainJSONParses() {
        let got = CloudDraftWire.cloudDrafts(
            fromText: #"{"drafts":[{"title":"제목","body":"본문이다."}]}"#)
        XCTAssertEqual(got, [CloudDraftWire.Draft(title: "제목", body: "본문이다.")])
    }

    // MARK: - 뜯기: 모델이 지시를 안 지킬 때

    func testFencedJSONParses() {
        let text = """
            ```json
            {"drafts": [{"title": "제목", "body": "본문이다."}]}
            ```
            """
        XCTAssertEqual(CloudDraftWire.cloudDrafts(fromText: text),
                       [CloudDraftWire.Draft(title: "제목", body: "본문이다.")])
    }

    func testProseAroundJSONParses() {
        let text = """
            네, 아래와 같이 정리했습니다.

            {"drafts":[{"title":"제목","body":"본문이다."}]}

            더 필요하시면 말씀해 주세요.
            """
        XCTAssertEqual(CloudDraftWire.cloudDrafts(fromText: text)?.count, 1)
    }

    // MARK: - 뜯기: 설치된 공식 CLI 가 내는 모양 (#55 사다리 2층)

    /// ★ **이 뜯기가 두 벌이 되지 않게 여기서 잰다.** `CliDrafter`(앱 층)는 표준출력을
    /// 자기가 뜯지 않고 이 함수를 그대로 부른다 — executable 이라 `swift test` 가 못 부르는
    /// 자리라서 **여기가 그 층의 유일한 자물쇠**다. 픽스처는 #54 스파이크가 실제로 본 모양이다.
    ///
    /// ⚠ `실측 2026-08-31`(#54 스파이크): 「코드펜스를 붙이지 마라」는 지시문에도 모델이
    /// ```json 을 두른다. 그것 하나는 위 `testFencedJSONParses` 가 이미 잡고, 여기서 재는
    /// 것은 **CLI 가 얹는 것들**이다: 펜스에 언어표가 없는 판 · 펜스 뒤의 마무리 한 줄.
    func testCLIFenceWithoutLanguageTagParses() {
        let text = """
            ```
            {"drafts":[{"title":"크래시 40건을 6유형으로 갈랐다","body":"본문이다."}]}
            ```
            """
        XCTAssertEqual(CloudDraftWire.cloudDrafts(fromText: text),
                       [CloudDraftWire.Draft(title: "크래시 40건을 6유형으로 갈랐다", body: "본문이다.")])
    }

    /// 펜스 **앞뒤로** 말을 붙인 판. CLI 는 대화형 제품이라 이 모양이 클라우드보다 잦다.
    func testCLIFenceWithTrailingProseParses() {
        let text = """
            요청하신 대로 정리했습니다.

            ```json
            {"drafts":[{"title":"제목","body":"본문이다."}]}
            ```

            추가로 필요하신 것이 있으면 알려 주세요.
            """
        XCTAssertEqual(CloudDraftWire.cloudDrafts(fromText: text),
                       [CloudDraftWire.Draft(title: "제목", body: "본문이다.")])
    }

    /// 이야기가 없다고 판정한 CLI 답 — 펜스가 둘려도 **빈 목록이지 `nil` 이 아니다.**
    /// ⚠ 여기가 갈리면 목차·연락처 덩이마다 기계 자르기가 되살아난다.
    func testCLIFencedEmptyListIsAVerdict() {
        XCTAssertEqual(CloudDraftWire.cloudDrafts(fromText: "```json\n{\"drafts\":[]}\n```"), [])
    }

    /// CLI 가 로그인 안내나 사용법만 뱉은 판 — `nil` 이라야 사다리가 온디바이스로 내려간다.
    /// ⚠ **양성 대조와 짝이다**: 위 셋이 통과하는데 이것이 `nil` 이 아니면 뜯기가 너무 너그러운 것이다.
    func testCLIWithoutJSONIsNil() {
        XCTAssertNil(CloudDraftWire.cloudDrafts(
            fromText: "Invalid API key · Please run /login\nUsage: claude [options] [prompt]"))
    }

    // MARK: - 뜯기: 그 밖의 모양

    /// 벌거벗은 배열 — 모델이 `drafts` 껍데기를 빼먹는 흔한 모양.
    func testBareArrayParses() {
        let got = CloudDraftWire.cloudDrafts(fromText: #"[{"title":"가","body":"나"}]"#)
        XCTAssertEqual(got, [CloudDraftWire.Draft(title: "가", body: "나")])
    }

    /// 한 장만 낸 모양.
    func testSingleObjectParses() {
        XCTAssertEqual(CloudDraftWire.cloudDrafts(fromText: #"{"title":"가","body":"나"}"#),
                       [CloudDraftWire.Draft(title: "가", body: "나")])
    }

    /// ★ **빈 목록은 사고가 아니라 판정이다** — 「이 덩이엔 이야기가 없다」.
    /// `nil`(= 온디바이스로 물러섬)과 **다른 답**이어야 한다.
    func testEmptyListIsAVerdictNotAFailure() {
        XCTAssertEqual(CloudDraftWire.cloudDrafts(fromText: #"{"drafts":[]}"#), [])
        XCTAssertEqual(CloudDraftWire.cloudDrafts(fromText: "[]"), [])
    }

    /// JSON 이 아예 없으면 `nil` — 부르는 쪽이 그걸 「온디바이스로 가라」로 읽는다.
    func testNoJSONIsNil() {
        XCTAssertNil(CloudDraftWire.cloudDrafts(fromText: "죄송합니다. 그 요청은 도와드릴 수 없습니다."))
        XCTAssertNil(CloudDraftWire.cloudDrafts(fromText: ""))
        XCTAssertNil(CloudDraftWire.cloudDrafts(fromText: "{망가진 JSON"))
    }

    /// 우리 칸이 아닌 JSON 은 뜯은 척하지 않는다.
    func testForeignJSONIsNil() {
        XCTAssertNil(CloudDraftWire.cloudDrafts(fromText: #"{"answer":"네"}"#))
    }

    /// 본문에 중괄호·따옴표가 들어와도 짝이 안 어긋난다.
    func testBracesInsideStringsSurvive() {
        let text = #"{"drafts":[{"title":"함수 {a} 를 고쳤다","body":"\"닫는 괄호}\" 를 넣었다"}]}"#
        XCTAssertEqual(CloudDraftWire.cloudDrafts(fromText: text),
                       [CloudDraftWire.Draft(title: "함수 {a} 를 고쳤다", body: "\"닫는 괄호}\" 를 넣었다")])
    }

    /// 상한을 넘겨 주면 **자른다** — 모델이 넷을 내고 화면이 셋만 받는 조용한 손실을 막는다.
    func testLimitCuts() {
        let rows = (1...5).map { #"{"title":"제\#($0)","body":"본문\#($0)"}"# }.joined(separator: ",")
        XCTAssertEqual(CloudDraftWire.cloudDrafts(fromText: "{\"drafts\":[\(rows)]}", limit: 3)?.count, 3)
    }

    /// 제목·본문이 **둘 다** 빈 장은 버린다. 하나만 빈 것은 화면이 메운다 — 여기서 메우면 자가 두 벌이 된다.
    func testEmptyRowsDropped() {
        let text = #"{"drafts":[{"title":"","body":""},{"title":" 가 ","body":""},{"body":"나"}]}"#
        XCTAssertEqual(CloudDraftWire.cloudDrafts(fromText: text),
                       [CloudDraftWire.Draft(title: "가", body: ""),
                        CloudDraftWire.Draft(title: "", body: "나")])
    }

    // MARK: - 뜯기: 제공자마다 글자가 어디 있나

    func testOpenAIShape() {
        let data = Data(#"{"choices":[{"message":{"role":"assistant","content":"본문"}}]}"#.utf8)
        XCTAssertEqual(CloudDraftWire.cloudText(from: data, provider: .openai), "본문")
        XCTAssertEqual(CloudDraftWire.cloudText(from: data, provider: .openrouter), "본문")
    }

    /// ⚠ 게이트웨이 일부는 `content` 를 **조각 목록**으로 준다. 문자열만 기대하면 그 백엔드가 통째로 죽는다.
    func testOpenAIPartsShape() {
        let data = Data(#"{"choices":[{"message":{"content":[{"type":"text","text":"본"},{"type":"text","text":"문"}]}}]}"#.utf8)
        XCTAssertEqual(CloudDraftWire.cloudText(from: data, provider: .openai), "본문")
    }

    func testAnthropicShape() {
        let data = Data(#"{"content":[{"type":"thinking","thinking":"음"},{"type":"text","text":"본문"}],"stop_reason":"end_turn"}"#.utf8)
        XCTAssertEqual(CloudDraftWire.cloudText(from: data, provider: .anthropic), "본문")
    }

    func testOllamaShape() {
        let chat = Data(#"{"message":{"role":"assistant","content":"본문"},"done":true}"#.utf8)
        XCTAssertEqual(CloudDraftWire.cloudText(from: chat, provider: .ollama), "본문")
        let generate = Data(#"{"response":"본문","done":true}"#.utf8)
        XCTAssertEqual(CloudDraftWire.cloudText(from: generate, provider: .ollama), "본문")
    }

    func testWrongShapeIsNil() {
        XCTAssertNil(CloudDraftWire.cloudText(from: Data("not json".utf8), provider: .openai))
        XCTAssertNil(CloudDraftWire.cloudText(from: Data(#"{"choices":[]}"#.utf8), provider: .openai))
    }

    func testErrorMessageExtraction() {
        let openai = Data(#"{"error":{"message":"Incorrect API key provided","type":"invalid_request_error"}}"#.utf8)
        XCTAssertEqual(CloudDraftWire.cloudErrorMessage(from: openai), "Incorrect API key provided")
        let ollama = Data(#"{"error":"model not found"}"#.utf8)
        XCTAssertEqual(CloudDraftWire.cloudErrorMessage(from: ollama), "model not found")
        XCTAssertNil(CloudDraftWire.cloudErrorMessage(from: Data("<html>502</html>".utf8)))
    }

    // MARK: - 요청 짓기

    func testRequestPathsAndHeaders() throws {
        let openai = try XCTUnwrap(CloudDraftWire.cloudRequest(
            provider: .openai, base: "https://example.invalid/v1/", key: "K", model: "m",
            instructions: "지시", prompt: "글"))
        XCTAssertEqual(openai.url?.absoluteString, "https://example.invalid/v1/chat/completions")
        XCTAssertEqual(openai.value(forHTTPHeaderField: "Authorization"), "Bearer K")

        let anthropic = try XCTUnwrap(CloudDraftWire.cloudRequest(
            provider: .anthropic, base: "https://example.invalid/v1", key: "K", model: "m",
            instructions: "지시", prompt: "글"))
        XCTAssertEqual(anthropic.url?.absoluteString, "https://example.invalid/v1/messages")
        XCTAssertEqual(anthropic.value(forHTTPHeaderField: "x-api-key"), "K")
        XCTAssertEqual(anthropic.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")

        let ollama = try XCTUnwrap(CloudDraftWire.cloudRequest(
            provider: .ollama, base: "http://localhost:11434", key: "", model: "m",
            instructions: "지시", prompt: "글"))
        XCTAssertEqual(ollama.url?.absoluteString, "http://localhost:11434/api/chat")
        XCTAssertNil(ollama.value(forHTTPHeaderField: "Authorization"), "키가 없는데 헤더가 붙었다")
    }

    /// ★ **키는 URL 에 절대 안 실린다.** 주소는 로그·프록시에 남는다.
    func testKeyNeverInURL() throws {
        for provider in [CloudDraftWire.Provider.openai, .anthropic, .ollama, .openrouter] {
            let req = try XCTUnwrap(CloudDraftWire.cloudRequest(
                provider: provider, base: "https://example.invalid/v1", key: "sk-SECRET", model: "m",
                instructions: "지시", prompt: "글"))
            XCTAssertFalse(req.url?.absoluteString.contains("SECRET") ?? true,
                           "\(provider) 의 URL 에 키가 실렸다")
        }
    }

    /// 지시문과 이번 글이 **갈린 채로** 실린다 — 섞으면 원문 안의 명령형이 지시로 읽힌다.
    func testInstructionsAndPromptGoInSeparateSlots() throws {
        let req = try XCTUnwrap(CloudDraftWire.cloudRequest(
            provider: .anthropic, base: "https://example.invalid/v1", key: "K", model: "m",
            instructions: "지시문", prompt: "이번 글"))
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(req.httpBody))
                                    as? [String: Any])
        XCTAssertEqual(body["system"] as? String, "지시문")
        let msgs = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(msgs.first?["content"] as? String, "이번 글")

        let oa = try XCTUnwrap(CloudDraftWire.cloudRequest(
            provider: .openai, base: "https://example.invalid/v1", key: "K", model: "m",
            instructions: "지시문", prompt: "이번 글"))
        let oaBody = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(oa.httpBody))
                                      as? [String: Any])
        let oaMsgs = try XCTUnwrap(oaBody["messages"] as? [[String: Any]])
        XCTAssertEqual(oaMsgs.map { $0["role"] as? String }, ["system", "user"])
        XCTAssertEqual(oaBody["stream"] as? Bool, false, "스트리밍이 켜진 채로 나갔다 — 한 번에 받는 길이다")
    }

    func testEmptyBaseOrModelMakesNoRequest() {
        XCTAssertNil(CloudDraftWire.cloudRequest(provider: .openai, base: "", key: "K", model: "m",
                                                 instructions: "지시", prompt: "글"))
        XCTAssertNil(CloudDraftWire.cloudRequest(provider: .openai, base: "https://example.invalid/v1",
                                                 key: "K", model: "", instructions: "지시", prompt: "글"))
    }

    /// 낱말이 갈리면 클라우드가 **안 켜진다**(조용히 다른 데로 보내지 않는다).
    func testProviderNamesMatchBackendTypeRawValues() {
        for raw in ["ollama", "openai", "anthropic", "openrouter"] {
            XCTAssertNotNil(CloudDraftWire.Provider(rawValue: raw), "\(raw) 를 못 알아본다")
        }
        XCTAssertNil(CloudDraftWire.Provider(rawValue: "gemini"))
    }

    // MARK: - 다녀오는 길 (목 HTTP)

    func testFetchHappyPath() async throws {
        let payload = #"{"choices":[{"message":{"content":"```json\n{\"drafts\":[{\"title\":\"제\",\"body\":\"본\"}]}\n```"}}]}"#
        MockProtocol.reply = .init(status: 200, body: Data(payload.utf8))
        let req = try XCTUnwrap(CloudDraftWire.cloudRequest(
            provider: .openai, base: "https://example.invalid/v1", key: "K", model: "m",
            instructions: "지시", prompt: "글"))
        let out = await CloudDraftWire.cloudFetch(request: req, provider: .openai,
                                                  session: MockProtocol.session())
        XCTAssertEqual(out, .ok([CloudDraftWire.Draft(title: "제", body: "본")]))
    }

    /// ★ 키가 틀렸을 때 — **사유가 사람 말로 오고, 거기 키가 없다.**
    func testFetchHTTPErrorFallsBack() async throws {
        MockProtocol.reply = .init(status: 401,
                                   body: Data(#"{"error":{"message":"Incorrect API key provided"}}"#.utf8))
        let req = try XCTUnwrap(CloudDraftWire.cloudRequest(
            provider: .openai, base: "https://example.invalid/v1", key: "sk-SECRET", model: "m",
            instructions: "지시", prompt: "글"))
        let out = await CloudDraftWire.cloudFetch(request: req, provider: .openai,
                                                  session: MockProtocol.session())
        guard case .fallback(let why) = out else { return XCTFail("401 인데 폴백이 아니다: \(out)") }
        XCTAssertTrue(why.contains("401"), why)
        XCTAssertTrue(why.contains("Incorrect API key provided"), why)
        XCTAssertFalse(why.contains("SECRET"), "사유 한 줄에 키가 샜다")
    }

    func testFetchNetworkErrorFallsBack() async throws {
        MockProtocol.reply = .init(error: URLError(.notConnectedToInternet))
        let req = try XCTUnwrap(CloudDraftWire.cloudRequest(
            provider: .openai, base: "https://example.invalid/v1", key: "K", model: "m",
            instructions: "지시", prompt: "글"))
        let out = await CloudDraftWire.cloudFetch(request: req, provider: .openai,
                                                  session: MockProtocol.session())
        guard case .fallback = out else { return XCTFail("끊긴 망인데 폴백이 아니다: \(out)") }
    }

    /// 200 인데 JSON 이 아닌 답 — 그것도 폴백이다(온디바이스가 받는다).
    func testFetchUnparseableFallsBack() async throws {
        MockProtocol.reply = .init(status: 200,
                                   body: Data(#"{"choices":[{"message":{"content":"미안해요, 못 하겠어요"}}]}"#.utf8))
        let req = try XCTUnwrap(CloudDraftWire.cloudRequest(
            provider: .openai, base: "https://example.invalid/v1", key: "K", model: "m",
            instructions: "지시", prompt: "글"))
        let out = await CloudDraftWire.cloudFetch(request: req, provider: .openai,
                                                  session: MockProtocol.session())
        guard case .fallback = out else { return XCTFail("못 뜯는 답인데 폴백이 아니다: \(out)") }
    }

    /// 「이야기 없음」은 **폴백이 아니다** — 온디바이스로 다시 돌리면 2판이 없앤 쓰레기가 돌아온다.
    func testFetchEmptyVerdictIsOK() async throws {
        MockProtocol.reply = .init(status: 200,
                                   body: Data(#"{"choices":[{"message":{"content":"{\"drafts\":[]}"}}]}"#.utf8))
        let req = try XCTUnwrap(CloudDraftWire.cloudRequest(
            provider: .openai, base: "https://example.invalid/v1", key: "K", model: "m",
            instructions: "지시", prompt: "글"))
        let out = await CloudDraftWire.cloudFetch(request: req, provider: .openai,
                                                  session: MockProtocol.session())
        XCTAssertEqual(out, .ok([]))
    }
}

/// 목 서버 — 진짜 키·진짜 망 없이 **다녀오는 길**만 잰다.
final class MockProtocol: URLProtocol {
    struct Reply {
        var status: Int = 200
        var body: Data = Data()
        var error: URLError? = nil
        init(status: Int = 200, body: Data = Data()) { self.status = status; self.body = body }
        init(error: URLError) { self.error = error }
    }
    nonisolated(unsafe) static var reply = Reply()

    static func session() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockProtocol.self]
        return URLSession(configuration: cfg)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let reply = MockProtocol.reply
        if let e = reply.error {
            client?.urlProtocol(self, didFailWithError: e)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }
}
