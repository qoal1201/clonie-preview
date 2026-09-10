import XCTest
@testable import ClonieCloud

/// 저장된 키가 **남의 주소로 안 나간다** — `BackendKeyRule` 자물쇠 (#65 ③ 잔여).
///
/// ## 이 파일이 왜 생겼나
///
/// 폐기 조건이 `type` 비교 하나였다. 그런데 `BackendType` 은 넷인데 화면의 프리셋 표는
/// 여덟이라 **OpenAI · NVIDIA NIM · llama.cpp · LM Studio · vLLM 다섯이 전부 `openai`** 다 —
/// 그 다섯 사이를 오가면 `type` 이 안 갈리고 앞 제공자의 키가 그대로 남아 **새 주소로 나갔다.**
/// 그리고 회신이 `hasKey: true` 라 새 제공자 화면이 「저장돼 있어요」라고 거짓말했다.
///
/// ⚠ **화면 쪽 배선은 `tests/backend-key.test.mjs` 가 잰다.** 여기는 마지막 문이다 —
/// 화면이 무엇을 싣든 저장을 실제로 하는 자는 이 판정 하나뿐이다.
///
/// ★ **무엇이 죽으면 이 파일이 빨개지나** (`정관 10조` — *"이게 꺼졌는지 어떻게 아나"*):
/// 사다리의 세 칸 중 하나라도 빠지면 빨개진다. 특히 `newURL != oldURL` 을 다시 걷으면
/// `testSameTypeDifferentURLDropsKey` 하나가 정확히 빨개진다 — 그게 이 파일의 이유다.
///
/// ⚠ 이름에 기대는 것은 **함수 이름까지**다. 줄 번호·인자 개수엔 안 기댄다
/// (`memory/feedback-selftest-cases-must-name-what-stays-unreal.md`).
final class BackendKeyRuleTests: XCTestCase {

    /// 아무것도 안 바뀐 저장 — 화면은 저장된 키를 되읽지 못하므로 **빈 칸은 「안 바꾼다」**다.
    private func unchanged(saved: String = "sk-저장된-키") -> String {
        BackendKeyRule.nextKey(saved: saved, typed: nil, clearRequested: false,
                               oldType: "openai", newType: "openai",
                               oldURL: "https://api.openai.com/v1",
                               newURL: "https://api.openai.com/v1")
    }

    // MARK: - 양성 대조 — 0건이 결론이 되지 않게

    func testUnchangedDestinationKeepsKey() {
        XCTAssertEqual(unchanged(), "sk-저장된-키",
                       "설정을 열었다 닫기만 해도 키가 날아간다")
    }

    // MARK: - ★ 이 파일이 있는 이유

    /// 같은 `type`, 다른 주소 — 프리셋 다섯이 공유하는 그 자리다.
    func testSameTypeDifferentURLDropsKey() {
        let got = BackendKeyRule.nextKey(
            saved: "sk-오픈에이아이-키", typed: nil, clearRequested: false,
            oldType: "openai", newType: "openai",
            oldURL: "https://api.openai.com/v1",
            newURL: "https://integrate.api.nvidia.com/v1")
        XCTAssertEqual(got, "", "앞 제공자의 키가 남아 **새 주소로 나간다**")
    }

    /// 프리셋 전환만이 아니라 **주소 칸을 손으로 고치는 길**도 같은 자리다.
    /// 화면이 `clearKey` 를 싣는 쪽으로 고쳤다면 이 칸이 안 막혔을 것이다.
    func testHandEditedURLDropsKey() {
        let got = BackendKeyRule.nextKey(
            saved: "sk-저장된-키", typed: nil, clearRequested: false,
            oldType: "openai", newType: "openai",
            oldURL: "http://localhost:1234/v1",
            newURL: "http://gpu.example.invalid:8000/v1")
        XCTAssertEqual(got, "")
    }

    // MARK: - 사다리의 순서가 뜻이다

    func testTypeChangeDropsKey() {
        let got = BackendKeyRule.nextKey(
            saved: "sk-저장된-키", typed: nil, clearRequested: false,
            oldType: "openai", newType: "anthropic",
            oldURL: "https://api.openai.com/v1",
            newURL: "https://api.anthropic.com/v1")
        XCTAssertEqual(got, "")
    }

    func testTypedKeyWinsOverDestinationChange() {
        let got = BackendKeyRule.nextKey(
            saved: "sk-옛-키", typed: "sk-새-키", clearRequested: false,
            oldType: "openai", newType: "openai",
            oldURL: "https://api.openai.com/v1",
            newURL: "https://integrate.api.nvidia.com/v1")
        XCTAssertEqual(got, "sk-새-키",
                       "제공자를 바꾸면서 새 키를 같이 친 사람의 키가 버려진다")
    }

    func testClearWinsOverEverything() {
        let got = BackendKeyRule.nextKey(
            saved: "sk-저장된-키", typed: "sk-치다-만-키", clearRequested: true,
            oldType: "openai", newType: "openai",
            oldURL: "https://api.openai.com/v1",
            newURL: "https://api.openai.com/v1")
        XCTAssertEqual(got, "", "「키 지우기」가 다른 칸에 졌다")
    }

    /// 빈 글자를 친 것은 **친 것이 아니다** — 화면이 안 실어 보내는 그 규약의 짝이다.
    func testEmptyTypedIsNotAKey() {
        let got = BackendKeyRule.nextKey(
            saved: "sk-저장된-키", typed: "", clearRequested: false,
            oldType: "openai", newType: "openai",
            oldURL: "https://api.openai.com/v1",
            newURL: "https://api.openai.com/v1")
        XCTAssertEqual(got, "sk-저장된-키")
    }
}
