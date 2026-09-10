import AppKit
import Foundation
import WebKit

/// QA 드라이브 — **앱이 파일로 받은 JS 를 자기 화면에서 집행하고 결과를 파일로 돌려준다** (#58).
///
/// ## 왜 있나
///
/// QA 에이전트가 이 앱을 「사람처럼」 몰려면 지금까지 길이 하나뿐이었다: 좌표를 계산해
/// `CGEvent` 로 클릭하기. 그 길은 셋을 요구한다 — **앱이 앞에 있을 것**(frontmost),
/// **창 위치를 알 것**(좌표), **포커스를 가져올 것**. 셋 다 대가가 크다:
/// 포커스를 뺏으므로 **사람이 실제로 쓰는 중에는 못 돌리고**, 창은 움직일 수 있어서
/// 좌표는 **조용히 빗나간다**(빗나간 클릭은 실패가 아니라 *엉뚱한 성공*으로 보인다).
///
/// 이 통로는 그 셋을 전부 안 쓴다. **파일 + darwin notification** 이 전부다 —
/// 앱은 뒤에 있어도, 숨어 있어도, 커서가 남의 앱에 있어도 집행한다.
/// 스냅샷 길(#24 B 층, `QASnapshot.swift`)과 **같은 모양**이고 방향만 반대다:
/// 저쪽은 화면을 파일로 내보내고, 이쪽은 동작을 파일로 받아들인다.
/// 잔심부름(폴더·시각 도장·로그·관찰자 설치)은 둘 다 `QAChannel` 것을 쓴다.
///
/// ## 쓰는 법
///
/// 유효한 `GHOSTBAR_QA_SESSION=example`로 QA 앱을 실행한 경우:
///
///     echo '{"id":"t1","js":"document.querySelectorAll(\".card\").length"}' \
///       > /tmp/ghostbar-qa-example/drive.json
///     notifyutil -p com.local.ghostbar.qa.drive.example
///     cat /tmp/ghostbar-qa-example/drive-result-t1.json
///     cat /tmp/ghostbar-qa-example/qa-drive.log
///
/// `id` 는 결과 파일 이름이 된다. 파싱조차 못 해서 **id 를 모를 때**의 결과는
/// `drive-result-error.json` 으로 간다 — 「결과가 없다」와 「트리거가 안 왔다」를
/// 결과 파일만 보고도 가를 수 있게.
///
/// ⚠ **id 는 매 요청 새로 쓰는 것을 권장한다.** 트리거 하나가 자기 결과 슬롯
/// (`drive-result-<id>.json` 과 `drive-result-error.json`)을 **집행 전에 지우고 시작**하므로
/// 낡은 결과가 이번 것으로 읽히는 일은 없다. 그래도 id 를 재사용하면 **로그와 결과의 짝이
/// 사람 눈에서 흐려진다** — 같은 이름의 파일이 언제 것인지 로그를 뒤져야 안다.
///
/// ⚠ **유효한 QA 세션에서만 열린다.** `QASession.current` 가 없는 정상 번들에서는
/// 관찰자 설치와 직접 `fire()` 호출이 모두 즉시 돌아온다. QA 번들은 명시적인 세션 ID와
/// 절대 볼트 경로를 검증한 뒤에만 이 값을 만든다 — 환경변수를 주지 않은 QA 기동은
/// `AppDelegate` 가 종료하므로 조용히 열린 채로 남지 않는다.
///
/// ⚠ **창이 숨어 있어도 집행한다.** 스냅샷은 `isVisible` 가드를 두지만(안 보이는 것을
/// 찍으면 빈 그림이 나온다) 여기는 **그림이 아니라 JS 실행**이라 숨김과 무관하다 —
/// `WKWebView` 는 창이 `orderOut` 된 뒤에도 자기 문서를 그대로 들고 있다.
/// 못 하는 것은 웹뷰 자체가 아직 없을 때뿐이고, 그때는 로그와 결과 파일에 그렇게 적는다.
///
/// ## 알고 두는 한계
///
/// ① **같은 머신의 아무 프로세스나 이 통로로 웹뷰 JS 를 집행할 수 있다.** `/tmp` 는 누구나
///    쓰고 darwin notification 은 누구나 쏜다. `/tmp` 기반 로컬 QA 통로의 **수용된
///    트레이드오프**다 — #24 B 층(스냅샷)이 같은 결이고, 그쪽은 화면을 내보낸다.
///    반론과 그 자리의 판단은 #58 에 기록돼 있다.
/// ② **네이티브 잔여는 이 길로 못 조종한다.** 볼트 폴더 고르기(`NSOpenPanel`) ·
///    권한 다이얼로그 · Carbon 단축키 등록은 **웹뷰 밖**이라 JS 가 닿지 않는다.
///    설정 화면의 그 줄들을 *누르는 것*까지는 되지만, 그래서 뜨는 **패널은 못 만진다**.
///
/// ## 판정선 — 이 파일은 안 타지만 **유효한 QA 세션에서만 런타임에 열린다**
///
/// 이 파일 자체는 네트워크를 안 탄다 — 파일에만 쓴다. 판정선 검사
/// (`tests/check_interview_offline.py`)는 **브리지(`post`)에서 닿는 것만 순회하므로 이
/// 파일은 그 그래프 밖이다** — darwin notification 이 진입점이라 화면에서 오는 길이 없다.
/// 그래서 그 검사가 `QA_CHANNEL_FILES` 로 **선언한 목록**에 이 파일을 세워 통째로 훑는다
/// (`정관 2조`). 여기 `URLSession`·`URLRequest`·`http` 가 들어오면 그 절이 빨개진다.
///
/// ⚠ **유효한 QA 세션의 이 통로는 임의 JS 를 집행하므로 런타임에 `fetch()` 가 가능하다.**
/// 요청 파일에 그렇게 적어 쏘면 웹뷰가 바깥을 부른다 — **정적 검사가 원리적으로 못 닫는
/// 구멍**이고, QA 통로의 **수용된 성질**이다(①과 같은 결: 통로가 있다는 것 자체가 대가다).
/// 운영 경계는 **면접 실전 중에는 QA 드라이브를 안 쏘는 것**이다. 정상 번들은 코드 문턱에서
/// 이 통로를 열지 않는다.
/// 정적 검사가 지키는 것은 *제품 코드가 스스로 바깥을 부르지 않는다*이지
/// *이 통로로 아무것도 못 한다*가 아니다.
enum QADrive {

