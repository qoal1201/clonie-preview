import AVFoundation
import CoreMedia
import Foundation
import GhostbarCore
import ScreenCaptureKit
import Speech

/// 면접 모드의 **귀**. 두 관을 따로 문다 — 상대 목소리는 시스템 오디오, 내 목소리는 마이크.
///
/// 왜 따로인가 = `knowledge/two-audio-paths.md`: 들어오는 관과 나가는 관은 **만나지 않는다.**
/// 그래서 화자 분리가 필요 없고, 어느 쪽에서 왔는지가 곧 누가 말했는지다.
///
/// ⚠ **그 전제는 공짜가 아니다.** 스피커를 쓰면 상대 목소리가 공기를 타고 마이크로 돌아와
///   두 관이 **만난다** — 상대 말이 「내 말」로 전사된다. 그것을 막는 것이 `openMeLane` 의
///   에코 제거(AEC)이고, 그게 꺼지면 위 문장이 헤드폰 낀 사람에게만 참이 된다.
/// 한 스트림에 마이크를 합치는 `captureMicrophone` 은 macOS 15+ 라 **안 쓴다**(#7) — 두 경로 병행이 더 싸다.
///
/// 전사는 전부 온디바이스(`SpeechTranscriber`)다. 면접을 시작할 때는 모델을 내려받지 않는다 —
/// 모델 준비는 사람이 누르는 `prepareSpeechModel` 에만 있다.
///
/// ⚠ 이 파일은 macOS 26.0 을 전제한다. `Package.swift` 의 `platforms` 가 그것을 세우고,
///   그 승격이 이 코드와 **같은 커밋**에서 일어났다 (#7).
final class InterviewEars {

    /// 어느 관에서 온 소리인가. 화면의 이름표가 이 값을 그대로 쓴다.
    enum Who: String {
        case them   // 상대 — 시스템 오디오
        case me     // 나 — 마이크
    }

    /// 사람이 누른 모델 준비의 상태. 이 경로만 OS 에 설치를 요청한다.
    enum SpeechModelPreparationState: Equatable {
        case loading
        case ready
        case error(String)
    }

    /// 화면으로 나가는 유일한 신호.
    /// - `confirmed`: 이미 확정된 글자. **다시는 안 바뀐다.**
    /// - `volatile`: 미확정 꼬리. 다음 갱신에 바뀔 수 있다.
    /// - `query`: 검색에 넣을 글자(부호 걷은 것). 화면에 **안 보인다** — 보이는 것은 들린 그대로다.
    /// - `ended`: 이 발화가 끝났나. 화면은 이때 현재 줄을 지난 줄로 밀어 올린다.
    var onUpdate: ((Who, _ confirmed: String, _ volatile: String, _ query: String, _ ended: Bool) -> Void)?
    /// 사람이 손을 써야 닫히는 것만 올린다 (권한·장치). 화면에 한 줄로 뜬다.
    var onTrouble: ((String) -> Void)?

    private var lanes: [Who: Lane] = [:]
    private var stream: SCStream?
    private var systemTap: SystemAudioTap?
    private let engine = AVAudioEngine()
    private var micRunning = false
    private var startGeneration = 0
    private var starting = false
    private(set) var running = false

    private static let speechLocale = Locale(identifier: "ko-KR")

    // MARK: - 켜고 끄기

    /// - Parameter system: 시스템 오디오 관(상대 목소리)도 열까. **연습 모드는 `false`** (#36) —
    ///   묻는 것이 앱이라 상대가 없고, 그 관을 열면 **화면 기록 권한을 괜히 묻는다**
    ///   (`openThemLane` 이 `SCShareableContent` 를 만진다). 마이크 관은 언제나 연다 —
    ///   두 모드 다 「내 말」은 받아적어야 한다.
    func startEars(system: Bool = true) {
        guard !running, !starting else { return }
        starting = true
        startGeneration += 1
        let generation = startGeneration
        Task { [weak self] in
            guard let self else { return }
            let ready = await self.isSpeechModelReady()
            await MainActor.run {
                // 준비 상태를 묻는 동안 사용자가 멈췄으면 어떤 캡처도 열지 않는다.
                guard self.starting, generation == self.startGeneration else { return }
                self.starting = false
                guard ready else {
                    self.report("한국어 받아쓰기 모델을 먼저 준비해야 한다")
                    return
                }
                self.beginEars(system: system)
            }
        }
    }

