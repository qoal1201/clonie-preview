import AppKit

class MovableWindow: NSWindow {
    private var dragging = false

    /// 창을 끌 수 있는 **위쪽 띠의 높이.** 모드마다 머리가 달라서 Swift 가 정해준다(`applyMode`).
    ///
    /// ⚠ 화면(HTML)의 `-webkit-app-region: drag` 로는 **창이 안 움직인다** — 그건 Electron 것이고
    /// `WKWebView` 는 안 받는다. `.drag` 클래스가 실제로 하는 일은 `user-select: none` 뿐이다.
    /// **창을 끄는 것은 이 파일이 전부다.** 그래서 이 높이가 화면의 머리 높이와 어긋나면
    /// *"창이 잘 안 움직인다"* 가 된다 (박선호 2026-08-28).
    var headerHeight: CGFloat = 44

    /// 지금 어느 모드의 창인가. **위치를 모드마다 따로 기억하려고** 든다(`ChatWindow.saveFrame`).
    /// ⚠ 하나로 기억하면 면접 오버레이를 둔 자리가 쌓기 창의 자리를 덮어써서,
    /// 다음에 켤 때 창이 **매번 다른 데** 뜬다 (박선호 2026-08-28 이 겪은 것).
    var modeKey = "stack"

    override func sendEvent(_ event: NSEvent) {
        let h = contentView?.frame.height ?? frame.height
        let inHeader = event.locationInWindow.y >= h - headerHeight
        switch event.type {
        case .leftMouseDown:
            dragging = inHeader
        case .leftMouseUp:
            dragging = false
        case .leftMouseDragged where dragging:
            let o = frame.origin
            setFrameOrigin(NSPoint(x: o.x + event.deltaX, y: o.y - event.deltaY))
            return
        default: break
        }
        super.sendEvent(event)
    }
}
