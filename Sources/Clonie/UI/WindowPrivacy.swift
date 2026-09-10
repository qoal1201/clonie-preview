import AppKit
import Foundation

/// 창의 **화면 공유 노출**을 정하는 유일한 자리 (#24 C 층).
///
/// ## 왜 한 자리로 모았나
///
/// 이 앱의 제품 성질은 *"어느 모드에서도 안 잡힌다"* 다 (박선호 Q6). 그런데 그것을 만드는
/// `sharingType = .none` 이 **네 자리에 흩어져 있었다** — 채팅 창(2), 모드 전환, 설정창, 드롭다운.
/// 흩어진 판정선은 새 창을 하나 더 만들 때 **조용히 빠진다.** 그래서 대입을 여기 하나로 모으고,
/// `tests/check_qa_visible_gate.py` 가 *"`Sources/` 안에서 `sharingType` 이 이 파일 밖에 나오면 빨강"* 을 잰다.
///
/// ## 게이트 — 기본은 언제나 은신이다
///
/// 에이전트가 QA 로 확인할 수 있는 것이 **0건**이었다(#24). 네이티브 껍데기(설정창·반투명·모드 모핑)는
/// 화면 캡처로만 보이는데 창이 캡처에 안 잡히니 아무도 그 화면을 본 적이 없다.
/// → 환경변수 `CLONIE_QA_VISIBLE=1` 일 때만 `.readOnly` 로 연다.
///
/// ⚠ **이 게이트가 새면 제품이 죽는다.** 면접 중에 창이 공유에 잡히는 것이 최악의 실패다.
/// 그래서 세 겹을 건다:
///
/// 1. **먼저 `.none` 을 박고 시작한다.** 아래 `apply(to:)` 의 첫 줄이다 — 게이트 코드가
///    통째로 사라지거나 예외로 튀어도 남는 값이 은신이다. 「기본값이 무엇인가」가 **분기의
///    결과가 아니라 대입 순서**로 정해진다.
/// 2. **표식 없이는 안 켜진다.** `.readOnly` 는 표식을 다는 데 성공한 다음 줄에서만 일어난다.
///    두 줄이 **같은 함수 안**에 있고 검사가 그것을 잰다 — 표식만 지우는 편집이 불가능하다.
/// 3. **표식이 안 붙으면 은신으로 남는다.** `attachBadge` 가 `false` 를 내면 `.readOnly` 줄에
///    닿지 않는다. 실패가 「노출된 채 표식 없음」이 아니라 **「안 열림」**으로 떨어진다.
///
/// ⚠ **여기서 안 지키는 것 — 알고 두는 한계.** 켠 **뒤에** 표식 창을 누가 떼어내면
/// (`removeChildWindow`) 런타임이 그걸 모른다. 막는 것은 정적 검사 쪽이다 — 노출을 켜는
/// 코드가 이 함수 하나뿐이라는 것을 `tests/check_qa_visible_gate.py` 가 잰다.
///
/// ⚠ **`build.sh` 는 이 변수를 절대 안 세운다.** 검사가 그것도 본다.
/// `open Clonie.app` 은 환경변수를 안 넘기므로, QA 로 켜려면 알맹이를 직접 부른다:
///
///     CLONIE_QA_VISIBLE=1 ./Clonie.app/Contents/MacOS/Clonie &
///
/// ★ **판정선 밖의 길이 따로 있다** — `Services/QASnapshot.swift`(#24 B 층)는 앱이 자기 뷰를
/// 스스로 렌더해 파일로 낸다. 그건 윈도 서버를 안 타서 **이 변수 없이도 된다.**
/// 여기 C 층이 필요한 것은 「합성된 진짜 껍데기」뿐이다.
enum WindowPrivacy {

    /// ★ 게이트 이름. 검사와 문서가 같은 낱말을 보게 **여기 하나**에 둔다.
    static let qaVisibleEnvVar = "CLONIE_QA_VISIBLE"

    /// `1` 일 때만 참이다. 「비어 있지 않으면 참」이 아니다 — `0` 이나 `false` 를 넣고
    /// 껐다고 믿는 것이 흔한 조용한 실패라서, **받는 값을 하나로 좁힌다.**
    static var isQAVisible: Bool {
        ProcessInfo.processInfo.environment[qaVisibleEnvVar] == "1"
    }

    /// 이 창의 공유 노출을 정한다. **창을 만들거나 다시 띄우는 모든 자리가 이것을 부른다.**
    ///
    /// ⚠ 줄 순서가 판정선이다 (위 머리글 1·2). 고칠 때 순서를 바꾸지 마라 —
    /// `tests/check_qa_visible_gate.py` 가 빨개진다.
    static func apply(to window: NSWindow) {
        // ① 기본값. 무조건 먼저 박는다.
        window.sharingType = .none
        // ② 게이트가 닫혀 있으면 여기서 끝이다.
        guard isQAVisible else { return }
        // ③ 표식을 못 달면 **안 켠다.** 켜기와 표식이 갈라질 수 없다.
        guard attachBadge(to: window) else { return }
        window.sharingType = .readOnly
    }