    /// 준비 상태만 조회한다. 다운로드나 캡처를 시작하지 않는다.
    static func probeSpeechModel(completion: @escaping (String) -> Void) {
        Task {
            let transcriber = SpeechTranscriber(locale: speechLocale,
                transcriptionOptions: [], reportingOptions: [.volatileResults, .fastResults], attributeOptions: [])
            let status = await AssetInventory.status(forModules: [transcriber])
            let state = status == .installed ? "ready" : status == .unsupported ? "unsupported" : "required"
            DispatchQueue.main.async { completion(state) }
        }
    }

    /// 사용자가 명시적으로 요청했을 때만 한국어 받아쓰기 모델을 준비한다.
    /// 이 함수는 마이크·시스템 오디오 캡처를 열지 않는다.
    func prepareSpeechModel(onState: @escaping (SpeechModelPreparationState) -> Void) {
        Task { [weak self] in
            guard let self else { return }
            self.reportPreparation(.loading, to: onState)
            let transcriber = self.makeTranscriber()
            let status = await AssetInventory.status(forModules: [transcriber])
            guard status != .unsupported else {
                self.reportPreparation(.error("이 맥은 한국어 받아쓰기를 지원하지 않는다"), to: onState)
                return
            }
            if status == .installed {
                self.reportPreparation(.ready, to: onState)
                return
            }
            do {
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    try await request.downloadAndInstall()
                }
                guard await self.isSpeechModelReady() else {
                    self.reportPreparation(.error("한국어 받아쓰기 모델 준비를 마치지 못했다"), to: onState)
                    return
                }
                self.reportPreparation(.ready, to: onState)
            } catch {
                self.reportPreparation(.error("한국어 받아쓰기 모델을 준비하지 못했다: \(error.localizedDescription)"), to: onState)
            }
        }
    }

    private func beginEars(system: Bool) {
        guard !running else { return }
        running = true
        if system { Task { await self.openThemLane() } }
        askMicThenOpenMeLane()
    }

    /// ⚠ **몇 번 불러도 되게 둔다.** `running` 으로 막으면 세우는 중에 멈춘 경우
    /// (아래 `makeLane` 설명) 두 번째 호출이 뒷정리를 못 해 **마이크가 켜진 채 남는다.**
    func stopEars() {
        startGeneration += 1
        starting = false
        running = false
        if micRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            micRunning = false
        }
        let s = stream
        stream = nil
        systemTap = nil
        Task { try? await s?.stopCapture() }
        for lane in lanes.values { lane.close() }
        lanes.removeAll()
    }

    // MARK: - 상대 (시스템 오디오)

    private func openThemLane() async {
        guard let lane = await makeLane(.them) else { return }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let display = content.displays.first else {
                report("화면을 못 찾았다 — 상대 목소리를 못 문다"); return
            }
            let cfg = SCStreamConfiguration()
            cfg.capturesAudio = true
            cfg.excludesCurrentProcessAudio = true   // 우리 앱 소리가 되먹임되지 않게
            cfg.sampleRate = 48_000
            cfg.channelCount = 2
            cfg.width = 2; cfg.height = 2            // 그림은 안 쓴다. 0 은 못 넣어서 최소값이다
            cfg.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            // 회의 앱을 안 가린다 — Zoom·Meet·Teams 어느 것이든 잡히게. 우리 소리만 위에서 뺐다.
            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let tap = SystemAudioTap(format: lane.format) { [weak lane] buf in lane?.feed(buf) }
            let scs = SCStream(filter: filter, configuration: cfg, delegate: tap)
            try scs.addStreamOutput(tap, type: .audio, sampleHandlerQueue: .global(qos: .userInitiated))
            try await scs.startCapture()
            guard running else { try? await scs.stopCapture(); return }
            stream = scs
            systemTap = tap
        } catch {
            report("화면 녹화 권한이 없으면 상대 목소리를 못 문다 — 시스템 설정 > 개인정보 보호 > 화면 기록")
        }
    }

    // MARK: - 나 (마이크)

    private func askMicThenOpenMeLane() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            Task { await self.openMeLane() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                guard let self = self else { return }
                if granted { Task { await self.openMeLane() } }
                else { self.report("마이크 권한이 없다 — 상대 말은 받아적지만 내 말은 못 받아적는다") }
            }
        default:
            report("마이크 권한이 없다 — 상대 말은 받아적지만 내 말은 못 받아적는다")
        }
    }

    private func openMeLane() async {
        guard running, let lane = await makeLane(.me) else { return }
        let input = engine.inputNode

        // ── 에코 제거(AEC)를 **탭 걸기 전에** 켠다 ──
        //
        // 헤드폰 없이 스피커로 상대 목소리를 들으면 마이크가 그것을 같이 문다. 그러면 상대 말이
        // 「내 말」(me 관)로 전사돼 **화면의 나/면접관이 계속 뒤집히고**, 에코로 들어온 「내 말」이
        // 자동 카드 선택을 오작동시킨다. 두 관이 만나지 않는다는 이 파일의 전제(머리글)가
        // 스피커 앞에서만 깨지는데, **헤드폰 없는 실전 면접이 곧 그 자리다.**
        //
        // ⚠ **끄고 켜는 것은 엔진이 멈췄을 때만 된다** (`AVAudioIONode.h` 의 `setVoiceProcessingEnabled`
        //   설명). 여기가 그 자리다 — `engine.start()` 는 아래에 있다.
        // ⚠ **실패해도 귀는 안 죽인다.** 에코가 안 걷히는 것이지 마이크가 닫히는 게 아니라,
        //   생 마이크로 그냥 간다. 사람이 손쓸 게 없어 `report` 가 아니라 로그로 낸다.
        do {
            try input.setVoiceProcessingEnabled(true)
            // AEC 를 켜면 macOS 가 **다른 소리를 낮춘다**(덕킹). 낮아지는 그 소리가 하필
            // 스피커로 나오는 **상대 목소리**라, 그대로 두면 이쪽 에코를 걷는 대가로
            // 시스템 오디오 관의 전사가 죽는다. 우리는 두 관을 다 받아적어야 하므로 최소로 내린다.
            // `실측 2026-08-30`: 이 API 는 macOS 14.0+ 라 이 레포(26.0 전제)에선 조건 없이 쓴다.
            //   기본값은 (advanced=false, level=`.default`), 내려놓는 값은 `.min`.
            var ducking = input.voiceProcessingOtherAudioDuckingConfiguration
            ducking.enableAdvancedDucking = false
            ducking.duckingLevel = .min
            input.voiceProcessingOtherAudioDuckingConfiguration = ducking
        } catch {
            FileHandle.standardError.write(
                Data("[cue] 에코 제거를 못 켰다 — 생 마이크로 간다(스피커를 쓰면 상대 말이 내 말로 샌다): \(error)\n".utf8))
        }

        // ⚠ **포맷은 AEC 를 켠 뒤에 읽는다.** 켜면 바뀐다 — `실측 2026-08-30` 이 맥(내장 마이크):
        //   `1 ch 48kHz` → **`9 ch` 48kHz deinterleaved**. 아래 변환기가 이 포맷 위에 지어지므로
        //   순서가 뒤집히면 탭이 뱉는 것과 변환기가 아는 것이 갈린다.
        let inFormat = input.inputFormat(forBus: 0)
        guard inFormat.sampleRate > 0 else {
            report("입력 장치를 못 잡았다 — 내 말은 안 받아적힌다"); return
        }
        let conv = AVAudioConverter(from: inFormat, to: lane.format)
        // ⚠ **이걸 안 잡으면 내 말이 소리 없이 죽는다.** 채널이 여럿인 입력에서 모노로 갈 때
        //   `AVAudioConverter` 의 기본 `channelMap` 이 `[-1]`(원본 채널 없음)로 잡혀
        //   **오류 0건 · 프레임 정상 · 내용은 전부 0** 을 뱉는다
        //   (`실측 2026-08-30`: 9→1 변환에서 변환 RMS `0.000000`, `err` 는 nil).
        //   위 9채널은 **전 채널이 같은 신호**였으므로(채널별 RMS 동일) 첫 채널을 집으면 된다.
        //   AEC 가 꺼진 1채널 입력에선 기본 맵이 이미 정상이라 이 자리는 지나간다.
        if let conv = conv, conv.channelMap.contains(where: { $0.intValue < 0 }) {
            conv.channelMap = Array(repeating: NSNumber(value: 0), count: Int(lane.format.channelCount))
        }
        input.installTap(onBus: 0, bufferSize: 4_096, format: inFormat) { [weak lane] buf, _ in
            guard let lane = lane, let conv = conv else { return }
            let ratio = lane.format.sampleRate / inFormat.sampleRate
            let cap = AVAudioFrameCount(Double(buf.frameLength) * ratio) + 512
            guard let out = AVAudioPCMBuffer(pcmFormat: lane.format, frameCapacity: cap) else { return }
            var err: NSError?
            var handed = false
            conv.convert(to: out, error: &err) { _, status in
                if handed { status.pointee = .noDataNow; return nil }
                status.pointee = .haveData; handed = true; return buf
            }
            guard err == nil, out.frameLength > 0 else { return }
            lane.feed(out)
        }
        do {
            try engine.start()
            micRunning = true
        } catch {
            input.removeTap(onBus: 0)
            report("마이크를 여는 데 실패했다 — 내 말은 안 받아적힌다")
            return
        }
        // 세우는 사이에 멈췄으면 곧바로 되돌린다. 안 그러면 **마이크가 켜진 채 남고**,
        // 다음 면접에서 같은 버스에 탭이 두 번 걸려 AVAudioEngine 이 예외로 앱을 죽인다.
        if !running {
            input.removeTap(onBus: 0)
            engine.stop()
            micRunning = false
        }
    }

    // MARK: - 전사 한 갈래 세우기

    private func makeLane(_ who: Who) async -> Lane? {
        let transcriber = makeTranscriber()
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            report("이 맥에서 한국어 받아쓰기 형식을 못 찾았다"); return nil
        }
        let lane = Lane(who: who, transcriber: transcriber, format: format) { [weak self] w, c, v, q, e in
            self?.onUpdate?(w, c, v, q, e)
        }
        // ⚠ **검사와 등록이 같은 자리에서 일어나야 한다.** 여기까지 오는 데 모델 준비·포맷 조회로
        //   1초 넘게 걸리고, 그 사이에 `stopEars()` 가 지나갔으면 이 갈래는 **목록 밖에서 살아남는다**.
        let accepted = await MainActor.run { () -> Bool in
            guard self.running else { return false }
            self.lanes[who] = lane
            return true
        }
        guard accepted else { return nil }
        lane.open()
        return lane
    }

    private func makeTranscriber() -> SpeechTranscriber {
        SpeechTranscriber(locale: Self.speechLocale,
                          transcriptionOptions: [],
                          reportingOptions: [.volatileResults, .fastResults],
                          attributeOptions: [])
    }

    private func isSpeechModelReady() async -> Bool {
        let transcriber = makeTranscriber()
        return await AssetInventory.status(forModules: [transcriber]) == .installed
    }

    private func reportPreparation(_ state: SpeechModelPreparationState,
                                   to callback: @escaping (SpeechModelPreparationState) -> Void) {
        DispatchQueue.main.async { callback(state) }
    }

    private func report(_ message: String) {
        DispatchQueue.main.async { self.onTrouble?(message) }
    }
}

