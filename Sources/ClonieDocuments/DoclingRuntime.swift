import Foundation

/// Installation may download the pinned interpreter, wheels and public models. Conversion
/// executes a separate process with network access disabled before loading any document.
public actor DoclingRuntime: DocumentConversionService {
    public enum RuntimeError: LocalizedError {
        case resources, preparation, conversion, busy
        public var errorDescription: String? {
            switch self {
            case .resources: return "문서 변환 도구가 앱에 없습니다. 앱을 다시 설치해 주세요."
            case .preparation: return "문서 변환 준비를 완료하지 못했습니다. 인터넷 연결과 여유 공간을 확인한 뒤 다시 시도해 주세요."
            case .conversion: return "문서를 변환하지 못했습니다. 원본은 보존했습니다."
            case .busy: return "다른 문서를 변환하고 있습니다. 잠시 뒤 다시 시도해 주세요."
            }
        }
    }
    private let root: URL
    private let resources: URL?
    private var active: ConversionProcess?
    // An explicit prepare can be consumed by the immediately following conversion.
    // Every subsequent job validates the on-disk cache again, including failed-job retries.
    private var readyForNextConversion = false
    private var needsDeepValidation = false

    public init(runtimeRoot: URL? = nil, resourceDirectory: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        root = runtimeRoot ?? support.appendingPathComponent("Clonie/DocumentConversion/v1", isDirectory: true)
        // No developer virtual environment or checkout fallback is used by shipped apps.
        resources = resourceDirectory ?? Bundle.main.resourceURL?.appendingPathComponent("document-conversion", isDirectory: true)
    }

    public func cancel() async { active?.cancel() }

    public func prepare() async throws {
        guard active == nil else { throw RuntimeError.busy }
        readyForNextConversion = false
        guard let resources, FileManager.default.fileExists(atPath: resources.appendingPathComponent("bootstrap.sh").path) else { throw RuntimeError.resources }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        do {
            var arguments = [resources.appendingPathComponent("bootstrap.sh").path, root.path, resources.path]
            if needsDeepValidation { arguments.append("--deep") }
            try await execute(URL(fileURLWithPath: "/bin/bash"), arguments)
            readyForNextConversion = true
            needsDeepValidation = false
        } catch is CancellationError { throw CancellationError() }
        catch { throw RuntimeError.preparation }
    }

    public func convert(_ source: URL) async throws -> DocumentConversion {
        if !readyForNextConversion { try await prepare() }
        guard active == nil, let resources else { throw RuntimeError.busy }
        readyForNextConversion = false
        let output = root.appendingPathComponent("result-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: output) }
        do {
            try await execute(URL(fileURLWithPath: "/usr/bin/sandbox-exec"),
                              ["-p", "(version 1)(allow default)(deny network*)",
                               root.appendingPathComponent("python/bin/python3").path,
                               "-I", resources.appendingPathComponent("convert.py").path, "convert", root.path, source.path, output.path])
            struct Reply: Decodable { let markdown: String; let partial: Bool; let warnings: [String] }
            let reply = try JSONDecoder().decode(Reply.self, from: Data(contentsOf: output))
            return .init(markdown: reply.markdown, partial: reply.partial, warnings: reply.warnings)
        } catch is CancellationError { throw CancellationError() }
        catch {
            // The next user retry distinguishes damaged cache bytes from a bad document.
            // A healthy deep check returns without downloading anything.
            needsDeepValidation = true
            throw RuntimeError.conversion
        }
    }

    private func execute(_ executable: URL, _ arguments: [String]) async throws {
        let job = ConversionProcess(executable: executable, arguments: arguments, root: root)
        active = job
        defer { active = nil }
        try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) { try job.run() }.value
        } onCancel: { job.cancel() }
    }
}

/// The lock closes the cancel-before-launch race; file-backed logs avoid pipe deadlocks.
private final class ConversionProcess: @unchecked Sendable {
    private let lock = NSLock()
    private let process = Process()
    private let root: URL
    private var cancelled = false
    init(executable: URL, arguments: [String], root: URL) {
        self.root = root
        process.executableURL = executable; process.arguments = arguments
        process.environment = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": root.path,
            "TMPDIR": FileManager.default.temporaryDirectory.path,
            "HF_HOME": root.appendingPathComponent("hf").path,
            "DOCLING_CACHE_DIR": root.appendingPathComponent("cache").path,
            "HF_HUB_DISABLE_TELEMETRY": "1", "DO_NOT_TRACK": "1", "ANONYMIZED_TELEMETRY": "False",
            "TOKENIZERS_PARALLELISM": "false", "PYTHONNOUSERSITE": "1",
            "PIP_DISABLE_PIP_VERSION_CHECK": "1"
        ]
    }
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        if process.isRunning { process.terminate() }
    }
    func run() throws {
        let log = root.appendingPathComponent("last-runtime.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }
        process.standardOutput = handle; process.standardError = handle
        lock.lock()
        if cancelled { lock.unlock(); throw CancellationError() }
        do { try process.run() } catch { lock.unlock(); throw error }
        lock.unlock()
        process.waitUntilExit()
        lock.lock(); let didCancel = cancelled; lock.unlock()
        if didCancel { throw CancellationError() }
        guard process.terminationStatus == 0 else { throw DoclingRuntime.RuntimeError.conversion }
    }
}
