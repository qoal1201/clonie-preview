import Foundation
import XCTest
@testable import ClonieMCP

final class RelayConnectionTests: XCTestCase {
    func testOnlyHTTPSOrExplicitNumericLoopbackAcceptsCredentials() throws {
        func config(_ endpoint: String, local: Bool = false) throws -> RelayConfiguration {
            try .init(endpoint: URL(string: endpoint)!, deviceID: UUID(), vaultID: UUID(),
                      clientID: "chat", allowProposals: false, allowLoopback: local)
        }
        for url in ["http://example.com", "http://127.0.0.1:3000", "https://user:pass@example.com",
                    "https://example.com/path", "https://example.com?key=x", "https://example.com#x"] {
            XCTAssertThrowsError(try config(url))
        }
        XCTAssertThrowsError(try config("http://localhost:3000", local: true))
        _ = try config("https://relay.example.com")
        _ = try config("http://127.0.0.1:3000", local: true)
    }

    func testMacRejectsUnknownToolsExpiredJobsAndUnapprovedProposals() throws {
        let now = Date()
        func job(_ name: String, deadline: Double? = nil) -> RelayJob {
            .init(id: UUID(), name: name, arguments: [:],
                  deadline: deadline ?? now.addingTimeInterval(25).timeIntervalSince1970 * 1000)
        }
        for name in ["apply_proposal", "shell", "vault_write"] {
            XCTAssertThrowsError(try job(name).validate(allowProposals: false, now: now))
        }
        XCTAssertThrowsError(try job("vault_read", deadline: now.timeIntervalSince1970 * 1000).validate(allowProposals: true, now: now))
        XCTAssertThrowsError(try job("vault_read", deadline: now.addingTimeInterval(61).timeIntervalSince1970 * 1000).validate(allowProposals: true, now: now))
        XCTAssertThrowsError(try job("vault_read", deadline: .infinity).validate(allowProposals: true, now: now))
        try job("vault_read").validate(allowProposals: false, now: now)
        try job("vault_write").validate(allowProposals: true, now: now)
    }
}