// MARK: - 한 갈래: 오디오를 먹고 발화를 뱉는다

/// 한 관의 전사. **발화를 자르는 자리이기도 하다** — 조용해지면 한 발화가 끝난 것으로 본다.
///
/// ⚠ 안 자르면 확정 글자가 면접 내내 쌓이고, 그러면 검색어가 대화 전체가 돼 순위가 죽는다.
private final class Lane {
    let who: InterviewEars.Who
    let format: AVAudioFormat

    private let transcriber: SpeechTranscriber
    private let analyzer: SpeechAnalyzer
    private let stream: AsyncStream<AnalyzerInput>
    private let cont: AsyncStream<AnalyzerInput>.Continuation
    private let emit: (InterviewEars.Who, String, String, String, Bool) -> Void

    private var reader: Task<Void, Never>?
    private var confirmed: [String] = []
    private var volatileText = ""
    private var silence: DispatchWorkItem?

    /// 마지막 글자 뒤 이만큼 조용하면 한 발화가 끝난 것으로 본다.
    ///
    /// ⚠ **3.0 초로 뒀다가 재보고 올렸다.** 확정(`isFinal`) 결과는 미확정 꼬리가 멎은 **한참 뒤에** 온다 —
    /// `실측 2026-08-28`: 이 코드로 **2.92초**, #15 프로브에서 **3.11초**. 3.0 이면 확정이 오기 직전에
    /// 발화를 끊어 **한 질문이 두 줄로 갈리고 검색어가 중간에 초기화된다.**
    /// 반대로 너무 길면 두 질문이 한 줄로 붙는데, 그쪽은 화자가 바뀌면 화면이 알아서 끊는다(`onEar`).
    /// → 관측된 최대(3.11)에 약 0.9초를 얹는다.
    private static let silenceGap: TimeInterval = 4.0

