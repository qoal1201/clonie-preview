import AVFoundation
import CoreMedia
import Foundation
import ClonieCore
import ScreenCaptureKit

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
/// 현재 전사는 온디바이스 Apple 어댑터다. 수집기는 공통 PCM·전사 결과 계약만 사용한다.
/// 면접을 시작할 때는 모델을 내려받지 않는다 —
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
    var onResult: ((Who, Int, SpeechTranscriptionResult) -> Void)?
    var onInput: ((Who, Float) -> Void)?
    var onCaptureState: ((CaptureReadiness.Snapshot) -> Void)?
    private var finishing = false
    var onTrouble: ((String) -> Void)?

    private var lanes: [Who: Lane] = [:]
    private var stream: SCStream?
    private var systemTap: SystemAudioTap?
    private var systemStartTask: Task<Void, Never>?
    private let engine = AVAudioEngine()
    private var micRunning = false
    private var startGeneration = 0
    var captureGeneration: Int { startGeneration }
    private var readiness: CaptureReadiness?
    private var starting = false
    private(set) var running = false
    private let transcription: any SpeechTranscriptionBackend

    init(transcription: any SpeechTranscriptionBackend = AppleSpeechTranscription()) {
        self.transcription = transcription
    }

    // MARK: - 켜고 끄기

    /// - Parameter system: 시스템 오디오 관(상대 목소리)도 열까. **연습 모드는 `false`** (#36) —
    ///   묻는 것이 앱이라 상대가 없고, 그 관을 열면 **화면 기록 권한을 괜히 묻는다**
    ///   (`openThemLane` 이 `SCShareableContent` 를 만진다). 마이크 관은 언제나 연다 —
    ///   두 모드 다 「내 말」은 받아적어야 한다.
    func startEars(system: Bool = true) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.startEars(system: system) }
            return
        }
        guard !running, !starting, !finishing else { return }
        starting = true
        startGeneration += 1
        let generation = startGeneration
        readiness = CaptureReadiness(system: system)
        publishCaptureState()
        Task { [weak self] in
            guard let self else { return }
            let ready = await self.isSpeechModelReady()
            await MainActor.run {
                // 준비 상태를 묻는 동안 사용자가 멈췄으면 어떤 캡처도 열지 않는다.
                guard self.starting, generation == self.startGeneration else { return }
                self.starting = false
                guard ready else {
                    self.failInput(.me, message: "한국어 받아쓰기 모델을 먼저 준비해 주세요.", generation: generation)
                    if system { self.failInput(.them, message: "한국어 받아쓰기 모델을 먼저 준비해 주세요.", generation: generation) }
                    return
                }
                self.beginEars(system: system)
            }
        }
    }

    /// 준비 상태만 조회한다. 다운로드나 캡처를 시작하지 않는다.
    static func probeSpeechModel(completion: @escaping (String) -> Void) {
        Task {
            let status = await AppleSpeechTranscription().modelState()
            let state = status == .ready ? "ready" : status == .unsupported ? "unsupported" : "required"
            DispatchQueue.main.async { completion(state) }
        }
    }

    /// 사용자가 명시적으로 요청했을 때만 한국어 받아쓰기 모델을 준비한다.
    /// 이 함수는 마이크·시스템 오디오 캡처를 열지 않는다.
    func prepareSpeechModel(onState: @escaping (SpeechModelPreparationState) -> Void) {
        Task { [weak self] in
            guard let self else { return }
            self.reportPreparation(.loading, to: onState)
            do {
                try await self.transcription.prepareModel()
                self.reportPreparation(.ready, to: onState)
            } catch {
                self.reportPreparation(.error("한국어 받아쓰기 모델을 준비하지 못했다: \(error.localizedDescription)"), to: onState)
            }
        }
    }

    private func beginEars(system: Bool) {
        guard !running else { return }
        running = true
        let generation = startGeneration
        if system { systemStartTask = Task { await self.openThemLane(generation: generation) } }
        askMicThenOpenMeLane(generation: generation)
    }

    /// ⚠ **몇 번 불러도 되게 둔다.** `running` 으로 막으면 세우는 중에 멈춘 경우
    /// (아래 `makeLane` 설명) 두 번째 호출이 뒷정리를 못 해 **마이크가 켜진 채 남는다.**
    func stopEars() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.stopEars() }
            return
        }
        startGeneration += 1
        finishing = false
        starting = false
        running = false
        readiness = nil
        onCaptureState?(.stopped)
        systemStartTask?.cancel()
        systemStartTask = nil
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

    /// 입력을 먼저 닫고 결과 스트림을 수습한다. 화면 숨김과는 독립적인 명시적 종료다.
    @MainActor
    func finishEars() async -> Bool {
        guard !finishing else { return false }
        finishing = true
        starting = false
        systemStartTask?.cancel()
        systemStartTask = nil
        if micRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            micRunning = false
        }
        let capture = stream
        stream = nil
        systemTap = nil
        let draining = Array(lanes.values)
        // stopCapture가 늦어져도 입력·결과 마감의 상한은 같은 타이머가 지킨다.
        let completed: Bool = await withCheckedContinuation { continuation in
            var resolved = false
            let resolve: (Bool) -> Void = { ok in
                guard !resolved else { return }
                resolved = true
                continuation.resume(returning: ok)
            }
            Task { @MainActor in
                try? await capture?.stopCapture()
                var ok = true
                await withTaskGroup(of: Bool.self) { group in
                    for lane in draining { group.addTask { await lane.finish() } }
                    for await finished in group { ok = ok && finished }
                }
                resolve(ok)
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                guard !resolved else { return }
                draining.forEach { $0.close() }
                resolve(false)
            }
        }
        stopEars()
        return completed
    }

    // MARK: - 상대 (시스템 오디오)

    @MainActor
    private func openThemLane(generation: Int) async {
        defer { if startGeneration == generation { systemStartTask = nil } }
        guard let lane = await makeLane(.them, generation: generation) else { return }
        let isCurrent = {
            !Task.isCancelled && self.running && !self.finishing && self.startGeneration == generation
                && self.lanes[.them] === lane && self.readiness?.snapshot.failed["them"] == nil
        }
        var accepted = false
        var pendingStream: SCStream?
        defer {
            if !accepted, lanes[.them] === lane {
                lane.close()
                lanes[.them] = nil
            }
        }
        guard isCurrent() else { return }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            // 화면 목록을 기다리는 동안 끝내기·숨김이 지나갔으면 캡처를 시작하지 않는다.
            guard isCurrent() else { return }
            guard let display = content.displays.first else {
                failInput(.them, message: "화면을 찾지 못해 상대 오디오를 시작하지 못했습니다.", generation: generation); return
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
            let tap = SystemAudioTap(format: lane.format, hand: { [weak lane] buf in lane?.feed(buf) },
                                     stopped: { [weak self] message in
                self?.failInput(.them, message: message, generation: generation)
            })
            let scs = SCStream(filter: filter, configuration: cfg, delegate: tap)
            try scs.addStreamOutput(tap, type: .audio, sampleHandlerQueue: .global(qos: .userInitiated))
            guard isCurrent() else { return }
            // 시작 완료 전에도 stopEars가 같은 스트림을 중단할 수 있어야 한다.
            stream = scs
            systemTap = tap
            pendingStream = scs
            try await scs.startCapture()
            guard isCurrent(), stream === scs else {
                try? await scs.stopCapture()
                return
            }
            accepted = true
        } catch {
            if let pendingStream {
                if stream === pendingStream { stream = nil; systemTap = nil }
                try? await pendingStream.stopCapture()
            }
            if isCurrent() {
                failInput(.them, message: "상대 오디오를 시작하지 못했습니다. 화면 및 시스템 오디오 기록 권한을 확인해 주세요.", generation: generation)
            }
        }
    }

    // MARK: - 나 (마이크)

    private func askMicThenOpenMeLane(generation: Int) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            Task { await self.openMeLane(generation: generation) }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                guard let self = self else { return }
                if granted { Task { await self.openMeLane(generation: generation) } }
                else { self.failInput(.me, message: "마이크 권한이 없어 내 목소리를 수집하지 못합니다.", generation: generation) }
            }
        default:
            failInput(.me, message: "마이크 권한이 없어 내 목소리를 수집하지 못합니다.", generation: generation)
        }
    }

    private func openMeLane(generation: Int) async {
        guard let lane = await makeLane(.me, generation: generation) else { return }
        await MainActor.run {
            guard self.running, !self.finishing, self.startGeneration == generation,
                  self.lanes[.me] === lane, self.readiness?.snapshot.failed["me"] == nil else {
                lane.close()
                return
            }
            self.installMicrophone(lane, generation: generation)
        }
    }

    /// stop/start와 같은 메인 실행 구간에서 검사·AEC·tap 설치·시작을 마친다.
    @MainActor
    private func installMicrophone(_ lane: Lane, generation: Int) {
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
            failInput(.me, message: "마이크 입력 장치를 찾지 못했습니다.", generation: generation); return
        }
        guard let conv = AVAudioConverter(from: inFormat, to: lane.format) else {
            lane.close()
            failInput(.me, message: "마이크 오디오 형식을 변환하지 못했습니다.", generation: generation)
            return
        }
        // ⚠ **이걸 안 잡으면 내 말이 소리 없이 죽는다.** 채널이 여럿인 입력에서 모노로 갈 때
        //   `AVAudioConverter` 의 기본 `channelMap` 이 `[-1]`(원본 채널 없음)로 잡혀
        //   **오류 0건 · 프레임 정상 · 내용은 전부 0** 을 뱉는다
        //   (`실측 2026-08-30`: 9→1 변환에서 변환 RMS `0.000000`, `err` 는 nil).
        //   위 9채널은 **전 채널이 같은 신호**였으므로(채널별 RMS 동일) 첫 채널을 집으면 된다.
        //   AEC 가 꺼진 1채널 입력에선 기본 맵이 이미 정상이라 이 자리는 지나간다.
        if conv.channelMap.contains(where: { $0.intValue < 0 }) {
            conv.channelMap = Array(repeating: NSNumber(value: 0), count: Int(lane.format.channelCount))
        }
        input.installTap(onBus: 0, bufferSize: 4_096, format: inFormat) { [weak lane] buf, _ in
            guard let lane = lane else { return }
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
            failInput(.me, message: "마이크를 시작하지 못했습니다.", generation: generation)
            return
        }
        // 이 구간에는 await가 없으므로 stopEars가 설치 도중 끼어들지 않는다.
    }

    // MARK: - 전사 한 갈래 세우기

    private func makeLane(_ who: Who, generation: Int) async -> Lane? {
        guard await MainActor.run(body: { self.running && !self.finishing && self.startGeneration == generation }) else { return nil }
        let session: any SpeechTranscriptionSession
        do { session = try await transcription.makeSession() }
        catch { failInput(who, message: error.localizedDescription, generation: generation); return nil }
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
            sampleRate: session.sampleRate, channels: 1, interleaved: false) else {
            session.cancel()
            failInput(who, message: "받아쓰기 오디오 형식을 준비하지 못했습니다.", generation: generation); return nil
        }
        let lane = Lane(who: who, session: session, format: format, raw: { [weak self] result in
            guard let self, self.running, self.startGeneration == generation else { return }
            self.onResult?(who, generation, result)
        }, input: { [weak self] level in
            guard let self, self.running, !self.finishing, self.startGeneration == generation else { return }
            let before = self.readiness?.snapshot
            self.readiness?.receive(who.rawValue)
            if before != self.readiness?.snapshot { self.publishCaptureState() }
            self.onInput?(who, level)
        }, trouble: { [weak self] message in self?.failInput(who, message: message, generation: generation) }) { [weak self] w, c, v, q, e in
            guard let self, self.running, self.startGeneration == generation else { return }
            self.onUpdate?(w, c, v, q, e)
        }
        // ⚠ **검사와 등록이 같은 자리에서 일어나야 한다.** 여기까지 오는 데 모델 준비·포맷 조회로
        //   1초 넘게 걸리고, 그 사이에 `stopEars()` 가 지나갔으면 이 갈래는 **목록 밖에서 살아남는다**.
        let accepted = await MainActor.run { () -> Bool in
            guard self.running, !self.finishing, self.startGeneration == generation,
                  self.readiness?.snapshot.failed[who.rawValue] == nil else { return false }
            self.lanes[who] = lane
            lane.open()
            return true
        }
        guard accepted else { session.cancel(); return nil }
        return lane
    }

    private func isSpeechModelReady() async -> Bool {
        await transcription.modelState() == .ready
    }

    private func reportPreparation(_ state: SpeechModelPreparationState,
                                   to callback: @escaping (SpeechModelPreparationState) -> Void) {
        DispatchQueue.main.async { callback(state) }
    }

    private func publishCaptureState() {
        if let readiness { onCaptureState?(readiness.snapshot) }
    }

    private func failInput(_ who: Who, message: String, generation: Int) {
        DispatchQueue.main.async {
            guard self.startGeneration == generation, !self.finishing, self.readiness != nil else { return }
            let before = self.readiness?.snapshot
            self.readiness?.fail(who.rawValue, message: message)
            guard before != self.readiness?.snapshot else { return }
            if who == .me, self.micRunning {
                self.engine.inputNode.removeTap(onBus: 0)
                self.engine.stop()
                self.micRunning = false
            }
            if who == .them, let stream = self.stream {
                self.stream = nil; self.systemTap = nil
                Task { try? await stream.stopCapture() }
            }
            self.publishCaptureState()
            self.onTrouble?(message)
        }
    }
}

