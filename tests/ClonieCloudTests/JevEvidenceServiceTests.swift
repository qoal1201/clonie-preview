import Foundation
import XCTest
@testable import ClonieCloud

final class JevEvidenceServiceTests: XCTestCase {
    private func request(_ path: String) -> URLRequest {
        URLRequest(url: URL(string: "https://jev-test.invalid/\(path)")!)
    }

    private func configuration() -> URLSessionConfiguration {
        let configuration = JevEvidenceService.ephemeralConfiguration()
        configuration.protocolClasses = [JevResponseProtocol.self]
        return configuration
    }

    func testSuccessfulResponseAndExactSizeLimit() async throws {
        let small = try await JevEvidenceService.fetch(request("ok"), configuration: configuration())
        XCTAssertEqual(small, Data("{}".utf8))
        let limit = try await JevEvidenceService.fetch(request("limit"), configuration: configuration())
        XCTAssertEqual(limit.count, JevEvidenceService.maximumResponseBytes)
    }

    func testOversizedStreamFailsEvenWithoutContentLength() async throws {
        do {
            _ = try await JevEvidenceService.fetch(request("oversized"), configuration: configuration())
            XCTFail("The streamed limit must apply without a Content-Length header")
        } catch {
            XCTAssertEqual(error as? JevEvidenceService.Failure, .responseTooLarge)
        }
    }

    func testHTTPFailureDoesNotRetryOrReturnServerBody() async throws {
        let calls = RequestCount()
        let observer = NotificationCenter.default.addObserver(
            forName: JevResponseProtocol.started, object: nil, queue: nil
        ) { notification in
            if notification.object as? String == "/rejected" { calls.increment() }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        do {
            _ = try await JevEvidenceService.fetch(request("rejected"), configuration: configuration())
            XCTFail("HTTP failures must not be returned as result bytes")
        } catch {
            XCTAssertEqual(error as? JevEvidenceService.Failure, .rejected(statusCode: 429))
            XCTAssertFalse(String(describing: error).contains("server-private-detail"))
        }
        XCTAssertEqual(calls.value, 1)
    }

    func testNonHTTPResponseFailsClosed() async throws {
        do {
            _ = try await JevEvidenceService.fetch(request("non-http"), configuration: configuration())
            XCTFail("Only HTTP responses are supported")
        } catch {
            XCTAssertEqual(error as? JevEvidenceService.Failure, .invalidResponse)
        }
    }

    func testRedirectStatusIsNotTreatedAsSuccessfulResult() async throws {
        do {
            _ = try await JevEvidenceService.fetch(request("redirect"), configuration: configuration())
            XCTFail("A redirect response must not become judgment result bytes")
        } catch {
            XCTAssertEqual(error as? JevEvidenceService.Failure, .rejected(statusCode: 302))
        }
    }

    func testCancellationStopsPendingRequest() async throws {
        let started = expectation(description: "request started")
        let stopped = expectation(description: "request stopped")
        let beganObserver = NotificationCenter.default.addObserver(
            forName: JevResponseProtocol.started, object: nil, queue: nil
        ) { notification in
            if notification.object as? String == "/pending" { started.fulfill() }
        }
        let stoppedObserver = NotificationCenter.default.addObserver(
            forName: JevResponseProtocol.stopped, object: nil, queue: nil
        ) { notification in
            if notification.object as? String == "/pending" { stopped.fulfill() }
        }
        defer {
            NotificationCenter.default.removeObserver(beganObserver)
            NotificationCenter.default.removeObserver(stoppedObserver)
        }
        let config = configuration()
        let request = request("pending")
        let task = Task { try await JevEvidenceService.fetch(request, configuration: config) }
        await fulfillment(of: [started], timeout: 3)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("A cancelled request must not return a result")
        } catch {
            XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled)
        }
        await fulfillment(of: [stopped], timeout: 3)
    }
}

private final class RequestCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); defer { lock.unlock() }; count += 1 }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

/// All requests are intercepted; no credentials, external server, or paid call.
private final class JevResponseProtocol: URLProtocol {
    static let started = Notification.Name("JevEvidenceServiceTests.started")
    static let stopped = Notification.Name("JevEvidenceServiceTests.stopped")

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url!.path
        NotificationCenter.default.post(name: Self.started, object: path)
        if path == "/pending" { return }
        let response: URLResponse
        if path == "/non-http" {
            response = URLResponse(url: request.url!, mimeType: nil, expectedContentLength: 2, textEncodingName: nil)
        } else {
            response = HTTPURLResponse(url: request.url!, statusCode: path == "/rejected" ? 429 : path == "/redirect" ? 302 : 200,
                                       httpVersion: nil, headerFields: nil)!
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let body: Data
        switch path {
        case "/limit": body = Data(repeating: 65, count: JevEvidenceService.maximumResponseBytes)
        case "/oversized": body = Data(repeating: 65, count: JevEvidenceService.maximumResponseBytes + 1)
        case "/rejected": body = Data("server-private-detail".utf8)
        default: body = Data("{}".utf8)
        }
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        NotificationCenter.default.post(name: Self.stopped, object: request.url!.path)
    }
}
