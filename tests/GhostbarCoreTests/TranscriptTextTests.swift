import XCTest
@testable import GhostbarCore

/// 전사기가 붙이는 문장부호를 검색 앞에서 걷는 것 하나만 잠근다.
///
/// **왜 이게 테스트할 값인가** — `실측 2026-08-28`(#15): 같은 문장인데 끝의 `?` 하나로
/// 정답 순위가 2위 → 3위로 밀렸다. 전사 글자는 하나도 안 틀렸는데(CER 0%) 순위만 밀렸고,
/// 부호를 걷으니 평균 1.7위 → 1.3위(텍스트 직접 입력과 동률)로 돌아왔다.
/// 근거 = `knowledge/audio-chain-latency.md`.
final class TranscriptTextTests: XCTestCase {

    /// ★ #15 가 실제로 잰 그 문장. 이 케이스가 이 파일의 존재 이유다.
    func testDropsTrailingQuestionMark() {
        XCTAssertEqual(
            TranscriptText.forSearch("실패했던 경험이 있다면 무엇을 배우셨나요?"),
            "실패했던 경험이 있다면 무엇을 배우셨나요")
    }

    func testDropsPeriodAndComma() {
        XCTAssertEqual(
            TranscriptText.forSearch("네, 안녕하세요. 반갑습니다."),
            "네 안녕하세요 반갑습니다")
    }

    /// 양성 대조의 반대 — **안 바꿔야 할 것은 안 바꾼다.** 이게 없으면
    /// 「전부 지운다」로 구현해도 위 두 케이스가 통과한다.
    func testLeavesCleanSentenceAlone() {
        let s = "일정이 촉박할 때는 어떻게 하시나요"
        XCTAssertEqual(TranscriptText.forSearch(s), s)
    }

    /// ⚠ 어절 사이 공백을 없애면 안 된다. 한국어에서 낱말이 붙으면 색인이 달라진다.
    func testKeepsWordSpacing() {
        XCTAssertEqual(TranscriptText.forSearch("주도적으로 문제를 해결한"),
                       "주도적으로 문제를 해결한")
    }

    /// 숫자는 남고 자릿점은 걷힌다. 수식 기호(`+`)는 부호가 아니라 **기호**라 남는다.
    func testKeepsDigitsAndMathSymbols() {
        XCTAssertEqual(TranscriptText.forSearch("2,154줄을 +3 늘렸다"),
                       "2154줄을 +3 늘렸다")
    }

    /// ⚠ **알고 두는 자리** — `%` 는 유니코드에서 기호가 아니라 **부호**(Po)라 같이 걷힌다.
    /// #15 가 잰 것이 `filter { !$0.isPunctuation }` 그대로이므로 **실측과 코드를 안 갈라놓는다.**
    /// 면접 질문에 `%` 가 들어갈 일이 드물어 지금은 값이 없다 — 걸리면 그때 재고 이 케이스를 뒤집는다.
    func testPercentSignIsDroppedToo() {
        XCTAssertEqual(TranscriptText.forSearch("전환율이 12% 올랐다"), "전환율이 12 올랐다")
    }

    func testTrimsEnds() {
        XCTAssertEqual(TranscriptText.forSearch("  들린 말  "), "들린 말")
    }

    func testEmptyStaysEmpty() {
        XCTAssertEqual(TranscriptText.forSearch(""), "")
        XCTAssertEqual(TranscriptText.forSearch("   "), "")
    }

    /// 부호만 온 볼라틸 조각. 검색에 넣을 것이 없으면 빈 문자열이어야 화면이 「기다린다」로 돈다.
    func testPunctuationOnlyBecomesEmpty() {
        XCTAssertEqual(TranscriptText.forSearch("…?!"), "")
    }
}