// MARK: - 한 갈래: 오디오를 먹고 발화를 뱉는다

/// 한 관의 전사. **발화를 자르는 자리이기도 하다** — 조용해지면 한 발화가 끝난 것으로 본다.
///
/// ⚠ 안 자르면 확정 글자가 면접 내내 쌓이고, 그러면 검색어가 대화 전체가 돼 순위가 죽는다.
private final class Lane {
    let who: InterviewEars.Who
    let format: AVAudioFormat

    private let session: any SpeechTranscriptionSession
    private let raw: (SpeechTranscriptionResult) -> Void
    private let input: (Float) -> Void
    private let trouble: (String) -> Void
    private var lastInput = Date.distantPast
    private let emit: (InterviewEars.Who, String, String, String, Bool) -> Void

    private var reader: Task<Void, Never>?
    private var transcript = LiveTranscriptWindow()
    private var silence: DispatchWorkItem?

    /// 마지막 글자 뒤 이만큼 조용하면 한 발화가 끝난 것으로 본다.
    ///
    /// ⚠ **3.0 초로 뒀다가 재보고 올렸다.** 확정(`isFinal`) 결과는 미확정 꼬리가 멎은 **한참 뒤에** 온다 —
    /// `실측 2026-08-28`: 이 코드로 **2.92초**, #15 프로브에서 **3.11초**. 3.0 이면 확정이 오기 직전에
    /// 발화를 끊어 **한 질문이 두 줄로 갈리고 검색어가 중간에 초기화된다.**
    /// 반대로 너무 길면 두 질문이 한 줄로 붙는데, 그쪽은 화자가 바뀌면 화면이 알아서 끊는다(`onEar`).
    /// → 관측된 최대(3.11)에 약 0.9초를 얹는다.
    private static let silenceGap: TimeInterval = 4.0

