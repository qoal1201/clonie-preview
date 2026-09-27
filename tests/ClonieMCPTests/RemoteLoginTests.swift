import Foundation
import XCTest
@testable import ClonieMCP

final class MemoryRemoteCredentials: RemoteCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    init(_ value: String? = nil) { self.value = value }
    func load() throws -> String? { lock.lock(); defer { lock.unlock() }; return value }
    func save(_ token: String) throws { lock.lock(); defer { lock.unlock() }; value = token }
    func clear() throws { lock.lock(); defer { lock.unlock() }; value = nil }
}

func remoteTestConfiguration() throws -> RemoteServiceConfiguration {
    try .init(relay: URL(string: "https://relay.example.test")!, issuer: URL(string: "https://login.example.test/")!,
              desktopClientID: "native", chatClientID: "chat")
}
func remoteTokenResponse(access: String = "access", refresh: String = "rotated", expires: Int = 3600) -> Data {
    try! JSONSerialization.data(withJSONObject: ["access_token": access, "refresh_token": refresh,
        "expires_in": expires, "token_type": "Bearer", "scope": "clonie:device"])
}
func remoteCallback(_ attempt: RemoteLoginAttempt, code: String = "code+&=?") -> URL {
    var url = URLComponents(url: attempt.redirect, resolvingAgainstBaseURL: false)!
    url.queryItems = [.init(name: "state", value: attempt.state), .init(name: "code", value: code)]
    return url.url!
}

final class RemoteLoginTests: XCTestCase {
    func testNativeKeychainIsolatedRoundTrip() throws {
        guard ProcessInfo.processInfo.environment["CLONIE_TEST_KEYCHAIN"] == "1" else {
            throw XCTSkip("Native Keychain opt-in check; uses a unique disposable fixture only")
        }
        let service = "com.local.clonie.qa.remote-login-test." + UUID().uuidString
        let store = RemoteKeychainStore(service: service, account: "fixture")
        defer { try? store.clear() }
        XCTAssertNil(try store.load())
        try store.save("not-a-real-token-one")
        let reopened = RemoteKeychainStore(service: service, account: "fixture")
        XCTAssertEqual(try reopened.load(), "not-a-real-token-one")
        try reopened.save("not-a-real-token-two")
        XCTAssertEqual(try store.load(), "not-a-real-token-two")
        try reopened.clear()
        XCTAssertNil(try store.load())
    }

