import AppKit
import ClonieCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var chatWindow: ChatWindow?
    var globalHotKey: GlobalHotKey?
    private var settingsItem: NSMenuItem?
    private var preparingToQuit = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !QASession.isQABundle || QASession.current != nil else {
            FileHandle.standardError.write(Data("[qa] Explicit CLONIE_QA_SESSION and CLONIE_QA_VAULT are required.\n".utf8))
            exit(2)
        }
        InstallationIdentity.migrateLegacyPreferences()
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
            mark.size = NSSize(width: 18, height: 18)
            mark.isTemplate = true
            item.button?.image = mark
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
        appMenu.addItem(menuItem("Clonie 종료", action: #selector(quit), key: "q"))
        let editMenu = NSMenu(title: "편집")
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

    func setSettingsEnabled(forMode mode: String) { settingsItem?.isEnabled = mode == "stack" }

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
            let picker = NSOpenPanel()
            picker.canChooseFiles = false
            picker.canChooseDirectories = true
            picker.canCreateDirectories = true
            picker.allowsMultipleSelection = false
            picker.prompt = "연결"
            picker.message = "조각이 .md 파일로 살 폴더를 고른다. 이미 쓰던 볼트를 골라도 된다."
            picker.directoryURL = VaultLocation.current
            WindowPrivacy.apply(to: picker)
            let finish: (NSApplication.ModalResponse) -> Void = { response in
                done(response == .OK ? picker.url : nil)
            }
            if let host = self?.chatWindow?.window {
                if !host.isVisible {
                    NSApp.activate()
                    host.makeKeyAndOrderFront(nil)
                }
                picker.beginSheetModal(for: host, completionHandler: finish)
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
