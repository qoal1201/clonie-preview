import AppKit
import ClonieCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var chatWindow: ChatWindow?
    var globalHotKey: GlobalHotKey?
    private var settingsItem: NSMenuItem?
    private var mainSettingsItem: NSMenuItem?
    private var preparingToQuit = false
    private var vaultPicker: NSOpenPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !QASession.isQABundle || QASession.current != nil else {
            FileHandle.standardError.write(Data("[qa] Explicit CLONIE_QA_SESSION and CLONIE_QA_VAULT are required.\n".utf8))
            exit(2)
        }
        NSApp.setActivationPolicy(.accessory)
        installMenus()
        QASnapshot.installQASnapshotObserver()
        QADrive.installQADriveObserver()
        if let session = QASession.current {
            chatWindow = ChatWindow()
            QAChannel.ensureDirectory()
            QAChannel.append("session=\(session.id) vault=\(session.vaultURL.path) pid=\(ProcessInfo.processInfo.processIdentifier)",
                             to: QAChannel.outputDirectory + "/session.log")
        } else {
            let hotKeys = GlobalHotKey()
            hotKeys.register(.toggle, RecordingShortcut.toggle) { [weak self] in
                self?.hotKeyToggleChat()
            }
            globalHotKey = hotKeys
            toggleChat()
        }
    }

    private func installMenus() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let mark = Bundle.main.image(forResource: "ClonieMenuTemplate") {
            let menuMarkWidth: CGFloat = 18
            let aspectRatio = mark.size.width > 0 ? mark.size.height / mark.size.width : 1
            mark.size = NSSize(width: menuMarkWidth, height: menuMarkWidth * aspectRatio)
            mark.isTemplate = true
            item.button?.image = mark
            item.button?.imageScaling = .scaleProportionallyDown
            item.button?.imagePosition = QASession.isQABundle ? .imageLeft : .imageOnly
            item.button?.title = QASession.isQABundle ? " QA" : ""
        } else {
            item.button?.title = QASession.isQABundle ? "Clonie QA" : "Clonie"
        }
        // Activate after a menu action; activation during menu tracking closes the menu.
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(menuItem("Clonie 열기", action: #selector(toggleChat)))
        menu.addItem(.separator())
        let settings = menuItem("설정…", action: #selector(configureBackend))
        settingsItem = settings
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(menuItem("Clonie 종료", action: #selector(quit), key: "q"))
        item.menu = menu

        let main = NSMenu()
        let appMenu = NSMenu(title: "Clonie")
        appMenu.autoenablesItems = false
        let mainSettings = menuItem("설정…", action: #selector(configureBackend), key: ",")
        mainSettingsItem = mainSettings
        appMenu.addItem(mainSettings)
        appMenu.addItem(.separator())
        appMenu.addItem(menuItem("Clonie 종료", action: #selector(quit), key: "q"))
        let editMenu = NSMenu(title: "편집")
        editMenu.addItem(menuItem("실행 취소", action: #selector(undoEditor), key: "z"))
        let redo = menuItem("다시 실행", action: #selector(redoEditor), key: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        for (title, action, key) in [
            ("오려두기", #selector(NSText.cut(_:)), "x"),
            ("복사하기", #selector(NSText.copy(_:)), "c"),
            ("붙여넣기", #selector(NSText.paste(_:)), "v"),
            ("전체 선택", #selector(NSText.selectAll(_:)), "a")
        ] {
            editMenu.addItem(NSMenuItem(title: title, action: action, keyEquivalent: key))
        }
        for submenu in [appMenu, editMenu] {
            let parent = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
            parent.submenu = submenu
            main.addItem(parent)
        }
        NSApp.mainMenu = main
    }

    @objc private func undoEditor() { performEditorHistory("undo") }
    @objc private func redoEditor() { performEditorHistory("redo") }

    private func performEditorHistory(_ direction: String) {
        guard let web = chatWindow?.webView.view,
              let host = web.window,
              (NSApp.keyWindow ?? host) === host,
              host.attachedSheet == nil else {
            NSApp.sendAction(NSSelectorFromString(direction + ":"), to: nil, from: self)
            return
        }
        // An inactive window has no NSApp.keyWindow. Its DOM still owns the focused
        // field and history. Let the page choose CM versus ordinary input history;
        // a separate native window or sheet keeps the AppKit responder chain.
        web.evaluateJavaScript("performEditorHistory('\(direction)')", completionHandler: nil)
    }

    private func menuItem(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc func toggleChat() {
        if chatWindow == nil { chatWindow = ChatWindow() }
        chatWindow?.showAndFocus()
    }

    func hotKeyToggleChat() {
        if let chatWindow, chatWindow.window.isVisible {
            chatWindow.webView.hideWindow()
            return
        }
        toggleChat()
        chatWindow?.webView.flushPendingVaultReload()
        chatWindow?.webView.view.evaluateJavaScript("render()", completionHandler: nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        toggleChat()
        return true
    }

    @objc func configureBackend() {
        DispatchQueue.main.async { [weak self] in
            self?.toggleChat()
            self?.chatWindow?.webView.view.evaluateJavaScript("openSettingsScreen()", completionHandler: nil)
        }
    }

    func setSettingsEnabled(forMode mode: String) {
        settingsItem?.isEnabled = mode == "stack"
        mainSettingsItem?.isEnabled = mode == "stack"
    }

    /// A shortcut becomes persistent only after Carbon accepts it.
    func applyShortcut(_ slot: GlobalHotKey.Slot, _ shortcut: RecordingShortcut) -> Bool {
        let storage = RecordingShortcut.store(for: slot)
        let previous = RecordingShortcut.current(slot)
        guard globalHotKey?.register(slot, shortcut) == true else {
            globalHotKey?.register(slot, previous)
            return false
        }
        RecordingShortcut.save(shortcut, prefix: storage.prefix)
        return true
    }

    func shortcutRegistered(_ slot: GlobalHotKey.Slot) -> Bool {
        globalHotKey?.isRegistered(slot) == true
    }

    func pickVaultFolder(_ done: @escaping (URL?) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { done(nil); return }
            // A visible workspace may be behind another app. Bring its picker back
            // instead of queuing another sheet when a connection request is repeated.
            NSApp.activate()
            if let existing = self.vaultPicker {
                self.chatWindow?.window.makeKeyAndOrderFront(nil)
                existing.makeKeyAndOrderFront(nil)
                done(nil)
                return
            }
            let picker = NSOpenPanel()
            self.vaultPicker = picker
            picker.canChooseFiles = false
            picker.canChooseDirectories = true
            picker.canCreateDirectories = true
            picker.allowsMultipleSelection = false
            picker.prompt = "연결"
            picker.directoryURL = VaultLocation.current
            WindowPrivacy.apply(to: picker)
            let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
                self?.vaultPicker = nil
                done(response == .OK ? picker.url : nil)
            }
            if let host = self.chatWindow?.window {
                host.makeKeyAndOrderFront(nil)
                picker.beginSheetModal(for: host, completionHandler: finish)
                picker.makeKeyAndOrderFront(nil)
            } else {
                NSApp.activate()
                picker.level = .modalPanel
                picker.begin(completionHandler: finish)
                picker.makeKeyAndOrderFront(nil)
            }
        }
    }

    func openSystemPrivacy(_ which: String) {
        let anchors = ["mic": "Privacy_Microphone", "screen": "Privacy_ScreenCapture"]
        guard let anchor = anchors[which],
              let destination = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(destination)
    }

    // The WebView acknowledges its pending editor save before the process exits.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !preparingToQuit else { return .terminateLater }
        guard let editor = chatWindow?.webView else { return .terminateNow }
        preparingToQuit = true
        editor.prepareForTermination { [weak self] saved in
            self?.preparingToQuit = false
            sender.reply(toApplicationShouldTerminate: saved)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) { chatWindow?.webView.flushVaultWrites() }
    @objc func quit() { NSApp.terminate(nil) }
}
