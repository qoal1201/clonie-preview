import AppKit
import ClonieCore

final class ChatWindow: NSObject, NSWindowDelegate {
    let window: MovableWindow
    let webView: WKWebViewWrapper
    private let backdrop: NSVisualEffectView
    private var accessibilityObserver: NSObjectProtocol?
    private var fullScreenChanging = false

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
        window.level = .normal
        Self.setWindowButtons(window, on: true)
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
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let preferences = AccessibilityPreferences.current
            self.applyWindowStyle(preferences: preferences)
            self.webView.sendAccessibilityPreferences(preferences)
        }
    }

    deinit {
        if let accessibilityObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver)
        }
    }

    func showAndFocus() {
        webView.reapplyLatestWindowMode()
        NSApp.activate()
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        WindowPrivacy.apply(to: window)
    }

    func applyWindowStyle(preferences: AccessibilityPreferences = .current) {
        let transparent = WindowStyle.usesTransparentBackground(
            mode: window.modeKey, reduceTransparency: preferences.reduceTransparency)
        // Stack includes settings, preparation and import, including the initial WebKit load.
        window.isOpaque = !transparent
        window.backgroundColor = transparent
            ? .clear
            : NSColor(calibratedRed: 23 / 255, green: 23 / 255, blue: 26 / 255, alpha: 1)
        backdrop.alphaValue = transparent ? WindowStyle.blur : 0
        backdrop.isHidden = backdrop.alphaValue <= 0.001
    }

    static func frameKey(_ mode: String) -> String { "windowFrame.\(mode)" }

    /// Stack keeps the user's size. Overlay modes keep only their last position and use the
    /// size requested by the current screen.
    static func frameForMode(current: NSRect, remembered: NSRect?, defaultFrame: NSRect,
                             sameMode: Bool, keepsRememberedSize: Bool) -> NSRect {
        WindowFramePolicy.frame(
            current: current, remembered: remembered, defaultFrame: defaultFrame,
            sameMode: sameMode, keepsRememberedSize: keepsRememberedSize)
    }

    /// A frame saved on a disconnected display must still leave the whole window reachable.
    static func frameOnScreen(_ frame: NSRect, visibleFrames: [NSRect], preferred: NSRect?) -> NSRect {
        WindowFramePolicy.frameOnScreen(frame, visibleFrames: visibleFrames, preferred: preferred)
    }

    static func setWindowButtons(_ window: NSWindow, on: Bool) {
        for button: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = !on
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        webView.hideWindow()
        return false
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        fullScreenChanging = true
        webView.windowWillEnterFullScreen()
    }
    func windowDidEnterFullScreen(_ notification: Notification) {
        webView.windowDidEnterFullScreen()
        fullScreenChanging = false
    }
    func windowWillExitFullScreen(_ notification: Notification) {
        fullScreenChanging = true
        webView.windowWillExitFullScreen()
    }
    func windowDidExitFullScreen(_ notification: Notification) {
        webView.windowDidExitFullScreen()
        fullScreenChanging = false
    }
    func windowDidResize(_ notification: Notification) { saveFrame() }
    func windowDidMove(_ notification: Notification) { saveFrame() }

    private func saveFrame() {
        guard !fullScreenChanging, webView.canPersistWindowFrame,
              !window.styleMask.contains(.fullScreen) else { return }
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: Self.frameKey(window.modeKey))
    }
}
