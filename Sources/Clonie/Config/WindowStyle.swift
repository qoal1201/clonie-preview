import Foundation

/// 창 껍데기의 **두 손잡이** — 블러와 불투명도 (#6 → #61 B·C).
///
/// ## 둘이 어떻게 나뉘나 — 겹치지 않게
///
/// - **`blur`** = 창 **뒤**를 얼마나 흐리나. AppKit 의 `NSVisualEffectView` 가 낸다
///   (`ChatWindow.backdrop`). 화면(JS)은 이걸 못 만든다 — 그래서 Swift 가 든다.
/// - **`opacity`** = 창 **안**의 판이 얼마나 불투명한가. 화면의 `#app` 배경 알파다.
///   화면(HTML/CSS)이 그 자리라 화면이 든다.
///
/// ⚠ **둘은 곱해져서 보인다.** 판이 완전 불투명(`opacity = 1`)이면 뒤가 아무리 흐려도
/// 안 보인다 — 그게 이상한 게 아니라 **이 두 손잡이의 뜻 그대로**다: 불투명도를 내려야
/// 흐린 뒤가 드러난다. 슬라이더 둘을 나란히 두는 이유가 그것이다.
///
/// ⚠ **값은 여기 한 자리에 산다.** 화면이 `setWindowStyle` 로 밀어 주고, 창이 뜰 때
/// `setWindowStyleValues` 로 되돌아간다 — 두 곳에 기본값을 두면 한쪽이 조용히 낡는다.
enum WindowStyle {

    /// 기본값. **블러 0 · 불투명 1** = 지금까지의 그 화면이다.
    /// ⚠ 기본을 바꾸면 **이미 쓰던 사람의 창이 다음 실행에 달라진다** — 안 바꾼다.
    static let defaultBlur = 0.0
    static let defaultOpacity = 1.0

    private static let blurKey = "windowBlur"
    private static let opacityKey = "windowOpacity"

    /// 0…1 로 좁힌다. 화면에서 온 값이라 **믿지 않는다** — NaN·음수·10 이 올 수 있다.
    static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        guard v.isFinite else { return lo }
        return Swift.min(Swift.max(v, lo), hi)
    }

    static var blur: Double {
        get {
            let d = UserDefaults.standard
            guard d.object(forKey: blurKey) != nil else { return defaultBlur }
            return clamp(d.double(forKey: blurKey), 0, 1)
        }
        set { UserDefaults.standard.set(clamp(newValue, 0, 1), forKey: blurKey) }
    }

    /// ⚠ **바닥이 0 이 아니라 0.35 다.** 0 이면 창이 통째로 사라지고, 그러면 슬라이더를
    /// 되돌릴 손잡이도 같이 사라진다 — 되돌릴 수 없는 화면을 만들지 않는다.
    static let opacityFloor = 0.35

    static var opacity: Double {
        get {
            let d = UserDefaults.standard
            guard d.object(forKey: opacityKey) != nil else { return defaultOpacity }
            return clamp(d.double(forKey: opacityKey), opacityFloor, 1)
        }
        set { UserDefaults.standard.set(clamp(newValue, opacityFloor, 1), forKey: opacityKey) }
    }
}
