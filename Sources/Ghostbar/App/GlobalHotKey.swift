import Carbon

/// 자리마다 콜백 하나. **Carbon 콜백이 C 함수라 인스턴스를 못 물어서** 전역에 둔다.
/// 키는 `EventHotKeyID.id` 이고 그게 곧 `GlobalHotKey.Slot` 이다.
private var _hotKeyCallbacks: [UInt32: () -> Void] = [:]

/// ⚠ **어느 단축키가 눌렸는지 이벤트에서 읽어야 한다.**
/// 전엔 이 함수가 `EventHotKeyID` 를 안 보고 콜백 하나를 무조건 불렀다 —
/// 그래서 둘째를 등록하면 첫째가 그 자리를 잃었다 (#2 실측 2026-08-26).
private func hotKeyProc(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var hkID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hkID
    )
    guard status == noErr, let callback = _hotKeyCallbacks[hkID.id] else { return noErr }
    callback()
    return noErr
}

/// 앱이 앞에 없어도 먹는 단축키. **여러 개를 든다** (#2).
class GlobalHotKey {

    /// 전역 단축키가 사는 자리. `rawValue` 가 Carbon 의 `EventHotKeyID.id` 로 그대로 간다.
    /// ⚠ **0 을 쓰지 마라** — 등록 안 된 자리와 구별이 안 된다.
    enum Slot: UInt32, CaseIterable {
        case toggle  = 1   // 창 보이기/숨기기
        case capture = 2   // 화면 캡처 (#2)

        /// 화면(JS)이 부르는 이름. **여기가 그 낱말의 정본이다** — 화면은 이 글자를 그대로 보낸다.
        var name: String {
            switch self {
            case .toggle:  return "toggle"
            case .capture: return "capture"
            }
        }

        /// 모르는 이름은 `nil`. 화면이 오래됐거나 오타면 **아무 자리도 안 건드린다.**
        init?(name: String) {
            guard let s = Slot.allCases.first(where: { $0.name == name }) else { return nil }
            self = s
        }
    }

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?

    private static let keyCodeMap: [String: UInt32] = [
        "a": 0,  "s": 1,  "d": 2,  "f": 3,  "h": 4,  "g": 5,
        "z": 6,  "x": 7,  "c": 8,  "v": 9,  "b": 11, "q": 12,
        "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
        "9": 25, "7": 26, "8": 28, "0": 29,
        "o": 31, "u": 32, "i": 34, "p": 35, "l": 37,
        "j": 38, "k": 40, "n": 45, "m": 46,
    ]

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyProc, 1, &spec, nil, &handler)
    }

    /// 한 자리의 단축키를 (다시) 등록한다.
    ///
    /// - `action` 을 주면 그 자리의 콜백을 갈아끼운다. 안 주면 콜백은 그대로 두고 키만 바꾼다 —
    ///   설정창에서 단축키를 고쳤을 때 쓰는 길이다.
    /// - **돌려주는 값이 「지금 이 단축키가 실제로 먹나」다.**
    ///
    /// ⚠ **`false` 를 삼키지 마라.** 전엔 키가 없으면 `guard` 로 조용히 return 했고,
    /// 그래서 기본 캡처 단축키(`⌘⇧` · 키 없음)가 **등록된 적이 없는데 아무도 몰랐다**
    /// (#2 실측 2026-08-26: 실패 모양이 침묵이었다). 부르는 쪽이 이 값을 보고 빨갛게 만든다.
    @discardableResult
    func register(_ slot: Slot, _ shortcut: RecordingShortcut,
                  action: (() -> Void)? = nil) -> Bool {
        if let action = action { _hotKeyCallbacks[slot.rawValue] = action }
        if let old = refs[slot.rawValue] {
            UnregisterEventHotKey(old)
            refs[slot.rawValue] = nil
        }
        // 키 없는 단축키(모디파이어만)는 Carbon 이 못 잡는다. 그걸 고른 것 자체가 실패다.
        guard !shortcut.key.isEmpty,
              let keyCode = Self.keyCodeMap[shortcut.key.lowercased()] else { return false }
        var carbonMods: UInt32 = 0
        if shortcut.modifiers.contains(.command) { carbonMods |= UInt32(cmdKey) }
        if shortcut.modifiers.contains(.option)  { carbonMods |= UInt32(optionKey) }
        if shortcut.modifiers.contains(.control) { carbonMods |= UInt32(controlKey) }
        if shortcut.modifiers.contains(.shift)   { carbonMods |= UInt32(shiftKey) }
        let hkID = EventHotKeyID(signature: OSType(0x5645494C), id: slot.rawValue)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, carbonMods, hkID,
                                         GetApplicationEventTarget(), 0, &ref)
        // ⚠ 다른 앱이 이미 물고 있으면 여기서 실패한다 — 그것도 침묵하면 안 된다.
        guard status == noErr, let ref = ref else { return false }
        refs[slot.rawValue] = ref
        return true
    }

    /// 그 자리가 **지금 실제로 등록돼 있나.** 설정창이 열릴 때 처음 칠하는 색이 이 값이다 —
    /// 안 그러면 기동 때 실패한 단축키가 「고치기 전까지」 초록으로 보인다 (`정관 10조`).
    func isRegistered(_ slot: Slot) -> Bool { refs[slot.rawValue] != nil }

    deinit {
        for ref in refs.values { UnregisterEventHotKey(ref) }
        if let h = handler { RemoveEventHandler(h) }
    }
}
