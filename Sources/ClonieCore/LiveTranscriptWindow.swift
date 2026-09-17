import Foundation

/// 실시간 화면·검색에 쓰는 현재 발화. 전체 대화 기록과는 별개다.
/// 전사 엔진의 구간 ID·개정 번호를 사용해 부분 수정과 중복 확정을 구별한다.
public struct LiveTranscriptWindow {
    private var segments: [Int: SpeechTranscriptionResult] = [:]
    private var closedSegments: Set<Int> = []

    public init() {}

    private var ordered: [SpeechTranscriptionResult] {
        segments.values.sorted { $0.segmentID < $1.segmentID }
    }

    public var confirmed: String { join(ordered.filter(\.isFinal)) }
    public var volatile: String { join(ordered.filter { !$0.isFinal }) }
    public var text: String { join(ordered) }
    public var query: String { TranscriptText.forSearch(text) }
    public var isEmpty: Bool { text.isEmpty }

    /// 닫힌 검색 발화의 늦은 확정으로 새 질문을 만들지 않는다.
    /// 전체 기록을 만들 때는 이 반환값과 무관하게 원래 구간 결과를 보존해야 한다.
    @discardableResult
    public mutating func ingest(_ result: SpeechTranscriptionResult) -> Bool {
        guard !closedSegments.contains(result.segmentID) else { return false }
        if let previous = segments[result.segmentID] {
            guard !previous.isFinal, result.revision > previous.revision else { return false }
        }
        segments[result.segmentID] = result
        return true
    }

    /// 검색용 침묵 분할이다. 모델 구간이나 사람의 전체 답변이 끝났다는 뜻이 아니다.
    public mutating func closeUtterance() {
        closedSegments.formUnion(segments.keys)
        segments.removeAll()
    }

    private func join(_ results: [SpeechTranscriptionResult]) -> String {
        results.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
}
