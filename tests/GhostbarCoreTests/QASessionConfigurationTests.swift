import XCTest
@testable import GhostbarCore

final class QASessionConfigurationTests: XCTestCase {
    func testQARequiresExplicitSessionAndAbsoluteVault() throws {
        XCTAssertThrowsError(try QASessionConfiguration(environment: [:]))
        XCTAssertThrowsError(try QASessionConfiguration(environment: ["GHOSTBAR_QA_SESSION": "qa-a", "GHOSTBAR_QA_VAULT": "/tmp/.."]))
        XCTAssertThrowsError(try QASessionConfiguration(environment: ["GHOSTBAR_QA_SESSION": "qa-a"]))
        XCTAssertThrowsError(try QASessionConfiguration(environment: ["GHOSTBAR_QA_SESSION": "../user", "GHOSTBAR_QA_VAULT": "/tmp/qa-vault"]))
        XCTAssertThrowsError(try QASessionConfiguration(environment: ["GHOSTBAR_QA_SESSION": "qa-a", "GHOSTBAR_QA_VAULT": "relative/vault"]))
    }

    func testSessionsCannotShareDriveSignalOrOutput() throws {
        let a = try QASessionConfiguration(environment: ["GHOSTBAR_QA_SESSION": "qa-a", "GHOSTBAR_QA_VAULT": "/tmp/a/vault"])
        let b = try QASessionConfiguration(environment: ["GHOSTBAR_QA_SESSION": "qa-b", "GHOSTBAR_QA_VAULT": "/tmp/b/vault"])
        XCTAssertEqual(a.signal("drive"), "com.local.ghostbar.qa.drive.qa-a")
        XCTAssertNotEqual(a.signal("drive"), "com.local.ghostbar.qa.drive")
        XCTAssertNotEqual(a.signal("drive"), b.signal("drive"))
        XCTAssertNotEqual(a.outputDirectory, b.outputDirectory)
        XCTAssertEqual(a.vaultURL, URL(fileURLWithPath: "/tmp/a/vault", isDirectory: true).resolvingSymlinksInPath())
    }
}
