import AppKit

final class ChatWindow: NSObject, NSWindowDelegate {
    let window: MovableWindow
    let webView: WKWebViewWrapper
    private let backdrop: NSVisualEffectView

    override init() {
        let stored = UserDefaults.standard.string(forKey: Self.frameKey("stack"))
            .map(NSRectFromString)
        let restored = stored.flatMap { $0.width > 100 && $0.height > 100 ? $0 : nil }
        let frame = restored ?? NSRect(x: 0, y: 0, width: 800, height: 620)
        window = MovableWindow(contentRect: frame,
                               styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                               backing: .buffered, defer: false)
        let bounds = NSRect(origin: .zero, size: frame.size)
        webView = WKWebViewWrapper(frame: bounds)
        backdrop = NSVisualEffectView(frame: bounds)
        super.init()
        window.title = "Clonie"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        Self.setWindowButtons(window, on: false)
        if restored == nil { window.center() }
        backdrop.material = .hudWindow
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        let content = NSView(frame: bounds)
        content.autoresizingMask = [.width, .height]
        // Siblings keep the editor visible when the optional blur layer is hidden.
        for layer in [backdrop, webView.view] as [NSView] {
            layer.autoresizingMask = [.width, .height]
            content.addSubview(layer)
        }
        window.contentView = content
        WindowPrivacy.apply(to: window)
        window.delegate = self
        applyWindowStyle()
    }

    func showAndFocus() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        WindowPrivacy.apply(to: window)
    }

    func applyWindowStyle() {
        backdrop.alphaValue = WindowStyle.blur
        backdrop.isHidden = backdrop.alphaValue <= 0.001
    }

    static func frameKey(_ mode: String) -> String { "windowFrame.\(mode)" }

    static func setWindowButtons(_ window: NSWindow, on: Bool) {
        for button: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = !on
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        webView.hideWindow()
        return false
    }

    func windowDidExitFullScreen(_ notification: Notification) { webView.finishHideAfterFullScreen() }
    func windowDidResize(_ notification: Notification) { saveFrame() }
    func windowDidMove(_ notification: Notification) { saveFrame() }

    private func saveFrame() {
        guard !window.styleMask.contains(.fullScreen) else { return }
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: Self.frameKey(window.modeKey))
    }
}
