import Foundation

/// Cloud 또는 명시적으로 허용한 개발용 제공자 연결의 HTTP 한 번을 수행한다.
///
/// 호출마다 쿠키·캐시가 없는 세션을 만들고, 리다이렉트와 재시도를 따로 수행하지 않는다.
/// 오류는 응답 본문이나 요청 정보를 싣지 않는 닫힌 종류로만 돌아간다.
public enum JevEvidenceService {
    public enum Failure: Error, Equatable {
        case invalidResponse
        case rejected(statusCode: Int)
        case responseTooLarge
    }

    static let maximumResponseBytes = 1_000_000

    public static func fetch(_ request: URLRequest) async throws -> Data {
        try await fetch(request, configuration: ephemeralConfiguration())
    }

    // Tests replace only URL loading. Request policy and streamed size limits
    // still run through the same implementation as the app.
    static func ephemeralConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        return configuration
    }

    static func fetch(_ request: URLRequest, configuration: URLSessionConfiguration) async throws -> Data {
        let delegate = JevNoRedirectDelegate()
        let session = URLSession(configuration: configuration,
                                 delegate: delegate,
                                 delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw Failure.rejected(statusCode: http.statusCode)
        }

        var data = Data()
        if http.expectedContentLength > 0 {
            let announced = min(http.expectedContentLength, Int64(maximumResponseBytes))
            data.reserveCapacity(Int(announced))
        }
        for try await byte in bytes {
            guard data.count < maximumResponseBytes else { throw Failure.responseTooLarge }
            data.append(byte)
        }
        return data
    }
}

private final class JevNoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
