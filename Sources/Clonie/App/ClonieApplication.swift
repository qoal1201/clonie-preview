import AppKit

/// Clonie의 실행 진입점.
/// AppKit이 실행 중인 동안 delegate를 강하게 유지해 앱 수명을 명시한다.
@main
enum ClonieApplication {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate

        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
