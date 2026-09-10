import AppKit
import WebKit

class ChatWindow: NSObject, NSWindowDelegate {
    let window: MovableWindow
    let webView: WKWebViewWrapper
    /// 웹 콘텐츠 **뒤**의 블러 판 (#61 B). 세기는 `applyWindowStyle` 이 정한다.
    private var backdrop: NSVisualEffectView?

    override init() {
        // 기동은 언제나 쌓기 모드다 — 그 모드의 자리를 되살린다.
        let savedStr = UserDefaults.standard.string(forKey: ChatWindow.frameKey("stack"))
        let defaultFrame = NSRect(x: 0, y: 0, width: 800, height: 620)
        var initialFrame = defaultFrame
        var shouldCenter = true
        if let s = savedStr {
            let f = NSRectFromString(s)
            if f.width > 100 && f.height > 100 { initialFrame = f; shouldCenter = false }
        }

        window = MovableWindow(
            contentRect: initialFrame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // ★ 창 단추 셋은 **모드가 정한다** (#67 재편). 여기서는 숨긴 채로 뜨고, 화면이 첫
        //   `resizeWindow` 를 보내는 순간 `applyMode` 가 쌓기면 켠다 — 면접 오버레이에
        //   창 단추가 뜨면 그것이 곧 「이 창은 앱이다」라는 표지가 된다.
        //   ⚠ 순서가 이 방향인 이유: 창은 화면(JS)보다 먼저 뜬다. 켜 놓고 시작하면
        //     면접 모드로 복귀하는 사람이 **단추가 깜빡이는 것**을 본다.
        ChatWindow.setWindowButtons(window, on: false)
        window.level = .floating
        if shouldCenter { window.center() }
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true

        webView = WKWebViewWrapper(frame: window.contentLayoutRect)
        webView.view.autoresizingMask = [.width, .height]
        // ★ 블러 판 (#6 → #61 B) — **웹 콘텐츠 뒤에 깔린다.** 화면(CSS)은 창 **뒤**를 못
        //   흐리게 하고(`backdrop-filter` 는 같은 문서 안만 본다), 그래서 이 층은 Swift 것이다.
        //   ⚠ `contentView` 가 이제 이 뷰다. `WindowPrivacy` 의 QA 표식은 **자식 창**이라
        //     여기 영향을 안 받는다(그 파일 `attachBadge` 머리글의 그 실측).
        //   ⚠ 세기는 `alphaValue` 로 낸다 — 재료(`material`)를 바꿔 가며 세기를 흉내내면
        //     단계가 몇 개짜리 이산값이 되고 슬라이더가 거짓말을 한다.
        let backdrop = NSVisualEffectView(frame: window.contentLayoutRect)
        backdrop.material = .hudWindow
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.autoresizingMask = [.width, .height]
        self.backdrop = backdrop
        // ⚠ 웹뷰는 블러 판의 **자식이 아니라 형제**다. 자식이면 `applyWindowStyle` 의
        //   `isHidden`(기본 블러 0)이 웹뷰까지 숨겨 **실행하자마자 창이 통째로 투명**해진다 —
        //   `실측 2026-08-31`: 그 모양으로 출고돼 박선호가 빈 화면을 받았다.
        let container = NSView(frame: window.contentLayoutRect)
        container.autoresizingMask = [.width, .height]
        backdrop.frame = container.bounds
        webView.view.frame = container.bounds
        container.addSubview(backdrop)
        container.addSubview(webView.view)
        window.contentView = container
        // ⚠ **`contentView` 를 앉힌 뒤에** 부른다. 전엔 이 줄이 위(`hasShadow` 앞)에 있었는데,
        //   그러면 QA 표식이 방금 갈아끼운 `contentView` 와 함께 떨어져 나간다 (#24 C 층).
        WindowPrivacy.apply(to: window)
        super.init()
        window.delegate = self
        applyWindowStyle()
    }

    /// 저장된 블러 세기를 창에 건다 (#61 B). **여러 번 불려도 안전하다** — 설정 화면의
    /// 슬라이더가 움직일 때마다 온다.
    /// ⚠ `0` 이면 판을 **숨긴다.** `alphaValue = 0` 인 `NSVisualEffectView` 는 안 그려지지만
    /// 합성 층에는 남는다 — 안 쓰는 층을 남겨 둘 이유가 없다.
    func applyWindowStyle() {
        guard let b = backdrop else { return }
        let blur = WindowStyle.blur
        b.isHidden = blur <= 0.001
        b.alphaValue = blur
    }

    func showAndFocus() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        WindowPrivacy.apply(to: window)
    }

