import Foundation
import ClonieDocuments

/// Slow synchronous extraction must not occupy VaultTools' actor or the cooperative
/// executor. One queue bounds concurrent OCR; cancelling a request discards its result.
final class SourceReadExecutor: @unchecked Sendable {
    typealias Operation = @Sendable (String, Int, Int) throws -> SourceCatalog.Page
    private let queue = DispatchQueue(label: "com.local.clonie.mcp-source-read", qos: .utility)
    private let operation: Operation

    init(operation: @escaping Operation) { self.operation = operation }

    func read(path: String, offset: Int, limit: Int) async throws -> SourceCatalog.Page {
        let job = SourceReadJob()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard job.install(continuation) else { return }
                queue.async { [operation] in
                    job.run { try operation(path, offset, limit) }
                }
            }
        } onCancel: {
            job.finish(.failure(CancellationError()))
        }
    }
}

/// Handles cancellation before registration, while queued, or during extraction.
/// The lock protects the single terminal result; continuations resume outside it.
private final class SourceReadJob: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<SourceCatalog.Page, Error>?
    private var continuation: CheckedContinuation<SourceCatalog.Page, Error>?

    func install(_ continuation: CheckedContinuation<SourceCatalog.Page, Error>) -> Bool {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(with: result)
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func run(_ operation: () throws -> SourceCatalog.Page) {
        lock.lock()
        let shouldRun = result == nil
        lock.unlock()
        guard shouldRun else { return }
        // The existing platform extractor is synchronous: an active OCR may finish
        // after cancellation, but its late result can never become a successful reply.
        finish(Result { try operation() })
    }

    func finish(_ result: Result<SourceCatalog.Page, Error>) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}
