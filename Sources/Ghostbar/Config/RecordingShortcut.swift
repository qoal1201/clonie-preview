import AppKit

/// 전역 단축키 한 벌. **읽고 쓰는 것뿐이다** — 거는 것은 `GlobalHotKey`(Carbon),
/// 사람에게 보여 주는 글자는 **화면(JS)** 이 만든다.
///
/// ⚠ **글자를 여기서 안 만든다** (2026-08-31, 설정 통합). 전엔 `displayString` 이 있었고
/// 화면도 같은 글자를 만들어야 했다 — 녹화 중에는 아직 저장 안 된 조합을 그려야 하므로.
/// 자가 둘이 되는 자리라 **화면 쪽 하나만 남겼다.**
struct RecordingShortcut {
    var modifiers: NSEvent.ModifierFlags
    var key: String // empty = modifier-only

    static let defaultCapture   = RecordingShortcut(modifiers: [.command, .shift], key: "")
    static let defaultToggle    = RecordingShortcut(modifiers: [.command, .option], key: "m")

    /// 자리 하나 = **저장 접두사 하나 + 기본값 하나**. 이 짝의 정본이 여기다.
    ///
    /// ⚠ **셋째였던 「녹음(mic)」은 죽었다** (2026-08-31 실측). 접두사 `shortcut` 으로
    /// 저장까지 되고 있었는데 **읽는 곳이 없었다** — `GlobalHotKey.Slot` 에 그 자리가 없어
    /// 전역으로 안 걸렸고, 화면의 `setShortcut` 은 빈 스텁이었다. 「고를 수 있는데 아무 일도
    /// 안 나는 칸」이라 걷었다.
    static func store(for slot: GlobalHotKey.Slot) -> (prefix: String, fallback: RecordingShortcut) {
        switch slot {
        case .toggle:  return ("toggleShortcut", .defaultToggle)
        case .capture: return ("captureShortcut", .defaultCapture)
        }
    }

    static func load(prefix: String, fallback: RecordingShortcut) -> RecordingShortcut {
        let raw = UserDefaults.standard.integer(forKey: "\(prefix)Modifiers")
        guard raw != 0 else { return fallback }
        let mods = NSEvent.ModifierFlags(rawValue: UInt(raw))
            .intersection([.command, .option, .control, .shift])
        let key = UserDefaults.standard.string(forKey: "\(prefix)Key") ?? ""
        return RecordingShortcut(modifiers: mods, key: key)
    }

    static func save(_ s: RecordingShortcut, prefix: String) {
        UserDefaults.standard.set(Int(s.modifiers.rawValue), forKey: "\(prefix)Modifiers")
        UserDefaults.standard.set(s.key, forKey: "\(prefix)Key")
    }

    /// 그 자리에 지금 앉아 있는 것.
    static func current(_ slot: GlobalHotKey.Slot) -> RecordingShortcut {
        let s = store(for: slot)
        return load(prefix: s.prefix, fallback: s.fallback)
    }

    static var capture: RecordingShortcut { current(.capture) }
    static var toggle:  RecordingShortcut { current(.toggle) }

    /// 화면이 보낸 꾸러미 → 단축키. **모디파이어가 하나도 없으면 `nil`** 이다 —
    /// 맨 글자 하나를 전역 핫키로 걸면 그 키를 어디서도 못 친다.
    ///
    /// ⚠ **⇧ 단독은 모디파이어로 안 센다** (#65 ④). `⇧A` 는 그냥 대문자 `A` 라, 그것을
    /// 전역 핫키로 걸면 **어느 앱에서도 대문자를 못 친다** — 맨 글자를 막는 것과 같은 이유다.
    /// 그래서 세는 것은 `⌘`·`⌥`·`⌃` 셋이고, `⇧` 는 그 위에 얹는 것으로만 산다.
    /// 판정이 화면(`recKey`)에도 한 벌 있다 — 거기가 좁혀야 사람이 **받아들여지지 않을 조합을
    /// 애초에 못 고르고**, 여기가 좁혀야 다른 길로 들어온 것도 안 걸린다.
    static func fromJS(_ b: [String: Any]) -> RecordingShortcut? {
        var mods: NSEvent.ModifierFlags = []
        if (b["cmd"]   as? NSNumber)?.boolValue == true { mods.insert(.command) }
        if (b["opt"]   as? NSNumber)?.boolValue == true { mods.insert(.option) }
        if (b["ctrl"]  as? NSNumber)?.boolValue == true { mods.insert(.control) }
        if (b["shift"] as? NSNumber)?.boolValue == true { mods.insert(.shift) }
        guard !mods.intersection([.command, .option, .control]).isEmpty else { return nil }
        let key = (b["key"] as? String)?.lowercased() ?? ""
        return RecordingShortcut(modifiers: mods, key: key)
    }

    var jsJSON: String {
        let c = modifiers.contains(.command)
        let o = modifiers.contains(.option)
        let t = modifiers.contains(.control)
        let s = modifiers.contains(.shift)
        let k = key.replacingOccurrences(of: "\"", with: "\\\"")
        return "{\"cmd\":\(c),\"opt\":\(o),\"ctrl\":\(t),\"shift\":\(s),\"key\":\"\(k)\"}"
    }
}