    func testPKCEUsesRFCVectorAndPinsCallbackStateAndIssuer() throws {
        XCTAssertEqual(RemoteLoginAttempt.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
                       "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let a = try RemoteLoginAttempt(configuration: remoteTestConfiguration(), callbackScheme: "com.local.clonie.qa")
        XCTAssertEqual(a.verifier.count, 43)
        XCTAssertEqual(try a.code(from: remoteCallback(a)), "code+&=?")
        let params = URLComponents(url: a.authorizationURL, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(params.first { $0.name == "code_challenge_method" }?.value, "S256")
        XCTAssertEqual(params.first { $0.name == "prompt" }?.value, "login")
        XCTAssertFalse(params.contains { $0.name == "client_secret" || $0.value == a.verifier })
        for url in ["com.local.clonie.qa://evil/callback?state=\(a.state)&code=x",
                    "com.local.clonie.qa://oauth/callback?state=wrong&code=x",
                    "com.local.clonie.qa://oauth/callback?state=\(a.state)&code=x&code=y",
                    "com.local.clonie.qa://oauth/callback?state=\(a.state)&code=x&iss=https://evil.test/",
                    "com.local.clonie.qa://oauth/callback?state=\(a.state)&code=x#ignored",
                    "com.local.clonie.qa://oauth/callback?state=\(a.state)&error=access_denied"] {
            XCTAssertThrowsError(try a.code(from: URL(string: url)!))
        }
    }

    func testDeploymentRejectsInsecureOrCredentialBearingOrigins() throws {
        for url in ["http://login.example.test", "https://user:secret@login.example.test",
                    "https://login.example.test/path", "https://login.example.test?secret=x"] {
            XCTAssertThrowsError(try RemoteServiceConfiguration(relay: URL(string: url)!, issuer: URL(string: url)!,
                                                                 desktopClientID: "native", chatClientID: "chat"))
        }
        XCTAssertThrowsError(try RemoteLoginAttempt(configuration: remoteTestConfiguration(), callbackScheme: "untrusted"))
    }

    func testNewLoginRejectsOldCallbackAndExchangesOnceWithFormEncoding() async throws {
        let store = MemoryRemoteCredentials()
        let session = RemoteLoginSession(configuration: try remoteTestConfiguration(), storage: store) { request in
            XCTAssertEqual(request.url?.path, "/oauth/token")
            let body = String(data: request.httpBody!, encoding: .utf8)!
            XCTAssertTrue(body.contains("code=code%2B%26%3D%3F"))
            XCTAssertFalse(body.contains("client_secret"))
            return remoteTokenResponse()
        }
        let old = try await session.begin(callbackScheme: "com.local.clonie.qa")
        let current = try await session.begin(callbackScheme: "com.local.clonie.qa")
        do { try await session.complete(old, callback: remoteCallback(old)); XCTFail("old login accepted") }
        catch { XCTAssertEqual(error as? RemoteLoginError, .callback) }
        try await session.complete(current, callback: remoteCallback(current))
        XCTAssertEqual(try store.load(), "rotated")
        let access = try await session.accessToken()
        XCTAssertEqual(access, "access")
        do { try await session.complete(current, callback: remoteCallback(current)); XCTFail("callback replay accepted") }
        catch { XCTAssertEqual(error as? RemoteLoginError, .callback) }
    }

    func testConcurrentRequestsRotateExactlyOnceAndCacheAccessOnlyInMemory() async throws {
        actor Counter { var calls = 0; func call() { calls += 1 } }
        let counter = Counter(), store = MemoryRemoteCredentials("old")
        let session = RemoteLoginSession(configuration: try remoteTestConfiguration(), storage: store) { _ in
            await counter.call()
            try await Task.sleep(for: .milliseconds(30))
            return remoteTokenResponse()
        }
        let tokens = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<12 { group.addTask { try await session.accessToken() } }
            var tokens: [String] = []
            for try await token in group { tokens.append(token) }
            return tokens
        }
        XCTAssertEqual(Set(tokens), ["access"])
        let calls = await counter.calls
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(try store.load(), "rotated")
    }

    func testAmbiguousRefreshFailureErasesOldTokenAndDoesNotRetry() async throws {
        let store = MemoryRemoteCredentials("old")
        let session = RemoteLoginSession(configuration: try remoteTestConfiguration(), storage: store) { _ in
            throw RemoteLoginError.network
        }
        do { _ = try await session.accessToken(); XCTFail("failed refresh succeeded") } catch {}
        XCTAssertNil(try store.load())
        do { _ = try await session.accessToken(); XCTFail("old token retried") }
        catch { XCTAssertEqual(error as? RemoteLoginError, .credentials) }
    }

    func testSignOutPreventsLateRefreshFromRestoringCredentialsEvenIfProviderIsOffline() async throws {
        actor Gate {
            var waiter: CheckedContinuation<Data, Never>?
            func wait() async -> Data { await withCheckedContinuation { waiter = $0 } }
            func release() { waiter?.resume(returning: remoteTokenResponse()); waiter = nil }
            var started: Bool { waiter != nil }
        }
        let gate = Gate(), store = MemoryRemoteCredentials("old")
        let session = RemoteLoginSession(configuration: try remoteTestConfiguration(), storage: store) { request in
            if request.url?.path == "/oauth/revoke" { throw RemoteLoginError.network }
            return await gate.wait()
        }
        let pending = Task { try await session.accessToken() }
        for _ in 0..<100 { if await gate.started { break }; try await Task.sleep(for: .milliseconds(2)) }
        let started = await gate.started
        XCTAssertTrue(started)
        let revoked = try await session.signOut()
        XCTAssertFalse(revoked)
        await gate.release()
        do { _ = try await pending.value; XCTFail("logout was undone") } catch {}
        XCTAssertNil(try store.load())
    }
}