    /// CLI 에서 쏘는 이름. `notifyutil -p <이것>`.
    static var signal: String { QAChannel.signal("drive") }

    /// 주고받는 자리. 스냅샷과 **같은 폴더**다 — `QAChannel` 이 든다.
    static var outputDirectory: String { QAChannel.outputDirectory }

    /// 무엇을 집행할지 적어두는 파일. `{"id": "<문자열>", "js": "<실행할 JS>"}`.
    static var requestPath: String { outputDirectory + "/drive.json" }

    /// 매 트리거마다 한 줄. **성공도 적는다** — 「결과 파일이 없다」가 *집행이 실패한 것*인지
    /// *트리거가 안 온 것*인지 구별 못 하면 QA 가 헛짚는다.
    static var logPath: String { outputDirectory + "/qa-drive.log" }

    // MARK: - 설치

    /// darwin notify 관찰자를 건다. `AppDelegate` 가 기동에 한 번 부른다.
    /// 전용 스레드·런루프 이야기는 `QAChannel.installObserver` 가 든다.
    static func installQADriveObserver() {
        guard QASession.current != nil else { return }
        QAChannel.installObserver(signal: signal) { QADrive.fire() }
    }

    // MARK: - 한 번 집행

    /// 트리거 한 번 = 요청 하나. 메인 스레드에서 돈다.
    static func fire() {
        guard QASession.current != nil else { return }
        let stamp = QAChannel.timestamp()
        QAChannel.ensureDirectory()
        // ⚠ **낡은 결과부터 치운다.** 안 그러면 이번 트리거가 결과를 못 쓴 경우
        //   (요청 파일이 없다·id 를 못 읽었다) 지난번 성공이 그 자리에 그대로 남아
        //   QA 가 **이번 것으로 읽는다.** id 를 모를 때의 자리는 지금 지우고,
        //   id 별 자리는 id 를 읽은 직후에 지운다.
        clearResult(id: nil)

        guard let raw = FileManager.default.contents(atPath: requestPath) else {
            fail(stamp, id: nil, "요청 파일이 없다: \(requestPath)")
            return
        }
        let parsed = try? JSONSerialization.jsonObject(with: raw)
        guard let obj = parsed as? [String: Any],
              let js = obj["js"] as? String else {
            fail(stamp, id: nil, "요청을 못 읽었다 — {\"id\":…, \"js\":…} 모양이 아니다")
            return
        }
        // ⚠ id 는 **파일 이름이 된다.** 경로를 품은 id 는 결과를 엉뚱한 데 쓰게 하므로
        //   아예 못 읽은 것으로 취급한다 — 조용히 고쳐 쓰면 QA 가 자기 결과 파일을 못 찾는다.
        guard let id = obj["id"] as? String, !id.isEmpty,
              !id.contains("/"), id != ".", id != ".." else {
            fail(stamp, id: nil, "id 가 비었거나 파일 이름으로 못 쓴다 (경로 문자 금지)")
            return
        }
        clearResult(id: id)

        // ⚠ **`isVisible` 를 안 본다** — 머리글 참고. 숨은 창의 웹뷰도 문서를 들고 있다.
        guard let chat = (NSApp.delegate as? AppDelegate)?.chatWindow else {
            fail(stamp, id: id, "채팅 창이 아직 안 만들어졌다 — 집행할 웹뷰가 없다")
            return
        }

        chat.webView.view.evaluateJavaScript(js) { value, error in
            if let error = error {
                fail(stamp, id: id, "\(error)")
            } else {
                succeed(stamp, id: id, value: value)
            }
        }
    }

