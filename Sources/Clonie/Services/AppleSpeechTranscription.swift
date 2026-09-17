import AVFoundation
import ClonieCore
import Foundation
import Speech

/// 현재 기본 구현. 모델 채택 결론과 분리하며 플랫폼 SDK는 이 어댑터 안에서 사용한다.
final class AppleSpeechTranscription: SpeechTranscriptionBackend {
    let identifier = "apple-speech-ko-KR"
    private let locale = Locale(identifier: "ko-KR")

    func modelState() async -> SpeechTranscriptionModelState {
        switch await AssetInventory.status(forModules: [makeTranscriber()]) {
        case .installed: return .ready
        case .unsupported: return .unsupported
        default: return .required
        }
    }

    func prepareModel() async throws {
        switch await modelState() {
        case .ready: return
        case .unsupported: throw Failure.unsupported
        case .required: break
        }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [makeTranscriber()]) {
            try await request.downloadAndInstall()
        }
        guard await modelState() == .ready else { throw Failure.modelRequired }
    }

    func makeSession() async throws -> any SpeechTranscriptionSession {
        let transcriber = makeTranscriber()
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw Failure.audioFormat
        }
        return try AppleSpeechSession(transcriber: transcriber, analyzerFormat: format)
    }

    private func makeTranscriber() -> SpeechTranscriber {
        SpeechTranscriber(locale: locale, transcriptionOptions: [],
                          reportingOptions: [.volatileResults, .fastResults], attributeOptions: [])
    }

    enum Failure: LocalizedError {
        case unsupported, modelRequired, audioFormat, audioConversion

        var errorDescription: String? {
            switch self {
            case .unsupported: return "이 맥은 한국어 받아쓰기를 지원하지 않는다"
            case .modelRequired: return "모델 준비 상태를 확인하지 못했습니다. Clonie를 종료한 뒤 다시 열어 준비 상태를 확인해 주세요."
            case .audioFormat: return "이 맥에서 한국어 받아쓰기 형식을 못 찾았다"
            case .audioConversion: return "받아쓰기 오디오 형식을 변환하지 못했다"
            }
        }
    }
}

/// Float32 PCM과 공통 결과 형식 사이에서만 Apple 타입을 다룬다.
private final class AppleSpeechSession: SpeechTranscriptionSession {
    let sampleRate: Double
    let results: AsyncThrowingStream<SpeechTranscriptionResult, Error>
    private let output: AsyncThrowingStream<SpeechTranscriptionResult, Error>.Continuation
    private let transcriber: SpeechTranscriber
    private let analyzer: SpeechAnalyzer
    private let input: AsyncStream<AnalyzerInput>
    private let inputContinuation: AsyncStream<AnalyzerInput>.Continuation
    private let inputFormat: AVAudioFormat
    private let analyzerFormat: AVAudioFormat
    private let converter: AVAudioConverter?
    private let queue = DispatchQueue(label: "clonie.apple-speech-input")
    private enum State { case idle, running, finishing, finished, cancelled, failed }
    private var state = State.idle
    private var receivedAudio = false
    private var failure: Error?
    private var reader: Task<Void, Never>?
    private var analysis: Task<Void, Error>?
    private var finishing: Task<Void, Error>?

    init(transcriber: SpeechTranscriber, analyzerFormat: AVAudioFormat) throws {
        guard let inputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
            sampleRate: analyzerFormat.sampleRate, channels: 1, interleaved: false) else {
            throw AppleSpeechTranscription.Failure.audioFormat
        }
        self.sampleRate = inputFormat.sampleRate
        self.inputFormat = inputFormat
        self.analyzerFormat = analyzerFormat
        self.transcriber = transcriber
        self.analyzer = SpeechAnalyzer(modules: [transcriber])
        self.converter = inputFormat == analyzerFormat ? nil : AVAudioConverter(from: inputFormat, to: analyzerFormat)
        guard inputFormat == analyzerFormat || converter != nil else {
            throw AppleSpeechTranscription.Failure.audioFormat
        }
        (input, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()
        (results, output) = AsyncThrowingStream<SpeechTranscriptionResult, Error>.makeStream()
    }

