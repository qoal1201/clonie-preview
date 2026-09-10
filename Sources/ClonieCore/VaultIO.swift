import Foundation

/// ★ **볼트를 주 스레드에서 떼는 자리** (QA 2026-08-30 블로커 F1).
///
/// ## 무엇이 있었나
///
/// `실측 2026-08-30`(고착 스택 `clonie-sample*.txt`): 화면의 저장이
/// `saveDocument` → `VaultStore.save` → `AtomicFile.write` 의 `replaceItemAt` 까지
/// **주 스레드에서 그대로 내려갔다.** 그 자리에서 macOS 가 「문서 폴더 접근」 권한을 묻는데,
/// 사람이 그 창을 안 누르면 `replaceItemAt` 이 안 돌아온다 — **앱이 25분 멈춰 있었다.**
/// 재기동하면 이번엔 `sendDocument` → `VaultStore.load` 의 `open()` 이 같은 모양으로 굳었다.
/// 그동안 화면은 아무 말도 안 했다. 실패가 `stderr` 로만 나갔기 때문이다.
///
/// ## 그래서 이것이 지키는 셋
///
/// - **주 스레드에 파일 접근이 없다.** 읽기도 쓰기도 큐 뒤에 산다.
/// - **순서가 보장된다.** 큐가 **직렬**이다 — 저장 두 개가 겹치면 나중 것이 이겨야 하는데,
///   병렬로 두면 어느 쪽이 마지막으로 디스크에 앉는지가 스케줄러 몫이 된다.
///   (`ContentGraph` 가 색인을 직렬 큐 뒤에 둔 것과 같은 규율 — #32.)
/// - **끝나면 말한다.** 성공·실패·「오래 걸린다」가 전부 콜백으로 나가고, 부르는 쪽이 그것을
///   화면에 띄운다. 조용히 실패하는 길이 여기 없다.
///
/// ## 종료
///
/// `flush(timeout:)` 이 **밀린 저장이 디스크에 앉을 때까지** 기다린다. 이게 없으면
/// ⌘Q 가 마지막 저장을 통째로 버린다 — 주 스레드에서 하던 때는 공짜로 얻던 성질이다.
/// ⚠ **무한정 기다리지 않는다.** 권한 창에 걸린 쓰기는 안 돌아오고, 그걸 기다리면
/// 종료가 그 자리에서 다시 굳는다 — 멈춘 앱을 못 끄게 되는 것이 제일 나쁘다.
///
/// ⚠ **AppKit 을 안 든다** — 이식 경계(ADR 0003). `VaultWatcher` 가 `Dispatch` 를 쓰는 것과
/// 같은 자리이고, 앱 층에 두지 않은 이유는 하나 더 있다: **executable 은 `swift test` 가
/// 못 부른다**(Package.swift 의 그 주석). 순서 보장과 종료 플러시는 시험으로 잠가야 한다.
public final class VaultIO {

    /// 볼트에서 일어난 일 — 화면에 그대로 옮길 수 있는 모양.
    public enum Trouble: Equatable, Sendable {
        /// 아직 안 끝났다. 권한 창이 떠 있을 때가 대부분이다.
        case slow
        /// 못 썼다/못 읽었다. **권한이 거부된 경우**를 따로 든다 — 사람이 할 일이 다르다.
        case denied
        /// 읽은 뒤 같은 파일이 외부에서 달라졌다. 오류 안에 양쪽 내용과 충돌 사본 자리가 있다.
        case conflict(VaultConflictError)
        /// 그 밖의 실패. 딸린 글자는 시스템이 준 설명이다.
        case failed(String)

        /// 사람에게 보일 한 줄. **여기 한 곳에만 산다** — 두 곳에 두면 한쪽이 낡는다.
        public var message: String {
            switch self {
            case .slow:
                return "볼트에 쓰는 중이다 — 폴더 접근 권한 창이 떠 있으면 그것부터 눌러라. "
                     + "허용할 때까지 조각이 디스크에 안 앉는다"
            case .denied:
                return "볼트 폴더에 접근할 권한이 없다 — 조각이 저장되지 않았다. "
                     + "권한을 허용하거나 쓸 수 있는 다른 폴더를 볼트로 골라라"
            case .conflict(let conflict):
                return conflict.localizedDescription
            case .failed(let why):
                return "볼트에 저장하지 못했다 — \(why)"
            }
        }
    }

