import XCTest
@testable import ClonieCore

final class RetrievalAnchorsTests: XCTestCase {
    func testExactQuantitiesDoNotConfuseDecimalOrderOrDigitSubstrings() {
        XCTAssertEqual(RetrievalAnchors.coverage(query: "오류율 8.0%", source: "오류율 0.8%"), 0)
        XCTAssertEqual(RetrievalAnchors.coverage(query: "표본 230개", source: "표본 1230개"), 0)
        XCTAssertEqual(RetrievalAnchors.coverage(query: "R17의 복구", source: "R71 배포"), 0)
    }
    func testEquivalentWrittenUnitsMatchWithoutCorrectingDifferentAmounts() {
        XCTAssertEqual(RetrievalAnchors.coverage(query: "320만원", source: "3,200,000원"), 1)
        XCTAssertEqual(RetrievalAnchors.coverage(query: "320만원", source: "320,000원"), 0)
        XCTAssertEqual(RetrievalAnchors.coverage(query: "8.0퍼센트 K2 250ms", source: "8% k2 250밀리초"), 1)
    }
    func testBonusIsBoundedAndDoesNotChangeUnanchoredSearch() {
        XCTAssertEqual(RetrievalAnchors.orderScore(cosine: 0.8, query: "협업", source: "협업 사례"), 0.8)
        XCTAssertLessThan(RetrievalAnchors.orderScore(cosine: 0.5, query: "R17", source: "R17"), 0.8)
        XCTAssertGreaterThan(RetrievalAnchors.orderScore(cosine: 0.79, query: "R17", source: "R17"), 0.8)
    }
}
