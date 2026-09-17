import XCTest
@testable import ClonieCore

final class SessionDraftGroundingTests: XCTestCase {
    func testReproducedMalformedBudgetQuantityIsUnsupported() {
        let proposal = "프로젝트 예산을 3°50만 원으로 변경했다고 기록했다."
        let source = "프로젝트 예산을 350만 원으로 변경했다. 이정 기록에 320만 원은 확인됐다."

        XCTAssertEqual(
            SessionDraftGrounding.unsupportedQuantities(proposal: proposal, source: source),
            ["3°50만 원"]
        )
        XCTAssertEqual(
            SessionDraftGrounding.unsupportedQuantities(
                proposal: "프로젝트 예산을 350만 원으로 변경했다고 기록했다.",
                source: "프로젝트 예산을 3 50 만원으로 변경했다. 이정 기록에 320만 원은 확인됐다."
            ),
            []
        )
    }

    func testLineBreakDoesNotJoinTwoNumbers() {
        XCTAssertEqual(
            SessionDraftGrounding.unsupportedQuantities(
                proposal: "프로젝트 예산은 350만 원이다.",
                source: "프로젝트 예산은 3\n50 만원이다."
            ),
            ["350만 원"]
        )
        XCTAssertEqual(
            SessionDraftGrounding.unsupportedQuantities(
                proposal: "프로젝트 예산은 3\n50 만원이다.",
                source: "프로젝트 예산은 350만 원이다."
            ),
            ["3", "50 만원"]
        )
    }

    func testWhitespaceAndManWonSpellingAreEquivalent() {
        XCTAssertEqual(
            SessionDraftGrounding.unsupportedQuantities(
                proposal: "예산은 3 50 만원이다.",
                source: "예산은 350만 원이다."
            ),
            []
        )
        XCTAssertEqual(
            SessionDraftGrounding.unsupportedQuantities(
                proposal: "오류율은 8.0%이다.",
                source: "오류율은 8%이다."
            ),
            []
        )
    }

    func testDifferentValuesAndUnitFamiliesAreUnsupported() {
        XCTAssertEqual(
            SessionDraftGrounding.unsupportedQuantities(
                proposal: "예산 350만 원, 오류율 8.0%, 처리비 3500천 원.",
                source: "예산 320만 원, 오류율 0.8%, 처리비 3500만 원."
            ),
            ["350만 원", "8.0%", "3500천 원"]
        )
    }

    func testProposalWithoutQuantitiesIsAllowed() {
        XCTAssertEqual(
            SessionDraftGrounding.unsupportedQuantities(
                proposal: "이정 담당자가 승인 이유를 확인했다.",
                source: "이준 담당자가 승인 이유를 확인했다."
            ),
            []
        )
    }

    // Name transcription and entity matching are deliberately outside this
    // numeric grounding helper; those checks belong to the reviewer layer.
}
