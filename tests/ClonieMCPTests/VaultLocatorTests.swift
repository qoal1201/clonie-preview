import XCTest
@testable import ClonieMCP

/// 우선순위 = 인자 → 환경변수 → 앱 UserDefaults(`com.local.ghostbar` / `vaultPath`) → `~/Documents/Clonie`.
/// 앱과 **같은 볼트**를 여는 것이 둘째 문의 전제라, 앱이 저장한 자리를 읽는 셋째 단이 핵심이다.
final class VaultLocatorTests: XCTestCase {
    private var suite: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        suiteName = "clonie-mcp-test-\(UUID().uuidString)"
        suite = UserDefaults(suiteName: suiteName)
    }
    override func tearDown() {
        suite.removePersistentDomain(forName: suiteName)
    }

    func testArgumentWins() throws {
        suite.set("/tmp/from-defaults", forKey: VaultLocator.appDefaultsKey)
        let url = try VaultLocator.resolve(argument: "/tmp/from-arg",
                                           environment: [VaultLocator.environmentKey: "/tmp/from-env"],
                                           defaults: suite)
        XCTAssertEqual(url.path, "/tmp/from-arg")
    }

    func testEnvironmentBeatsDefaults() throws {
        suite.set("/tmp/from-defaults", forKey: VaultLocator.appDefaultsKey)
        let url = try VaultLocator.resolve(argument: nil,
                                           environment: [VaultLocator.environmentKey: "/tmp/from-env"],
                                           defaults: suite)
        XCTAssertEqual(url.path, "/tmp/from-env")
    }

    func testAppDefaultsAreRead() throws {
        suite.set("/tmp/from-defaults", forKey: VaultLocator.appDefaultsKey)
        let url = try VaultLocator.resolve(argument: nil, environment: [:], defaults: suite)
        XCTAssertEqual(url.path, "/tmp/from-defaults")
    }

    func testEmptyStringsAreNotChoices() throws {
        // .mcpb 가 빈 칸을 `--vault ""` 로 넘길 수 있다 — 빈 글자는 「안 줬다」다.
        suite.set("", forKey: VaultLocator.appDefaultsKey)
        let url = try VaultLocator.resolve(argument: "", environment: [VaultLocator.environmentKey: ""], defaults: suite)
        XCTAssertTrue(url.path.hasSuffix("/Documents/Clonie"), url.path)
    }

    func testUnfilledMcpbPlaceholderIsNotAChoice() throws {
        // .mcpb 의 볼트 칸을 비워 두면 Claude Desktop 이 치환 안 된 자리표시자를
        // 그대로 넘길 수 있다 — 빈 글자와 같은 「안 줬다」로 다뤄야 한다.
        suite.set("/tmp/from-defaults", forKey: VaultLocator.appDefaultsKey)
        let url = try VaultLocator.resolve(argument: "${user_config.vault}", environment: [:], defaults: suite)
        XCTAssertEqual(url.path, "/tmp/from-defaults")
    }

    func testTildeExpands() throws {
        let url = try VaultLocator.resolve(argument: "~/somewhere", environment: [:], defaults: suite)
        XCTAssertFalse(url.path.contains("~"))
        XCTAssertTrue(url.path.hasSuffix("/somewhere"))
    }
}