    init(who: InterviewEars.Who, session: any SpeechTranscriptionSession, format: AVAudioFormat,
         raw: @escaping (SpeechTranscriptionResult) -> Void, input: @escaping (Float) -> Void,
         trouble: @escaping (String) -> Void, emit: @escaping (InterviewEars.Who, String, String, String, Bool) -> Void) {
        self.who = who
        self.session = session
        self.format = format
        self.emit = emit
        self.raw = raw
        self.input = input
        self.trouble = trouble
    }

    func open() {
        reader = Task { [weak self] in
            guard let self = self else { return }
            do {
                for try await result in self.session.results {
                    guard !Task.isCancelled else { break }
                    await MainActor.run { self.ingest(result) }
                }
            } catch {
                if !Task.isCancelled { self.trouble("받아쓰기가 멈췄습니다: \(error.localizedDescription)") }
                // 전사가 죽으면 화면은 조용해진다. 통로를 늘리지 않고 알리는 자리가 없어 로그로 낸다.
                FileHandle.standardError.write(Data("[cue] 전사 갈래(\(self.who.rawValue)) 종료: \(error)\n".utf8))
            }
        }
        session.start()
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        session.append(samples)
        if Date().timeIntervalSince(lastInput) > 0.25 {
            lastInput = Date()
            let level = sqrt(samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(samples.count))
            DispatchQueue.main.async { self.input(level) }
        }
    }

