import AppKit
import ScreenCaptureKit

/// 화면 한 장을 PNG base64 로. **채팅(LLM) 경로가 쓴다** — 면접 모드는 안 부른다.
///
/// ⚠ 2026-08-28 에 `CGWindowListCreateImage` 에서 옮겨왔다. 그 API 는 **macOS 26 에서 unavailable** 이라
/// `platforms` 를 26.0 으로 올린 순간(#7) 컴파일이 멈췄다 — 승격이 데려온 강제 변경이고,
/// 애플이 대체로 지목한 것이 `ScreenCaptureKit` 이다(`정관 1조`: 상류가 가리키는 것을 쓴다).
func captureScreenBase64(maxWidth: Int = 1440) async -> String? {
    guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
          let display = content.displays.first else {
        CGRequestScreenCaptureAccess()   // 권한이 없어서 못 잡은 것일 수 있다 — 한 번 묻는다
        return nil
    }
    let scale = display.width > maxWidth ? Double(maxWidth) / Double(display.width) : 1.0
    let cfg = SCStreamConfiguration()
    cfg.width = max(1, Int(Double(display.width) * scale))
    cfg.height = max(1, Int(Double(display.height) * scale))
    let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
    guard let cg = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
    else { return nil }
    return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.base64EncodedString()
}
