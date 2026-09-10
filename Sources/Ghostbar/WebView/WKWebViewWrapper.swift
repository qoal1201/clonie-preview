import WebKit
import AVFoundation
import AppKit
import GhostbarCore
import GhostbarCloud
import GhostbarDocuments

class WKWebViewWrapper: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    let view: WKWebView
    let recorder = AudioRecorder()
    var isRecording = false
    var currentStreamSession: URLSession?
    var storedScreenshot: String? = nil
    /// 면접 모드에서만 산다 (#17). 처음 면접에 들어갈 때 만들어지고 그 뒤로는 켜고 끄기만 한다.
    var ears: InterviewEars?
    /// 조각 저장소 — **md 볼트 폴더 하나**다 (ADR 0003 §1, #30).
    ///
    /// ⚠ 뒤가 JSON 한 장에서 폴더로 바뀌었지만 **화면은 모른다** — `load()`/`save()` 모양이
    /// 그대로고 `saveDocument` 통로도 그대로다. 첫 열기에 옛 `cue.json` 이 md 로 옮겨간다.
    ///
    /// ⚠ **직접 부르지 않는다 — `vault` 를 지난다** (QA 블로커 F1). 이 타입의 `load`/`save` 는
    /// 파일을 만지고, 그것을 주 스레드에서 부르면 권한 창 하나에 앱이 통째로 굳는다
    /// (`실측 2026-08-30`: 25분). 여기 남겨 둔 이유는 **자리(볼트·사이드카 경로)를 아는 것이
    /// 이 객체**라서다.
    var store: VaultStore? = VaultLocation.makeStore()
    /// 볼트 입출력의 **유일한 문** (블로커 F1). 직렬 큐 뒤에서 돌고, 실패·대기를 화면으로 낸다.
    private var vault: VaultIO?
    /// 볼트를 **밖에서** 고쳤는데 아직 성공적으로 다시 읽지 못했다는 신호 (옵시디언 등).
    /// 신호가 오면 즉시 읽고, 실패한 경우 창을 다시 열 때 한 번 더 시도한다.
    private var watcher: VaultWatcher?
    private var vaultChangedOutside = false
    /// 앱 종료 전에 화면의 자동 저장 대기와 비동기 저장 확인을 끝내는 한 벌.
    private var terminationCompletion: ((Bool) -> Void)?
    private var terminationTimeout: DispatchWorkItem?
    private var terminationToken: String?
    /// 화면에는 불투명한 문자열만 주고, 실제 리비전은 네이티브 안에 둔다 (#84).
    /// 여러 `evaluateJavaScript`가 엇갈려도 화면이 받은 문서와 기준선이 같은 한 벌이어야 한다.
    private var vaultRevisions: [String: VaultRevision] = [:]
    private var vaultRevisionOrder: [String] = []
    /// 화면에서 아직 저장하지 않은 파일의 옛 기준선. 전체 볼트 판이 아니라 해당 파일만 든다.
    /// `pinVaultRevisions`가 매번 현재 집합으로 갈아끼워 저장·취소 뒤에는 남지 않는다.
    private var pinnedVaultRevisions: [String: VaultRevision] = [:]
    /// 볼트를 다시 묶은 뒤 늦게 돌아온 옛 큐의 콜백을 버리는 세대다.
    private var vaultGeneration = 0
    /// 내용 그래프 (#32, ADR 0003 §3-①). 저장 순간 조각을 임베딩해 사이드카에 쌓고,
    /// 아주 가까운 조각이 이미 있으면 **기존 알림 띠**로 한 줄 말한다.
    /// ⚠ 볼트가 없으면 색인도 없다 — 사이드카는 볼트 안에 산다. 그래서 `store` 를 따라간다.
    private var graph: ContentGraph?
    /// 면접관 관의 **굳은 글자**가 마지막으로 어디까지였나 (#34). 질의 벡터를 언제 만들지
    /// 가르는 데만 쓴다 — 어절마다 만들면 큐가 밀린다.
    private var lastConfirmedThem = ""
    private let speechSetup = InterviewEars()
    private var speechPreparing = false

    init(frame: NSRect = .zero) {
        let config = WKWebViewConfiguration()
        let cc = WKUserContentController()
        config.userContentController = cc
        view = WKWebView(frame: frame, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        super.init()
        // ⚠ 이 배열이 브리지의 전부다 — 여기 없는 이름으로 `post` 하면 **조용히 아무 일도 안 난다**.
        //   #9 이 `saveDocument` 를, #17 이 `startListening`·`stopListening` 을,
        //   #33 이 `embedDraft` 를 더했다. Swift→JS 는 `receiveDocument`·`onEar`·`onEarTrouble`.
        //   ⚠ **여기 이름이 늘면 화면만 고치는 길이 그 기능에는 안 통한다** — 브라우저 단독
        //     (`cue.html`)에서 그 통로가 없어 조용히 아무 일도 안 난다. #33 은 그 대가를 알고
        //     늘렸다: 저장 전 글자의 벡터는 화면이 혼자 만들 방법이 없다(`ContentGraph.embedDraft`).
        //   #40 이 `pickIngestFiles`·`draftFragment` 를 더했다 — 둘 다 브라우저 단독으로는
        //   할 수 없는 것이다(파일 고르기 창 · 온디바이스 모델). Swift→JS 는
        //   `onIngestFiles`·`onFragmentDraft`.
        //   #47 이 `tidyQuestion` 을 더했다 — 같은 사정(온디바이스 모델)이다. Swift→JS 는
        //   `onQuestionTidy`. ⚠ **화면 쪽에서 이 통로를 여는 자리는 쌓기 모드뿐이다** —
        //   면접 중에 모델을 물고 있을 이유가 없다(`QuestionTidier` 머리글).
        //   #61 이 셋을 더했다 — **프론트 설정 화면**이 쓰는 것들이다(그릴 Q2):
        //   `detectCli`(공식 CLI 가 깔렸나·로그인됐나 — 남의 프로세스를 띄워야 안다) ·
        //   `saveBackend`(백엔드·키·모델 저장 — ⚠ 키는 화면으로 **안 돌아간다**) ·
        //   `setWindowStyle`(창 뒤 블러 — `NSVisualEffectView` 는 CSS 가 못 만든다).
        //   셋 다 **쌓기 모드 아래에서만** 열린다 — 판정선(`stackRender`) 바깥이다.
        //   Swift→JS 는 `onCliStatus`·`onBackendSaved`·`setWindowStyleValues`.
        //   ★ 2026-08-31 설정 통합이 **`openSettings` 를 죽이고 셋을 세웠다**(박선호:
        //   *"단축키 설정이나 그런것들도 그냥 설정창 하나로 다 통합시키고"*). 네이티브 미니
        //   패널이 사라졌으니 그 창을 여는 통로도 같이 죽었고, 그 창이 하던 일이 통로가 됐다:
        //   `probeSystem`(단축키·권한·볼트를 한 벌로 잰다) · `saveShortcut`(걸어 보고 저장) ·
        //   `openSystem`(폴더 고르기 창 · 시스템 설정 열기 — `what` 한 칸으로 가른다,
        //   `startListening` 이 `system` 을 얹은 것과 같은 모양). 셋 다 쌓기 모드 아래다.
        //   Swift→JS 는 `setSystemState` 하나 — 옛 `setShortcut`·`setCaptureShortcut` 둘을
        //   **대체한다**(그 둘은 화면에서 빈 스텁이라 답이 버려지고 있었다).
        //   ★ 2026-09-01 이 `saveCliConfig` 를 더했다 (박선호: *"모델 선택이나 추론 설정도
        //     가능한가? 너는 그냥 배선된 버튼만 만들어둬"*). 구독(CLI) 층의 모델·추론이
        //     `UserDefaults` 에 앉는 자리다 — **회신이 없다**(화면이 방금 보낸 값을 이미 든다).
        //     ⚠ **키 근처가 아니다** — 오는 것은 벤더 표가 화면에 실어 보낸 목록 안의 글자뿐이고,
        //       그 밖은 저장 안 한다(`CliDrafter.saveTuning`).
        for name in ["sendMessage","loadModels","copyText","startRecording","stopRecording","stopStream","checkWhisper","closeWindow","captureScreen","clearScreenshot","initModel","probeSystem","saveShortcut","openSystem","resizeWindow","saveDocument","vaultAction","terminationReady","prepareSpeechModel","pinVaultRevisions","startListening","stopListening","embedDraft","pickIngestFiles","draftFragment","tidyQuestion","detectCli","saveCliConfig","saveBackend","setWindowStyle"] {
            cc.add(self, name: name)
        }
        view.navigationDelegate = self
        vault = store.map { VaultIO(store: $0, requireExistingRoot: true) }
        graph = store.map { ContentGraph(sidecarURL: $0.sidecarURL) }
        loadHTML()
        sendSavedModel()
        startVaultWatch()
    }

    // MARK: - 내용 그래프 (#32)

    /// 조각을 색인하고, 아주 가까운 것이 이미 있으면 **기존 알림 띠**에 한 줄 띄운다.
    ///
    /// ⚠ **여기서 기다리지 않는다.** `실측 2026-08-30`: 조각 50장 콜드 색인이 4.1초다 —
    /// 저장 버튼에 매달면 창이 4초 멈춘다. 웜은 73ms, 한 장 고쳤을 때는 109ms 라
    /// 「거의 없다」에 가깝지만, **콜드가 한 번은 반드시 온다**(볼트를 처음 열 때).
    ///
    /// ⚠ 통로를 늘리지 않았다 — `onIndexNotice`·`receiveVectors` 는 **Swift→JS** 이고,
    /// 브리지 배열(JS→Swift)은 안 건드렸다 (개수는 안 적는다 — `AGENTS.md`, 여기 적혀 있던
    /// 「15개」가 실제 19개가 된 채로 낡아 있었다. `실측 2026-08-31` matt 리뷰가 잡음).
    ///
    /// ★ 질문도 같이 넘긴다 (#34). ⚠ **쓰는 곳이 바뀌었다** (#53, ADR 0005): 라이브 검색의
    /// **개념 매개** 갈래가 걷혀서, 지금 이 벡터를 읽는 것은 화면의 **준비도 줄**과 연습의
    /// 「준비된 답변이 없다」뿐이다 — 둘 다 「질문 ↔ 조각」을 내용 직접 자로 잰다.
    /// 인코딩은 그대로 양쪽 `query: ` 다(`ContentIndexer` 가 안다).
    private func indexFragments(_ document: CueDocument) {
        graph?.index(fragments: document.fragments, questions: document.questions) { [weak self] line in
            self?.view.evaluateJavaScript("onIndexNotice(\(jsLiteral(line)))",
                                          completionHandler: nil)
        } onVectors: { [weak self] json in
            self?.view.evaluateJavaScript("receiveVectors(\(jsLiteral(json)))",
                                          completionHandler: nil)
        } onState: { [weak self] state in
            self?.view.evaluateJavaScript("onIndexState(\(jsLiteral(state)))", completionHandler: nil)
        }
    }

    /// 볼트가 밖에서 바뀌면 곧바로 다시 읽는다. `receiveDocument`가 편집 DOM과 로컬 변경을
    /// 새 디스크 문서 위에 되놓으므로, 창을 닫을 때까지 외부 변경을 미룰 이유가 없다.
    private func startVaultWatch() {
        guard let store = store else { return }
        watcher = VaultWatcher(vaultURL: store.vaultURL) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.vaultChangedOutside = true
                self.sendDocument(kind: "reload")
            }
        }
        watcher?.start()
    }

    /// 사용자가 설정창에서 **다른 폴더를 연결**했다. 저장소와 감시를 그리로 옮기고 화면을 새로 채운다.
    func rebindVault() {
        watcher?.stop()
        watcher = nil
        // ⚠ **옛 볼트의 밀린 저장을 먼저 흘려보낸다** (블로커 F1). 안 그러면 방금 쓴 조각이
        //   갈아끼워진 뒤에 옛 폴더로 앉거나, 권한 창에 걸린 채 남는다.
        vault?.flush()
        vaultGeneration += 1
        vaultRevisions.removeAll()
        vaultRevisionOrder.removeAll()
        pinnedVaultRevisions.removeAll()
        store = VaultLocation.makeStore()
        vault = store.map { VaultIO(store: $0, requireExistingRoot: true) }
        // 자리를 옮겼으니 옛 볼트의 사고는 이제 남의 이야기다 — 띠를 걷는다.
        clearVaultTrouble()
        // 사이드카 경로가 색인기 안에 박혀 있다 — 볼트를 옮기면 **색인기도 옮긴다**.
        // 안 옮기면 새 볼트의 조각이 옛 볼트의 `.clonie/` 에 쌓인다.
        if let s = store {
            if let g = graph { g.rebind(sidecarURL: s.sidecarURL) }
            else { graph = ContentGraph(sidecarURL: s.sidecarURL) }
        }
        vaultChangedOutside = false
        startVaultWatch()
        sendDocument(kind: "load")
    }

    /// 창을 다시 띄울 때 부른다. 밀린 변경이 있으면 그때 문서를 다시 읽는다.
    func flushPendingVaultReload() {
        guard vaultChangedOutside else { return }
        vaultChangedOutside = false
        sendDocument(kind: "reload")
    }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "resizeWindow":
            // ⚠ 통로를 안 늘렸다 — 크기 옆에 `mode` 를 얹었을 뿐이다 (#18 인수 조건: 새 브리지 통로 0개).
            guard let b = message.body as? [String: Any],
                  let w = (b["w"] as? NSNumber)?.doubleValue,
                  let h = (b["h"] as? NSNumber)?.doubleValue else { return }
            applyMode((b["mode"] as? String) ?? "stack",
                      content: NSSize(width: w, height: h))
        case "sendMessage":
            guard let body = message.body as? [String: Any],
                  let messages = body["messages"] as? [[String: Any]],
                  let model = body["model"] as? String else { return }
            let useScreenshot = (body["screenshot"] as? NSNumber)?.boolValue == true
            let img = useScreenshot ? storedScreenshot : nil
            streamResponse(messages: messages, model: model, image: img)
        case "captureScreen":
            captureForHotKey()
        case "clearScreenshot":
            storedScreenshot = nil
        case "startListening":
            // ⚠ **통로를 안 늘렸다** — 기존 이름에 「어느 관을 열까」를 얹었다 (#36,
            //   `resizeWindow` 가 크기 옆에 `mode` 를 얹은 것과 같은 모양). 연습 모드는
            //   묻는 것이 앱이라 상대 목소리가 없고, 시스템 오디오를 열면 화면 기록 권한만
            //   괜히 묻게 된다. 짐이 없거나 낡은 화면이면 **둘 다 연다** — 면접이 기본값이다.
            let earsBody = message.body as? [String: Any]
            startInterviewEars(system: (earsBody?["system"] as? NSNumber)?.boolValue ?? true)
        case "stopListening":
            stopInterviewEars()
        case "prepareSpeechModel":
            guard !speechPreparing else { return }
            speechPreparing = true
            speechSetup.prepareSpeechModel { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .loading: self.sendSpeechModelState("loading")
                case .ready: self.speechPreparing = false; self.sendSpeechModelState("ready")
                case .error(let message): self.speechPreparing = false; self.sendSpeechModelState("error", message: message)
                }
            }
        case "vaultAction":
            if let body = message.body as? [String: Any] { handleVaultAction(body) }
        case "saveDocument":
            // 화면이 리비전 표와 문서 전체 JSON을 보낸다. 조각 규모(5,000장 순회 2.58ms, #4)에선
            // 통째로 쓰는 것이 부분 갱신보다 싸고, 무엇보다 **부분 실패가 없다.**
            guard let body = message.body as? [String: Any],
                  let json = body["json"] as? String,
                  let revisionID = body["revision"] as? String,
                  let requestID = (body["requestID"] as? NSNumber)?.intValue,
                  let vault = vault else { return }
            guard var revision = vaultRevisions[revisionID] else {
                failDocumentSave(requestID)
                sendDocument(kind: "reload")
                return
            }
            let overrideIDs = (body["revisionOverrides"] as? [String: Any]) ?? [:]
            do {
                let grouped = Dictionary(grouping: overrideIDs.compactMap { id, value -> (String, String)? in
                    guard let token = value as? String else { return nil }
                    return (token, id)
                }, by: \.0)
                guard grouped.values.reduce(0, { $0 + $1.count }) == overrideIDs.count else {
                    throw VaultRevisionError.differentVault(expected: "invalid-token", actual: "current-vault")
                }
                for (token, rows) in grouped {
                    guard let editingRevision = vaultRevisions[token] ?? pinnedVaultRevisions[token] else {
                        throw VaultRevisionError.differentVault(expected: "expired-token", actual: "current-vault")
                    }
                    revision = try revision.preservingFileBaselines(
                        for: Set(rows.map(\.1)), from: editingRevision)
                }
            } catch {
                FileHandle.standardError.write(Data("[cue] 저장 실패(리비전): \(error)\n".utf8))
                failDocumentSave(requestID)
                sendDocument(kind: "reload")
                return
            }
            let doc: CueDocument
            do {
                doc = try FragmentStore.makeDecoder()
                    .decode(CueDocument.self, from: Data(json.utf8))
            } catch {
                // 화면이 보낸 글자를 못 읽었다 — 디스크까지 안 갔다. 이건 우리 버그라
                // 사용자가 고칠 것이 없고, 그래서 띠가 아니라 로그다.
                FileHandle.standardError.write(Data("[cue] 저장 실패(해독): \(error)\n".utf8))
                failDocumentSave(requestID)
                return
            }
            // ★ **주 스레드에서 안 쓴다** (블로커 F1). `VaultStore.save` 는 파일을 만지고,
            //   권한 창이 뜨면 그 자리에서 안 돌아온다 — 그 25분이 이 한 줄의 이유다.
            let generation = vaultGeneration
            vault.save(doc, expecting: revision) { [weak self] trouble in
                self?.showVaultTrouble(trouble)
            } completion: { [weak self] result in
                guard let self = self else { return }
                guard generation == self.vaultGeneration else { return }
                switch result {
                case .success(let saved):
                    self.clearVaultTrouble()
                    // 저장 직후 다시 읽어야 그 사이 다른 md에 들어온 변경도 화면에 합쳐진다.
                    // 읽기 실패 때만 저장 결과를 폴백으로 써서, 성공한 저장을 실패처럼 재전송하지 않는다.
                    self.sendDocument(kind: "save", requestID: requestID,
                                      fallback: (doc, saved))
                case .failure(let error):
                    if error is VaultConflictError {
                        // Core가 쓰려던 내용을 `.clonie/conflicts`에 보존했다. 이제 현재 디스크를
                        // 읽어 화면의 초안과 합친다. 충돌 띠는 성공한 읽기가 지우지 않는다.
                        self.sendDocument(kind: "conflict", requestID: requestID,
                                          preserveTrouble: true)
                    } else {
                        self.failDocumentSave(requestID)
                    }
                }
            }
        case "terminationReady":
            let body = message.body as? [String: Any]
            guard let token = body?["token"] as? String,
                  token == terminationToken else { return }
            let ok = (body?["ok"] as? NSNumber)?.boolValue ?? (body?["ok"] as? Bool) ?? false
            finishTerminationPreparation(ok)
        case "pinVaultRevisions":
            // 화면이 현재 편집 중인 파일별 옛 기준선을 알린다. 한 번 받은 전체 revision에서
            // 필요한 파일만 잘라 두므로 32회 reload 뒤에도 저장 기준은 살고, 메모리는 지나간
            // reload 수가 아니라 아직 저장하지 않은 파일 수를 따른다.
            guard let body = message.body as? [String: Any],
                  let requested = body["revisions"] as? [String: Any] else { return }
            var next: [String: VaultRevision] = [:]
            for (token, value) in requested {
                guard let ids = value as? [String], !ids.isEmpty,
                      let source = vaultRevisions[token] ?? pinnedVaultRevisions[token]
                else { continue }
                next[token] = source.selectingFileBaselines(for: Set(ids))
            }
            pinnedVaultRevisions = next
        case "embedDraft":
            // ★ **화면이 벡터를 물어보는 통로** (#33, ADR 0003 §3-②). 아직 저장 안 된 글자 —
            //   치고 있는 조각 초안, 방금 붙여넣은 자소서 문항 — 는 `receiveVectors` 꾸러미에
            //   없고 화면은 CoreML 을 못 부른다. 그래서 이 통로가 하나 늘었다(15 → 16).
            //   ⚠ 돌려주는 것은 **벡터뿐이다.** 코사인·순위·기본 켜짐은 화면이 낸다
            //     (ADR 0003 §4 의 갈림 · `tests/chip-suggest.test.mjs` 가 그것을 잠근다).
            guard let b = message.body as? [String: Any],
                  let slot = b["slot"] as? String,
                  let kind = b["kind"] as? String,
                  let text = b["text"] as? String,
                  !text.isEmpty else { return }
            graph?.embedDraft(slot: slot, kind: kind, text: text) { [weak self] slot, text, b64 in
                guard let self = self,
                      let data = try? JSONSerialization.data(withJSONObject: ["slot": slot,
                                                                              "text": text,
                                                                              "v": b64]),
                      let json = String(data: data, encoding: .utf8) else { return }
                self.view.evaluateJavaScript("onDraftVector(\(jsLiteral(json)))",
                                             completionHandler: nil)
            }
        case "pickIngestFiles":
            // ★ **파일 고르기 창은 화면이 못 연다** (#40). WebView 의 `<input type=file>` 은
            //   `loadHTMLString(baseURL: nil)` 아래에서 안 뜨고, 뜬다 해도 hwpx·docx 를
            //   평문으로 바꾸는 것은 브라우저가 못 한다. 그래서 통로가 하나 늘었다.
            pickAndExtractDocuments()
        case "draftFragment":
            // ★ 온디바이스 모델로 **이야기 0~3장** (#40 2판). **상관 id 를 그대로 되돌려준다** —
            //   화면이 창을 줄지어 던지고, 응답 순서는 보장되지 않는다.
            // ⚠ **`parts` 는 없어도 된다** (#40 2판 조정) — 붙지 않은 창은 안 싣고, 옛 화면·
            //   브라우저 단독도 안 싣는다. 그때는 1 이고, 그 길이 예전 그대로다.
            //   **새 통로가 아니라 이 꾸러미의 칸 하나다** — 브리지 배열은 그대로 19개다.
            // ⚠ **`cloud` 도 같은 길이다** (#51) — 새 통로가 아니라 이 꾸러미의 칸 하나다.
            //   안 오면 `false` 고, 그때 예전 길(온디바이스)로 그대로 간다.
            guard let b = message.body as? [String: Any],
                  let id = b["id"] as? String,
                  let text = b["text"] as? String else { return }
            draftFragment(id: id, text: text,
                          parts: b["parts"] as? Int ?? 1,
                          ask: b["ask"] as? Bool ?? false,
                          cloud: b["cloud"] as? Bool ?? false)
        case "tidyQuestion":
            // ★ 수확된 면접 질문 한 줄을 표준 문장으로 (#47). `draftFragment` 와 **같은 모양**이다 —
            //   상관 id + 글자 하나, 답은 `onQuestionTidy` 로 같은 id 를 달고 돌아간다.
            guard let b = message.body as? [String: Any],
                  let id = b["id"] as? String,
                  let text = b["text"] as? String else { return }
            tidyQuestion(id: id, text: text)
        case "detectCli":
            // ★ 공식 CLI 감지 (#61 B) — **비동기다.** 파일이 있나는 공짜지만 로그인은
            //   남의 프로세스를 띄워야 알고(`실측`: 0.16~0.3초), 그건 주 스레드가 기다릴 일이 아니다.
            //   ⚠ 답에 **경로·계정이 안 실린다** (`CliDrafter.statuses` 머리글).
            //   ★ 터미널 한 줄 둘(`install`·`login`)이 여기 실린다 (#61 리뷰 발견 ④) —
            //     화면이 같은 표를 한 벌 더 들던 자리를 걷었다. **통로는 그대로다.**
            //   ★ **모델·추론도 여기 실린다** (2026-09-01). 지금 고른 값과 **고를 수 있는 목록**
            //     둘 다다 — 화면이 그 표를 한 벌 더 들면 모델 이름이 바뀌는 날 두 곳이 갈린다
            //     (`install`·`login` 두 줄을 #61 리뷰 발견 ④ 가 같은 이유로 여기로 옮겼다).
            //     ⚠ 비밀값이 아니다: 목록도 지금 값도 **벤더 표의 고정 글자**다.
            //   ★ **두뇌 선택도 여기 실린다** (2026-09-01, `DrafterChoice`): 지금 고른 것 ·
            //     고를 수 있는 넷(이름표까지).
            //   ★ **키 층 요약은 여기서 걷었다** (2026-09-02, matt 2축 리뷰 H3). 같은 값이
            //     `sendCloudReady` 에도 실려 **집이 둘**이었고, 그래서 키를 저장한 직후 두뇌
            //     목록이 낡은 채로 남았다(설정을 닫았다 다시 열어야 고쳐졌다). 집은 하나다 —
            //     `sendCloudReady`. ⚠ 그래서 **이 통로가 끝나면 그것을 부른다**(아래):
            //     로그인을 방금 쟀으니 「누가 만들어요」와 「자동은 어디로」도 그때 정확해진다.
            Task { [weak self] in
                let list = await CliDrafter.statuses()
                let choices: ([CliDrafter.Choice]) -> [[String: String]] = {
                    $0.map { ["v": $0.value, "l": $0.label] }
                }
                let payload: [String: Any] = [
                    "choice": DrafterChoice.current.rawValue,
                    "choices": DrafterChoice.allCases.map { ["v": $0.rawValue, "l": $0.label] },
                    "cli": list.map {
                    ["id": $0.id, "name": $0.name,
                     "installed": $0.installed, "loggedIn": $0.loggedIn,
                     "install": $0.installCmd, "login": $0.loginCmd,
                     "model": $0.model, "reasoning": $0.reasoning,
                     "models": choices($0.models), "reasonings": choices($0.reasonings)] }]
                guard let data = try? JSONSerialization.data(withJSONObject: payload),
                      let json = String(data: data, encoding: .utf8) else { return }
                await MainActor.run {
                    self?.view.evaluateJavaScript("onCliStatus(\(jsLiteral(json)))",
                                                  completionHandler: nil)
                    // ★ **방금 로그인을 쟀다** — 그 자국을 읽는 것은 `sendCloudReady` 쪽이고
                    //   (`DrafterChoice.shownLane`), 그래서 여기서 한 번 더 민다. 통로를 안 늘렸다.
                    //   ⚠ 순서가 뜻이다: 두뇌 목록을 먼저 그리고, 키 층·「자동은 어디로」가
                    //     뒤이어 와서 그 목록을 **같은 화면에서** 고쳐 쓴다(`setCloudDrafter`).
                    self?.sendCloudReady()
                }
            }
        case "saveCliConfig":
            // ★ 구독(CLI) 층의 모델·추론 (박선호 2026-09-01). **키 근처에 안 간다** —
            //   저장되는 것은 벤더 표의 목록 안에 있는 글자뿐이고, 그 밖은 그냥 안 저장한다.
            //   거르는 자는 `CliDrafter.saveTuning` **하나**다: 여기서 한 번 더 좁히면
            //   목록이 두 곳에 서고, 그 둘이 갈리는 날 「고를 수는 있는데 저장이 안 되는」 칸이 난다.
            // ⚠ **회신이 없다** (#61 리뷰 발견 ⑦ 와 같은 자리). 저장은 `UserDefaults.set` 뿐이라
            //   실패를 낼 통로가 없고, 화면은 방금 보낸 값을 이미 들고 그것으로 칸을 그리고 있다.
            //   설정 화면을 다시 열면 `detectCli` 가 저장된 값을 그대로 싣고 돌아온다.
            // ★ **두뇌 선택도 이 통로로 온다** (2026-09-01, `DrafterChoice`). 통로를 안 늘렸다 —
            //   저장되는 것이 「지능 설정의 한 칸」이라는 점에서 모델·추론과 같은 성질이고,
            //   브리지 이름이 늘면 브라우저 단독 화면이 그 통로를 영영 못 연다(배열 머리글).
            //   ⚠ 꾸러미로 가른다: `choice` 가 있으면 두뇌, `vendor` 가 있으면 모델·추론.
            //   ⚠ **저장된 뒤에 `sendCloudReady()` 를 부른다** — 받기 화면의 「…에 보내요」 한 줄이
            //     선택을 따라가야 한다. 새 통로가 아니라 이미 있는 Swift→JS 밀어주기다.
            guard let b = message.body as? [String: Any] else { return }
            if let raw = b["choice"] as? String {
                if DrafterChoice.save(raw) { sendCloudReady() }
                return
            }
            guard let vendor = b["vendor"] as? String else { return }
            CliDrafter.saveTuning(vendorId: vendor,
                                  model: b["model"] as? String,
                                  reasoning: b["reasoning"] as? String)
        case "saveBackend":
            // ★ 프론트 설정이 백엔드·키·모델을 저장한다 (#61 B·C).
            // ⚠ **키를 화면으로 되돌려주지 않는다.** 나가는 것은 「저장됐나 · 키가 있나」뿐이다 —
            //   화면은 WebView 라 거기 앉힌 글자는 우리 손을 떠난다(`sendCloudReady` 와 같은 규율).
            // ⚠ **키 칸이 비어 있으면 지우는 것이 아니라 그대로 둔다.** 화면이 저장된 키를
            //   되읽지 못하므로(위), 빈 칸을 「지워라」로 읽으면 **설정을 한 번 열었다 닫는 것만으로
            //   키가 날아간다.** 지우는 것은 `clearKey` 를 명시했을 때뿐이다.
            // ⚠ **단 목적지가 갈리면 그 규율이 뒤집힌다** (#65 ③). 키 슬롯이 하나뿐이라
            //   목적지가 바뀐 순간 저장된 키는 **주인이 없다** — 키는 제공자에 속한다.
            //   그대로 두면 회신 `hasKey:true` 가 나가고, 새 제공자 화면이 「저장돼 있어요」라고
            //   거짓말한다(그리고 그 키로 남의 제공자를 부른다). 그래서 **새 키가 같이 오지 않는
            //   목적지 전환은 저장된 키를 버린다.** 회신은 그 결과를 그대로 싣는다.
            // ★ **판정은 `GhostbarCloud.BackendKeyRule` 이 든다** (#65 ③ 잔여). 여기 있던 사다리는
            //   `type` 만 봤는데 `BackendType` 넷 vs 화면 프리셋 여덟이 안 맞아 **다섯이 같은
            //   `openai`** 였다 — 그 사이 전환에서 키가 새 주소로 나갔다. 이 파일은 executable 이라
            //   `swift test` 가 못 부르므로, 판정만 라이브러리로 옮겨 잠갔다
            //   (`tests/GhostbarCloudTests/BackendKeyRuleTests.swift`). 여기 남는 것은 **읽고 넘기기**뿐이다.
            guard let b = message.body as? [String: Any] else { return }
            var cfg = BackendConfig.current
            let oldType = cfg.type, oldURL = cfg.url
            if let t = b["type"] as? String, let bt = BackendType(rawValue: t) { cfg.type = bt }
            if let u = (b["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !u.isEmpty { cfg.url = u }
            let newKey = (b["key"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            cfg.apiKey = BackendKeyRule.nextKey(
                saved: cfg.apiKey, typed: newKey,
                clearRequested: (b["clearKey"] as? NSNumber)?.boolValue == true,
                oldType: oldType.rawValue, newType: cfg.type.rawValue,
                oldURL: oldURL, newURL: cfg.url)
            BackendConfig.current = cfg
            if let m = (b["model"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                UserDefaults.standard.set(m.isEmpty ? nil : m, forKey: "selectedModel")
            }
            // ⚠ **「됐나」를 안 싣는다** (#61 리뷰 발견 ⑦). 위 저장은 `UserDefaults.set` 뿐이라
            //   실패를 낼 통로가 없고, 그런데도 `ok: true` 를 실으면 화면이 **없는 실패를 다루는
            //   죽은 갈래**를 들게 된다. 저장이 실패할 수 있는 자리로 옮겨가면 그때 실결과를 싣는다.
            let saved: [String: Any] = ["type": cfg.type.rawValue,
                                        "hasKey": !cfg.apiKey.isEmpty,
                                        "model": UserDefaults.standard.string(forKey: "selectedModel") ?? ""]
            if let data = try? JSONSerialization.data(withJSONObject: saved),
               let json = String(data: data, encoding: .utf8) {
                view.evaluateJavaScript("onBackendSaved(\(jsLiteral(json)))", completionHandler: nil)
            }
            // 키·모델이 여기서 정해진다 — 받기 화면의 「더 좋은 정리」가 켤 수 있는지도 같이 바뀐다 (#51).
            sendCloudReady()
        case "copyText":
            // `loadHTMLString(baseURL:nil)` 아래에서는 WebKit 클립보드 API가 없을 수 있다.
            // 명령·로그인 문자열처럼 비밀값이 아닌 텍스트만 좁은 네이티브 통로로 옮긴다.
            guard let b = message.body as? [String: Any],
                  let text = b["text"] as? String else { return }
            let id = b["id"] as? String ?? ""
            _ = NSPasteboard.general.clearContents()
            let ok = NSPasteboard.general.setString(text, forType: .string)
            let okLiteral = ok ? "true" : "false"
            view.evaluateJavaScript("onNativeCopyText(\(okLiteral),\(jsLiteral(id)))",
                                    completionHandler: nil)
        case "setWindowStyle":
            // ★ 창 뒤 블러 (#6 → #61 B). **불투명도는 화면이 든다** — 그건 `#app` 배경 알파라
            //   CSS 자리다(`WindowStyle` 머리글의 갈림). 여기서는 그 값을 **보관만** 한다:
            //   창이 다시 뜰 때 `setWindowStyleValues` 로 되돌려 줘야 화면이 그 판을 복원한다.
            guard let b = message.body as? [String: Any] else { return }
            if let v = (b["blur"] as? NSNumber)?.doubleValue { WindowStyle.blur = v }
            if let v = (b["opacity"] as? NSNumber)?.doubleValue { WindowStyle.opacity = v }
            DispatchQueue.main.async {
                (NSApp.delegate as? AppDelegate)?.chatWindow?.applyWindowStyle()
            }
        case "initModel":
            sendSavedModel()
            sendSystemState()
            sendScreenshotPrompt()
        case "probeSystem":
            // ★ **열 때마다 다시 잰다.** 사람이 시스템 설정에서 권한을 켜고 돌아오는 것이
            //   이 화면의 동선이라, 한 번 잰 값을 들고 있으면 **켠 뒤에도 꺼져 보인다**.
            sendSystemState()
        case "saveShortcut":
            // ⚠ **저장은 Swift 가 정한다** — 화면은 조합만 보낸다. 걸리지 않는 조합은
            //   저장 안 되고, 답(`setSystemState`)에 실린 옛 값이 그대로 화면에 다시 앉는다.
            guard let b = message.body as? [String: Any],
                  let slot = (b["slot"] as? String).flatMap({ GlobalHotKey.Slot(name: $0) }) else { return }
            var bad = "조합"
            if let s = RecordingShortcut.fromJS(b),
               (NSApp.delegate as? AppDelegate)?.applyShortcut(slot, s) == true { bad = "" }
            sendSystemState(failedSlot: bad.isEmpty ? nil : slot)
        case "openSystem":
            // ★ 네이티브가 아니면 못 하는 것 — 폴더 고르기·시스템 설정·볼트 출처 파일 열기.
            //   출처는 사람이 본문의 링크 버튼을 눌렀을 때만 이리 온다. 화면 경로를 믿지 않고
            //   Core 문지기가 실제 파일과 symlink 경계를 다시 확인한다.
            guard let body = message.body as? [String: Any],
                  let what = body["what"] as? String else { return }
            if what == "source" {
                guard let fromPath = body["fromPath"] as? String,
                      let reference = body["reference"] as? String,
                      let store else { return }
                do {
                    let url = try VaultReferenceResolver(vaultURL: store.vaultURL)
                        .resolve(reference: reference, from: fromPath)
                    NSWorkspace.shared.open(url)
                } catch {
                    FileHandle.standardError.write(Data("[cue] 출처 열기 거부: \(error)\n".utf8))
                }
                return
            }
            guard let app = NSApp.delegate as? AppDelegate else { return }
            if what == "vault" {
                app.pickVaultFolder { [weak self] url in
                    defer { self?.sendSystemState() }
                    guard let url else { return }
                    do {
                        try VaultLocation.set(url)
                        self?.rebindVault()
                    } catch {
                        self?.view.evaluateJavaScript("onIndexNotice(\(jsLiteral(error.localizedDescription)))", completionHandler: nil)
                    }
                }
            } else {
                app.openSystemPrivacy(what)
            }
        case "loadModels":
            let requestID = ((message.body as? [String: Any])?["requestID"] as? NSNumber)?.intValue
            fetchModels(requestID: requestID)
        case "checkWhisper": checkWhisperInstall()
        case "startRecording":
            guard !isRecording else { return }
            requestMicAndRecord()
        case "closeWindow":
            hideWindow()
        case "stopStream":
            currentStreamSession?.invalidateAndCancel()
            currentStreamSession = nil
            DispatchQueue.main.async { self.view.evaluateJavaScript("endStream()", completionHandler: nil) }
        case "stopRecording":
            guard isRecording else { return }
            isRecording = false
            recorder.onDone = { [weak self] url in
                guard let self = self, let url = url else {
                    DispatchQueue.main.async { self?.view.evaluateJavaScript("onTranscription(null)", completionHandler: nil) }
                    return
                }
                DispatchQueue.main.async { self.view.evaluateJavaScript("onTranscribing()", completionHandler: nil) }
                transcribe(audioURL: url) { [weak self] text in
                    DispatchQueue.main.async {
                        if let t = text {
                            let esc = t.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
                            self?.view.evaluateJavaScript("onTranscription('\(esc)')", completionHandler: nil)
                        } else {
                            self?.view.evaluateJavaScript("onTranscription(null)", completionHandler: nil)
                        }
                    }
                }
            }
            recorder.stop()
        default: break
        }
    }

    /// 화면을 잡아 `storedScreenshot` 에 앉힌다.
    ///
    /// 화면이 부르는 길(`captureScreen` 통로)과 **전역 단축키가 부르는 길**(#2)이 이 하나로 모인다 —
    /// 두 벌로 두면 한쪽이 조용히 낡는다. 창을 띄우지 않으므로 단축키 쪽에서 그대로 쓸 수 있다.
    func captureForHotKey() {
        Task { [weak self] in
            guard let self = self else { return }
            let b64 = await captureScreenBase64()
            await MainActor.run {
                if let b64 = b64 {
                    self.storedScreenshot = b64
                    self.view.evaluateJavaScript("onScreenshotCaptured()", completionHandler: nil)
                } else {
                    self.view.evaluateJavaScript("onScreenshotError()", completionHandler: nil)
                }
            }
        }
    }

    // MARK: - 던져넣기 (#40)

    /// 파일 고르기 창을 열고, 고른 것들을 **평문으로** 바꿔 화면에 넘긴다.
    ///
    /// ⚠ 창을 여는 것은 주 스레드, **읽는 것은 아니다.** `DocumentExtractor` 는 PDF·zip 을
    /// 만지는데 백 장짜리 문서 하나가 창을 그대로 세운다 (블로커 F1 이 볼트에서 겪은 것과
    /// 같은 모양). 그래서 고르기 → 백그라운드 추출 → 주 스레드 통보 셋으로 나뉜다.
    ///
    /// ⚠ **아무것도 안 골라도 화면에 답한다.** 안 그러면 화면의 「읽는 중」이 영영 안 걷힌다.
    ///
    /// ★ **`runModal` 을 안 쓴다 — 시트다** (#78). 이 앱은 `LSUIElement` 라 다른 앱이 맨앞이면
    /// `activate(ignoringOtherApps:)` 가 **무시된다**(macOS 14+ 는 협조적 활성화다). 그러면
    /// 패널이 **아무 데도 안 뜬 채** `runModal` 이 메인 런루프를 잡고, 채팅창도 QA 통로도 그때부터
    /// 죽는다 — 사람 눈에는 「앱이 굳음」이고 강제 종료가 유일한 출구였다
    /// (`실측 2026-09-04`, macOS 26.2: Claude 가 맨앞일 때 16초+ 잡힘 · AX 창 목록엔 채팅창 하나뿐).
    /// 시트는 **부모 창에 붙어 사람이 보고 있는 그 창 위에** 뜨고 메인을 안 잡는다.
    /// 자물쇠 = `tests/check_no_modal_runloop.py`.
    private func pickAndExtractDocuments() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = true
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowedContentTypes = DocumentExtractor.contentTypes
            panel.message = "자기소개서·이력서를 고른다 (pdf · docx · hwpx · md · txt)"
            panel.prompt = "가져오기"
            // 면접 중에 열릴 수 있는 창이다 — 은신을 여기도 박는다 (#80 ②, `pickVaultFolder` 와 같은 줄).
            WindowPrivacy.apply(to: panel)
            // ★ 끝나는 길은 **하나**다 — 시트든 폴백이든 같은 닫음을 쓴다. 두 벌로 두면
            //   한쪽만 화면에 답하는 판이 생기고, 그게 「읽는 중」이 안 걷히는 모양이다.
            let finish: (NSApplication.ModalResponse) -> Void = { [weak self] resp in
                guard let self = self else { return }
                guard resp == .OK, !panel.urls.isEmpty else {
                    // ⚠ **취소도 여기로 온다.** 화면에 빈 답을 줘야 「읽는 중」이 걷힌다.
                    self.sendIngestFiles(files: [], errors: [])
                    return
                }
                let urls = panel.urls
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    let result = DocumentExtractor.extract(urls: urls)
                    DispatchQueue.main.async {
                        self?.sendIngestFiles(files: result.files, errors: result.errors)
                    }
                }
            }
            // ⚠ **`isVisible` 까지 본다.** 면접 모드는 창을 `orderOut` 하는데 `view.window` 는
            //   그때도 `nil` 이 아니다 — 안 보이는 창에 시트를 붙이면 시트도 안 뜨고 답도 안 온다.
            if let host = self.view.window {
                // ★ **숨은 창은 되살려서 붙인다** (#80 ③). 전 판은 여기서 `panel.begin` 으로
                //   따로 띄웠는데 `실측 2026-09-04` 이 그 길을 깼다: 다른 앱이 맨앞(전체화면)인
                //   채로 쏘니 **패널 창은 생겼는데 화면에 안 올라왔다** — CG 목록에 880×448
                //   layer 8 로 있는데 `onscreen=false`, AX 창 목록 0, 맨앞은 그 앱 그대로.
                //   `NSApp.activate()` 는 macOS 14+ 에서 **협조적**이라 남이 안 양보하면 무시된다.
                //   붙일 창이 있는데 뒤에 뜬 패널은 사람에게 「아무 일도 안 일어남」이다.
                // ⚠ **되살리는 것은 창뿐이다 — 귀는 안 켠다.** 끄는 쪽(`hideWindow`)은 귀도 끄지만
                //   여기서 켜면 이 함수가 면접 상태의 주인이 된다. 지금 이 길로 오는 화면 동선은
                //   없고(쌓기 전용 버튼), 온다면 「보이는 창 + 꺼진 귀」가 「안 보이는 패널」보다 낫다.
                if !host.isVisible {
                    NSApp.activate()
                    host.makeKeyAndOrderFront(nil)
                }
                panel.beginSheetModal(for: host, completionHandler: finish)
            } else {
                // 창 자체가 아직 없을 때만 따로 뜬다 — 붙일 데가 없으니 이 길밖에 없다.
                // 앞으로 끌어와야 보이므로 **신 API**를 쓰고(deprecated 된 `ignoringOtherApps:` 가
                // #78 의 절반이었다), 층위도 올린다 — 채팅창이 `.floating` 이라 안 올리면
                // 우리 창이 고르기 창을 덮는다.
                NSApp.activate()
                panel.level = .modalPanel
                panel.begin(completionHandler: finish)
                panel.makeKeyAndOrderFront(nil)
            }
        }
    }

    /// ⚠ **통로를 안 늘렸다** — `onIngestFiles` 는 Swift→JS 다 (`onIndexNotice` 와 같은 길).
    private func sendIngestFiles(files: [DocumentExtractor.Extracted],
                                 errors: [DocumentExtractor.Failure]) {
        let payload: [String: Any] = [
            "files": files.map { ["name": $0.name, "text": $0.text] },
            "errors": errors.map { ["name": $0.name, "why": $0.why] }
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        for e in errors {
            FileHandle.standardError.write(Data("[cue] 던져넣기: \(e.name) — \(e.why)\n".utf8))
        }
        view.evaluateJavaScript("onIngestFiles(\(jsLiteral(json)))", completionHandler: nil)
    }

    /// 원문 한 창 → **이야기 0~3장**. **비동기다** — 온디바이스라도 몇 초가 걸린다.
    ///
    /// ⚠ 실패를 조용히 삼키지 않는다. 화면이 「만드는 중」을 걷으려면 성공이든 실패든
    /// **같은 id 로 한 번은** 답이 와야 한다.
    ///
    /// ★ **응답 모양이 바뀌었다** (#40 2판): `{id,title,body}` 단수 → `{id,drafts:[{title,body}]}`.
    /// 화면(`onFragmentDraft`)이 같은 커밋에서 같이 바뀌었다 — 계약이 갈리는 자리가 없다.
    /// ⚠ **`drafts` 가 빈 배열인 것은 실패가 아니다.** 「이 창엔 재사용할 이야기가 없다」는
    /// 판정이고, 그래서 `error` 를 안 붙인다.
    ///
    /// ★ `parts`·`ask` 는 **화면만 아는 창의 모양**이다 (#40 2·3판 조정): 몇 편을 붙였나,
    /// 그리고 이것이 면접 문항의 답인가. 화면이 실어 보낸다 — Swift 가 글자를 다시 뜯어
    /// 판정하면 자가 두 벌이 된다. 쓰는 자리는 `FragmentDrafter` 의 지시문 한 문단뿐이다.
    /// ★ `cloud` = **사람이 「공통 지능」을 켰나** (#51 → #55). 켜져 있으면 **사다리를
    /// 위에서 아래로** 탄다: ① 본인 키 클라우드(`CloudDrafter`) → ② 이 맥에 깔린 공식
    /// CLI(`CliDrafter`) → ③ 온디바이스(`FragmentDrafter`). 각 층이 어떤 이유로든 안 되면
    /// **그 자리에서 다음 층**으로 내려가고, 중간에 멈추는 자리가 없다.
    /// ⚠ **준비 안 된 층은 부르지도 않는다.** 키가 없는 사람에게 ①의 「키를 넣으세요」가
    /// 실패 사유로 잡히면, ②가 잘 돌아도 띠에 엉뚱한 줄이 뜬다. 각 층의 `Readiness` 는
    /// 파일·`UserDefaults` 만 보는 싼 판정이라 여기서 먼저 물어봐도 공짜다.
    /// ⚠ 물러선 이유는 `cloudWhy` 로 **같이** 실어 보낸다. 화면이 그걸 띠 한 줄로 말한다 —
    /// 조용히 물러서면 사람은 자기가 켠 것이 안 쓰였다는 것을 영영 모른다.
    /// ⚠ **한 층이라도 성공하면 `cloudWhy` 를 안 싣는다.** ①이 죽고 ②가 살았으면 사람이
    /// 켠 것은 쓰인 것이다 — 거기에 사유를 띄우면 화면이 거짓말을 한다.
    /// ⚠ `cloudWhy` 는 **`error` 가 아니다.** 초안은 왔으니 화면의 판정(`draftVerdict`)이
    /// 그것을 실패로 읽으면 안 된다 — 그래서 칸이 따로다.
    ///
    /// ★ **사다리가 갈래 셋이 됐다** (박선호 2026-09-01, `DrafterChoice`):
    /// - `auto` — **위 문단 그대로다.** 행동이 하나도 안 바뀐다
    /// - `key` · `claude` · `codex` — **그 층 하나만** 두드린다. 죽어 있으면 **조용한 폴백이 없다**:
    ///   온디바이스로 내려가지 않고 `error:"unavailable"` + 정직한 한 줄로 답한다
    /// ⚠ **왜 `unavailable` 인가**: 화면(`onFragmentDraft`)이 그 값을 받으면 큐를 세우고
    ///   남은 덩이를 **기계 자르기**로 채우며 사유를 띠에 세운다(`fallbackIntake`). 그게
    ///   「다른 두뇌로 새지 않으면서 사람이 이유를 보는」 유일한 기존 통로다. `failed` 로 내면
    ///   덩이마다 같은 실패를 스무 번 다시 겪는다.
    /// ⚠ **그때는 `cloudWhy` 를 안 싣는다** — 화면이 그 칸에 「공통 지능을 못 썼어요」를
    ///   앞에 붙이는데, 우리 한 줄이 이미 무엇을 못 썼는지 말하고 있다(같은 말 두 번).
    private func draftFragment(id: String, text: String, parts: Int, ask: Bool, cloud: Bool) {
        Task { [weak self] in
            var payload: [String: Any] = ["id": id]
            var outcome: FragmentDrafter.Outcome? = nil
            var whys: [String] = []
            let choice = DrafterChoice.current
            if cloud {
                // ★ **고른 두뇌가 가리키는 층 하나**를 먼저 정한다. `auto` 면 사다리 순서 그대로다.
                let lane = choice.lane
                if case .key = lane {
                    switch await CloudDrafter.draftViaCloud(text: text, parts: parts, ask: ask) {
                    case .ok(let drafts):
                        payload["via"] = "cloud"
                        outcome = .ok(drafts)
                    case .fallback(let why):
                        whys.append(why)
                        FileHandle.standardError.write(Data("[cue] 내 키: \(why)\n".utf8))
                    }
                }
                if case .cli(let v) = lane {
                    // ⚠ `auto` 는 **그 자리에서 다음 벤더**까지 탄다(`only` 를 안 준다) — 전 판 그대로다.
                    //   명시 선택은 그 벤더 하나로 좁힌다.
                    switch await CliDrafter.draftViaCLI(text: text, parts: parts, ask: ask,
                                                        only: choice == .auto ? nil : v) {
                    case .ok(let drafts):
                        payload["via"] = "cli"
                        outcome = .ok(drafts)
                    case .fallback(let why):
                        whys.append(why)
                        FileHandle.standardError.write(Data("[cue] 구독 CLI: \(why)\n".utf8))
                    }
                }
                // ★ `auto` 에서만 키가 죽으면 CLI 로 내려간다 — **사다리는 여기 한 줄로 남았다.**
                if outcome == nil, choice == .auto, case .key = lane, CliDrafter.cliReadiness().ready {
                    switch await CliDrafter.draftViaCLI(text: text, parts: parts, ask: ask) {
                    case .ok(let drafts):
                        payload["via"] = "cli"
                        outcome = .ok(drafts)
                    case .fallback(let why):
                        whys.append(why)
                        FileHandle.standardError.write(Data("[cue] 구독 CLI: \(why)\n".utf8))
                    }
                }
                // ★ **명시 선택은 여기서 끝난다.** 온디바이스로 안 샌다.
                if outcome == nil, choice != .auto {
                    // ⚠ `via` 를 안 싣는다 — 그 칸은 **뽑힌 이야기가 어디서 왔나**의 표식이고
                    //   (`draftList` 의 `how`), 여기엔 이야기가 없다. 「none」 같은 낱말을 넣으면
                    //   화면의 낱말표에 없어서 **조용히 「초안」으로 읽힌다.**
                    var p = payload
                    p["error"] = "unavailable"
                    if case .device = lane {
                        p["why"] = choice.notConnected
                    } else {
                        p["why"] = choice.noAnswer(whys.joined(separator: " · "))
                    }
                    await self?.sendDraftPayload(p)
                    return
                }
                if outcome == nil, !whys.isEmpty {
                    payload["cloudWhy"] = whys.joined(separator: " · ")
                }
            }
            if outcome == nil {
                payload["via"] = "device"
                outcome = await FragmentDrafter.draft(text: text, parts: parts, ask: ask)
            }
            switch outcome ?? .failed("초안을 만들지 못했다") {
            case .ok(let drafts):
                payload["drafts"] = drafts.map { ["title": $0.title, "body": $0.body] }
            case .unavailable(let why):
                payload["error"] = "unavailable"
                payload["why"] = why
            case .failed(let why):
                payload["error"] = "failed"
                payload["why"] = why
            }
            await self?.sendDraftPayload(payload)
        }
    }

    /// 답 하나를 화면으로. **나가는 문이 하나여야 한다** — 명시 선택이 죽었을 때 일찍
    /// 답하는 길이 생기면서 뽑았다(`draftFragment`). 두 벌이면 한쪽만 `id` 를 빠뜨린다.
    private func sendDraftPayload(_ payload: [String: Any]) async {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        await MainActor.run {
            self.view.evaluateJavaScript("onFragmentDraft(\(jsLiteral(json)))",
                                         completionHandler: nil)
        }
    }

    /// 수확된 면접 질문 한 줄 → 정돈된 한 줄 (#47). **비동기다.**
    ///
    /// ⚠ 실패해도 **같은 id 로 답한다** — 화면이 줄(`tidyQ`)을 한 칸씩 미는데, 답이 안 오면
    /// 그 줄이 그 자리에 멈춘다. 실패 답은 화면에서 「원문 유지」로 읽힌다.
    private func tidyQuestion(id: String, text: String) {
        Task { [weak self] in
            var payload: [String: Any] = ["id": id]
            switch await QuestionTidier.tidy(text: text) {
            case .ok(let tidied):
                payload["text"] = tidied
            case .junk:
                // ★ 문지기가 「질문이 아니다」로 판정했다 (#47 후속). **새 통로가 아니라 이 꾸러미의
                //   칸 하나다** — `parts`·`cloud` 가 `draftFragment` 에 얹힌 것과 같은 모양이다.
                // ⚠ 이 열쇠 이름(`junk`)은 화면의 `onQuestionTidy` 가 읽는 그 이름이다.
                //   한쪽만 고치면 **판정이 조용히 사라진다** — 그 자리를 `tests/tidy.test.mjs` 가 잠근다.
                payload["junk"] = true
            case .unavailable(let why):
                payload["error"] = "unavailable"
                payload["why"] = why
            case .failed(let why):
                payload["error"] = "failed"
                payload["why"] = why
            }
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let json = String(data: data, encoding: .utf8) else { return }
            await MainActor.run {
                self?.view.evaluateJavaScript("onQuestionTidy(\(jsLiteral(json)))",
                                              completionHandler: nil)
            }
        }
    }

    // MARK: - 모드가 껍데기까지 바뀐다 (#18)

    /// 화면이 모드를 바꿀 때 **창과 앱 껍데기**를 같이 옮긴다.
    ///
    /// - 쌓기 = `.regular` — 독 아이콘이 있고 **⌘Q 로 꺼진다.** `.accessory` 는 앱 메뉴바를 아예 안 띄워서
    ///   `NSApp.mainMenu` 에 Quit 이 있어도 **키 등가물이 안 산다** (박선호 2026-08-28: *"종료도 잘 안되고"*).
    /// - 면접 = `.accessory` — 독·⌘Tab 에서 사라진다. 은신은 그대로.
    ///
    /// ⚠ **정책을 바꾸면 창이 흔들린다** (`실측 2026-08-28`, 레포 밖 프로브):
    /// `.regular → .accessory` 뒤에 **키창을 잃고 맨앞앱이 남에게 넘어갔다.** 위치도 한 번은 12·19pt 밀렸다
    /// (매번은 아니다 — 간헐적이라 더 나쁘다). 그래서 **되살리고 프레임을 다시 박는 것이 처방**이다.
    /// 공유 노출은 전환을 넘겨도 은신으로 살아 있었지만, **판정선이라 매번 다시 박는다.**
    /// - Parameter mode: 화면이 보낸 모드 이름. `live` 만 오버레이고 나머지(`stack`·`practice`)는
    ///   **일반 창**이다 (#36). 이름을 그대로 받는 이유는 **자리를 모드마다 따로 기억**하기
    ///   위해서다 — `live`/그 외 둘로 접으면 연습 창을 둔 자리가 쌓기 창의 자리를 덮어써서
    ///   *"켤 때마다 창이 다른 데 뜬다"* 가 다시 일어난다 (박선호 2026-08-28 이 겪은 것).
    func applyMode(_ mode: String, content: NSSize) {
        // ★ 메뉴바 「Settings…」가 여기서 회색이 된다 (#61 리뷰 발견 ⑧). **창이 없어도 돈다** —
        //   메뉴는 창과 무관하게 살아 있으므로 아래 `guard` 위에 있어야 한다.
        (NSApp.delegate as? AppDelegate)?.setSettingsEnabled(forMode: mode)
        guard let win = view.window else { return }
        let live = mode == "live"
        let want: NSApplication.ActivationPolicy = live ? .accessory : .regular
        // Background QA must never acquire focus when the web view reports its mode.
        let backgroundQA = QASession.current != nil && !WindowPrivacy.isQAVisible
        if !backgroundQA && NSApp.activationPolicy() != want {
            NSApp.setActivationPolicy(want)
            NSApp.activate(ignoringOtherApps: true)
            win.makeKeyAndOrderFront(nil)
        }
        // ★ 창 층위도 모드를 따른다 (박선호 2026-08-28: *"일반적인 상하계층 ui가 작동을 안하고 무조건
        //   제일 상위로 보이나?"*). 상류 Ghostbar 는 **떠 있는 오버레이 바**라 `.floating` 을 기동에 한 번
        //   걸고 끝냈다. 우리 쌓기 모드는 「일반 앱」이라 다른 창 뒤로 갈 수 있어야 한다.
        //   ⚠ 면접 모드는 `.floating` 이 필수다 — 면접관 얼굴 위에 떠 있는 것이 자리 결정(Q5)의 전제다.
        win.level = live ? .floating : .normal
        // ★ 창 단추 셋도 모드를 따른다 (#67 재편). 쌓기·연습은 「일반 앱」이라 단추가 있어야
        //   하고(확대가 곧 **캔버스 확대**의 첫 걸음이다 — #67 스펙 3), 면접 오버레이는
        //   그 단추가 뜨는 순간 「이건 앱 창이다」를 화면 위에 광고한다.
        // ⚠ **연습도 켜진다.** 스펙(#67)이 말한 것은 「저장소에 보임 · 면접에 숨김」 둘뿐인데,
        //   여기서 새 축을 만들지 않고 **이 파일이 이미 쓰는 `live` 갈림**을 그대로 탔다 —
        //   연습 창은 층위도 독 아이콘도 쌓기와 같은 「일반 창」이라 단추만 없으면 그게 어긋난다.
        ChatWindow.setWindowButtons(win, on: !live)
        // 끌 수 있는 띠를 화면의 머리 높이에 맞춘다 — 면접은 지난 발화 + 현재 발화(≈92pt),
        // 쌓기는 위 막대(≈44pt). 그 아래는 눌러야 하는 것들이라 안 준다.
        (win as? MovableWindow)?.headerHeight = live ? 92 : 44
        (win as? MovableWindow)?.modeKey = mode
        // ★ **스페이스**도 모드를 따른다. `실측 2026-08-28`: `collectionBehavior` 가 기본값(0) 이었다 —
        //   그러면 창이 **한 스페이스에만 산다.** 전체화면 앱(Zoom·Meet 을 전체화면으로 쓰는 것이 흔하다)은
        //   자기 스페이스를 갖는데, 거기엔 이 창이 **안 따라간다.** 브라우저 탭 전환은 같은 스페이스라 되고,
        //   전체화면 회의는 다른 스페이스라 안 되는 것이다 (박선호 2026-08-28 이 물은 자리).
        //   ⚠ 쌓기 모드는 기본값으로 돌려놓는다 — 「일반 앱」이 모든 스페이스를 따라다니면 그게 이상하다.
        win.collectionBehavior = live
            ? [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            : []
        // ★ 자리는 **그 모드가 마지막에 있던 자리**로 돌아간다. 없으면 지금 창의 중심에 맞춘다.
        //   ⚠ 전엔 기억이 하나뿐이라 모드를 오갈 때마다 서로의 자리를 덮어썼고,
        //   그래서 켤 때마다 창이 다른 데 떴다 (박선호 2026-08-28).
        let old = win.frame
        var f = win.frameRect(forContentRect: NSRect(x: 0, y: 0, width: content.width, height: content.height))
        let key = ChatWindow.frameKey(mode)
        let remembered = (UserDefaults.standard.string(forKey: key).map(NSRectFromString)) ?? .zero
        if remembered.width > 100, remembered.height > 100 {
            f.origin = remembered.origin
        } else {
            f.origin.x = old.midX - f.width / 2
            f.origin.y = old.midY - f.height / 2
        }
        win.setFrame(f, display: true, animate: true)   // 줄며 바뀌는 것 자체가 전환 신호다 (라운드 9)
        // ⚠ 공유 노출은 **두 모드 다** 은신이다 — 박선호 Q6: *"어느 모드에서도 안 잡힌다.
        //   그게 우리 특성이야"*. 이건 층위와 **무관한 별개의 줄**이고, 층위를 낮춰도 안 잡히는 건 그대로다.
        //   값을 정하는 것은 `WindowPrivacy` 하나다 (#24 C 층) — 여기서 직접 대입하지 않는다.
        WindowPrivacy.apply(to: win)
    }

    // MARK: - 면접 모드의 귀 (#17)

    /// 화면이 면접 모드로 들어갈 때 켜고 나올 때 끈다. **면접 모드에서만 산다** —
    /// 쌓기 모드에서 마이크·시스템 오디오를 물고 있을 이유가 없다.
    /// - Parameter system: 시스템 오디오(상대 목소리) 관도 열까. 연습 모드는 `false` —
    ///   묻는 것이 앱이라 상대가 없다 (#36). 마이크 관은 **언제나** 연다.
    func startInterviewEars(system: Bool = true) {
        if ears == nil {
            let e = InterviewEars()
            e.onUpdate = { [weak self] who, confirmed, volatileTail, query, ended in
                guard let self = self else { return }
                let payload: [String: Any] = ["who": who.rawValue, "confirmed": confirmed,
                                              "volatile": volatileTail, "query": query, "ended": ended]
                if let data = try? JSONSerialization.data(withJSONObject: payload),
                   let json = String(data: data, encoding: .utf8) {
                    self.view.evaluateJavaScript("onEar(\(jsLiteral(json)))", completionHandler: nil)
                }
                // ★ 라이브 검색의 질의 벡터 (#34).
                //
                // ⚠ **`onEar` 를 다시 부르지 않는다.** 그게 처음 짠 모양이었는데 틀렸다:
                //   `onEar` 는 `ended` 에서 현재 줄을 지난 줄로 밀어 올리고 버퍼를 비운다.
                //   같은 짐을 벡터만 얹어 한 번 더 보내면 **비운 글자가 되살아나** 현재 줄에
                //   다시 앉는다. 그래서 벡터는 **자기 통로**로 간다.
                // ⚠ **`onEar` 에 얹어 한 번에 보내지도 않는다.** 그러면 전사 표시가 임베딩을
                //   기다린다 — 콜드 색인이 도는 중이면 그게 4초다(`ContentGraph` 주석).
                //   전사는 즉시, 벡터는 뒤따라. 그 사이 화면은 bigram 으로 돈다.
                //
                // ⚠ JS→Swift 통로는 **여전히 15개**다. 늘어난 것은 Swift→JS 뿐이고
                //   그쪽은 배열에 안 박혀 있다(`onIndexNotice` 가 #32 에서 같은 길로 왔다).
                //
                // ⚠ **어절마다 안 만든다.** 임베딩 한 건이 12ms 인데 전사는 한 발화에 수십 번
                //   갱신된다 — 매번 만들면 큐가 밀려 낡은 벡터만 도착한다. **굳은 글자가
                //   자랐을 때와 발화가 끝났을 때**만 만든다.
                // ⚠ 면접관 관만 본다. 내 말(`me`)은 조각을 펴는 데만 쓰이고 순위를 안 매긴다.
                guard who == .them, !query.isEmpty else { return }
                let grew = confirmed != self.lastConfirmedThem
                self.lastConfirmedThem = confirmed
                guard ended || grew else { return }
                self.graph?.embedQuery(query) { [weak self] b64 in
                    guard let self = self,
                          let data = try? JSONSerialization.data(withJSONObject: ["query": query,
                                                                                  "v": b64]),
                          let json = String(data: data, encoding: .utf8) else { return }
                    self.view.evaluateJavaScript("onQueryVector(\(jsLiteral(json)))",
                                                 completionHandler: nil)
                }
            }
            e.onTrouble = { [weak self] message in
                self?.view.evaluateJavaScript("onEarTrouble(\(jsLiteral(message)))", completionHandler: nil)
            }
            ears = e
        }
        ears?.startEars(system: system)
    }

    func stopInterviewEars() {
        ears?.stopEars()
    }

    func requestMicAndRecord() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: startRecording()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                if granted { DispatchQueue.main.async { self?.startRecording() } }
                else { DispatchQueue.main.async {
                    self?.view.evaluateJavaScript("onMicError('Microphone permission denied.')", completionHandler: nil)
                }}
            }
        default:
            view.evaluateJavaScript("onMicError('Microphone denied. Enable in System Settings > Privacy > Microphone.')", completionHandler: nil)
        }
    }

    func startRecording() {
        isRecording = true
        recorder.start()
        view.evaluateJavaScript("onRecordingStarted()", completionHandler: nil)
    }

    func checkWhisperInstall() {
        let hasBin   = findWhisperBin() != nil
        let hasModel = findWhisperModel() != nil
        view.evaluateJavaScript("onWhisperStatus(\(hasBin),\(hasModel))", completionHandler: nil)
    }

    /// 「공통 지능」을 **켤 수 있나**를 화면에 알린다 (#51 → #55).
    ///
    /// ⚠ **통로를 안 늘렸다** — `setCloudDrafter` 는 Swift→JS 다(`onIndexNotice` 와 같은 길).
    /// 화면이 물어보는 모양으로 짜면 브리지 배열이 하나 늘고, 그러면 브라우저 단독 화면이
    /// 그 통로를 영영 못 연다. 밀어 주는 쪽이면 없는 창에서는 그냥 안 오는 것이 된다.
    /// ★ #55 가 **칸을 늘렸지 통로를 늘리지 않았다**: `key`(본인 키 층) · `cli`(설치된 공식
    /// CLI 층) · `cliName`. `ready` 는 이제 **둘 중 하나라도 되나**다 — 화면의 기본값이
    /// 그것을 보고 정해진다(#55: 연결된 공통 지능이 있으면 그것이 기본).
    /// ⚠ **키도 경로도 안 싣는다.** 나가는 것은 「되나 안 되나 · 제공자 이름 · 모델 이름 ·
    /// CLI 이름」뿐이다. 바이너리 경로엔 홈 디렉터리 이름이 들어가고, 화면은 WebView 라
    /// 거기 앉힌 글자는 우리 손을 떠난다.
    /// ★ **`ready` 의 뜻이 바뀌었다** (2026-09-01, `DrafterChoice`): 「어느 층이든 하나라도
    /// 되나」에서 **「지금 고른 두뇌가 되나」**로. 명시 선택은 다른 층으로 안 새므로, 고른 것이
    /// 죽어 있는데 「켤 수 있어요」라고 말하면 화면이 거짓말을 한다.
    /// ★ **칸 셋이 서로 다른 것을 뜻한다** (2026-09-02, matt 2축 리뷰 H3 에서 갈랐다):
    /// - `hasKey` = **키가 저장돼 있나.** 설정의 키 칸 placeholder 와 「키 지우기」가 이것을
    ///   읽는다(`paintBackendKey`). 전엔 이 자리도 `key` 를 읽었는데, 그건 모델·주소까지 본
    ///   값이라 **키를 넣고 모델을 안 고른 사람에게 「없어요」라고 거짓말**했다
    /// - `key` = **키 층이 준비됐나**(키·주소·모델 셋). 설정의 두뇌 목록에서 「API 키」 줄이
    ///   이것을 읽는다 — 그 값의 집이 여기 하나가 됐다(`detectCli` 에서 걷었다)
    /// - `lane` = **이번에 실제로 두드릴 층.** 「지금 어디로 나가나」는 이 칸이 든다
    /// ⚠ 겹쳐 담으면 **키를 넣어 둔 사람이 두뇌를 바꾼 순간 키 칸이 「없어요」로 바뀐다.**
    /// ★ **`ready`·`lane` 은 `shownLane` 이 정한다** (같은 리뷰 P1) — 로그인까지 본 쪽이다.
    /// 안 그러면 「Codex CLI 가 만들어요」와 설정의 「로그인이 필요해요」가 갈린다.
    /// ⚠ **`draftFragment` 는 계속 `lane` 이다** — 말하는 판정과 두드리는 판정은 다르다
    /// (`DrafterChoice.shownLane` 머리글).
    /// ★ **그래서 `ready` 는 「말」이지 「문」이 아니다** (2026-09-02, 리뷰 발견 ①). 화면은
    /// 이 칸으로 **무엇을 적을지**만 정하고, **보낼지 말지**는 `cloudArmed(ready, choice)` 가
    /// 정한다 — 명시 선택이면 `ready:false` 라도 토글이 살아 있고 `cloud:true` 가 나간다.
    /// 자국(`lastLoggedIn`)은 낡을 수 있는데, 그것 하나로 문을 닫으면 **자국을 안 믿는 쪽**
    /// (`lane`)이 애초에 안 불린다. 진짜로 죽어 있으면 `draftFragment` 가 `unavailable` 로
    /// 정직하게 떨어진다.
    func sendCloudReady() {
        let r = CloudDrafter.cloudReadiness()
        let c = CliDrafter.cliReadiness()
        let choice = DrafterChoice.current
        // 지금 고른 두뇌가 가리키는 층. 화면은 이 한 낱말로 「누가 만드나」를 그린다.
        var lane = "device", cliName = c.name, ready = false
        switch choice.shownLane {
        case .key:        lane = "key";  ready = true
        case .cli(let v): lane = "cli";  ready = true; cliName = v.name
        case .device:     break
        }
        // 못 켤 때만 이유를 싣는다. ⚠ 자동일 때는 **키 쪽 안내에 CLI 갈래를 한 마디 붙인다** —
        //   안 붙이면 3층이 있다는 것을 아무 화면도 말하지 않는다. 명시 선택일 때는 그 말이
        //   거짓이 된다(다른 층으로 안 샌다) — 그래서 `DrafterChoice` 의 한 줄을 그대로 쓴다.
        let why = ready ? ""
            : (choice == .auto
                ? r.why + " · 공식 CLI(\(CliDrafter.binaryNames))가 깔려 있어도 켜져요"
                : choice.notConnected)
        // ★ `type`·`url` 은 #61 B 가 더했다 — **프론트 설정 화면이 지금 고른 프리셋을 그리려면**
        //   그 둘이 필요하다. ⚠ **키는 여전히 안 싣는다.** 나가는 것은 「키가 있나」(`key`)뿐이다.
        let cfg = BackendConfig.current
        // ⚠ **`cli`(= CLI 층이 준비됐나)를 안 싣는다** (2026-09-02, 리뷰 발견 ⑥). 화면이 그 칸을
        //   **쓰기만 하고 아무 데서도 안 읽었다** — 읽는 것은 「이번에 두드릴 층」(`lane`) 하나다.
        //   `c` 는 계속 쓴다: `cliName` 의 기본값이 거기서 온다.
        // ★ `choice` 는 남는다 — 받기 화면이 「명시 선택인가」를 그것으로 판정하고(`cloudArmed`),
        //   설정 화면을 안 열면 `detectCli` 가 안 돌아 그 값을 줄 통로가 여기뿐이다.
        let payload: [String: Any] = ["ready": ready,
                                      "key": r.ready, "hasKey": !cfg.apiKey.isEmpty,
                                      "cliName": cliName,
                                      "lane": lane, "choice": choice.rawValue,
                                      // ★ 「자동」 줄의 이름표. **화면이 다시 유도하지 않는다** —
                                      //   판정도 글자도 `DrafterChoice.autoLabel` 하나가 짓는다.
                                      "autoLabel": DrafterChoice.autoLabel,
                                      "provider": r.provider,
                                      "type": cfg.type.rawValue, "url": cfg.url,
                                      "model": r.model, "why": why]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        view.evaluateJavaScript("setCloudDrafter(\(jsLiteral(json)))", completionHandler: nil)
    }

    func sendSavedModel() {
        if let saved = UserDefaults.standard.string(forKey: "selectedModel") {
            view.evaluateJavaScript("setSavedModel('\(saved)')", completionHandler: nil)
        }
    }

    /// ★ **시스템 상태 한 벌** — 단축키 둘 · 권한 둘 · 볼트 경로 (2026-08-31 설정 통합).
    ///
    /// 전엔 `setShortcut`·`setCaptureShortcut` 둘이 나갔는데 **화면 쪽이 빈 스텁**이라 답이
    /// 그대로 버려졌다(네이티브 패널이 그 값을 들고 있었으므로). 화면이 그 칸을 갖게 된 지금
    /// 한 이름으로 합친다 — 세 종류가 **같은 순간에 같이 낡기** 때문이다: 설정 화면을 열면
    /// 셋을 한 번에 다시 그린다.
    ///
    /// ⚠ **권한을 여기서 묻지 않는다.** `authorizationStatus`·`CGPreflight…` 는 **재기만**
    /// 하고 창을 안 띄운다 — 설정 화면을 열었다는 이유로 면접 직전에 권한 창이 뜨면 안 된다.
    /// 실제로 묻는 자리는 그 기능을 켤 때다(`requestMicAndRecord` · `ScreenCapture`).
    ///
    /// - Parameter failedSlot: 방금 고른 조합이 **안 걸린** 자리. 화면이 그 줄에만 한 줄 세운다.
    func sendSystemState(failedSlot: GlobalHotKey.Slot? = nil) {
        let app = NSApp.delegate as? AppDelegate
        let keys = GlobalHotKey.Slot.allCases.map { slot -> String in
            let reg = app?.shortcutRegistered(slot) ?? false
            return "\"\(slot.name)\":{\"k\":\(RecordingShortcut.current(slot).jsJSON),\"on\":\(reg)}"
        }.joined(separator: ",")
        let mic: String
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:    mic = "on"
        case .notDetermined: mic = "ask"
        default:             mic = "off"
        }
        let screen = CGPreflightScreenCaptureAccess() ? "on" : "off"
        let vaultPath = (VaultLocation.selected?.path ?? "")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let failed = failedSlot.map { "\"\($0.name)\"" } ?? "null"
        let json = "{\"keys\":{\(keys)},\"mic\":\"\(mic)\",\"screen\":\"\(screen)\","
            + "\"vault\":\"\(vaultPath)\",\"failed\":\(failed)}"
        view.evaluateJavaScript("setSystemState(\(jsLiteral(json)))", completionHandler: nil)
        if !speechPreparing {
            InterviewEars.probeSpeechModel { [weak self] state in
                guard let self = self, !self.speechPreparing else { return }
                self.sendSpeechModelState(state)
            }
        }
    }

    func sendScreenshotPrompt() {
        let prompt = UserDefaults.standard.string(forKey: "screenshotPrompt") ?? ""
        if prompt.isEmpty {
            view.evaluateJavaScript("setScreenshotPrompt(null)", completionHandler: nil)
        } else {
            let esc = prompt
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            view.evaluateJavaScript("setScreenshotPrompt('\(esc)')", completionHandler: nil)
        }
    }

    func fetchModels(requestID: Int? = nil) {
        sendModelsState("loading", requestID: requestID)
        let cfg = BackendConfig.current
        switch cfg.type {
        case .ollama:      fetchOllamaModels(cfg: cfg, requestID: requestID)
        case .openai:      fetchOpenAIModels(cfg: cfg, requestID: requestID)
        case .anthropic:   fetchAnthropicModels(cfg: cfg, requestID: requestID)
        case .openrouter:  fetchOpenAIModels(cfg: cfg, requestID: requestID)
        }
    }

    private func sendModelsState(_ state: String, message: String? = nil, requestID: Int? = nil) {
        var payload: [String: Any] = ["state": state]
        if let message, !message.isEmpty { payload["message"] = message }
        if let requestID { payload["requestID"] = requestID }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.view.evaluateJavaScript("onModelsState(\(json))", completionHandler: nil)
        }
    }

    private func modelData(_ data: Data?, response: URLResponse?) -> Data? {
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              let data else { return nil }
        return data
    }

    func fetchOllamaModels(cfg: BackendConfig, requestID: Int? = nil) {
        guard let url = URL(string: "\(cfg.url)/api/tags") else {
            sendModelsState("error", message: "모델 목록을 불러오지 못했어요", requestID: requestID)
            return
        }
        URLSession.shared.dataTask(with: url) { [weak self] data, response, _ in
            guard let self, let data = self.modelData(data, response: response),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["models"] as? [[String: Any]] else {
                self?.sendModelsState("error", message: "모델 목록을 불러오지 못했어요", requestID: requestID)
                return
            }
            let names = models.compactMap { $0["name"] as? String }
            DispatchQueue.main.async {
                let id = requestID.map { ",\($0)" } ?? ""
                self.view.evaluateJavaScript("receiveModels(\(jsonString(names)),'ollama'\(id))", completionHandler: nil)
            }
        }.resume()
    }

    func fetchAnthropicModels(cfg: BackendConfig, requestID: Int? = nil) {
        let base = cfg.url.isEmpty ? "https://api.anthropic.com/v1" : cfg.url
        guard let url = URL(string: "\(base)/models") else {
            sendModelsState("error", message: "모델 목록을 불러오지 못했어요", requestID: requestID)
            return
        }
        var req = URLRequest(url: url)
        req.setValue(cfg.apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
            guard let self, let data = self.modelData(data, response: response),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["data"] as? [[String: Any]] else {
                self?.sendModelsState("error", message: "모델 목록을 불러오지 못했어요", requestID: requestID)
                return
            }
            let names = models.compactMap { $0["id"] as? String }.sorted()
            DispatchQueue.main.async {
                let id = requestID.map { ",\($0)" } ?? ""
                self.view.evaluateJavaScript("receiveModels(\(jsonString(names)),'openai'\(id))", completionHandler: nil)
            }
        }.resume()
    }

    func fetchOpenAIModels(cfg: BackendConfig, requestID: Int? = nil) {
        guard let url = URL(string: "\(cfg.url)/models") else {
            sendModelsState("error", message: "모델 목록을 불러오지 못했어요", requestID: requestID)
            return
        }
        var req = URLRequest(url: url)
        if !cfg.apiKey.isEmpty { req.setValue("Bearer \(cfg.apiKey)", forHTTPHeaderField: "Authorization") }
        URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
            guard let self, let data = self.modelData(data, response: response),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["data"] as? [[String: Any]] else {
                self?.sendModelsState("error", message: "모델 목록을 불러오지 못했어요", requestID: requestID)
                return
            }
            let names = models.compactMap { $0["id"] as? String }.sorted()
            DispatchQueue.main.async {
                let id = requestID.map { ",\($0)" } ?? ""
                self.view.evaluateJavaScript("receiveModels(\(jsonString(names)),'openai'\(id))", completionHandler: nil)
            }
        }.resume()
    }

    func streamResponse(messages: [[String: Any]], model: String, image: String? = nil) {
        let cfg = BackendConfig.current
        var msgs = messages
        if let sp = UserDefaults.standard.string(forKey: "systemPrompt"), !sp.isEmpty {
            msgs.insert(["role": "system", "content": sp], at: 0)
        }
        switch cfg.type {
        case .ollama:     streamOllama(messages: msgs, model: model, cfg: cfg, image: image)
        case .openai:     streamOpenAI(messages: msgs, model: model, cfg: cfg, image: image)
        case .anthropic:  streamAnthropic(messages: msgs, model: model, cfg: cfg, image: image)
        case .openrouter: streamOpenAI(messages: msgs, model: model, cfg: cfg, image: image)
        }
    }

    func streamOllama(messages: [[String: Any]], model: String, cfg: BackendConfig, image: String? = nil) {
        guard let url = URL(string: "\(cfg.url)/api/chat") else { return }
        var msgs = messages
        if let img = image, !msgs.isEmpty {
            var last = msgs[msgs.count - 1]
            last["images"] = [img]
            msgs[msgs.count - 1] = last
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["model": model, "messages": msgs, "stream": true])
        startStream(req: req, parser: OllamaStreamParser())
    }

    func streamOpenAI(messages: [[String: Any]], model: String, cfg: BackendConfig, image: String? = nil) {
        guard let url = URL(string: "\(cfg.url)/chat/completions") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !cfg.apiKey.isEmpty { req.setValue("Bearer \(cfg.apiKey)", forHTTPHeaderField: "Authorization") }
        var msgs = messages
        if let img = image, !msgs.isEmpty {
            var last = msgs[msgs.count - 1]
            if let text = last["content"] as? String {
                last["content"] = [
                    ["type": "text", "text": text],
                    ["type": "image_url", "image_url": ["url": "data:image/png;base64,\(img)"]]
                ]
                msgs[msgs.count - 1] = last
            }
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["model": model, "stream": true, "messages": msgs])
        startStream(req: req, parser: OpenAIStreamParser())
    }

    func streamAnthropic(messages: [[String: Any]], model: String, cfg: BackendConfig, image: String? = nil) {
        let base = cfg.url.isEmpty ? "https://api.anthropic.com/v1" : cfg.url
        guard let url = URL(string: "\(base)/messages") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(cfg.apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        var userMsgs = messages.filter { ($0["role"] as? String) != "system" }
        let systemText = messages.first(where: { ($0["role"] as? String) == "system" })?["content"] as? String

        if let img = image, !userMsgs.isEmpty {
            var last = userMsgs[userMsgs.count - 1]
            if let text = last["content"] as? String {
                last["content"] = [
                    ["type": "text", "text": text],
                    ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": img]]
                ]
                userMsgs[userMsgs.count - 1] = last
            }
        }

        var body: [String: Any] = ["model": model, "max_tokens": 8096, "stream": true, "messages": userMsgs]
        if let sys = systemText, !sys.isEmpty { body["system"] = sys }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        startStream(req: req, parser: AnthropicStreamParser())
    }

    func startStream(req: URLRequest, parser: StreamParser) {
        currentStreamSession?.invalidateAndCancel()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30  // 30s of silence = hang, abort
        let delegate = StreamDelegate(webView: view, parser: parser)
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        currentStreamSession = session
        session.dataTask(with: req).resume()
    }

    func loadHTML() { view.loadHTMLString(chatHTML(), baseURL: nil) }

    // MARK: - 기동 주입 (Swift → JS 통로 하나)

    /// 화면이 다 뜬 **뒤에** 문서를 밀어넣는다.
    ///
    /// ⚠ `init` 에서 부르면 안 된다 — `loadHTMLString` 은 비동기라 그 시점엔 `receiveDocument`
    /// 가 아직 없고, `evaluateJavaScript` 는 **조용히 실패한다.** 그래서 navigation delegate 다.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        VaultLocation.restorePreviousDefault { [weak self] in
            guard let self else { return }
            if self.store == nil, VaultLocation.selected != nil { self.rebindVault() }
            else { self.sendDocument() }
            self.sendSystemState()
        }
        // 「더 좋은 정리」의 켤 수 있나 (#51). 여기서 미는 이유는 `sendDocument` 와 같다 —
        // `init` 시점엔 `setCloudDrafter` 가 아직 없고 `evaluateJavaScript` 는 조용히 실패한다.
        sendCloudReady()
        sendWindowStyle()
        // ★ 화면이 **검증용 숫자를 보여도 되나** (#61 E). 이 값은 은신을 안 정한다 —
        //   그건 `WindowPrivacy` 하나가 정하고 `tests/check_qa_visible_gate.py` 가 잰다.
        view.evaluateJavaScript("setQAVisible(\(WindowPrivacy.isQAVisible))",
                                completionHandler: nil)
    }

    /// 저장된 창 손잡이 둘을 화면으로 되돌린다 (#61 B).
    ///
    /// ⚠ **통로를 안 늘렸다** — `setWindowStyleValues` 는 Swift→JS 다(`setCloudDrafter` 와 같은 길).
    /// ⚠ 블러는 Swift 가 이미 걸었다(`applyWindowStyle`). 이 짐이 필요한 것은 **불투명도** 때문이다:
    /// 그 값은 화면의 `#app` 배경 알파라, 안 돌려주면 재기동마다 사람이 다시 맞춰야 한다.
    func sendWindowStyle() {
        let payload: [String: Any] = ["blur": WindowStyle.blur, "opacity": WindowStyle.opacity]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        view.evaluateJavaScript("setWindowStyleValues(\(jsLiteral(json)))", completionHandler: nil)
    }

    /// ★ **읽기도 주 스레드를 떠났다** (블로커 F1). 재기동 뒤의 고착이 바로 여기였다 —
    /// `sendDocument` → `VaultStore.load` → `open()` 이 권한 대기에 굳었다(`실측 2026-08-30`).
    ///
    /// 처음 연결하지 않았거나 첫 읽기에 실패하면 폴더 연결 화면을 보낸다.
    /// 외부 변경 뒤 다시 읽기 실패는 현재 문서와 초안을 유지하고 사유를 표시한다.
    func sendDocument(kind: String = "load", requestID: Int? = nil,
                      preserveTrouble: Bool = false,
                      fallback: (CueDocument, VaultSaveResult)? = nil) {
        guard let vault = vault else {
            view.evaluateJavaScript("onVaultDisconnected()", completionHandler: nil)
            return
        }
        let generation = vaultGeneration
        vault.perform({ try $0.loadWorkspace() }) { [weak self] trouble in
            self?.showVaultTrouble(trouble)
        } completion: { [weak self] workspaceResult in
            guard let self = self else { return }
            guard generation == self.vaultGeneration else { return }
            if case .success(let workspace) = workspaceResult {
                let versioned = workspace.versioned
                if !preserveTrouble { self.clearVaultTrouble() }
                if kind == "reload" { self.vaultChangedOutside = false }
                self.deliverDocument(versioned.result, revision: versioned.revision,
                                     kind: kind, requestID: requestID,
                                     savedRevision: fallback?.1.revision, workspace: workspace)
                return
            }
            if let (document, saved) = fallback {
                let loaded = LoadResult(document: document, paths: saved.paths)
                self.deliverDocument(loaded, revision: saved.revision,
                                     kind: kind, requestID: requestID,
                                     savedRevision: saved.revision)
            } else if let requestID {
                self.failDocumentSave(requestID)
            } else {
                if kind == "reload" { self.vaultChangedOutside = true }
                // 첫 읽기 실패는 예전처럼 빈 화면으로 물러선다. 리비전이 없으므로 저장은
                // 화면에서 대기하고, 권한을 고른 뒤 새 load가 오면 이어진다.
                if kind == "load" {
                    self.view.evaluateJavaScript("onVaultDisconnected()", completionHandler: nil)
                }
            }
        }
    }

    /// 실제 리비전을 네이티브에 보관하고 화면에는 짧게 사는 표만 보낸다.
    private func rememberVaultRevision(_ revision: VaultRevision) -> String {
        let id = UUID().uuidString
        vaultRevisions[id] = revision
        vaultRevisionOrder.append(id)
        // 화면이 잠깐 늦게 돌려주는 표를 위해 여러 판을 두되, 큰 baseline을 끝없이 들지는 않는다.
        while vaultRevisionOrder.count > 32 {
            vaultRevisions.removeValue(forKey: vaultRevisionOrder.removeFirst())
        }
        return id
    }

    private func deliverDocument(_ loaded: LoadResult, revision: VaultRevision,
                                 kind: String, requestID: Int?,
                                 savedRevision: VaultRevision? = nil, workspace: VaultWorkspace? = nil) {
        guard let json = VaultIO.documentPayloadJSON(loaded) else {
            if let requestID { failDocumentSave(requestID) }
            return
        }
        let revisionID = rememberVaultRevision(revision)
        var metadata: [String: Any] = ["kind": kind, "revision": revisionID]
        if let workspace {
            metadata["folders"] = workspace.folders
            metadata["entries"] = workspace.entries.map {
                ["id": $0.id, "path": $0.path, "kind": $0.kind,
                 "byteCount": $0.byteCount, "manageable": $0.manageable] as [String: Any]
            }
            metadata["trash"] = workspace.trashEntries.map { entry -> [String: Any] in
                var row: [String: Any] = ["id": entry.id, "storedRelativePath": entry.storedRelativePath,
                                          "kind": entry.kind.rawValue, "legacy": entry.legacy]
                if let path = entry.originalPath { row["originalPath"] = path }
                return row
            }
        }
        if let savedRevision {
            metadata["savedRevision"] = savedRevision == revision
                ? revisionID : rememberVaultRevision(savedRevision)
        }
        if let requestID { metadata["requestID"] = requestID }
        guard let data = try? JSONSerialization.data(withJSONObject: metadata),
              let meta = String(data: data, encoding: .utf8) else {
            if let requestID { failDocumentSave(requestID) }
            return
        }
        let notice = loaded.quarantined.map {
            "읽을 수 없는 저장 파일을 옆으로 치웠다: \($0.lastPathComponent)"
        }
        view.evaluateJavaScript(
            "receiveDocument(\(jsLiteral(json)),\(notice.map(jsLiteral) ?? "null"),\(meta))",
            completionHandler: nil)
        // 볼트를 읽을 때 색인해야 옵시디언에서 더한 조각도 그래프에 앉는다.
        indexFragments(loaded.document)
    }

    /// 파일 정리도 기존 저장 큐와 리비전 검사를 통과한다.
    private func handleVaultAction(_ body: [String: Any]) {
        guard let requestID = (body["requestID"] as? NSNumber)?.intValue else { return }
        let respond: ([String: Any]) -> Void = { [weak self] payload in
            var result = payload; result["requestID"] = requestID
            guard let data = try? JSONSerialization.data(withJSONObject: result),
                  let json = String(data: data, encoding: .utf8) else { return }
            self?.view.evaluateJavaScript("onVaultAction(\(json))", completionHandler: nil)
        }
        guard let vault = vault, let token = body["revision"] as? String,
              let revision = vaultRevisions[token], let action = body["action"] as? String else {
            respond(["error": "폴더 상태가 바뀌었어요. 다시 읽은 뒤 시도해 주세요."]); return
        }
        let generation = vaultGeneration
        let value: (String) -> String = { body[$0] as? String ?? "" }
        let id = value("id"), path = value("path"), name = value("name"), folder = value("folder")
        if value("phase") != "apply" {
            vault.perform({ store -> [VaultLinkImpact] in
                let workspace = try store.loadWorkspace()
                let source = action.hasSuffix("File") ? workspace.paths[id] ?? "" : path
                let parent = source.split(separator: "/").dropLast().joined(separator: "/")
                let fileName = source.split(separator: "/").last.map(String.init) ?? ""
                switch action {
                case "nestFile":
                    return try store.previewMoveFile(id: id, underFile: value("targetID"), expecting: revision).linkImpacts
                case "renameFile", "renameFolder", "renameEntry":
                    return try store.previewMove(from: source, to: [parent, name].filter { !$0.isEmpty }.joined(separator: "/"), expecting: revision).linkImpacts
                case "moveFile", "moveFolder", "moveEntry":
                    return try store.previewMove(from: source, to: [folder, fileName].filter { !$0.isEmpty }.joined(separator: "/"), expecting: revision).linkImpacts
                case "trashFile", "trashFolder":
                    return try store.previewTrash(at: source, expecting: revision).linkImpacts
                default: return []
                }
            }) { [weak self] result in
                guard let self = self, generation == self.vaultGeneration else { return }
                switch result {
                case .success(let impacts):
                    respond(["preview": true, "impacts": impacts.map { ["markdownPath": $0.markdownPath, "reference": $0.reference] }])
                case .failure(let error): respond(["error": error.localizedDescription])
                }
            }
            return
        }
        if action == "openEntry" {
            vault.perform({ store -> URL in
                let catalog = VaultEntryCatalog(rootURL: store.vaultURL)
                let entry = try catalog.entry(at: path)
                guard entry.kind == "file", entry.manageable else {
                    throw VaultMutationError.wrongKind(path)
                }
                return try catalog.url(at: path)
            }) { [weak self] result in
                guard let self, generation == self.vaultGeneration else { return }
                switch result {
                case .success(let url):
                    let ext = url.pathExtension.lowercased()
                    let textTypes: Set<String> = ["swift", "sh", "bash", "zsh", "command", "py", "rb", "pl", "js", "mjs", "cjs", "ts", "tsx", "jsx", "json", "yml", "yaml", "toml", "xml", "html", "css", "c", "h", "cpp", "rs", "go", "sql", "txt", "md", "markdown"]
                    // Viewing a script must not launch its interpreter.
                    if textTypes.contains(ext) || ext.isEmpty || FileManager.default.isExecutableFile(atPath: url.path) {
                        guard let editor = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") else {
                            respond(["error": "텍스트 편집기를 찾을 수 없어요."]); return
                        }
                        NSWorkspace.shared.open([url], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                            DispatchQueue.main.async { respond(error.map { ["error": $0.localizedDescription] } ?? ["ok": true]) }
                        }
                    } else if NSWorkspace.shared.open(url) { respond(["ok": true]) }
                    else { respond(["error": "이 파일을 여는 앱을 찾을 수 없어요."]) }
                case .failure(let error): respond(["error": error.localizedDescription])
                }
            }
            return
        }
        vault.perform({ store -> VaultMutationResult in
            switch action {
            case "createFolder": return try store.createFolder(at: path, expecting: revision)
            case "createFile": return try store.createFile(at: path, expecting: revision)
            case "renameFile": return try store.renameFile(id: id, toFileName: name, expecting: revision)
            case "moveFile": return try store.moveFile(id: id, toFolder: folder, expecting: revision)
            case "nestFile": return try store.moveFile(id: id, underFile: value("targetID"), expecting: revision)
            case "renameFolder": return try store.renameFolder(at: path, toName: name, expecting: revision)
            case "moveFolder": return try store.moveFolder(at: path, toFolder: folder, expecting: revision)
            case "renameEntry": return try store.renameEntry(at: path, toName: name, expecting: revision)
            case "moveEntry": return try store.moveEntry(at: path, toFolder: folder, expecting: revision)
            case "trashFile": return try store.trashFile(id: id, expecting: revision)
            case "trashFolder": return try store.trashFolder(at: path, expecting: revision)
            case "restore": return try store.restoreTrash(id: value("trashID"), to: body["to"] as? String, expecting: revision)
            case "undo": return try store.undo(operationID: value("operationID"), expecting: revision)
            default: throw NSError(domain: "ClonieVaultAction", code: 1, userInfo: [NSLocalizedDescriptionKey: "알 수 없는 파일 작업이에요."])
            }
        }) { [weak self] result in
            guard let self = self, generation == self.vaultGeneration else { return }
            switch result {
            case .success(let mutation):
                self.deliverDocument(mutation.workspace.versioned.result, revision: mutation.revision,
                                     kind: "reload", requestID: nil, workspace: mutation.workspace)
                var result: [String: Any] = ["ok": true]
                if let operation = mutation.operation {
                    result["operationID"] = operation.id
                    result["sourcePath"] = action == "undo" ? operation.destinationPath : operation.sourcePath
                    result["destinationPath"] = action == "undo" ? operation.sourcePath : operation.destinationPath
                }
                if let createdID = mutation.createdID { result["createdID"] = createdID }
                respond(result)
            case .failure(let error):
                respond(["error": error.localizedDescription])
                self.sendDocument(kind: "reload", preserveTrouble: true)
            }
        }
    }

    private func sendSpeechModelState(_ state: String, message: String = "") {
        view.evaluateJavaScript("onSpeechModelState(\(jsLiteral(state)),\(jsLiteral(message)))", completionHandler: nil)
    }

    private func failDocumentSave(_ requestID: Int) {
        view.evaluateJavaScript("onDocumentSaveFailed(\(requestID))", completionHandler: nil)
    }

    /// 창을 숨긴다 — **문이 둘이고 자리가 하나다** (화면의 ✕ = `closeWindow` · 창 단추의 닫기 =
    /// `ChatWindow.windowShouldClose`). 둘이 각자 짜면 한쪽에 한 줄이 늘 때 다른 쪽이 조용히 낡는다.
    ///
    /// ⚠ 창을 숨기면 **귀도 끈다.** 이 앱은 `LSUIElement` 라 독 아이콘이 없어서, 숨긴 창은
    /// 사용자에게 「닫힌 것」으로 보인다 — 그 상태로 마이크를 물고 있으면 안 된다.
    /// 다시 열 때 화면이 `render()` 로 스스로 켠다.
    func hideWindow() {
        stopInterviewEars()
        // ★ **전체화면이면 먼저 나온다** (박선호 2026-09-02: *"전체화면으로 키우고 화면을 닫으면
        //   그냥 검은색 화면이 됨"*). 전체화면 창을 그대로 `orderOut` 하면 그 스페이스는 남고
        //   창만 사라져 **검은 판**이 된다. 나오는 것은 비동기라, 다 나온 뒤(`windowDidExitFullScreen`)
        //   `finishHideAfterFullScreen` 이 마저 숨긴다.
        if let win = view.window, win.styleMask.contains(.fullScreen) {
            hidePendingFullScreenExit = true
            win.toggleFullScreen(nil)
            return
        }
        DispatchQueue.main.async { self.view.window?.orderOut(nil) }
    }

    /// JS가 아직 예약된 자동 저장을 즉시 저장하고, 저장 확인까지 받은 뒤 종료 허가를 돌려준다.
    /// `applicationShouldTerminate`가 종료를 보류하고 이 completion을 기다린다.
    func prepareForTermination(completion: @escaping (Bool) -> Void) {
        guard terminationCompletion == nil else { completion(false); return }
        terminationCompletion = completion
        let token = UUID().uuidString
        terminationToken = token
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.terminationToken == token else { return }
            self.finishTerminationPreparation(false, timedOut: true)
        }
        terminationTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: timeout)
        view.evaluateJavaScript("prepareForTermination(\(jsLiteral(token)))") { [weak self] _, error in
            guard error != nil, let self, self.terminationToken == token else { return }
            self.finishTerminationPreparation(false)
        }
    }

    private func finishTerminationPreparation(_ ok: Bool, timedOut: Bool = false) {
        guard let completion = terminationCompletion else { return }
        terminationCompletion = nil
        let token = terminationToken
        terminationToken = nil
        terminationTimeout?.cancel()
        terminationTimeout = nil
        if !ok {
            let message = timedOut ? "종료 전에 저장 확인을 받지 못했어요. 초안을 보존했으니 다시 시도해 주세요." : ""
            view.evaluateJavaScript("cancelTerminationPreparation(\(jsLiteral(token ?? "")),\(jsLiteral(message)))",
                                    completionHandler: nil)
        }
        completion(ok)
    }

    /// `hideWindow` 가 전체화면을 먼저 풀고 남긴 숨기기. `ChatWindow.windowDidExitFullScreen` 이 부른다.
    private var hidePendingFullScreenExit = false
    func finishHideAfterFullScreen() {
        guard hidePendingFullScreenExit else { return }
        hidePendingFullScreenExit = false
        DispatchQueue.main.async { self.view.window?.orderOut(nil) }
    }

    // MARK: - 볼트 사고를 화면으로 (블로커 F1)

    /// ⚠ **통로를 안 늘렸다** — `onVaultTrouble` 은 Swift→JS 이고 그쪽은 브리지 배열에
    /// 안 박혀 있다 (`onIndexNotice`·`onQueryVector` 가 같은 길로 왔다).
    /// ⚠ stderr 도 **같이** 낸다. 띠는 사람 것이고 로그는 다음 세션 것이다.
    private func showVaultTrouble(_ trouble: VaultIO.Trouble) {
        if trouble != .slow {
            FileHandle.standardError.write(Data("[cue] 볼트: \(trouble.message)\n".utf8))
        }
        view.evaluateJavaScript("onVaultTrouble(\(jsLiteral(trouble.message)))",
                                completionHandler: nil)
    }

    /// 잘 끝났다 — 띠를 걷는다. **빈 글자가 「걷어라」다** (화면 `onVaultTrouble` 규약).
    private func clearVaultTrouble() {
        view.evaluateJavaScript("onVaultTrouble(\"\")", completionHandler: nil)
    }

    /// 종료 직전에 부른다 — **밀린 저장이 디스크에 앉을 때까지** 기다린다 (블로커 F1).
    ///
    /// ⚠ 주 스레드에서 하던 때는 이게 공짜였다. 큐 뒤로 보낸 순간 ⌘Q 가 마지막 저장을
    /// 버릴 수 있게 됐고, 그래서 이 함수가 같이 생겼다. 안 끝나도 **돌아온다**(`VaultIO.flush`).
    func flushVaultWrites() {
        guard let vault = vault else { return }
        if !vault.flush() {
            FileHandle.standardError.write(
                Data("[cue] 볼트: 종료 시각에 밀린 저장이 안 끝났다 — 권한 창을 확인해라\n".utf8))
        }
    }
}

/// 임의의 문자열을 **JS 문자열 리터럴**로 만든다.
///
/// 손으로 `\\` 와 `'` 만 바꾸는 이 파일의 기존 방식(`onTranscription` 등)은 줄바꿈·제어문자에서 깨진다.
/// 조각 본문에는 그것들이 들어간다 — 그래서 표준 인코더를 쓴다.
/// ⚠ JSON 은 U+2028/U+2029 를 날것으로 두는데 **JS 문자열 리터럴에선 그게 줄바꿈**이다. 그것만 더 막는다.
func jsLiteral(_ s: String) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: s, options: [.fragmentsAllowed]),
          let lit = String(data: data, encoding: .utf8) else { return "\"\"" }
    return lit
        .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
        .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
}