    /// 지울 수 없는 표식을 창에 단다. 성공하면 `true`.
    ///
    /// 여러 번 불려도 안전하다 — `applyMode` 가 **모드 전환마다** 다시 부른다.
    /// 이미 달려 있으면 자리만 다시 잡는다.
    ///
    /// ⚠ **표식은 자식 창이다. `contentView` 의 서브뷰가 아니다** (`실측 2026-08-29`).
    /// 처음엔 `contentView` 에 서브뷰로 얹었다. 붙기는 붙었는데 — `attachBadge` 가 `true` 를
    /// 냈고 그래서 창이 실제로 캡처에 잡혔다 — **화면에는 안 보였다.** 채팅 창의
    /// `contentView` 는 `WKWebView` 라 웹 콘텐츠가 자기 레이어로 합성되고, 거기 얹은
    /// `NSView` 는 `positioned: .above` 로 넣어도 그 밑에 깔린다.
    /// **켜졌는데 표식이 안 보이는 것이 이 티켓이 막으려던 바로 그 실패**라서 자식 창으로 옮겼다.
    /// 자식 창은 합성 순서를 안 타고, 부모가 움직이면 AppKit 이 같이 옮긴다.
    private static func attachBadge(to window: NSWindow) -> Bool {
        let badge = (window.childWindows?.compactMap { $0 as? QAVisibleBadgeWindow }.first)
            ?? QAVisibleBadgeWindow(guarding: window)
        if badge.parent !== window {
            window.addChildWindow(badge, ordered: .above)
        }
        badge.reposition()
        return badge.parent === window
    }
}

/// 표식이 사는 창. **부모 창의 자식**이라 웹 콘텐츠 합성 위에 뜬다.
///
/// ⚠ 이 창 자체는 캡처에 **잡혀야 한다** — 안 잡히면 표식이 있으나 마나다.
/// `NSWindow` 기본값이 `.readOnly` 지만, 기본값에 기대지 않고 여기서 명시한다.
final class QAVisibleBadgeWindow: NSPanel {

    private weak var guarded: NSWindow?
    private var resizeWatch: NSObjectProtocol?

    static let size = NSSize(width: 186, height: 24)

    init(guarding parent: NSWindow) {
        self.guarded = parent
        super.init(contentRect: NSRect(origin: .zero, size: QAVisibleBadgeWindow.size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        sharingType = .readOnly          // ★ 표식은 잡혀야 한다
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true        // 밑에 있는 것을 계속 누를 수 있게
        level = .floating
        isReleasedWhenClosed = false
        contentView = QAVisibleBadge(frame: NSRect(origin: .zero, size: QAVisibleBadgeWindow.size))

        // 부모가 **크기**를 바꾸면 자리를 다시 잡는다. 옮기는 것은 AppKit 이 알아서 따라온다.
        resizeWatch = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: parent, queue: .main
        ) { [weak self] _ in self?.reposition() }
    }

    deinit {
        if let w = resizeWatch { NotificationCenter.default.removeObserver(w) }
    }

    /// 부모 창의 **왼쪽 위** 모서리에 앉힌다.
    func reposition() {
        guard let parent = guarded else { return }
        let f = parent.frame
        setFrameOrigin(NSPoint(x: f.minX + 8,
                               y: f.maxY - QAVisibleBadgeWindow.size.height - 8))
    }
}

/// 「이 빌드는 화면 공유에 잡힌다」를 화면에 말하는 붉은 딱지. `QAVisibleBadgeWindow` 의 알맹이다.
///
/// ⚠ **이건 장식이 아니라 인수조건이다** (#24: *"켜진 상태가 화면에 보인다 — 표식 없이는 안 켜진다"*).
/// 이 플래그가 켜진 빌드를 면접에 들고 들어가는 것이 **눈에 보여야** 한다.
final class QAVisibleBadge: NSView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0.80, green: 0.06, blue: 0.10, alpha: 0.97).cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(0.95).cgColor
        layer?.borderWidth = 1.5
        layer?.cornerRadius = 4

        let label = NSTextField(labelWithString: "QA 노출 중 — 면접 금지")
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.textColor = .white
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.frame = NSRect(x: 8, y: 4, width: frameRect.width - 16, height: frameRect.height - 8)
        label.autoresizingMask = [.width, .height]
        addSubview(label)
    }

    required init?(coder: NSCoder) { nil }

    /// 밑에 있는 것을 계속 누를 수 있게 한다.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
