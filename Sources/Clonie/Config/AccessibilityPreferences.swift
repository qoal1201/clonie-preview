import AppKit

/// System display preferences are presentation overrides, never saved window settings.
struct AccessibilityPreferences: Encodable {
    let reduceTransparency: Bool
    let increaseContrast: Bool
    let reduceMotion: Bool

    static var current: Self {
        let workspace = NSWorkspace.shared
        return Self(
            reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
            increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast,
            reduceMotion: workspace.accessibilityDisplayShouldReduceMotion
        )
    }
}
