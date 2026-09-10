import Foundation
import GhostbarCore
import GhostbarEmbedding
import GhostbarIndex

/// ★ **앱 층에서 내용 그래프를 굴리는 자리** (#32, ADR 0003 §3-①).
///
/// `GhostbarIndex` 는 「어떻게 세나」를 알고, 여기는 「언제 돌리고 누구한테 말하나」를 안다.
/// 그 둘을 안 가르면 색인 로직이 `WKWebViewWrapper` 안으로 흘러들어가 **`swift test` 가
/// 못 재는 자리**가 된다.
///
/// ⚠ **주 스레드에서 안 돈다.** 모델을 여는 데만 수백 ms 가 들고, 콜드 색인은 조각 수에
/// 비례한다. 그걸 저장 버튼에 매달면 **창이 그만큼 멈춘다.** 그래서 직렬 큐 하나 뒤에 둔다 —
/// 직렬인 이유는 색인 두 개가 같은 사이드카 파일에 동시에 쓰면 안 되기 때문이다.
///
/// ## 모델이 없으면 — 앱은 그대로 돈다
///
/// `#31` 과 같은 방식으로 **왜 못 하는지를 크게 한 번 말하고 물러난다.** 조용히 아무 일도
/// 안 하는 것과 다르다 — 그러면 다음 사람이 「자동 상호참조가 왜 안 되지」를 코드에서 찾는다.
/// ⚠ **띠로는 안 띄운다.** 모델 부재는 설치 상태이지 사용자가 지금 고칠 일이 아니고, 볼트를
/// 열 때마다 같은 띠가 뜨면 그건 알림이 아니라 소음이다. 세션당 한 번 stderr 로 낸다.
final class ContentGraph {

    /// 색인은 **한 줄로** 돈다. 병렬로 돌리면 같은 `.clonie/embeddings.json` 에 둘이 쓴다.
    private let queue = DispatchQueue(label: "com.local.ghostbar.content-index", qos: .utility)

    /// 볼트마다 하나. 설정창에서 다른 폴더를 연결하면 `rebind` 가 갈아끼운다.
    private var sidecarURL: URL
    /// 모델을 여는 것은 비싸다 — **한 번 열고 계속 쓴다.**
    private var indexer: ContentIndexer?
    private var openAttempted = false
    private var announcedMissing = false

    /// CoreML 호출은 중간 취소할 수 없다. 대신 이 수를 올려 옛 결과가 화면에 도착하는 것을 막는다.
    /// 색인 세대는 새 문서 스냅샷마다, 볼트 세대는 rebind마다 변한다.
    private let generationLock = NSLock()
    private var vaultGeneration: UInt64 = 0
    private var indexGeneration: UInt64 = 0

    private struct IndexGeneration {
        let vault: UInt64
        let index: UInt64
    }

    init(sidecarURL: URL) {
        self.sidecarURL = sidecarURL
    }

    /// 사용자가 다른 볼트를 연결했다. **색인기를 버린다** — 사이드카 경로가 그 안에 박혀 있다.
    /// 세대를 큐에 넣기 전에 올려, 이미 돌고 있는 옛 CoreML 결과도 전달 직전 버린다.
    func rebind(sidecarURL: URL) {
        let generation = advanceVaultGeneration()
        pendingLock.lock()
        pendingQuery = nil
        pendingDrafts.removeAll()
        pendingLock.unlock()
        queue.async {
            guard self.isCurrentVault(generation) else { return }
            self.sidecarURL = sidecarURL
            self.indexer = nil
            self.openAttempted = false
            self.announcedMissing = false
        }
    }

    /// 아직 안 실어 보낸 가장 새 질의. **낡은 것은 버리려고** 든다 (#34).
    private var pendingQuery: String?
    /// 칸마다 아직 안 실어 보낸 가장 새 초안 (#33). 키 = 화면이 정한 칸 이름(`edit`·`c0`…).
    private var pendingDrafts: [String: String] = [:]
    private let pendingLock = NSLock()