    init(who: InterviewEars.Who, transcriber: SpeechTranscriber, format: AVAudioFormat,
         emit: @escaping (InterviewEars.Who, String, String, String, Bool) -> Void) {
        self.who = who
        self.transcriber = transcriber
        self.format = format
        self.emit = emit
        (stream, cont) = AsyncStream<AnalyzerInput>.makeStream()
        analyzer = SpeechAnalyzer(modules: [transcriber])
    }

    func open() {
        reader = Task { [weak self] in
            guard let self = self else { return }
            do {
                for try await result in self.transcriber.results {
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespaces)
                    if text.isEmpty { continue }
                    await MainActor.run { self.ingest(text, isFinal: result.isFinal) }
                }
            } catch {
                // 전사가 죽으면 화면은 조용해진다. 통로를 늘리지 않고 알리는 자리가 없어 로그로 낸다.
                FileHandle.standardError.write(Data("[cue] 전사 갈래(\(self.who.rawValue)) 종료: \(error)\n".utf8))
            }
        }
        Task { try? await analyzer.start(inputSequence: stream) }
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        cont.yield(AnalyzerInput(buffer: buffer))
    }

    func close() {
        silence?.cancel()
        cont.finish()
        reader?.cancel()
        let a = analyzer
        Task { try? await a.finalizeAndFinishThroughEndOfInput() }
    }

    // MARK: 글자가 하나 들어올 때마다

    @MainActor
    private func ingest(_ text: String, isFinal: Bool) {
        if isFinal {
            confirmed.append(text)
            volatileText = ""
        } else {
            volatileText = text
        }
        push(ended: false)
        armSilence()
    }

    @MainActor
    private func push(ended: Bool) {
        let head = confirmed.joined(separator: " ")
        let whole = (head + " " + volatileText).trimmingCharacters(in: .whitespaces)
        emit(who, head, volatileText, TranscriptText.forSearch(whole), ended)
    }

    @MainActor
    private func armSilence() {
        silence?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, !self.confirmed.isEmpty || !self.volatileText.isEmpty else { return }
            self.push(ended: true)
            self.confirmed.removeAll()
            self.volatileText = ""
        }
        silence = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Lane.silenceGap, execute: work)
    }
}

