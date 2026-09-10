import XCTest
import MCP
@testable import ClonieMCP

/// 배선만 잰다 — 모듈 셋이 서고 SDK 가 import 되나. 논리는 다른 파일이 잰다.
final class PackageWiringTests: XCTestCase {
    func testModulesLink() {
        XCTAssertEqual(ClonieMCPVersion.string, "0.1.1")
        // SDK 가 링크됐다는 증거 하나 — 타입이 보인다.
        _ = Server.self
    }
}
