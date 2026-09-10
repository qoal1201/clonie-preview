import Foundation

/// 모델이 **없을 때 무슨 일이 벌어지나**를 정하는 곳 (#31).
///
/// 모델은 git 에 안 든다(ADR 0003 §5) — 그래서 "없음"은 예외 상황이 아니라 **정상 상태 중 하나**다.
/// 새 클론·새 기기·캐시를 지운 사람이 전부 여기로 온다.
///
/// ## ⚠ 조용히 죽지 않는다는 것이 이 파일의 전부다
///
/// 없을 때 빈 벡터나 0 점수를 돌려주면 **검색이 그냥 안 맞는 제품**이 된다 — 아무것도 안 터지고
/// 아무도 못 알아챈다. 그래서 `status` 는 셋 중 하나를 **말로** 낸다: 준비됨 · 없음(찾은 자리 나열) ·
/// 깨짐(뭐가 빠졌는지). `TextEmbedder` 는 준비됨이 아니면 **생성 자체가 실패**한다.
public enum EmbeddingModelStore {

    /// 모델 산출물이 앉는 곳. `scripts/fetch-model.sh` 가 여기에 쓴다.
    ///
    /// ⚠ **`~/Library/Caches` 가 아니다.** 캐시는 macOS 가 말없이 비울 수 있고, 235MB 짜리가
    ///   그렇게 사라지면 앱이 어느 날 갑자기 모델을 잃는다. Application Support 는 안 비워진다.
    public static let defaultDirectory: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Ghostbar/models/multilingual-e5-small-ko-v2",
                                isDirectory: true)

    /// 환경변수로 덮을 수 있다 — **테스트와 CI 가 이걸 쓴다.**
    public static let directoryOverrideKey = "GHOSTBAR_MODEL_DIR"
    /// `.app/Contents/Resources/` 안에서 선택적으로 동봉한 변환 모델의 자리.
    public static let bundledDirectoryName = "EmbeddingModel"

    /// 실제로 볼 자리들.
    ///
    /// ⚠ **`GHOSTBAR_MODEL_DIR` 이 있으면 거기만 본다 — 기본 자리로 안 물러선다.**
    ///   물러서면 두 가지가 깨진다: ① 「이 모델로 재라」고 가리킨 사람이 **모르는 사이에 다른
    ///   모델로 재게** 된다 ② 「모델 없음」을 시험할 방법이 사라진다 — 빈 폴더를 가리켜도
    ///   기본 자리에서 찾아버려서 그 갈래가 영영 안 돌게 된다(`실측 2026-08-30`, #31: 실제로
    ///   그렇게 못 쟀다).
    public static func searchPaths(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleResourcesURL: URL? = Bundle.main.resourceURL
    ) -> [URL] {
        if let p = environment[directoryOverrideKey], !p.isEmpty {
            return [URL(fileURLWithPath: (p as NSString).expandingTildeInPath, isDirectory: true)]
        }
        var paths: [URL] = []
        if let bundleResourcesURL {
            paths.append(bundleResourcesURL.appendingPathComponent(bundledDirectoryName,
                                                                   isDirectory: true))
        }
        paths.append(defaultDirectory)
        return paths
    }

    /// `manifest.json` 이 말해주는 것. 앱은 이걸 **먼저** 읽는다.
    public struct Manifest: Sendable {
        public let directory: URL
        public let modelID: String
        public let revision: String
        public let dimensions: Int
        public let precision: String
        public let maxSequenceLength: Int
        /// 모델이 미리 컴파일해둔 시퀀스 길이들. 그 사이 길이는 **위로 올림 패딩**한다.
        public let enumeratedShapes: [Int]
        public let modelURL: URL
        public let tokenizerURL: URL

        /// `query: ` / `passage: ` — e5 계열의 프리픽스 규약. 변환 스크립트가 여기 박아 보낸다.
        public let queryPrefix: String
        public let passagePrefix: String
    }

    public enum Status: Sendable {
        case ready(Manifest)
        /// 어디에도 없다. 어디를 봤는지 같이 낸다 — 안 그러면 사용자가 어디에 두어야 할지 모른다.
        case missing(searched: [URL])
        /// 디렉터리는 있는데 알맹이가 빠졌다.
        case incomplete(directory: URL, missing: [String])
        /// 있는데 못 읽는다(manifest 가 깨졌거나 형식이 바뀌었다).
        case unreadable(directory: URL, reason: String)

        public var manifest: Manifest? {
            if case .ready(let m) = self { return m }
            return nil
        }
        public var isReady: Bool { manifest != nil }

        /// 사람이 읽고 **다음에 뭘 할지 아는** 한 덩어리. 로그·테스트 출력·오류 메시지가 같이 쓴다.
        public var explanation: String {
            switch self {
            case .ready(let m):
                return "임베딩 모델 준비됨 — \(m.modelID)@\(String(m.revision.prefix(12))) "
                     + "\(m.dimensions)차 \(m.precision) · \(m.directory.path)"
            case .missing(let searched):
                return """
                임베딩 모델이 없다. 본 자리:
                \(searched.map { "  - " + $0.path }.joined(separator: "\n"))
                받으려면: ./scripts/fetch-model.sh
                """
            case .incomplete(let dir, let missing):
                return """
                임베딩 모델이 깨졌다 — \(dir.path)
                없는 것: \(missing.joined(separator: ", "))
                다시 받으려면: ./scripts/fetch-model.sh --force
                """
            case .unreadable(let dir, let reason):
                return "임베딩 모델을 못 읽는다 — \(dir.path)\n이유: \(reason)"
            }
        }
    }

    /// 지금 상태. **부작용이 없다** — 읽기만 한다.
    public static func status(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleResourcesURL: URL? = Bundle.main.resourceURL
    ) -> Status {
        let fm = FileManager.default
        let paths = searchPaths(environment: environment, bundleResourcesURL: bundleResourcesURL)

        for dir in paths {
            let manifestURL = dir.appendingPathComponent("manifest.json")
            guard fm.fileExists(atPath: manifestURL.path) else { continue }

            do {
                let data = try Data(contentsOf: manifestURL)
                guard let j = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return .unreadable(directory: dir, reason: "manifest.json 최상위가 객체가 아니다")
                }
                guard let modelDir = j["model_dir"] as? String,
                      let tokFile = j["tokenizer_file"] as? String,
                      let dims = j["dimensions"] as? Int,
                      let modelID = j["model_id"] as? String,
                      let revision = j["revision"] as? String else {
                    return .unreadable(directory: dir, reason: "manifest.json 에 필수 항목이 없다")
                }
                let prefixes = j["prefix_convention"] as? [String: String] ?? [:]
                let modelURL = dir.appendingPathComponent(modelDir, isDirectory: true)
                let tokURL = dir.appendingPathComponent(tokFile)

                var missing: [String] = []
                if !fm.fileExists(atPath: modelURL.path) { missing.append(modelDir) }
                if !fm.fileExists(atPath: tokURL.path) { missing.append(tokFile) }
                if !missing.isEmpty { return .incomplete(directory: dir, missing: missing) }

                return .ready(Manifest(
                    directory: dir,
                    modelID: modelID,
                    revision: revision,
                    dimensions: dims,
                    precision: j["precision"] as? String ?? "unknown",
                    maxSequenceLength: j["max_seq_length"] as? Int ?? 512,
                    enumeratedShapes: (j["enumerated_shapes"] as? [Int])?.sorted() ?? [512],
                    modelURL: modelURL,
                    tokenizerURL: tokURL,
                    queryPrefix: prefixes["query"] ?? "query: ",
                    passagePrefix: prefixes["passage"] ?? "passage: "))
            } catch {
                return .unreadable(directory: dir, reason: "\(error)")
            }
        }
        return .missing(searched: paths)
    }
}

public enum EmbeddingError: Error, CustomStringConvertible {
    case modelUnavailable(EmbeddingModelStore.Status)
    case tokenizerUnreadable(URL, String)
    case modelLoadFailed(URL, String)
    case inferenceFailed(String)
    /// 만든 벡터의 차원이 manifest 가 약속한 것과 다르다 — 조용히 넘기면 안 되는 자리다.
    case dimensionMismatch(expected: Int, got: Int)

    public var description: String {
        switch self {
        case .modelUnavailable(let s): return s.explanation
        case .tokenizerUnreadable(let u, let w): return "토크나이저를 못 읽었다 — \(u.path)\n이유: \(w)"
        case .modelLoadFailed(let u, let w): return "CoreML 모델을 못 열었다 — \(u.path)\n이유: \(w)"
        case .inferenceFailed(let w): return "추론이 실패했다 — \(w)"
        case .dimensionMismatch(let e, let g): return "차원이 다르다 — manifest 는 \(e), 모델은 \(g)"
        }
    }
}