    func windowDidResize(_ notification: Notification) { saveFrame() }
    func windowDidMove(_ notification: Notification)   { saveFrame() }
    func windowWillClose(_ notification: Notification) {}
    /// 닫기가 전체화면에서 눌렸으면 `hideWindow` 가 먼저 나오기만 시켰다 — 다 나온 여기서 숨긴다.
    func windowDidExitFullScreen(_ notification: Notification) { webView.finishHideAfterFullScreen() }

    /// 모드마다 따로 기억한다 — 면접 오버레이는 면접관 얼굴 위에, 쌓기 창은 책상 위에.
    static func frameKey(_ mode: String) -> String { "windowFrame.\(mode)" }

    /// ★ 창 단추 셋(닫기·최소화·확대)을 켜고 끈다 (#67 재편, 박선호가 목업에서 확정한
    /// **macOS 크롬**). 켜는 자리는 `applyMode` 하나다 — 쌓기·연습은 「일반 앱」이고
    /// 면접은 오버레이라, 그 갈림이 이미 `live` 로 서 있다.
    ///
    /// ⚠ **이것을 「신호등」이라 부르지 않는다.** 이 레포에서 그 낱말은 준비도 하나를 뜻한다
    /// (`CONTEXT.md`: *"시스템 상태에는 절대 안 쓴다"*). 색이 셋이라고 같은 말을 쓰면
    /// 그 불변식이 문서에서만 참이 된다.
    /// ⚠ **확대(zoom)가 실제로 먹는다.** `styleMask` 에 `.resizable` 이 있어서다 — 없으면
    /// 단추는 뜨는데 눌러도 아무 일이 안 난다(이 앱에서 가장 비싼 실패: 독 아이콘이 없어
    /// 사람이 앱이 죽었는지 아닌지 못 가린다).
    /// ⚠ **닫기는 창을 없애지 않는다** — `isReleasedWhenClosed` 가 `false` 라 화면의 ✕ 와
    /// 같은 자리로 간다(`windowShouldClose`).
    static func setWindowButtons(_ w: NSWindow, on: Bool) {
        w.standardWindowButton(.closeButton)?.isHidden       = !on
        w.standardWindowButton(.miniaturizeButton)?.isHidden = !on
        w.standardWindowButton(.zoomButton)?.isHidden        = !on
    }

    /// ★ 창 단추의 닫기가 **화면의 ✕ 와 같은 일**을 하게 한다 (#67 재편).
    ///
    /// 그냥 닫게 두면 창은 사라지는데 귀(마이크·시스템 오디오)가 살아 있을 수 있고,
    /// 독 아이콘도 없어 되부를 길이 단축키뿐이라는 것을 사람이 모른다.
    ///
    /// ⚠ **여기서 그 일을 다시 짜지 않는다** (matt Standards 리뷰). 화면의 ✕ 는 `closeWindow`
    /// 통로로 가고 그 통로가 이미 「귀 끄기 + 숨기기」를 들고 있다 — 여기서 두 줄을 베끼면
    /// 그 통로에 한 줄이 늘 때 **창 단추의 닫기만 조용히 낡는다**(이 파일이 아는 그 모양).
    /// 그래서 같은 함수를 부른다.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        webView.hideWindow()
        return false
    }

    /// ⚠ **전체화면일 때는 안 적는다** (`실측 2026-09-02`, #67 재편의 **창 단추** 검증 중에 잡혔다).
    /// 확대 단추로 한 번 전체화면에 들어가면 `windowDidResize` 가 **화면 크기 그대로**를
    /// 적었고, 나온 뒤에도 그 값이 남아 **다음 기동부터 창이 영영 화면만 하게** 떴다
    /// (`실측`: `windowFrame.stack` 이 `{{245,81},{1180,760}}` → `{{0,0},{1512,949}}`).
    /// 전체화면은 「이 창을 어디에 뒀나」가 아니라 **잠깐의 상태**라, 기억할 자리가 아니다.
    private func saveFrame() {
        guard !window.styleMask.contains(.fullScreen) else { return }
        UserDefaults.standard.set(NSStringFromRect(window.frame),
                                  forKey: ChatWindow.frameKey(window.modeKey))
    }
}
