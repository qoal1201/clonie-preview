import Foundation
import XCTest
@testable import ClonieEmbedding
@testable import ClonieIndex

/// 모델이 없는 환경에서 **조용히 skip 하지 않는다** — 규칙의 정본과 그 이유는
/// `tests/ClonieEmbeddingTests/ScoreParityTests.swift` 머리글에 있다. 여기는 그것을
/// 두 번째 시험 타깃에서 쓸 수 있게 옮겨온 것이고, **판정은 한 글자도 안 바꿨다.**
///
/// - 없으면(`.missing`) 통과시키되 「안 쟀다」를 출력에 박는다
/// - 깨졌으면(`.incomplete`·`.unreadable`) 빨강 — 있는데 안 도는 것은 사고다
/// - `CLONIE_REQUIRE_EMBEDDING_MODEL=1` 이면 없는 것도 빨강
enum IndexTestSupport {

    static let requireModelKey = "CLONIE_REQUIRE_EMBEDDING_MODEL"

    /// - Returns: `nil` 이면 「없어서 못 쟀다」. 부르는 쪽은 **그냥 돌아간다.**
    static func indexerOrAnnounceMissing(sidecarURL: URL,
                                        _ function: String = #function) -> ContentIndexer? {
        switch ContentIndexer.open(sidecarURL: sidecarURL) {
        case .ready(let indexer):
            return indexer
        case .unavailable(let status):
            switch status {
            case .ready:
                XCTFail("준비됐다는데 색인기를 못 만들었다 — 여기 오면 안 된다")
                return nil
            case .incomplete, .unreadable:
                XCTFail("모델이 있는데 못 읽는다. 이건 skip 이 아니라 빨강이다.\n\(status.explanation)")
                return nil
            case .missing(let searched):
                if ProcessInfo.processInfo.environment[requireModelKey] == "1" {
                    XCTFail("\(requireModelKey)=1 인데 모델이 없다.\n\(status.explanation)")
                    return nil
                }
                print("""

                    ┌──────────────────────────────────────────────────────────────────────┐
                    │ ⚠ 내용 그래프 자물쇠가 \(function) 에서 **안 돌았다** — 모델이 없다.
                    │   이 초록은 「맞다」가 아니라 「재지 못했다」는 뜻이다.
                    \(searched.map { "│   본 자리: \($0.path)" }.joined(separator: "\n"))
                    │   받는 법: ./scripts/fetch-model.sh
                    │   없는 것을 빨강으로 올리려면: \(requireModelKey)=1 swift test
                    └──────────────────────────────────────────────────────────────────────┘

                    """)
                return nil
            }
        }
    }

    /// 시험용 임시 폴더. 끝나면 지운다.
    static func makeTempDirectory(_ label: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clonie-index-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return .nan }
        let i = Int((Double(sorted.count - 1) * p).rounded())
        return sorted[i]
    }
}