    // MARK: - 결과 한 벌

    // ★ 결과를 쓰는 길은 **둘뿐**이다: `succeed` 와 `fail`. `write` 는 private 이고
    //   둘 말고는 아무도 안 부른다 — 그래서 `ok: true` 인데 `error` 가 붙거나 그 반대인
    //   조합이 **애초에 안 만들어진다.** (리뷰가 물은 「타입이 막게」의 이 파일 판이다:
    //   새 타입을 세우는 대신 만드는 자리를 둘로 좁혔다.)

    /// 성공 한 벌 — 로그와 결과 파일에 **같은 사실**을 적는다.
    private static func succeed(_ stamp: String, id: String, value: Any?) {
        QAChannel.append("\(stamp) id=\(id) 성공 → drive-result-\(id).json", to: logPath)
        write(id: id, ok: true, value: value, error: nil)
    }

    /// 실패 한 벌. **문구를 한 번만 쓴다** — 로그와 결과 파일이 갈리면 QA 가 어느 쪽을
    /// 믿을지 모른다. `id` 가 `nil` 이면 결과는 `drive-result-error.json` 으로 간다.
    private static func fail(_ stamp: String, id: String?, _ reason: String) {
        let head = id.map { "id=\($0) 실패 — " } ?? ""
        QAChannel.append("\(stamp) \(head)\(reason)", to: logPath)
        write(id: id, ok: false, value: nil, error: reason)
    }

    /// 결과 파일의 경로. **id 를 모르면 `drive-result-error.json`.**
    private static func resultPath(id: String?) -> String {
        outputDirectory + "/drive-result-\(id ?? "error").json"
    }

    /// 이번 트리거가 쓸 자리를 비운다 — 낡은 결과가 이번 것으로 읽히지 않게.
    private static func clearResult(id: String?) {
        try? FileManager.default.removeItem(atPath: resultPath(id: id))
    }

    private static func write(id: String?, ok: Bool, value: Any?, error: String?) {
        QAChannel.ensureDirectory()
        var payload: [String: Any] = ["id": id ?? "error", "ok": ok]
        if QASession.current != nil, let chat = (NSApp.delegate as? AppDelegate)?.chatWindow {
            payload["native"] = ["windowVisible": chat.window.isVisible,
                                 "windowKey": chat.window.isKeyWindow,
                                 "appActive": NSApp.isActive]
        }
        if ok { payload["value"] = jsonSafeValue(value) }
        if let error = error { payload["error"] = error }
        // ⚠ 직렬화는 여기서 실패할 길이 없다 — `jsonSafeValue` 가 못 담는 것을 이미
        //   문자열로 강등했고 나머지는 String·Bool 이다. 그래서 폴백을 안 둔다
        //   (전엔 재직렬화 재시도 + 하드코딩 바이트 두 층이 있었는데 **도달 불가 죽은 코드**였다).
        //   `try?` 로 두는 것은 파일 쓰기 쪽(디스크·권한) 때문이다.
        guard let bytes = try? JSONSerialization.data(withJSONObject: payload,
                                                      options: [.fragmentsAllowed]) else { return }
        try? bytes.write(to: URL(fileURLWithPath: resultPath(id: id)))
    }

    /// JS 가 돌려준 것을 JSON 에 담을 수 있는 모양으로 바꾼다.
    ///
    /// `undefined`·`null` 은 **JSON null** 이다 — 「값이 없다」와 「집행이 실패했다」를
    /// 가르는 것은 `ok` 이지 `value` 가 아니다. 담을 수 없는 것(날짜 등)은 버리지 않고
    /// `String(describing:)` 으로 **강등해서라도 쓴다** — 빈 결과보다 낫다.
    private static func jsonSafeValue(_ raw: Any?) -> Any {
        guard let raw = raw, !(raw is NSNull) else { return NSNull() }
        return JSONSerialization.isValidJSONObject([raw]) ? raw : String(describing: raw)
    }
}
