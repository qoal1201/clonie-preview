import Foundation

/// QA 통로가 **본문째 나눠 갖던 것**을 한 자리로 모은 것 — 산출물 폴더 · 시각 도장 ·
/// 로그 덧붙이기 · darwin notify 관찰자 설치.
///
/// ## 왜 있나
///
/// QA 길이 둘이다: **내보내는 쪽**(`QASnapshot.swift`, #24 B 층 — 화면을 파일로 찍는다)과
/// **받아들이는 쪽**(`QADrive.swift`, #58 — 집행할 JS 를 파일로 받는다). 방향만 반대고
/// 잔심부름은 **글자까지 같았다** — 폴더 만들기 · 시각 도장 · 로그 한 줄 · 전용 스레드 관찰자.
/// 복제된 채로 두면 한쪽만 고치는 편집이 가능하고, 그러면 **두 길의 산출물이 조용히 갈린다**
/// (다른 폴더 · 다른 시각 형식 · 한쪽만 죽은 관찰자).
///
/// ⚠ **여기 있는 것은 QA 산출물의 규약이지 기능이 아니다.** 새 QA 길이 생기면
/// 그 길도 이것을 쓰고, `tests/check_interview_offline.py` 의 `QA_CHANNEL_FILES` 목록에
/// 그 파일을 **사람이 더한다** (아래 「판정선」 참고).
///
/// ## 판정선 — 네트워크를 안 탄다
///
/// QA 통로는 파일에만 쓴다. ⚠ **판정선 검사는 브리지(`post`)에서 닿는 것만 순회하므로
/// 이 파일들은 그 그래프 밖이다** — 대신 `tests/check_interview_offline.py` 가
/// `QA_CHANNEL_FILES` 로 **선언한 목록**을 통째로 훑는다(`정관 2조`). 여기 그 낱말이
/// 들어오면 그 절이 빨개진다.
enum QAChannel {

    /// QA 산출물이 떨어지는 자리. **두 길이 같은 폴더를 쓴다** — 한 자리에 모여야 QA 가
    /// 「찍힌 것」과 「집행한 것」을 같은 시각선에서 읽는다.
    /// `/tmp` 라 재부팅에 사라진다 — QA 산출물이라 그게 맞다.
    static var outputDirectory: String { QASession.current?.outputDirectory ?? "/tmp/ghostbar-qa" }

    static func signal(_ action: String) -> String {
        QASession.current?.signal(action) ?? "com.local.ghostbar.qa.\(action)"
    }

    // MARK: - 관찰자 설치

    /// darwin notify 관찰자를 **전용 스레드**에 건다. 알림이 오면 `onFire` 를 메인에서 부른다.
    ///
    /// ⚠ **관찰자를 메인 스레드에 걸면 안 된다.** `CFNotificationCenterAddObserver` 는 부른
    /// 스레드의 런루프 **기본 모드**에 관찰자를 건다 — 그러면 메뉴가 열려 있는 동안
    /// (`NSEventTrackingRunLoopMode`) 트리거가 **떨어지지 않고 줄을 선다.**
    /// `실측 2026-08-29`: 메인에 걸었을 때, 메뉴를 연 채 쏘고 Esc 로 닫았더니 **그때서야** 찍혔고
    /// 로그의 시각은 쏜 때가 아니라 메뉴가 닫힌 때였다. QA 길에서 이건 조용한 거짓말이다 —
    /// 「안 찍힌다」와 「나중에 찍힌다」를 구별 못 하게 한다.
    /// → 그래서 **자기 런루프를 가진 전용 스레드**에 건다. 고친 뒤 다시 재니 메뉴가 열린 채로도
    ///   **즉시** 찍혔다. 쏘는 쪽(`notifyutil -p`)은 그대로다.
    ///
    /// ⚠ 이래도 **모달은 못 넘는다.** 알림은 이 스레드로 제때 오지만 AppKit·WebKit 을 만지려면
    /// 결국 메인으로 넘어가야 하고, 앱 모달 런루프는 그 메인을 붙잡고 있다.
    /// 잰 것과 경위 = `QASnapshot.swift` 머리글의 「이 길이 못 찍는 것」.
    /// ★ **그래서 이 앱은 모달을 아예 안 띄운다** (#78, 2026-09-04): 파일·폴더 고르기는
    ///   시트(`beginSheetModal`)와 비모달(`begin`)로 뜬다. `runModal` 이 0건인 것은
    ///   `tests/check_no_modal_runloop.py` 가 잰다 — 다시 생기면 이 통로가 그날 다시 죽는다.
    ///
    /// ⚠ **`onFire` 는 C 콜백을 건너야 한다.** `CFNotificationCallback` 은 `@convention(c)` 라
    /// 아무것도 캡처 못 한다 — 그래서 클로저를 상자에 담아 `observer` 포인터로 넘기고
    /// 콜백에서 도로 꺼낸다. 상자는 **일부러 영구히 잡아둔다**(`passRetained`): 관찰자는
    /// 앱 수명 내내 살아 있어야 하고, 놓으면 트리거가 죽은 포인터를 밟는다.
    static func installObserver(signal: String, onFire: @escaping () -> Void) {
        let box = Unmanaged.passRetained(Handler(onFire)).toOpaque()
        let thread = Thread {
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                box,
                // ⚠ 첫 인자는 **센터**고 `observer` 는 **둘째**다 — 위에서 넘긴 상자가 여기로 온다.
                { _, observer, _, _, _ in
                    guard let observer = observer else { return }
                    let handler = Unmanaged<Handler>.fromOpaque(observer).takeUnretainedValue()
                    // AppKit·WebKit 은 메인에서만 만진다.
                    DispatchQueue.main.async { handler.run() }
                },
                signal as CFString,
                nil,
                .deliverImmediately)
            // ⚠ 런루프는 **소스가 하나도 없으면 즉시 반환한다** — 그러면 스레드가 끝나고
            //   관찰자가 조용히 죽는다. 포트를 하나 박아 확실히 살려둔다.
            RunLoop.current.add(NSMachPort(), forMode: .default)
            while RunLoop.current.run(mode: .default, before: .distantFuture) {}
        }
        thread.name = signal
        thread.start()
    }

    /// C 콜백을 건너가는 상자. `installObserver` 밖에서는 쓰지 않는다.
    private final class Handler {
        private let body: () -> Void
        init(_ body: @escaping () -> Void) { self.body = body }
        func run() { body() }
    }

    // MARK: - 잔심부름

    /// 파일 이름과 로그 줄에 같이 쓰는 시각 도장. **두 길이 같은 형식을 쓴다.**
    static func timestamp() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmmss.SSS"
        return fmt.string(from: Date())
    }

    /// 산출물 폴더를 만든다. 이미 있으면 아무 일도 안 한다.
    static func ensureDirectory() {
        try? FileManager.default.createDirectory(atPath: outputDirectory,
                                                 withIntermediateDirectories: true)
    }

    /// 로그에 한 줄씩 덧붙인다. **파일이 없으면 만든다** — 첫 줄이 조용히 사라지지 않게.
    static func append(_ line: String, to logPath: String) {
        ensureDirectory()
        let data = Data((line + "\n").utf8)
        let url = URL(fileURLWithPath: logPath)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
