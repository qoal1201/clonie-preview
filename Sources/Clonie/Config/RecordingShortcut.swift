import AppKit

/// Clonie 창 표시 단축키의 저장 및 화면 브리지 계약.
struct RecordingShortcut {
    var modifiers: NSEvent.ModifierFlags
    var key: String

    private static let fields: [(String, NSEvent.ModifierFlags)] = [
        ("cmd", .command), ("opt", .option), ("ctrl", .control), ("shift", .shift)
    ]
    private static let allowed: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
    static let defaultToggle = Self(modifiers: [.command, .option], key: "m")

    static func store(for slot: GlobalHotKey.Slot) -> (prefix: String, fallback: Self) {
        switch slot {
        case .toggle: return ("toggleShortcut", defaultToggle)
        }
    }

    static func load(prefix: String, fallback: Self, defaults: UserDefaults = .standard) -> Self {
        let storedModifiers = defaults.integer(forKey: prefix + "Modifiers")
        guard storedModifiers > 0 else { return fallback }
        return Self(
            modifiers: NSEvent.ModifierFlags(rawValue: UInt(storedModifiers)).intersection(allowed),
            key: defaults.string(forKey: prefix + "Key") ?? ""
        )
    }

    static func save(_ shortcut: Self, prefix: String, defaults: UserDefaults = .standard) {
        defaults.set(shortcut.key, forKey: prefix + "Key")
        defaults.set(Int(shortcut.modifiers.rawValue), forKey: prefix + "Modifiers")
    }

    static func current(_ slot: GlobalHotKey.Slot) -> Self {
        let choice = store(for: slot)
        return load(prefix: choice.prefix, fallback: choice.fallback)
    }

    static var toggle: Self { current(.toggle) }

    /// Shift만 있는 조합은 일반 타이핑을 가로채므로 허용하지 않는다.
    static func fromJS(_ payload: [String: Any]) -> Self? {
        let flags = fields.reduce(into: NSEvent.ModifierFlags()) { result, field in
            if (payload[field.0] as? NSNumber)?.boolValue == true { result.insert(field.1) }
        }
        guard !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
        return Self(modifiers: flags, key: (payload["key"] as? String ?? "").lowercased())
    }

    /// 키 문자열도 JSON 인코더를 거친다. 따옴표·역슬래시·개행을 직접 이어 붙이지 않는다.
    var jsJSON: String {
        var payload: [String: Any] = ["key": key]
        for (name, flag) in Self.fields { payload[name] = modifiers.contains(flag) }
        // 모든 값은 String/Bool이므로 JSONSerialization이 지원하는 타입이다.
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let encoded = String(data: data, encoding: .utf8) else { return "{}" }
        return encoded
    }
}