    func close() {
        silence?.cancel()
        session.cancel()
        reader?.cancel()
    }

    @MainActor
    func finish() async -> Bool {
        silence?.cancel()
        do {
            try await session.finish()
            await reader?.value
            push(ended: true)
            return true
        } catch { close(); return false }
    }

    // MARK: 글자가 하나 들어올 때마다

    @MainActor
    private func ingest(_ result: SpeechTranscriptionResult) {
        raw(result)
        guard transcript.ingest(result) else { return }
        push(ended: false)
        armSilence()
    }

    @MainActor
    private func push(ended: Bool) {
        emit(who, transcript.confirmed, transcript.volatile, transcript.query, ended)
    }

    @MainActor
    private func armSilence() {
        silence?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, !self.transcript.isEmpty else { return }
            self.push(ended: true)
            self.transcript.closeUtterance()
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
    private let stopped: (String) -> Void
    private var conv: AVAudioConverter?

    init(format: AVAudioFormat, hand: @escaping (AVAudioPCMBuffer) -> Void,
         stopped: @escaping (String) -> Void) {
        self.target = format
        self.hand = hand
        self.stopped = stopped
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
        stopped("상대 오디오 입력이 중단됐습니다: \(error.localizedDescription)")
        FileHandle.standardError.write(Data("[cue] 시스템 오디오 멈춤: \(error)\n".utf8))
    }
}
