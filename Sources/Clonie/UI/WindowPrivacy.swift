import AppKit
import Foundation

/// Screen capture policy. Normal launches remain protected in every window.
/// A process started with CLONIE_QA_VISIBLE=1 may be captured for native testing.
/// This opt-in changes no product layout, transparency, data path, or interaction.
/// The menu-bar indicator identifies the exception and can end it for this launch.
enum WindowPrivacy {
    static let qaVisibleEnvVar = "CLONIE_QA_VISIBLE"
    static let wasCaptureTestingRequested = ProcessInfo.processInfo.environment[qaVisibleEnvVar] == "1"
    private static var captureTestingEnded = false
    private static var indicator: CaptureTestingIndicator?

    static var isQAVisible: Bool {
        !captureTestingEnded && wasCaptureTestingRequested
    }

    static func apply(to window: NSWindow) {
        window.sharingType = .none
        guard isQAVisible else { return }
        guard attachIndicator() else { return }
        window.sharingType = .readOnly
    }

    private static func attachIndicator() -> Bool {
        if indicator == nil { indicator = CaptureTestingIndicator() }
        return indicator?.isAttached == true
    }

    /// A test run can restore protection without restarting or losing its place.
    /// New windows and later mode transitions stay protected for this process.
    static func endCaptureTesting() {
        captureTestingEnded = true
        for window in NSApp.windows { apply(to: window) }
        indicator?.remove()
        indicator = nil
    }
}

/// Kept outside the app window so traffic lights, content, and hit targets are
/// identical during native testing. Like other status items, this follows the
/// user's macOS menu-bar visibility setting; it is not an in-window warning.
private final class CaptureTestingIndicator: NSObject {
    private let item: NSStatusItem
    var isAttached: Bool { item.button != nil && item.isVisible }

    override init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        item.button?.title = "Clonie ◉"
        item.button?.toolTip = "Clonie 화면 캡처 허용 — 이번 실행"
        item.button?.setAccessibilityLabel("Clonie 화면 캡처 허용")
        let menu = NSMenu()
        let status = NSMenuItem(title: "이번 실행은 화면 캡처가 허용됩니다", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        let end = NSMenuItem(title: "캡처 보호 복원", action: #selector(endTesting), keyEquivalent: "")
        end.target = self
        menu.addItem(end)
        item.menu = menu
    }

    @objc private func endTesting() { WindowPrivacy.endCaptureTesting() }
    func remove() { NSStatusBar.system.removeStatusItem(item) }
}
