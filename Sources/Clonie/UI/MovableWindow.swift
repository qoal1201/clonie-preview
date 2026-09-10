import AppKit

/// WKWebView 안의 Clonie 헤더를 드래그 영역으로 사용하는 창이다.
class MovableWindow: NSWindow {
    private var isDraggingFromHeader = false

    /// 화면 모드가 헤더 높이를 조정한다. 기본값은 stack 모드의 높이다.
    var headerHeight: CGFloat = 44

    /// 창 위치를 저장할 모드별 UserDefaults 키에 사용한다.
    var modeKey = "stack"

    override func sendEvent(_ event: NSEvent) {
        let contentHeight = contentView?.bounds.height ?? frame.height
        let headerTop = contentHeight - headerHeight
        let inHeader = event.locationInWindow.y >= headerTop

        switch event.type {
        case .leftMouseDown:
            isDraggingFromHeader = inHeader
        case .leftMouseUp:
            isDraggingFromHeader = false
        case .leftMouseDragged where isDraggingFromHeader:
            let origin = frame.origin
            setFrameOrigin(NSPoint(
                x: origin.x + event.deltaX,
                y: origin.y - event.deltaY
            ))
            return
        default:
            break
        }

        super.sendEvent(event)
    }
}
