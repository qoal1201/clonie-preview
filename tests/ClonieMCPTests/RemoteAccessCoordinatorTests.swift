import Foundation
import XCTest
@testable import ClonieMCP

@MainActor
final class RemoteAccessCoordinatorTests: XCTestCase {
    func testLockedKeychainFailureKeepsLogoutRetryAvailable() async throws {
        struct Locked: RemoteCredentialStore {
            func load() throws -> String? { throw RemoteLoginError.keychain }
            func save(_ value: String) throws { throw RemoteLoginError.keychain }
            func clear() throws { throw RemoteLoginError.keychain }
        }
        let session = RemoteLoginSession(configuration: try remoteTestConfiguration(), storage: Locked()) { _ in
            XCTFail("locked credentials sent a request"); return Data()
        }
        let access = RemoteAccessCoordinator(session: session, vaultURL: URL(fileURLWithPath: "/tmp/first")) { _, _, _, _ in }
        await access.stop(signOut: true)
        XCTAssertEqual(access.state.phase, "ready")
        XCTAssertTrue(access.state.canDisconnect)
        XCTAssertFalse(access.state.message.isEmpty)
    }

    func testFolderSwitchWaitsForOldRunAndRejectsOldConsent() async throws {
        let started = expectation(description: "old worker started")
        let stopped = expectation(description: "old worker cleanup finished")
        let store = MemoryRemoteCredentials("refresh")
        let session = RemoteLoginSession(configuration: try remoteTestConfiguration(), storage: store) { _ in remoteTokenResponse() }
        var lastPath = ""
        let access = RemoteAccessCoordinator(session: session, vaultURL: URL(fileURLWithPath: "/tmp/first")) {
            url, allow, token, connected in
            XCTAssertEqual(url, URL(fileURLWithPath: "/tmp/first").standardizedFileURL.resolvingSymlinksInPath())
            XCTAssertFalse(allow)
            _ = try await token()
            await connected(UUID()); started.fulfill()
            do { try await Task.sleep(for: .seconds(30)) } catch {}
            // Simulate non-cancellable, bounded server revocation after cancellation.
            await Task.detached { try? await Task.sleep(for: .milliseconds(20)) }.value
            stopped.fulfill()
        }
        access.didChange = { lastPath = $0.vaultPath }
        let ticket = access.state.consentID
        access.connect(consentID: ticket, allowProposals: false) { _ in XCTFail("saved session opened browser"); throw RemoteLoginError.denied }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertEqual(access.state.phase, "connected")
        await access.selectVault(URL(fileURLWithPath: "/tmp/second"))
        await fulfillment(of: [stopped], timeout: 1)
        XCTAssertEqual(lastPath, URL(fileURLWithPath: "/tmp/second").standardizedFileURL.resolvingSymlinksInPath().path)
        XCTAssertEqual(access.state.phase, "ready")
        access.connect(consentID: ticket, allowProposals: true) { _ in XCTFail("old ticket started login"); throw RemoteLoginError.denied }
        XCTAssertEqual(access.state.phase, "ready")
        XCTAssertNotEqual(ticket, access.state.consentID)
    }

    func testCancelWhileLoggingInNeverStartsWorkerAndLateCallbackCannotReviveIt() async throws {
        let opened = expectation(description: "browser opened")
        let store = MemoryRemoteCredentials()
        let session = RemoteLoginSession(configuration: try remoteTestConfiguration(), storage: store) { _ in
            XCTFail("cancelled login exchanged a token"); return remoteTokenResponse()
        }
        let access = RemoteAccessCoordinator(session: session, vaultURL: URL(fileURLWithPath: "/tmp/first")) { _, _, _, _ in
            XCTFail("cancelled approval started worker")
        }
        access.connect(consentID: access.state.consentID, allowProposals: true) { url in
            opened.fulfill()
            do { try await Task.sleep(for: .seconds(30)) } catch {}
            return url // A misbehaving browser returns after cancellation.
        }
        await fulfillment(of: [opened], timeout: 2)
        await access.stop(signOut: true)
        XCTAssertEqual(access.state.phase, "ready")
        XCTAssertNil(try store.load())
    }
}