// MARK: - 시스템 오디오 탭

/// `ScreenCaptureKit` 이 주는 조각을 전사기가 받는 형식으로 바꿔 넘긴다.
/// 이 모양은 레포 밖 프로브에서 두 번 돌려 검증한 것을 그대로 옮긴 것이다 (#15).
private final class SystemAudioTap: NSObject, SCStreamOutput, SCStreamDelegate {
    private let target: AVAudioFormat
    private let hand: (AVAudioPCMBuffer) -> Void
    private var conv: AVAudioConverter?

    init(format: AVAudioFormat, hand: @escaping (AVAudioPCMBuffer) -> Void) {
        self.target = format
        self.hand = hand
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio,
              let fd = CMSampleBufferGetFormatDescription(sb),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd),
              let source = AVAudioFormat(streamDescription: asbd) else { return }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sb))
        guard frames > 0, let src = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: frames) else { return }
        src.frameLength = frames
        try? sb.withAudioBufferList { abl, _ in
            let dst = UnsafeMutableAudioBufferListPointer(src.mutableAudioBufferList)
            for i in 0..<min(abl.count, dst.count) {
                if let sp = abl[i].mData, let dp = dst[i].mData {
                    memcpy(dp, sp, Int(min(abl[i].mDataByteSize, dst[i].mDataByteSize)))
                }
            }
        }
        if conv == nil { conv = AVAudioConverter(from: source, to: target) }
        guard let conv = conv else { return }
        let cap = AVAudioFrameCount(Double(frames) * target.sampleRate / source.sampleRate) + 512
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: cap) else { return }
        var err: NSError?
        var handed = false
        conv.convert(to: out, error: &err) { _, status in
            if handed { status.pointee = .noDataNow; return nil }
            status.pointee = .haveData; handed = true; return src
        }
        guard err == nil, out.frameLength > 0 else { return }
        hand(out)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        FileHandle.standardError.write(Data("[cue] 시스템 오디오 멈춤: \(error)\n".utf8))
    }
}
