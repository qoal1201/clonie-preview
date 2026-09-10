import Carbon

/// Carbon 이벤트가 앱 객체를 직접 붙잡지 않도록 슬롯별 동작만 보관한다.
/// `GlobalHotKey` 인스턴스가 사라질 때 등록된 동작도 함께 비운다.
private var clonieHotKeyCallbacks: [UInt32: () -> Void] = [:]

private func clonieHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var identifier = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &identifier
    )
    guard status == noErr else { return status }
    clonieHotKeyCallbacks[identifier.id]?()
    return noErr
}

/// macOS 전역 단축키를 Clonie의 창 동작에 연결한다.
class GlobalHotKey {
    enum Slot: UInt32, CaseIterable {
        case toggle = 1

        var name: String {
            switch self {
            case .toggle: return "toggle"
            }
        }

        init?(name: String) {
            guard let slot = Self.allCases.first(where: { $0.name == name }) else { return nil }
            self = slot
        }
    }

    private static let keyCodes: [String: UInt32] = [
        "a": 0,  "s": 1,  "d": 2,  "f": 3,  "h": 4,  "g": 5,
        "z": 6,  "x": 7,  "c": 8,  "v": 9,  "b": 11, "q": 12,
        "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
        "9": 25, "7": 26, "8": 28, "0": 29,
        "o": 31, "u": 32, "i": 34, "p": 35, "l": 37,
        "j": 38, "k": 40, "n": 45, "m": 46,
    ]

    // FourCC("CLON") identifies Clonie's Carbon registrations.
    private static let eventSignature = OSType(0x434C4F4E)

    private var registrations: [Slot: EventHotKeyRef] = [:]
    private var callbackSlots = Set<Slot>()
    private var eventHandler: EventHandlerRef?

    init() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            clonieHotKeyHandler,
            1,
            &eventType,
            nil,
            &eventHandler
        )
        if status != noErr {
            eventHandler = nil
        }
    }

    /// 슬롯의 단축키를 등록하거나 현재 등록을 교체한다.
    /// `action`이 nil이면 기존 콜백을 유지한다.
    @discardableResult
    func register(
        _ slot: Slot,
        _ shortcut: RecordingShortcut,
        action: (() -> Void)? = nil
    ) -> Bool {
        if let action {
            clonieHotKeyCallbacks[slot.rawValue] = action
            callbackSlots.insert(slot)
        }

        unregister(slot)
        guard eventHandler != nil,
              let keyCode = Self.keyCodes[shortcut.key.lowercased()],
              !shortcut.key.isEmpty else {
            return false
        }

        var modifiers: UInt32 = 0
        if shortcut.modifiers.contains(.command) { modifiers |= UInt32(cmdKey) }
        if shortcut.modifiers.contains(.option)  { modifiers |= UInt32(optionKey) }
        if shortcut.modifiers.contains(.control) { modifiers |= UInt32(controlKey) }
        if shortcut.modifiers.contains(.shift)   { modifiers |= UInt32(shiftKey) }

        let id = EventHotKeyID(signature: Self.eventSignature, id: slot.rawValue)
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else { return false }
        registrations[slot] = reference
        return true
    }

    /// 슬롯의 Carbon 등록을 해제한다. 저장된 콜백은 다음 등록에서 재사용할 수 있게 둔다.
    func unregister(_ slot: Slot) {
        if let reference = registrations.removeValue(forKey: slot) {
            UnregisterEventHotKey(reference)
        }
    }

    func isRegistered(_ slot: Slot) -> Bool {
        registrations[slot] != nil
    }

    deinit {
        for slot in Array(registrations.keys) {
            unregister(slot)
        }
        for slot in callbackSlots {
            clonieHotKeyCallbacks.removeValue(forKey: slot.rawValue)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}