    func start() {
        queue.sync {
            guard state == .idle else { return }
            state = .running
            reader = Task { [transcriber, output, weak self] in
                var segmentID = 0
                var revision = 0
                do {
                    for try await result in transcriber.results {
                        guard !Task.isCancelled else { break }
                        let text = String(result.text.characters).trimmingCharacters(in: .whitespaces)
                        guard !text.isEmpty else { continue }
                        revision += 1
                        let start = result.range.start.seconds
                        let end = CMTimeRangeGetEnd(result.range).seconds
                        output.yield(SpeechTranscriptionResult(segmentID: segmentID, revision: revision,
                            text: text, isFinal: result.isFinal,
                            startTime: start.isFinite ? start : nil, endTime: end.isFinite ? end : nil))
                        if result.isFinal { segmentID += 1; revision = 0 }
                    }
                    output.finish()
                } catch {
                    if Task.isCancelled { output.finish() }
                    else { self?.recordFailure(error) }
                }
            }
            analysis = Task { [analyzer, input, weak self] in
                do { try await analyzer.start(inputSequence: input) }
                catch {
                    if !Task.isCancelled { self?.recordFailure(error) }
                    throw error
                }
            }
        }
    }

    func append(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        queue.sync {
            guard state == .running else { return }
            guard samples.count <= Int(UInt32.max),
                  let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(samples.count)),
                  let channel = buffer.floatChannelData?[0] else {
                failInput(AppleSpeechTranscription.Failure.audioConversion)
                return
            }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { source in channel.update(from: source.baseAddress!, count: source.count) }
            guard let converter else {
                receivedAudio = true
                inputContinuation.yield(AnalyzerInput(buffer: buffer))
                return
            }
            guard buffer.frameLength <= UInt32.max - 512,
                  let converted = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: buffer.frameLength + 512) else {
                failInput(AppleSpeechTranscription.Failure.audioConversion)
                return
            }
            var error: NSError?
            var supplied = false
            converter.convert(to: converted, error: &error) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true
                status.pointee = .haveData
                return buffer
            }
            if let error {
                failInput(error)
            } else if converted.frameLength > 0 {
                receivedAudio = true
                inputContinuation.yield(AnalyzerInput(buffer: converted))
            }
        }
    }

    func finish() async throws {
        let task = try queue.sync { () throws -> Task<Void, Error>? in
            if state == .cancelled { throw CancellationError() }
            if let failure { throw failure }
            if let finishing { return finishing }
            guard state == .running else {
                if state == .idle { state = .finished; inputContinuation.finish(); output.finish() }
                return nil
            }
            state = .finishing
            inputContinuation.finish()
            let task = Task { [analyzer, analysis, reader, output, receivedAudio] in
                do {
                    // start(inputSequence:)는 입력을 등록한 뒤 즉시 반환한다. 등록 전에
                    // finish가 앞서면 빈 세션의 결과 스트림이 닫히지 않을 수 있다.
                    try await analysis?.value
                    if receivedAudio {
                        try await analyzer.finalizeAndFinishThroughEndOfInput()
                        await reader?.value
                    } else {
                        // 오디오가 한 번도 없으면 확정할 시각도 없다. 빈 입력의
                        // 결과 대기에 머물지 않고 소비자 스트림을 직접 닫는다.
                        await analyzer.cancelAndFinishNow()
                        reader?.cancel()
                    }
                    output.finish()
                } catch {
                    output.finish(throwing: error)
                    await analyzer.cancelAndFinishNow()
                    analysis?.cancel()
                    reader?.cancel()
                    throw error
                }
            }
            finishing = task
            return task
        }
        try await task?.value
        try queue.sync {
            if state == .cancelled { throw CancellationError() }
            if let failure { throw failure }
            if state == .finishing { state = .finished }
        }
    }

    func cancel() {
        queue.sync {
            guard state != .cancelled, state != .finished else { return }
            state = .cancelled
            inputContinuation.finish()
            output.finish()
            reader?.cancel()
            analysis?.cancel()
            finishing?.cancel()
            Task { [analyzer] in await analyzer.cancelAndFinishNow() }
        }
    }

    /// 입력 큐에서만 호출한다. 변환 실패 뒤 오디오를 계속 쌓거나 성공으로 끝내지 않는다.
    private func failInput(_ error: Error) {
        state = .failed
        failure = error
        inputContinuation.finish()
        output.finish(throwing: error)
        reader?.cancel()
        analysis?.cancel()
        Task { [analyzer] in await analyzer.cancelAndFinishNow() }
    }

    private func recordFailure(_ error: Error) {
        queue.sync {
            guard state == .running || state == .finishing else { return }
            failInput(error)
        }
    }
}
