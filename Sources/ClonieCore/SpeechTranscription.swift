import Foundation

/// 전사 엔진과 수집기를 연결하는 형식. 플랫폼의 오디오·음성 SDK 타입을 노출하지 않는다.
/// 입력은 `sampleRate`의 단일 채널 Float32 PCM이며 한 배열은 연속된 오디오다.
public protocol SpeechTranscriptionSession: AnyObject {
    var sampleRate: Double { get }
    var results: AsyncThrowingStream<SpeechTranscriptionResult, Error> { get }

    /// 생성 직후에는 입력을 받지 않는다. 수집기가 시작을 승인한 뒤 한 번 호출한다.
    func start()
    func append(_ samples: [Float])
    /// 입력을 닫고 남은 확정 결과를 내보낸 뒤 반환한다. 사람의 답변 끝을 판정하지는 않는다.
    func finish() async throws
    /// 입력과 전사를 중단한다. 소비자는 이미 받은 이전 세션 결과를 새 세션에 적용하지 않아야 한다.
    /// `finish`와 달리 미확정 결과의 보존을 보장하지 않는다.
    func cancel()
}

public enum SpeechTranscriptionModelState: Sendable {
    case ready
    case required
    case unsupported
}

public protocol SpeechTranscriptionBackend {
    var identifier: String { get }
    /// 상태 확인은 모델 설치나 오디오 수집을 시작하지 않는다.
    func modelState() async -> SpeechTranscriptionModelState
    /// 사용자에게 요청받은 준비 경로에서만 호출한다.
    func prepareModel() async throws
    func makeSession() async throws -> any SpeechTranscriptionSession
}

/// 엔진의 구간 결과. 부분 결과는 같은 segmentID의 높은 revision으로 대체한다.
/// 구간 확정은 검색용 침묵 분할이나 실제 질문/답변 완료와 별개다.
public struct SpeechTranscriptionResult: Equatable, Sendable {
    public let segmentID: Int
    public let revision: Int
    public let text: String
    public let isFinal: Bool
    /// 해당 전사 스트림의 시작부터 센 오디오 시각. 엔진이 제공하지 않으면 nil이다.
    public let startTime: TimeInterval?
    public let endTime: TimeInterval?

    public init(segmentID: Int, revision: Int, text: String, isFinal: Bool,
                startTime: TimeInterval? = nil, endTime: TimeInterval? = nil) {
        self.segmentID = segmentID
        self.revision = revision
        self.text = text
        self.isFinal = isFinal
        self.startTime = startTime
        self.endTime = endTime
    }
}
