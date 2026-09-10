import XCTest
@testable import ClonieMCP
@testable import ClonieCore

/// 우선순위 = 인자 → 환경변수 → 새 앱 UserDefaults → (미이관일 때) 이전 앱 UserDefaults → 기본 볼트.
/// 앱과 **같은 볼트**를 여는 것이 둘째 문의 전제라, 앱이 저장한 자리를 읽는 셋째 단이 핵심이다.
final class VaultLocatorTests: XCTestCase {
    private var suite: UserDefaults!
    private var suiteName: String!
    private var legacySuite: UserDefaults!
    private var legacySuiteName: String!

    override func setUp() {
        suiteName = "clonie-mcp-test-\(UUID().uuidString)"
        suite = UserDefaults(suiteName: suiteName)
        legacySuiteName = "ghostbar-mcp-test-\(UUID().uuidString)"
        legacySuite = UserDefaults(suiteName: legacySuiteName)
    }
    override func tearDown() {
        suite.removePersistentDomain(forName: suiteName)
        legacySuite.removePersistentDomain(forName: legacySuiteName)
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

    func testLegacyDefaultsAreUsedOnlyAfterNewDefaults() throws {
        legacySuite.set("/tmp/from-legacy", forKey: VaultLocator.appDefaultsKey)
        let url = try VaultLocator.resolve(argument: nil,
                                           environment: [:],
                                           defaults: suite,
                                           legacyDefaults: legacySuite)
        XCTAssertEqual(url.path, "/tmp/from-legacy")
    }

    func testNewDefaultsBeatLegacyDefaults() throws {
        suite.set("/tmp/from-new", forKey: VaultLocator.appDefaultsKey)
        legacySuite.set("/tmp/from-legacy", forKey: VaultLocator.appDefaultsKey)
        let url = try VaultLocator.resolve(argument: nil,
                                           environment: [:],
                                           defaults: suite,
                                           legacyDefaults: legacySuite)
        XCTAssertEqual(url.path, "/tmp/from-new")
    }

    func testMigrationMarkerDisablesLegacyFallback() throws {
        legacySuite.set("/tmp/from-legacy", forKey: VaultLocator.appDefaultsKey)
        suite.set(true, forKey: InstallationIdentity.migrationMarkerKey)
        let url = try VaultLocator.resolve(argument: nil,
                                           environment: [:],
                                           defaults: suite,
                                           legacyDefaults: legacySuite)
        XCTAssertTrue(url.path.hasSuffix("/Documents/Clonie"), url.path)
    }

    func testLegacyFallbackIsReadOnly() throws {
        legacySuite.set("/tmp/from-legacy", forKey: VaultLocator.appDefaultsKey)
        let before = legacySuite.persistentDomain(forName: legacySuiteName)
        _ = try VaultLocator.resolve(argument: nil,
                                     environment: [:],
                                     defaults: suite,
                                     legacyDefaults: legacySuite)
        let after = legacySuite.persistentDomain(forName: legacySuiteName) ?? [:]
        XCTAssertEqual(after[VaultLocator.appDefaultsKey] as? String,
                       before?[VaultLocator.appDefaultsKey] as? String)
    }

    func testDefaultLegacyArgumentDoesNotReadLegacySuite() throws {
        legacySuite.set("/tmp/from-legacy", forKey: VaultLocator.appDefaultsKey)
        let url = try VaultLocator.resolve(argument: nil, environment: [:], defaults: suite)
        XCTAssertTrue(url.path.hasSuffix("/Documents/Clonie"), url.path)
    }
}