    /// 조각이 저장되거나 볼트를 새로 읽었을 때 부른다.
    ///
    /// - Parameter onNotice: 사람에게 보일 한 줄. **주 스레드에서** 불린다.
    ///   알릴 것이 없으면 아예 안 불린다 — 빈 띠를 띄우지 않는다.
    /// - Parameter onVectors: 화면이 라이브 검색에 쓸 **벡터 꾸러미** JSON (#34).
    ///   **주 스레드에서** 불린다. 색인이 성공했을 때만 온다 — 모델이 없으면 아예 안 불리고,
    ///   그때 화면은 bigram 으로 돈다(선언된 갈림).
    /// - Parameter onState: `indexing` · `ready` · `unavailable` · `error` 중 하나. 모든 전달은
    ///   현재 볼트·색인 세대인지 주 스레드에서도 다시 확인한다.
    func index(fragments: [Fragment],
               questions: [Question],
               onNotice: @escaping (String) -> Void,
               onVectors: @escaping (String) -> Void,
               onState: @escaping (String) -> Void = { _ in }) {
        // ★ 새 문서 스냅샷이 들어온 순간부터 이전 색인은 낡았다. 큐 앞에서 세대를 올려야
        // 이미 CoreML 안에 들어간 작업도 완료 콜백에서 걸러진다.
        let generation = advanceIndexGeneration()
        deliverIndex(generation, value: "indexing", callback: onState)
        queue.async {
            guard self.isCurrent(generation) else { return }

            guard let indexer = self.resolveIndexer() else {
                self.deliverIndex(generation, value: "unavailable", callback: onState)
                return
            }
            guard self.isCurrent(generation) else { return }

            do {
                let report = try indexer.reindex(fragments: fragments, questions: questions)
                guard self.isCurrent(generation) else { return }
                FileHandle.standardError.write(Data("[cue] \(report.summary)\n".utf8))
                // ★ 코사인·순위·색은 **화면에 산다** (#34, `tests/screen-load.mjs` 자물쇠).
                //   여기서 하는 것은 벡터를 글자로 만들어 건네는 것뿐이다.
                //   ⚠ 인코딩은 사이드카와 **같은 것**을 쓴다 — 두 벌이 되면 한쪽이 조용히 낡는다.
                if let json = Self.vectorPayload(dimensions: indexer.embedder.dimensions,
                                                 fragments: report.vectors,
                                                 passages: report.passageVectors,
                                                 questions: report.questionVectors) {
                    self.deliverIndex(generation, value: json, callback: onVectors)
                }
                self.deliverIndex(generation, value: "ready", callback: onState)
                // ⚠ **콜드 빌드에서는 안 알린다.** 처음 색인하는 볼트는 「전부 새 조각」이라
                //   쌓아둔 중복이 한꺼번에 쏟아진다 — 그건 알림이 아니라 벽이다.
                guard !report.coldBuild,
                      let line = ContentIndexer.duplicateNotice(report.duplicates,
                                                                fragments: fragments)
                else { return }
                self.deliverIndex(generation, value: line, callback: onNotice)
            } catch {
                // 색인이 실패해도 **저장은 이미 끝났다.** 사용자의 글은 안 잃는다 —
                // 잃는 것은 이번 판 그래프뿐이고, 다음 저장이 다시 만든다.
                FileHandle.standardError.write(Data("[cue] 색인 실패: \(error)\n".utf8))
                self.deliverIndex(generation, value: "error", callback: onState)
            }
        }
    }

    /// 면접 중 들린 질의 하나를 벡터로 (#34).
    ///
    /// ⚠ **색인과 같은 직렬 큐**를 쓴다. `TextEmbedder` 는 스레드 안전을 약속하지 않아서
    /// 큐를 나누면 두 스레드가 같은 CoreML 모델에 들어간다. 대가는 하나 — 콜드 색인이
    /// 도는 중이면 첫 질의가 그만큼(`실측`: 조각 50장 4.1초) 기다린다. 그 사이 화면은
    /// bigram 으로 돌고 있어서 **비어 있지 않다**.
    ///
    /// ⚠ **밀린 것은 버린다.** 말은 계속 자라는데 큐가 밀리면 낡은 질의의 벡터가 줄줄이
    /// 도착한다. 화면도 글자를 대조해 안 쓰지만(`scorer`), 안 만드는 편이 싸다.
    ///
    /// - Parameter completion: base64 벡터. **주 스레드에서** 불린다. 못 만들면 안 불린다.
    func embedQuery(_ text: String, completion: @escaping (String) -> Void) {
        let generation = currentVaultGeneration()
        pendingLock.lock(); pendingQuery = text; pendingLock.unlock()
        queue.async {
            self.pendingLock.lock()
            let newest = self.pendingQuery
            self.pendingLock.unlock()
            guard newest == text, self.isCurrentVault(generation) else { return }
            guard let indexer = self.resolveIndexer(),
                  self.isCurrentVault(generation),
                  let v = try? indexer.embedder.embed(query: text),
                  self.isCurrentVault(generation) else { return }
            let b64 = ContentIndexStore.encode(vector: v)
            self.deliverVault(generation, value: b64, callback: completion)
        }
    }

