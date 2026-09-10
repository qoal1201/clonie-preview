import Foundation
import XCTest
import ClonieCore
import ClonieEmbedding
@testable import ClonieMCP

/// 둘째 문 시험의 공통 부품. **판정은 없다** — 자리·문서·환경만 만든다.
enum MCPTestSupport {
    /// 임시 볼트. 「이미 있는 폴더를 연결한다」가 기본 동선이라 미리 만든다.
    static func makeVault(_ label: String = "vault") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clonie-mcp-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 모델을 **일부러 못 찾게** 하는 환경. 임베딩이 필요 없는 시험은 이걸로 돌아 빨라진다
    /// (`EmbeddingModelStore.searchPaths` 가 `CLONIE_MODEL_DIR` 을 먼저 본다).
    static let noModelEnvironment: [String: String] = ["CLONIE_MODEL_DIR": "/nonexistent/clonie-mcp-no-model"]

    /// 조각 셋 + 질문 둘. 검색 시험이 「배포」 질의로 첫째를 찾을 수 있게 뜻이 갈린다.
    static func sampleDocument() -> CueDocument {
        let t0 = Date(timeIntervalSince1970: 1_756_000_000)
        let t1 = t0.addingTimeInterval(60)
        let t2 = t0.addingTimeInterval(120)
        return CueDocument(
            questions: [Question(id: "q-1", text: "주도적으로 문제를 해결한 경험"),
                        Question(id: "q-2", text: "실패했던 경험과 거기서 배운 것")],
            fragments: [
                Fragment(id: "f-deploy", title: "배포 스크립트를 갈아엎었다",
                         body: "매번 손으로 하던 배포를 스크립트 한 줄로 줄였다. 실수가 사라졌다.",
                         questionIds: ["q-1"], createdAt: t0, updatedAt: t0),
                Fragment(id: "f-fail", title: "장애를 놓친 날",
                         body: "알람을 꺼 둔 채 주말을 보냈고 월요일에 장애를 알았다. 그 뒤로 당번 규칙을 세웠다.",
                         questionIds: ["q-2"], createdAt: t1, updatedAt: t1),
                Fragment(id: "f-pasta", title: "까르보나라 비법",
                         body: "계란 노른자와 페코리노를 불 끄고 섞는다. 크림은 넣지 않는다.",
                         questionIds: [], createdAt: t2, updatedAt: t2),
            ])
    }

    /// 모델이 없으면 「안 쟀다」를 출력에 박고 `nil` — `tests/ClonieIndexTests/IndexTestSupport.swift`
    /// 의 정책 그대로(깨진 것은 빨강, `CLONIE_REQUIRE_EMBEDDING_MODEL=1` 이면 없는 것도 빨강).
    static func modelOrAnnounceMissing(_ function: String = #function) -> EmbeddingModelStore.Manifest? {
        let status = EmbeddingModelStore.status()
        switch status {
        case .ready(let m): return m
        case .incomplete, .unreadable:
            XCTFail("모델이 있는데 못 읽는다. 이건 skip 이 아니라 빨강이다.\n\(status.explanation)")
            return nil
        case .missing(let searched):
            if ProcessInfo.processInfo.environment["CLONIE_REQUIRE_EMBEDDING_MODEL"] == "1" {
                XCTFail("CLONIE_REQUIRE_EMBEDDING_MODEL=1 인데 모델이 없다.\n\(status.explanation)")
                return nil
            }
            print("""

                ⚠ 둘째 문의 뜻 검색 시험 \(function) 이 **안 돌았다** — 모델이 없다.
                  이 초록은 「맞다」가 아니라 「재지 못했다」다. 본 자리: \(searched.map(\.path).joined(separator: ", "))
                  받는 법: ./scripts/fetch-model.sh

                """)
            return nil
        }
    }

    /// SwiftPM 이 제품을 놓는 자리 — xctest 번들 옆이다. 상류 SwiftPM 템플릿의 그 코드.
    static var productsDirectory: URL {
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            return bundle.bundleURL.deletingLastPathComponent()
        }
        fatalError("제품 폴더를 못 찾았다 — xctest 번들이 없다")
    }
}

/// 빌드된 `clonie-mcp` 를 **진짜 둘째 프로세스**로 띄우고 JSON-RPC 줄을 주고받는다.
/// SDK 의 `Client` 를 안 쓰는 이유: 이 시험이 잠그는 것은 「stdio 로 한 줄씩 오가는 프로토콜」 자체다.
final class StdioClient {
    private let process = Process()
    private let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
    private var buffer = Data()
    private var errBuffer = Data()
    private let lock = NSLock()
    private let arrived = DispatchSemaphore(value: 0)

    init(binary: URL, vault: URL, environment: [String: String]) {
        process.executableURL = binary
        process.arguments = ["--vault", vault.path]
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
    }

    func start() throws {
        stdout.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard let self = self, !d.isEmpty else { return }
            self.lock.lock(); self.buffer.append(d); self.lock.unlock()
            self.arrived.signal()
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard let self = self, !d.isEmpty else { return }
            self.lock.lock(); self.errBuffer.append(d); self.lock.unlock()
        }
        try process.run()
    }

    func notify(method: String) throws {
        try send(["jsonrpc": "2.0", "method": method])
    }

    func request(id: Int, method: String, params: [String: Any] = [:]) throws -> [String: Any] {
        try send(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if let line = takeLine() {
                let obj = try JSONSerialization.jsonObject(with: line) as? [String: Any] ?? [:]
                if (obj["id"] as? Int) == id { return obj }
                continue   // 알림 등 다른 줄은 건너뛴다
            }
            _ = arrived.wait(timeout: .now() + 0.5)
        }
        throw NSError(domain: "StdioClient", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "\(method) 응답이 20초 안에 안 왔다. stderr: \(stderrText())"])
    }

    func stop() {
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        stdin.fileHandleForWriting.closeFile()
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
    }

    /// **절대 안 멈춘다** — `request()` 가 20초 시간제한을 알릴 때 이 함수를 부르는데,
    /// 그 자리에서 자식이 멎어 있으면 `availableData` 로 직접 읽는 것은 무한 대기가 된다.
    /// 그래서 읽지 않는다: `start()` 가 붙인 핸들러가 이미 `errBuffer` 에 채워 뒀고,
    /// 여기는 그 메모리를 잠금 아래에서 돌려줄 뿐이다.
    func stderrText() -> String {
        lock.lock(); defer { lock.unlock() }
        return String(decoding: errBuffer, as: UTF8.self)
    }

    private func send(_ obj: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: obj)
        data.append(0x0A)
        stdin.fileHandleForWriting.write(data)
    }

    private func takeLine() -> Data? {
        lock.lock(); defer { lock.unlock() }
        guard let nl = buffer.firstIndex(of: 0x0A) else { return nil }
        let line = buffer.subdata(in: buffer.startIndex..<nl)
        buffer.removeSubrange(buffer.startIndex...nl)
        return line
    }
}
