import XCTest
@testable import ClonieMCP

/// 화면의 `eris` 와 **같은 세 점**을 잰다: 초록선 위 · 주황선 위 · 주황선 바로 아래.
/// 상수 값 자체가 화면과 같은지는 `tests/mcp-thresholds.test.mjs` 가 잰다 (정본은 JS).
final class ThresholdsTests: XCTestCase {
    func testNormalizedMakesGreenLineOne() {
        XCTAssertEqual(Thresholds.normalized(cosine: Thresholds.simGreenDirect), 1.0, accuracy: 1e-12)
    }

    func testLightMatchesScreenErisAtTheThreePoints() {
        XCTAssertEqual(Thresholds.light(normalized: 1.0), "g")
        XCTAssertEqual(Thresholds.light(normalized: Thresholds.simAmber), "a")
        XCTAssertEqual(Thresholds.light(normalized: Thresholds.simAmber - 1e-9), "r")
    }
}