    /// 아직 저장 안 된 글자 하나를 벡터로 (#33, ADR 0003 §3-②).
    ///
    /// ★ **왜 이것이 따로 필요한가.** 화면이 든 벡터는 `receiveVectors` 가 실어 온 **저장된**
    /// 조각·질문의 것뿐이다(#34). 지금 편집기에서 치고 있는 초안과 방금 붙여넣은 자소서 문항은
    /// 아직 문서에 없어서 그 꾸러미에 안 들어 있고, 임베딩은 CoreML 이라 화면이 혼자 못 만든다.
    /// 그래서 **화면이 물어보는 통로**가 하나 필요했다 — 이 레포에서 JS→Swift 배열이 는 것은
    /// #17 이후 처음이고, 그 대가(빌드 없이 화면만 고치는 길이 이 기능에는 안 통한다)를 알고 늘렸다.
    ///
    /// ⚠ **코사인·순위는 여기서 안 낸다.** 돌려주는 것은 벡터뿐이고 고르는 것은 화면이다 —
    /// ADR 0003 §4 의 갈림 그대로이고 `embedQuery` 와 같은 모양이다.
    ///
    /// ⚠ **프리픽스가 둘이다.** 조각 초안은 `passage:`, 자소서 문항은 `query:` —
    /// 문항은 조각이 아니라 **물음**이라 물음↔물음 대칭 과제가 된다(모델카드 §FAQ).
    /// 여기가 갈리면 아무것도 안 터지고 제안만 조용히 나빠진다.
    ///
    /// ⚠ **칸마다 최신 하나만 산다.** 사람이 치는 동안 요청이 줄지어 오는데 낡은 것을 다 계산하면
    /// 큐가 밀린다. `embedQuery` 와 같은 규율이되 **칸(`slot`)별**이다 — 던져 넣기는 후보 여럿이
    /// 동시에 살아 있어서 하나로 두면 마지막 후보만 남는다.
    ///
    /// - Parameter completion: `(slot, text, base64)`. **주 스레드에서** 불린다. 못 만들면 안 불린다.
    func embedDraft(slot: String, kind: String, text: String,
                    completion: @escaping (String, String, String) -> Void) {
        let generation = currentVaultGeneration()
        pendingLock.lock(); pendingDrafts[slot] = text; pendingLock.unlock()
        queue.async {
            self.pendingLock.lock()
            let newest = self.pendingDrafts[slot]
            self.pendingLock.unlock()
            guard newest == text, self.isCurrentVault(generation) else { return }
            guard let indexer = self.resolveIndexer(), self.isCurrentVault(generation) else { return }
            let v: [Float]
            do {
                v = kind == "query" ? try indexer.embedder.embed(query: text)
                                    : try indexer.embedder.embed(passage: text)
            } catch {
                FileHandle.standardError.write(Data("[cue] 초안 임베딩 실패: \(error)\n".utf8))
                return
            }
            guard self.isCurrentVault(generation) else { return }
            let b64 = ContentIndexStore.encode(vector: v)
            self.deliverVault(generation) { completion(slot, text, b64) }
        }
    }

    private func advanceIndexGeneration() -> IndexGeneration {
        generationLock.lock()
        indexGeneration &+= 1
        let generation = IndexGeneration(vault: vaultGeneration, index: indexGeneration)
        generationLock.unlock()
        return generation
    }

