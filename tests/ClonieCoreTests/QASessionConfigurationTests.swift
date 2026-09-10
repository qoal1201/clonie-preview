import XCTest
@testable import ClonieCore

final class QASessionConfigurationTests: XCTestCase {
    func testQARequiresExplicitSessionAndAbsoluteVault() throws {
        XCTAssertThrowsError(try QASessionConfiguration(environment: [:]))
        XCTAssertThrowsError(try QASessionConfiguration(environment: ["CLONIE_QA_SESSION": "qa-a", "CLONIE_QA_VAULT": "/tmp/.."]))
        XCTAssertThrowsError(try QASessionConfiguration(environment: ["CLONIE_QA_SESSION": "qa-a"]))
        XCTAssertThrowsError(try QASessionConfiguration(environment: ["CLONIE_QA_SESSION": "../user", "CLONIE_QA_VAULT": "/tmp/qa-vault"]))
        XCTAssertThrowsError(try QASessionConfiguration(environment: ["CLONIE_QA_SESSION": "qa-a", "CLONIE_QA_VAULT": "relative/vault"]))
    }

    func testSessionsCannotShareDriveSignalOrOutput() throws {
        let a = try QASessionConfiguration(environment: ["CLONIE_QA_SESSION": "qa-a", "CLONIE_QA_VAULT": "/tmp/a/vault"])
        let b = try QASessionConfiguration(environment: ["CLONIE_QA_SESSION": "qa-b", "CLONIE_QA_VAULT": "/tmp/b/vault"])
        XCTAssertEqual(a.signal("drive"), "com.local.clonie.qa.drive.qa-a")
        XCTAssertNotEqual(a.signal("drive"), "com.local.clonie.qa.drive")
        XCTAssertNotEqual(a.signal("drive"), b.signal("drive"))
        XCTAssertNotEqual(a.outputDirectory, b.outputDirectory)
        XCTAssertEqual(a.vaultURL, URL(fileURLWithPath: "/tmp/a/vault", isDirectory: true).resolvingSymlinksInPath())
    }
}