    /// 이 오류가 **권한 문제인가.** 되돌아오는 모양이 여럿이라 한 곳에서 판정한다.
    ///
    /// ⚠ 코드로만 본다. 글자(`localizedDescription`)로 가르면 시스템 언어가 바뀌는 순간 죽는다.
    public static func isPermissionDenied(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain {
            switch ns.code {
            case NSFileReadNoPermissionError, NSFileWriteNoPermissionError,
                 NSFileWriteVolumeReadOnlyError:
                return true
            default: break
            }
            // 진짜 이유가 `underlying` 에 숨어 있는 경우가 있다 (`replaceItemAt` 이 그렇다).
            if let under = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
                return isPermissionDenied(under)
            }
        }
        if ns.domain == NSPOSIXErrorDomain {
            return ns.code == Int(EACCES) || ns.code == Int(EPERM)
        }
        return false
    }

    /// 실패 하나를 화면이 먹는 모양으로. **판정은 여기 하나**다.
    public static func trouble(for error: Error) -> Trouble {
        if let conflict = error as? VaultConflictError { return .conflict(conflict) }
        return isPermissionDenied(error) ? .denied : .failed((error as NSError).localizedDescription)
    }

    /// **한 줄로** 돈다. 직렬인 이유 = 저장 순서. 위 머리글 참고.
    ///
    /// ⚠ `private` 이 아니라 **`internal`** 인 이유가 하나뿐이다: 시험이 이 큐를 막아
    /// 「권한 창에 걸린 쓰기」를 흉내낸다(`VaultIOTests`). 그 자리를 못 막으면 대기 안내와
    /// 플러시 시간제한이 **재는 척만 하고 늘 초록**이 된다 — 콜백 큐를 막는 것으로는
    /// 이 큐가 안 멈춘다(실측: 그렇게 짠 첫 판이 통과해 버렸다).
    let queue = DispatchQueue(label: "com.local.clonie.vault-io", qos: .userInitiated)
    /// 콜백이 앉을 자리. 화면을 만지는 쪽이라 기본은 주 큐다 (시험은 갈아끼운다).
    private let callbackQueue: DispatchQueue
    /// 이만큼 넘게 걸리면 「오래 걸린다」를 먼저 낸다.
    private let slowAfter: TimeInterval

    public let store: VaultStore
    private let requireExistingRoot: Bool

    /// - Parameters:
    ///   - slowAfter: 이 시간을 넘기면 `onTrouble(.slow)` 이 **먼저** 나간다. 권한 창에 걸린
    ///     사용자가 그 사이 아무 말도 못 듣는 것을 막는 자리다.
    public init(store: VaultStore,
                callbackQueue: DispatchQueue = .main,
                slowAfter: TimeInterval = 1.5,
                requireExistingRoot: Bool = false) {
        self.store = store
        self.requireExistingRoot = requireExistingRoot
        self.callbackQueue = callbackQueue
        self.slowAfter = slowAfter
    }

    public var vaultURL: URL { store.vaultURL }
    public var sidecarURL: URL { store.sidecarURL }

    /// 파일 정리도 문서 저장과 같은 큐를 통과한다. 읽기·미리보기·변경의 순서를 지킨다.
    public func perform<Value>(_ operation: @escaping (VaultStore) throws -> Value,
                               onTrouble: ((Trouble) -> Void)? = nil,
                               completion: @escaping (Result<Value, Error>) -> Void) {
        let slow = armSlowTimer(onTrouble)
        queue.async { [store, callbackQueue, requireExistingRoot] in
            let result = Result {
                try Self.checkRoot(store.vaultURL, required: requireExistingRoot)
                return try operation(store)
            }
            slow.cancel()
            callbackQueue.async {
                if case .failure(let error) = result { onTrouble?(Self.trouble(for: error)) }
                completion(result)
            }
        }
    }

    // MARK: - 화면으로 가는 짐 (#74 A)

    /// 화면이 `receiveDocument` 로 받는 그 짐.
    ///
    /// ⚠ **`CueDocument` 를 그대로 안 보낸다** — 문서는 디스크의 모양이고 `paths` 는
    /// 디스크에 없다(파생값이라 md 에 안 쓴다). 문서에 칸을 더하면 그 칸이 저장 왕복을 타고
    /// 파일로 내려간다. 그래서 **나갈 때만 입는 옷**을 따로 둔다.
    ///
    /// ⚠ 칸 이름 넷(`schemaVersion`·`questions`·`fragments`·`asked`)은 `CueDocument` 와 **글자까지 같다**
    /// — 화면이 지금 읽는 이름이고, 여기서 바꾸면 조각이 조용히 사라진다.
    public struct DocumentPayload: Encodable {
        public var schemaVersion: Int
        public var questions: [Question]
        public var fragments: [Fragment]
        /// 조각 id → 볼트 상대경로. 비어 있으면 화면이 전부 미분류 항성으로 그린다 (#74 B).
        public var paths: [String: String]
        /// 입력 기록 (#79). ⚠ **옵셔널이 아니다** — 문서에서는 `nil` 이 「안 건드린다」지만
        /// 나가는 짐에는 그 뜻이 없다. 화면은 옵셔널을 모르고 빈 배열만 안다.
        public var asked: [AskedEntry]
    }

    /// 읽은 결과를 화면의 짐 JSON 으로. **순수 함수다** — 디스크도 화면도 안 만진다.
    ///
    /// ⚠ `WKWebViewWrapper` 가 아니라 여기 사는 이유: executable 타깃은 `swift test` 가
    /// 못 부른다(`Package.swift` 그 주석). 잴 수 있는 자리에 둬야 `paths` 가 빠진 것을
    /// 시험이 잡는다 — 빠져도 화면은 안 깨지고 **별이 전부 미분류로 몰릴 뿐**이라,
    /// 사람 눈으로는 회귀가 안 보인다.
    ///
    /// - Returns: 인코딩이 실패하면 `nil`. 부르는 쪽은 아무것도 안 보낸다.
    public static func documentPayloadJSON(_ loaded: LoadResult) -> String? {
        let payload = DocumentPayload(schemaVersion: loaded.document.schemaVersion,
                                      questions: loaded.document.questions,
                                      fragments: loaded.document.fragments,
                                      paths: loaded.paths,
                                      asked: loaded.document.asked ?? [])
        guard let data = try? FragmentStore.makeEncoder().encode(payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - 읽기

    /// 볼트를 읽는다. **주 스레드를 안 잡는다.**
    ///
    /// - Parameter completion: `callbackQueue` 에서 불린다. 못 읽었으면 `nil` 과 함께
    ///   `onTrouble` 이 **먼저** 불린다 — 부르는 쪽은 빈 문서로 물러설 수 있다.
    public func load(onTrouble: ((Trouble) -> Void)? = nil,
                     completion: @escaping (LoadResult?) -> Void) {
        let slow = armSlowTimer(onTrouble)
        queue.async { [store, callbackQueue, requireExistingRoot] in
            let result = Result {
                try Self.checkRoot(store.vaultURL, required: requireExistingRoot)
                return try store.load()
            }
            slow.cancel()
            callbackQueue.async {
                switch result {
                case .success(let r): completion(r)
                case .failure(let e):
                    onTrouble?(Self.trouble(for: e))
                    completion(nil)
                }
            }
        }
    }

    /// 문서와 조건부 저장 기준선을 같은 직렬 큐에서 읽는다.
    public func loadVersioned(onTrouble: ((Trouble) -> Void)? = nil,
                              completion: @escaping (VersionedLoadResult?) -> Void) {
        let slow = armSlowTimer(onTrouble)
        queue.async { [store, callbackQueue, requireExistingRoot] in
            let result = Result {
                try Self.checkRoot(store.vaultURL, required: requireExistingRoot)
                return try store.loadVersioned()
            }
            slow.cancel()
            callbackQueue.async {
                switch result {
                case .success(let loaded): completion(loaded)
                case .failure(let error):
                    onTrouble?(Self.trouble(for: error))
                    completion(nil)
                }
            }
        }
    }

    // MARK: - 쓰기

    /// 문서를 저장한다. **주 스레드를 안 잡고, 부른 순서대로 앉는다.**
    ///
    /// - Parameter completion: `callbackQueue` 에서 불린다. 성공이면 `nil`.
    ///   실패는 `onTrouble` 로도 같이 나간다 (화면 띠가 그것을 먹는다).
    public func save(_ document: CueDocument,
                     onTrouble: ((Trouble) -> Void)? = nil,
                     completion: ((Error?) -> Void)? = nil) {
        let slow = armSlowTimer(onTrouble)
        queue.async { [store, callbackQueue, requireExistingRoot] in
            let result = Result {
                try Self.checkRoot(store.vaultURL, required: requireExistingRoot)
                return try store.save(document)
            }
            slow.cancel()
            callbackQueue.async {
                switch result {
                case .success:
                    completion?(nil)
                case .failure(let e):
                    onTrouble?(Self.trouble(for: e))
                    completion?(e)
                }
            }
        }
    }

    /// 읽을 때 받은 기준선과 일치하는 파일만 저장한다. 충돌을 문자열로 뭉개지 않고
    /// `Result.failure(VaultConflictError)`와 `Trouble.conflict` 양쪽으로 전달한다.
    public func save(_ document: CueDocument, expecting revision: VaultRevision,
                     newPaths: [String: String] = [:],
                     onTrouble: ((Trouble) -> Void)? = nil,
                     completion: ((Result<VaultSaveResult, Error>) -> Void)? = nil) {
        let slow = armSlowTimer(onTrouble)
        queue.async { [store, callbackQueue, requireExistingRoot] in
            let result = Result {
                try Self.checkRoot(store.vaultURL, required: requireExistingRoot)
                return try store.save(document, expecting: revision, newPaths: newPaths)
            }
            slow.cancel()
            callbackQueue.async {
                if case .failure(let error) = result {
                    onTrouble?(Self.trouble(for: error))
                }
                completion?(result)
            }
        }
    }

    private static func checkRoot(_ url: URL, required: Bool) throws {
        guard required else { return }
        do {
            guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)
            }
        } catch {
            if isPermissionDenied(error) { throw error }
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError,
                          userInfo: [NSLocalizedDescriptionKey: "연결한 폴더를 찾을 수 없다. 폴더를 다시 연결해 주세요.",
                                     NSUnderlyingErrorKey: error])
        }
    }

    // MARK: - 종료

    /// 밀린 일이 끝날 때까지 기다린다. 종료 직전에 부른다.
    ///
    /// - Returns: 다 비웠으면 `true`. 시간 안에 못 비웠으면 `false` — 그때도 **돌아온다**
    ///   (권한 창에 걸린 쓰기는 안 끝나고, 그걸 기다리면 앱을 못 끈다).
    @discardableResult
    public func flush(timeout: TimeInterval = 3.0) -> Bool {
        let done = DispatchSemaphore(value: 0)
        queue.async { done.signal() }      // 직렬이라 이게 통과하면 앞의 것은 전부 끝났다
        return done.wait(timeout: .now() + timeout) == .success
    }

    // MARK: -

    /// 「오래 걸린다」를 예약한다. 일이 제때 끝나면 `cancel()` 이 그것을 취소한다.
    private func armSlowTimer(_ onTrouble: ((Trouble) -> Void)?) -> DispatchWorkItem {
        let item = DispatchWorkItem { onTrouble?(.slow) }
        guard onTrouble != nil else { return item }   // 들을 사람이 없으면 예약도 안 한다
        callbackQueue.asyncAfter(deadline: .now() + slowAfter, execute: item)
        return item
    }
}