    private func advanceVaultGeneration() -> UInt64 {
        generationLock.lock()
        vaultGeneration &+= 1
        indexGeneration &+= 1
        let generation = vaultGeneration
        generationLock.unlock()
        return generation
    }

    private func currentVaultGeneration() -> UInt64 {
        generationLock.lock()
        let generation = vaultGeneration
        generationLock.unlock()
        return generation
    }

    private func isCurrent(_ generation: IndexGeneration) -> Bool {
        generationLock.lock()
        let current = vaultGeneration == generation.vault && indexGeneration == generation.index
        generationLock.unlock()
        return current
    }

    private func isCurrentVault(_ generation: UInt64) -> Bool {
        generationLock.lock()
        let current = vaultGeneration == generation
        generationLock.unlock()
        return current
    }

    /// 큐에서 확인한 것만으로는 부족하다. 메인 큐에 이미 쌓인 콜백도 그 사이 볼트가 바뀌면
    /// 버려야 하므로, **전달 직전** 같은 세대를 한 번 더 확인한다.
    private func deliverIndex(_ generation: IndexGeneration,
                              value: String,
                              callback: @escaping (String) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isCurrent(generation) else { return }
            callback(value)
        }
    }

    private func deliverVault(_ generation: UInt64,
                              value: String,
                              callback: @escaping (String) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isCurrentVault(generation) else { return }
            callback(value)
        }
    }

    private func deliverVault(_ generation: UInt64,
                              callback: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isCurrentVault(generation) else { return }
            callback()
        }
    }

    /// 벡터 꾸러미를 화면이 먹는 모양으로. 실패하면 `nil` — **빈 꾸러미를 보내지 않는다**
    /// (화면이 그걸 「벡터가 있다」로 읽고 전부 빨강으로 매긴다).
    private static func vectorPayload(dimensions: Int,
                                      fragments: [String: [Float]],
                                      passages: [String: [ContentIndexer.PassageVector]],
                                      questions: [String: [[Float]]]) -> String? {
        guard !fragments.isEmpty || !passages.isEmpty || !questions.isEmpty else { return nil }
        let encodedPassages: [String: [[String: Any]]] = passages.mapValues { values in
            values.map { value in
                let p = value.passage
                return [
                    "id": p.id,
                    "range": ["startUTF16": p.startUTF16, "endUTF16": p.endUTF16],
                    "text": p.text,
                    "sourceText": p.sourceText,
                    "hash": p.hash,
                    "vectorBase64": ContentIndexStore.encode(vector: value.vector),
                ]
            }
        }
        let payload: [String: Any] = [
            "dimensions": dimensions,
            "fragments": fragments.mapValues { ContentIndexStore.encode(vector: $0) },
            "passages": encodedPassages,
            "questions": questions.mapValues { $0.map { ContentIndexStore.encode(vector: $0) } },
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// - Returns: 모델이 없거나 못 열면 `nil`. **매번 다시 열어보지 않는다** —
    ///   없는 모델을 저장할 때마다 찾으면 그 비용이 저장 경로에 그대로 붙는다.
    private func resolveIndexer() -> ContentIndexer? {
        if let i = indexer { return i }
        guard !openAttempted else { return nil }
        openAttempted = true
        switch ContentIndexer.open(sidecarURL: sidecarURL) {
        case .ready(let i):
            indexer = i
            return i
        case .unavailable(let status):
            announceOnce(status)
            return nil
        }
    }

    /// #31 과 같은 모양의 상자. **한 번만** 낸다.
    private func announceOnce(_ status: EmbeddingModelStore.Status) {
        guard !announcedMissing else { return }
        announcedMissing = true
        FileHandle.standardError.write(Data("""

            ┌──────────────────────────────────────────────────────────────────────┐
            │ ⚠ 내용 그래프가 **안 자란다** — 임베딩 모델이 없다 (#32).
            │   앱은 그대로 돈다. 안 도는 것은 유사 조각 상호참조와 중복 알림뿐이다.
            \(status.explanation.split(separator: "\n").map { "│   \($0)" }.joined(separator: "\n"))
            └──────────────────────────────────────────────────────────────────────┘

            """.utf8))
    }
}
