import AppKit
import Foundation
import WebKit

/// QA 스냅샷 — **앱이 스스로 자기 화면을 파일로 찍는다** (#24 B 층).
///
/// ## 왜 있나
///
/// 이 앱의 창은 `sharingType = .none` 이다 — **화면 공유·녹화·스크린샷에 안 잡히는 것이 제품 특성**이고
/// 그건 판정선이라 QA 편의로 흔들 수 없다. 그래서 바깥에서 찍는 길(`screencapture`·윈도 서버)은
/// **원리적으로 검은 그림만** 돌려준다. 여기서 하는 것은 그 반대 방향이다:
/// **윈도 서버를 안 타고** 앱 안에서 `WKWebView` 가 자기 웹 콘텐츠를 다시 그린다.
/// `sharingType` 이 막는 경로가 아니라 **판정선 밖**이다.
///
/// ## 어떻게 쏘나
///
/// 유효한 `GHOSTBAR_QA_SESSION=example`로 QA 앱을 실행한 경우:
///
///     notifyutil -p com.local.ghostbar.qa.snapshot.example
///     ls /tmp/ghostbar-qa-example/
///
/// ⚠ **유효한 QA 세션에서만 열린다.** `QASession.current` 가 없는 정상 번들에서는
/// 관찰자 설치와 직접 `fire()` 호출이 모두 즉시 돌아온다. QA 번들은 명시적인 세션 ID와
/// 절대 볼트 경로를 검증한 뒤에만 이 값을 만든다 — 환경변수를 주지 않은 QA 기동은
/// `AppDelegate` 가 종료하므로 조용히 열린 채로 남지 않는다.
///
/// ⚠ **잔심부름은 `QAChannel` 이 든다** — 산출물 폴더 · 시각 도장 · 로그 · 관찰자 설치.
/// 반대 방향의 길(`QADrive.swift`, #58)과 **같은 것**을 쓴다. 관찰자를 왜 전용 스레드에
/// 거는지(실측 포함)는 거기 머리글에 있다.
///
/// ## 이 길이 못 찍는 것 — 알고 두는 한계 (`실측 2026-08-29`)
///
/// ⚠ **이 절의 주어는 죽었다.** 네이티브 설정창은 2026-08-31 에 프론트 설정 화면으로
/// 흡수됐고, 남아 있던 마지막 모달(`NSOpenPanel.runModal`)도 #78 에서 시트로 바뀌었다 —
/// **지금 이 앱에 `NSApp.runModal` 은 0건**이다(`tests/check_no_modal_runloop.py` 가 잰다).
/// 아래는 **그 모양이 다시 생기면 무슨 일이 나는지**의 실측 기록으로 남긴다.
///
/// **설정창(AppKit 패널)은 이 길로 못 찍었다.** 그것은 `NSApp.runModal` 로 떴는데,
/// 모달은 **메인 스레드를 붙잡는다.** AppKit 렌더는 메인에서만
/// 할 수 있으므로 스냅샷 작업이 메인 큐에 줄을 서고 **모달이 닫힐 때까지 안 돈다** —
/// 그때는 이미 `panel.orderOut` 으로 창이 사라진 뒤다. 잰 것: 모달을 띄운 채 쏘면 로그가
/// **한 줄도 안 늘고**, 그 뒤로 앱이 트리거에 통째로 무응답이 된다(메인이 막혀서).
/// 메뉴가 열려 있을 때 딸려오는 창은 `cacheDisplay` 로 **흰 빈 그림**만 나왔다 —
/// NSMenu 는 그 창의 `contentView` 에 안 그린다. 그래서 **패널 캡처를 아예 안 넣는다**:
/// 못 찍는 것보다 **빈 PNG 를 찍어두는 것이 QA 를 더 헛짚게 한다.**
/// 설정창을 찍으려면 다른 길이 필요하다 (#24 의 다른 층).
///
/// ⚠ **네트워크를 안 탄다** — 파일에만 쓴다. 판정선 검사(`tests/check_interview_offline.py`)는
/// **브리지(`post`)에서 닿는 것만 순회하므로 이 파일은 그 그래프 밖이다** — darwin
/// notification 이 진입점이라 화면에서 오는 길이 없다. 그래서 그 검사가 `QA_CHANNEL_FILES` 로
/// **선언한 목록**에 이 파일을 세워 통째로 훑는다(`정관 2조`). 여기 `URLSession`·`URLRequest`·
/// `http` 가 들어오면 그 절이 빨개진다.
enum QASnapshot {

    /// CLI 에서 쏘는 이름. `notifyutil -p <이것>`.
    static var signal: String { QAChannel.signal("snapshot") }

    /// 찍은 것이 떨어지는 자리. **드라이브 길과 같은 폴더**다 — `QAChannel` 이 든다.
    static var outputDirectory: String { QAChannel.outputDirectory }

    /// 매 트리거마다 한 줄. **성공도 적는다** — 「파일이 없다」가 *안 찍힌 것*인지
    /// *트리거가 안 온 것*인지 구별 못 하면 QA 가 헛짚는다.
    static var logPath: String { outputDirectory + "/qa-snapshot.log" }

    // MARK: - 설치

    /// darwin notify 관찰자를 건다. `AppDelegate` 가 기동에 한 번 부른다.
    /// 전용 스레드·런루프 이야기는 `QAChannel.installObserver` 가 든다.
    static func installQASnapshotObserver() {
        guard QASession.current != nil else { return }
        QAChannel.installObserver(signal: signal) { QASnapshot.fire() }
    }

    // MARK: - 한 번 찍기

    /// 트리거 한 번 = 채팅 창 하나.
    static func fire() {
        guard QASession.current != nil else { return }
        let stamp = QAChannel.timestamp()
        QAChannel.ensureDirectory()

        guard let chat = (NSApp.delegate as? AppDelegate)?.chatWindow, chat.window.isVisible else {
            appendLog("\(stamp) 채팅 창이 없다(안 만들어졌거나 숨김) — WKWebView 스냅샷을 건너뛴다")
            return
        }

        chat.webView.view.takeSnapshot(with: nil) { image, error in
            let path = outputDirectory + "/chat-\(stamp).png"
            if let image = image, writePNG(image, to: path) {
                appendLog("\(stamp) chat-\(stamp).png "
                          + "(\(Int(image.size.width))x\(Int(image.size.height)) pt)")
            } else {
                appendLog("\(stamp) WKWebView 스냅샷 실패: "
                          + (error.map { "\($0)" } ?? "이미지가 nil 인데 오류도 없다"))
            }
        }
    }

    // MARK: - 잔심부름

    private static func writePNG(_ image: NSImage, to path: String) -> Bool {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }

    private static func appendLog(_ line: String) {
        QAChannel.append(line, to: logPath)
    }
}
