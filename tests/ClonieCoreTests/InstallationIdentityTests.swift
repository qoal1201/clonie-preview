import Foundation
import XCTest
@testable import ClonieCore

final class InstallationIdentityTests: XCTestCase {
    private var defaults: UserDefaults!
    private var targetSuiteName: String!
    private var legacySuiteName: String!

    override func setUp() {
        targetSuiteName = "clonie-identity-target-\(UUID().uuidString)"
        legacySuiteName = "ghostbar-identity-legacy-\(UUID().uuidString)"
        // persistentDomain(forName:) 아래의 모든 읽기·쓰기를 UUID 도메인으로 격리한다.
        defaults = UserDefaults(suiteName: "clonie-identity-test-\(UUID().uuidString)")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: targetSuiteName)
        defaults.removePersistentDomain(forName: legacySuiteName)
        defaults = nil
    }

    private func migrate() {
        InstallationIdentity.migrateLegacyPreferences(
            bundleIdentifier: InstallationIdentity.productionBundleIdentifier,
            defaults: defaults,
            targetSuiteName: targetSuiteName,
            legacySuiteName: legacySuiteName
        )
    }

    func testNewValuesWinIncludingEmptyFalseAndZero() {
        defaults.setPersistentDomain([
            "legacyOnly": "kept",
            "sharedText": "old",
            "sharedFalse": true,
            "sharedZero": 7
        ], forName: legacySuiteName)
        defaults.setPersistentDomain([
            "sharedText": "",
            "sharedFalse": false,
            "sharedZero": 0
        ], forName: targetSuiteName)
        let legacyBefore = defaults.persistentDomain(forName: legacySuiteName)

        migrate()

        let target = defaults.persistentDomain(forName: targetSuiteName)
        XCTAssertEqual(target?["legacyOnly"] as? String, "kept")
        XCTAssertEqual(target?["sharedText"] as? String, "")
        XCTAssertEqual(target?["sharedFalse"] as? Bool, false)
        XCTAssertEqual(target?["sharedZero"] as? Int, 0)
        XCTAssertNotNil(target?[InstallationIdentity.migrationMarkerKey])
        let legacyAfter = defaults.persistentDomain(forName: legacySuiteName) ?? [:]
        XCTAssertEqual(legacyAfter["legacyOnly"] as? String, legacyBefore?["legacyOnly"] as? String)
        XCTAssertEqual(legacyAfter["sharedText"] as? String, legacyBefore?["sharedText"] as? String)
        XCTAssertEqual(legacyAfter["sharedFalse"] as? Bool, legacyBefore?["sharedFalse"] as? Bool)
        XCTAssertEqual(legacyAfter["sharedZero"] as? Int, legacyBefore?["sharedZero"] as? Int)
    }

    func testMigrationRunsOnceAndDoesNotResurrectDeletedValues() {
        defaults.setPersistentDomain(["old": "first"], forName: legacySuiteName)
        migrate()

        var target = defaults.persistentDomain(forName: targetSuiteName) ?? [:]
        target.removeValue(forKey: "old")
        defaults.setPersistentDomain(target, forName: targetSuiteName)
        defaults.setPersistentDomain(["old": "second", "newLater": true], forName: legacySuiteName)

        migrate()

        let after = defaults.persistentDomain(forName: targetSuiteName)
        XCTAssertNil(after?["old"])
        XCTAssertNil(after?["newLater"])
        XCTAssertNotNil(after?[InstallationIdentity.migrationMarkerKey])
    }

    func testMarkerIsWrittenWhenLegacyHasNoValues() {
        migrate()

        let target = defaults.persistentDomain(forName: targetSuiteName)
        XCTAssertEqual(target?.count, 1)
        XCTAssertNotNil(target?[InstallationIdentity.migrationMarkerKey])
    }

    func testQABundleUsesQALegacyIdentityAndUnknownBundleDoesNothing() {
        XCTAssertEqual(InstallationIdentity.legacyQABundleIdentifier, "com.local.ghostbar.qa")
        XCTAssertEqual(InstallationIdentity.qaBundleIdentifier, "com.local.clonie.qa")

        defaults.setPersistentDomain(["qaValue": "from-qa"], forName: legacySuiteName)
        InstallationIdentity.migrateLegacyPreferences(
            bundleIdentifier: InstallationIdentity.qaBundleIdentifier,
            defaults: defaults,
            targetSuiteName: targetSuiteName,
            legacySuiteName: legacySuiteName
        )
        XCTAssertEqual(defaults.persistentDomain(forName: targetSuiteName)?["qaValue"] as? String, "from-qa")

        defaults.removePersistentDomain(forName: targetSuiteName)
        defaults.setPersistentDomain(["value": "untouched"], forName: targetSuiteName)
        InstallationIdentity.migrateLegacyPreferences(
            bundleIdentifier: "com.local.unknown.\(UUID().uuidString)",
            defaults: defaults,
            targetSuiteName: targetSuiteName,
            legacySuiteName: legacySuiteName
        )
        XCTAssertEqual(defaults.persistentDomain(forName: targetSuiteName)?["value"] as? String, "untouched")
        XCTAssertNil(defaults.persistentDomain(forName: targetSuiteName)?[InstallationIdentity.migrationMarkerKey])
    }
}
