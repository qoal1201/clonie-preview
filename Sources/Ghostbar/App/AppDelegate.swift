import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var chatWindow: ChatWindow?
    var globalHotKey: GlobalHotKey?
    private var terminationPreparationInFlight = false
    /// 메뉴바 「Settings…」 칸. **모드에 따라 회색이 된다** (#61 리뷰 발견 ⑧) —
    /// 켜고 끄는 자리는 `setSettingsEnabled(forMode:)` 하나다.
    private var settingsItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if QASession.isQABundle && QASession.current == nil {
            FileHandle.standardError.write(Data("[qa] Explicit GHOSTBAR_QA_SESSION and GHOSTBAR_QA_VAULT are required.\n".utf8))
            exit(2)
        }
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            if let image = Bundle.main.image(forResource: "ClonieMenuTemplate") {
                image.size = NSSize(width: 18, height: 18)
                image.isTemplate = true
                button.image = image
                button.imagePosition = QASession.isQABundle ? .imageLeft : .imageOnly
                button.title = QASession.isQABundle ? " QA" : ""
            } else {
                // The bundled mark is optional during development; retain the established fallback.
                button.title = QASession.isQABundle ? "⬡ QA" : "⬡"
            }
        }
        buildMenu()
        addEditMenu()
        if !QASession.isQABundle {
            try? FileManager.default.createDirectory(
                atPath: NSHomeDirectory() + "/.ollama-chat",
                withIntermediateDirectories: true)
        }
        // ★ QA 스냅샷 길 (#24 B 층). 창이 은신이라 **바깥에서는 검은 그림만** 나온다 —
        //   그래서 앱이 자기 뷰를 스스로 렌더해 파일로 낸다. 쏘는 법·왜 = `QASnapshot.swift` 머리글.
        //   유효한 QA 번들·세션에서만 등록한다. 일반 배포 앱은 진단 통로를 열지 않는다.
        QASnapshot.installQASnapshotObserver()
        // ★ QA 드라이브 길 (#58). 스냅샷의 **반대 방향**이다 — 화면을 내보내는 게 아니라
        //   집행할 JS 를 파일로 받는다. 좌표 클릭(CGEvent)이 요구하는 포커스·좌표·frontmost
        //   셋을 전부 안 쓴다. 쓰는 법·한계 = `QADrive.swift` 머리글.
        //   ⚠ 둘의 잔심부름(폴더·시각 도장·로그·관찰자 설치)은 `QAChannel.swift` 하나가 든다.
        QADrive.installQADriveObserver()
        if !QASession.isQABundle { globalHotKey = GlobalHotKey() }
        globalHotKey?.register(.toggle, RecordingShortcut.toggle) { [weak self] in
            self?.hotKeyToggleChat()
        }
        // ★ 캡처도 **전역**이다 (#2) — 창을 띄우고 버튼을 누르는 사슬의 첫 칸을 끊는다.
        // ⚠ 기본값은 아직 **키가 없어서 등록이 안 된다.** 그게 지금 맞다 — 아래 `hotKeyCapture`
        //   설명과 #2 코멘트 참고. 사용자가 설정창에서 키를 고르면 그때부터 전역으로 먹는다.
        globalHotKey?.register(.capture, RecordingShortcut.capture) { [weak self] in
            self?.hotKeyCapture()
        }
        // ★ 실행하면 창이 바로 뜬다 (박선호 2026-08-28: *"앱 실행하면 그냥 저장소 모드로 바로 켜지면 되고"*).
        //   이 앱은 `LSUIElement` 라 독 아이콘이 없다 — 창이 안 뜨면 **아무 일도 안 일어난 것으로 보인다.**
        //   상류(Ghostbar)는 단축키로 불러내는 오버레이 바였고 그래서 조용히 떴다. 우리 제품은 저장소가 먼저다.
        //   ⚠ 모드는 화면(JS)이 정한다 — 기동은 언제나 쌓기 모드다. 단축키는 **숨기고 되부르는 길**로만 남는다.
        if let qa = QASession.current {
            chatWindow = ChatWindow()
            QAChannel.ensureDirectory()
            QAChannel.append("session=\(qa.id) vault=\(qa.vaultURL.path) pid=\(ProcessInfo.processInfo.processIdentifier)",
                             to: QAChannel.outputDirectory + "/session.log")
        } else {
            toggleChat()
        }
    }

    func hotKeyToggleChat() {
        if chatWindow == nil { chatWindow = ChatWindow() }
        if chatWindow?.window.isVisible == true {
            // 숨기면 귀도 끈다 (#17) — 안 보이는 창이 마이크를 물고 있지 않게.
            chatWindow?.webView.stopInterviewEars()
            chatWindow?.window.orderOut(nil)
        } else {
            chatWindow?.showAndFocus()
            // 창이 숨어 있는 동안 볼트가 밖에서 바뀌었으면 **여기서** 다시 읽는다 (#30).
            // 떠 있는 창에 밀어넣으면 쓰던 글이 날아가서, 미뤄뒀던 것을 이 자리에서 흘려보낸다.
            chatWindow?.webView.flushPendingVaultReload()
            // 화면이 스스로 다시 켠다. 면접 모드면 `render()` 가 startListening 을 다시 연다.
            chatWindow?.webView.view.evaluateJavaScript("render()", completionHandler: nil)
        }
    }

    /// ★ 전역 캡처 (#2). **창을 안 띄운다.**
    ///
    /// 창을 띄우면 그 순간 화면이 바뀌고, 무엇보다 이 티켓이 끊으려는 사슬
    /// (*창을 띄운다 → 버튼을 누른다 → 커서가 들킨다*)이 그대로 남는다.
    /// 창이 아직 없으면 만들기만 한다 — `ChatWindow.init` 은 창을 띄우지 않는다(실측).
    ///
    /// ⚠ **v1 에는 이 결과를 쓰는 곳이 없다.** 잡힌 그림은 `storedScreenshot` 에 앉고,
    /// 그걸 읽는 유일한 자리가 `sendMessage`(네트워크)인데 지금 화면은 그 통로를 안 연다.
    /// 배선은 맞고 소비자가 없다 — 경위와 갈래 = #2 코멘트.
    func hotKeyCapture() {
        if chatWindow == nil { chatWindow = ChatWindow() }
        chatWindow?.webView.captureForHotKey()
    }

    func addEditMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Cut",        action: #selector(NSText.cut(_:)),        keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy",       action: #selector(NSText.copy(_:)),       keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste",      action: #selector(NSText.paste(_:)),      keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)),  keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        NSApp.mainMenu = mainMenu
    }

    func buildMenu() {
        let menu = NSMenu()
        // ⚠ 전엔 `menu.delegate = self` 로 `menuWillOpen` 에서 `NSApp.activate` 를 불렀다. **걷었다** —
        //   메뉴가 열리는 동안 앱을 활성화하면 **AppKit 의 메뉴 추적이 취소된다.** 메뉴가 떴다가 바로 닫힌다
        //   (박선호 2026-08-28: *"누르자마자 밑에 창이 보이고 바로 사라짐"*).
        //   ⚠ #18 이 쌓기 모드를 `.regular` 로 만들면서 **눈에 보이게 됐다** — 활성화가 이제 창까지 앞으로 끌어온다.
        //   활성화가 필요한 자리는 메뉴가 아니라 **동작**이고, `showAndFocus()` 가 이미 거기서 한다.
        menu.autoenablesItems = false
        let openItem = NSMenuItem(title: "Open chat", action: #selector(toggleChat), keyEquivalent: "")
        openItem.target = self
        openItem.isEnabled = true
        menu.addItem(openItem)
        menu.addItem(.separator())
        // ★ **면접·연습 중에는 회색이다** (#61 리뷰 발견 ⑧). 전엔 눌러도 조용히 아무 일도
        //   안 났다 — 화면이 `openSettingsScreen()` 안에서 `return` 했고, 메뉴는 멀쩡히
        //   눌리는 채였다. 「눌리는데 아무 일도 안 나는 것」은 이 앱에서 가장 비싼 실패다
        //   (독 아이콘이 없어 사람이 앱이 죽었는지 아닌지 못 가린다).
        //   ⚠ **소리를 안 쓴다.** `NSSound.beep()` 이면 면접 중에 스피커로 새어 나간다.
        //   ⚠ 배선은 `menu.delegate` 가 아니다 — 여는 순간에 손대면 AppKit 메뉴 추적이
        //     또 깨진다(바로 위 주석). 모드가 바뀔 때 `applyMode` 가 이 칸을 직접 고친다.
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(configureBackend), keyEquivalent: "")
        settingsItem.target = self
        settingsItem.isEnabled = true
        menu.addItem(settingsItem)
        self.settingsItem = settingsItem
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        quitItem.isEnabled = true
        menu.addItem(quitItem)
        statusItem?.menu = menu
    }

    /// 독 아이콘을 누르거나 ⌘Tab 으로 돌아왔을 때 **창이 앞으로 나온다.**
    ///
    /// ⚠ 일반 앱이면 당연한 동작인데 이 앱엔 없었다 — 상류는 독 아이콘이 아예 없는 `.accessory` 였기 때문이다.
    /// #18 이 쌓기 모드를 `.regular` 로 만들자 **아이콘은 생겼는데 눌러도 아무 일도 안 나는** 상태가 됐다
    /// (박선호 2026-08-28: *"일반적인 앱처럼 레이아웃 상하관계가 제대로 작동을 안하는데?"*).
    /// ✕ 로 창을 숨긴 뒤엔 특히 그렇다 — 앱이 죽은 것처럼 보인다.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        toggleChat()
        return true
    }

    /// 화면의 800ms 자동 저장과 `VaultIO` 비동기 저장 확인을 받은 뒤에만 종료한다.
    /// 이미 준비 중이면 두 번째 Quit을 새 저장으로 겹치지 않는다.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationPreparationInFlight else { return .terminateLater }
        guard let webView = chatWindow?.webView else { return .terminateNow }
        terminationPreparationInFlight = true
        webView.prepareForTermination { [weak self] ok in
            guard let self else { return }
            self.terminationPreparationInFlight = false
            NSApp.reply(toApplicationShouldTerminate: ok)
        }
        return .terminateLater
    }

    @objc func toggleChat() {
        if chatWindow == nil { chatWindow = ChatWindow() }
        chatWindow?.showAndFocus()
    }


    /// 메뉴바 「Settings…」 — **채팅창의 프론트 설정 화면을 연다** (#61 D).
    ///
    /// ★ **설정 창은 이제 하나뿐이다** (2026-08-31, 박선호: *"단축키 설정이나 그런것들도
    /// 그냥 설정창 하나로 다 통합시키고"*). 백엔드·키·모델·블러에 이어 **단축키·권한·볼트까지**
    /// 화면(HTML)으로 내려왔다 — 네이티브에 남은 것은 창이 아니라 **동작 셋**뿐이다
    /// (`pickVaultFolder` · `openSystemPrivacy` · `applyShortcut`).
    ///
    /// ⚠ **면접·연습 중에는 안 끌고 간다** — 그 판정은 화면이 한다(`openSettingsScreen`).
    /// 여기서 모드를 알려면 Swift 가 화면 상태를 한 벌 더 들어야 하고, 그 순간 자가 둘이 된다.
    /// ★ 그래서 **메뉴 칸이 그동안 회색이다**(`setSettingsEnabled(forMode:)`) — 자를 옮긴 것이
    /// 아니라, 화면이 이미 Swift 에 알려 주는 모드 이름(`resizeWindow` 의 `mode`)을 그대로
    /// 쓰는 것이다. 이 함수 안의 판정은 여전히 화면이 한다.
    /// ⚠ 화면이 아직 안 떴으면 `evaluateJavaScript` 는 **조용히 실패한다.** 그때 사람이 보는
    /// 것은 방금 뜬 채팅창이고, 톱니가 바로 거기 있다 — 막다른 길이 아니다.
    @objc func configureBackend() {
        DispatchQueue.main.async { [weak self] in
            self?.toggleChat()
            self?.chatWindow?.webView.view.evaluateJavaScript("openSettingsScreen()",
                                                              completionHandler: nil)
        }
    }

    /// 메뉴바 「Settings…」를 모드에 맞춰 켜고 끈다 (#61 리뷰 발견 ⑧).
    ///
    /// ★ **부르는 자리는 `applyMode` 하나다** — 화면이 모드를 바꿀 때마다 크기와 함께 그 이름을
    /// 보내오므로(`resizeWindow` 가 `mode` 를 얹은 그 통로), 새 통로도 새 상태도 안 만들었다.
    /// ⚠ `menu.autoenablesItems` 가 `false` 라 AppKit 이 대신 안 해 준다 — 여기서 직접 세운다.
    /// ★ **`canvas` 이름이 죽었다** (#67 재편). 뜻 지도가 쌓기 홈의 **가운데 칸**이 되면서
    /// 그 화면만의 창 크기도, `windowFrame.canvas` 라는 따로 기억하던 자리도 같이 죽었다 —
    /// 화면이 보내는 이름은 이제 `live`·`practice`·`stack` 셋뿐이다(`sizeWindow`).
    /// ⚠ 회색이 되는 것은 여전히 **화면이 못 여는 곳**뿐이다(면접·연습).
    func setSettingsEnabled(forMode mode: String) {
        settingsItem?.isEnabled = mode == "stack"
    }

    // MARK: - 네이티브 잔여 — 창이 아니라 동작 셋이다 (2026-08-31 설정 통합)
    //
    // ★ **`showShortcutPanel` 은 죽었다.** 단축키 녹화·권한 줄·볼트 줄은 전부 프론트 설정
    //   화면의 「단축키·권한」 묶음으로 갔고, 여기 남은 것은 **WebView 가 원리적으로 못 하는
    //   세 동작**뿐이다. 창이 없으니 `runModal`·`NSPanel`·위젯 배치도 같이 사라졌다.
    //   ⚠ 그래도 `WindowPrivacy.apply` 는 남는다 — `NSOpenPanel` 이 면접 중에 뜰 수 있는
    //     창이고, `tests/check_qa_visible_gate.py` 가 이 파일을 그 자리로 세고 있다.

    /// 화면이 고른 조합을 **걸어 보고, 걸렸을 때만 저장한다.**
    ///
    /// ⚠ **순서를 뒤집었다.** 전 판(`ShortcutRecorder`)은 먼저 저장하고 실패는 빨간 칸으로만
    /// 알렸다 — 그러면 다음 기동에 「저장은 됐는데 안 먹는」 단축키가 남고, 사람은 자기가 고른
    /// 것이 살아 있다고 믿는다. 여기서는 안 걸리면 **옛 것을 도로 걸고** `false` 를 돌려준다.
    ///
    /// - Returns: 지금 이 단축키가 **실제로 먹나**. 화면이 이 값으로 한 줄을 세운다.
    func applyShortcut(_ slot: GlobalHotKey.Slot, _ s: RecordingShortcut) -> Bool {
        let box = RecordingShortcut.store(for: slot)
        let old = RecordingShortcut.load(prefix: box.prefix, fallback: box.fallback)
        guard globalHotKey?.register(slot, s) == true else {
            globalHotKey?.register(slot, old)
            return false
        }
        RecordingShortcut.save(s, prefix: box.prefix)
        return true
    }

    /// 그 자리가 **지금 실제로 걸려 있나.** 화면의 점이 이 값이다.
    func shortcutRegistered(_ slot: GlobalHotKey.Slot) -> Bool {
        globalHotKey?.isRegistered(slot) ?? false
    }

    /// 볼트 폴더 고르기 (#30). **`NSOpenPanel` 이 없으면 폴더를 못 고른다** —
    /// `loadHTMLString(baseURL: nil)` 아래의 `<input type=file>` 은 뜨지도 않고,
    /// 떠도 폴더는 애초에 못 고른다(#40 이 같은 이유로 `pickIngestFiles` 통로를 냈다).
    ///
    /// - Parameter done: 고른 뒤 경로. **안 골랐으면 안 부른다** — 화면은 그대로 둔다.
    ///
    /// ★ **`runModal` 을 안 쓴다 — 시트다** (#78). 왜와 실측은 `pickAndExtractDocuments`
    /// 머리글이 든다 (같은 병이었고 같은 약이다). 자물쇠 = `tests/check_no_modal_runloop.py`.
    func pickVaultFolder(_ done: @escaping (URL?) -> Void) {
        DispatchQueue.main.async { [weak self] in
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = true
            panel.prompt = "연결"
            panel.message = "조각이 .md 파일로 살 폴더를 고른다. 이미 쓰던 볼트를 골라도 된다."
            panel.directoryURL = VaultLocation.current
            // 면접 중에 열릴 수 있는 창이다 — 은신을 여기도 박는다.
            WindowPrivacy.apply(to: panel)
            // ⚠ **안 골랐으면 `done` 을 안 부른다** — 위 계약 그대로다. 시트로 바뀌면서
            //   달라진 것은 *언제* 오느냐뿐이고, 오지 않는 경우는 그대로다.
            let finish: (NSApplication.ModalResponse) -> Void = { resp in
                done(resp == .OK ? panel.url : nil)
            }
            // ★ **숨은 창은 되살려서 붙인다** (#80 ③ — `pickAndExtractDocuments` 와 같은 모양, 같은 실측).
            //   `orderOut` 된 창에 시트를 붙이면 시트도 안 뜨고, 따로 띄우면 다른 앱이 맨앞일 때
            //   패널이 화면에 안 올라온다(`NSApp.activate()` 는 협조적이다). 두 자리가 다른 모양이면
            //   같은 실측이 한쪽에서 다시 걸린다 — 그래서 여기도 같은 줄이다. 귀는 안 켠다(저쪽 주석).
            if let host = self?.chatWindow?.window {
                if !host.isVisible {
                    NSApp.activate()
                    host.makeKeyAndOrderFront(nil)
                }
                panel.beginSheetModal(for: host, completionHandler: finish)
            } else {
                // 창 자체가 아직 없을 때만 따로 뜬다. 신 API 로 앞으로 끌고(deprecated 된
                // `ignoringOtherApps:` 가 #78 의 절반이었다) 층위를 올린다 — 채팅창이
                // `.floating` 이라 안 올리면 우리 창이 고르기 창을 덮는다.
                NSApp.activate()
                panel.level = .modalPanel
                panel.begin(completionHandler: finish)
                panel.makeKeyAndOrderFront(nil)
            }
        }
    }

    /// 시스템 설정의 개인정보 보호 칸을 연다. **여기서 권한을 켤 수는 없다** —
    /// 여는 것이 우리가 할 수 있는 전부고, 그래서 화면 쪽 문구도 「연다」까지만 말한다.
    /// ⚠ 이 주소는 `x-apple.systempreferences:` 스킴이라 **네트워크가 아니다.**
    func openSystemPrivacy(_ which: String) {
        let anchor: String
        switch which {
        case "mic":    anchor = "Privacy_Microphone"
        case "screen": anchor = "Privacy_ScreenCapture"
        default: return
        }
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?" + anchor) else { return }
        NSWorkspace.shared.open(url)
    }

    /// ★ **끄기 전에 밀린 저장을 흘려보낸다** (QA 블로커 F1).
    ///
    /// 볼트 쓰기가 주 스레드에 있던 동안엔 이게 공짜였다 — 저장 버튼이 돌아왔을 때 이미
    /// 디스크에 앉아 있었다. `VaultIO` 가 그것을 직렬 큐 뒤로 보내면서 **⌘Q 가 마지막 저장을
    /// 앞지를 수 있게** 됐고, 그 구멍을 여기서 막는다.
    /// ⚠ 무한정 안 기다린다 — `VaultIO.flush` 가 시간을 재고 돌아온다(권한 창에 걸린 쓰기는
    /// 안 끝나고, 그걸 기다리면 **멈춘 앱을 못 끄게 된다**).
    func applicationWillTerminate(_ notification: Notification) {
        chatWindow?.webView.flushVaultWrites()
    }

    @objc func quit() { NSApp.terminate(nil) }
}
