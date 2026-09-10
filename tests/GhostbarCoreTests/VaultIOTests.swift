import XCTest
@testable import GhostbarCore

/// 볼트 입출력이 **주 스레드를 떠나면서 잃으면 안 되는 것들** — QA 2026-08-30 블로커 F1.
///
/// ## 무엇이 있었나
///
/// `실측 2026-08-30`(고착 스택): 저장이 주 스레드에서 `AtomicFile.write` 의 `replaceItemAt`
/// 까지 내려갔고, 거기서 macOS 가 「문서 폴더 접근」을 묻자 **앱이 25분 멈췄다.**
///
/// ## 큐 뒤로 보내면서 **새로 생긴** 위험 셋 — 이 파일이 그 셋을 잰다
///
/// 1. **순서.** 주 스레드에서 하던 때는 저장이 부른 순서대로 앉는 것이 공짜였다.
/// 2. **종료.** ⌘Q 가 마지막 저장을 앞지를 수 있게 됐다.
/// 3. **침묵.** 실패가 `stderr` 로만 나가면 사용자는 안 저장된 줄 모른다.
final class VaultIOTests: XCTestCase {

    private func tempVault() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vaultio-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            // 권한을 뺏어 둔 폴더가 있을 수 있다 — 되돌려 놓고 지운다.
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private let t = Date(timeIntervalSince1970: 1_700_000_000)

    private func doc(_ title: String) -> CueDocument {
        CueDocument(questions: [],
                    fragments: [Fragment(id: "f-1", title: title, body: "본문",
                                         questionIds: [], createdAt: t, updatedAt: t)])
    }

    /// 콜백을 **주 큐가 아닌 곳**에서 받는다 — XCTest 가 주 스레드를 막고 있어서,
    /// 기본값(`.main`)으로 두면 이 파일의 기다림이 통째로 교착한다.
    private func makeIO(_ vault: URL, slowAfter: TimeInterval = 60) -> VaultIO {
        VaultIO(store: VaultStore(vaultURL: vault),
                callbackQueue: DispatchQueue(label: "vaultio.test.cb"),
                slowAfter: slowAfter)
    }

    // MARK: - 1. 주 스레드를 안 잡는다

    func testWorkDoesNotRunOnTheCallingThread() throws {
        let io = makeIO(try tempVault())
        let onCallingThread = UnfairBox(false)
        let calling = Thread.current
        let done = expectation(description: "saved")
        io.save(doc("가")) { _ in
            onCallingThread.set(Thread.current == calling)
            done.fulfill()
        }
        // ⚠ 이 단언이 이 티켓의 알맹이다 — 부른 자리가 **바로 안 막힌다**.
        wait(for: [done], timeout: 5)
        XCTAssertFalse(onCallingThread.get(), "콜백이 부른 스레드에서 왔다 — 동기로 돌았다는 뜻이다")
    }

    // MARK: - 2. 순서

    func testSavesLandInTheOrderTheyWereAsked() throws {
        let vault = try tempVault()
        let io = makeIO(vault)
        let last = expectation(description: "last save")
        let titles = (0..<12).map { "제목 \($0)" }
        for (i, title) in titles.enumerated() {
            io.save(doc(title)) { _ in if i == titles.count - 1 { last.fulfill() } }
        }
        wait(for: [last], timeout: 10)
        // 마지막으로 부른 것이 디스크에 앉아 있어야 한다. 병렬이면 이게 스케줄러 몫이 된다.
        let back = try VaultStore(vaultURL: vault).load().document
        XCTAssertEqual(back.fragments.first?.title, titles.last)
    }

    func testReadSeesWritesQueuedBeforeIt() throws {
        let vault = try tempVault()
        let io = makeIO(vault)
        let read = expectation(description: "read")
        io.save(doc("먼저 쓴 것"))
        // ⚠ 저장이 끝나기를 **안 기다리고** 바로 읽는다 — 같은 직렬 큐라 순서가 지켜져야 한다.
        io.load { result in
            XCTAssertEqual(result?.document.fragments.first?.title, "먼저 쓴 것")
            read.fulfill()
        }
        wait(for: [read], timeout: 10)
    }

    // MARK: - 3. 종료 플러시

    func testFlushWaitsForQueuedWrites() throws {
        let vault = try tempVault()
        let io = makeIO(vault)
        for i in 0..<8 { io.save(doc("제목 \(i)")) }
        // ⌘Q 가 여기서 온다. 플러시가 없으면 마지막 저장이 통째로 사라진다.
        XCTAssertTrue(io.flush(timeout: 10), "밀린 저장을 못 비웠다")
        let back = try VaultStore(vaultURL: vault).load().document
        XCTAssertEqual(back.fragments.first?.title, "제목 7")
    }

    /// ⚠ **무한정 기다리지 않는다.** 권한 창에 걸린 쓰기는 안 끝나고, 그걸 기다리면
    /// **멈춘 앱을 못 끄게 된다** — 그게 이 블로커가 만든 상태 그대로다.
    func testFlushGivesUpInsteadOfHangingForever() throws {
        let io = makeIO(try tempVault())
        let gate = DispatchSemaphore(value: 0)
        // ★ **입출력 큐를 직접 막는다** — 권한 창에 걸린 `replaceItemAt` 의 대역이다.
        //   ⚠ 콜백 큐를 막는 것으로는 이게 안 된다(첫 판이 그래서 통과해 버렸다).
        io.queue.async { _ = gate.wait(timeout: .now() + 5) }
        io.save(doc("못 앉는 것"))
        let began = Date()
        XCTAssertFalse(io.flush(timeout: 0.4), "안 끝났는데 끝났다고 했다")
        XCTAssertLessThan(Date().timeIntervalSince(began), 2.0,
                          "시간이 지나도 안 돌아왔다 — 멈춘 앱을 못 끄게 된다")
        gate.signal()
    }

    // MARK: - 4. 침묵하지 않는다

    func testPermissionDeniedIsClassifiedAndReported() throws {
        let vault = try tempVault()
        let io = makeIO(vault)
        // 첫 저장으로 폴더 모양을 만들어 둔다 (사이드카까지).
        XCTAssertTrue({ io.save(doc("먼저")); return io.flush(timeout: 10) }())

        // **쓰기 권한을 뺏는다** — 권한 창을 안 띄우고 같은 실패를 만드는 자리.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: vault.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                       ofItemAtPath: vault.path) }

        let told = expectation(description: "화면에 말했다")
        let seen = UnfairBox<VaultIO.Trouble?>(nil)
        io.save(doc("못 쓸 것")) { trouble in
            guard trouble != .slow else { return }
            seen.set(trouble); told.fulfill()
        } completion: { error in
            XCTAssertNotNil(error, "못 썼는데 성공으로 돌아왔다")
        }
        wait(for: [told], timeout: 10)
        XCTAssertEqual(seen.get(), .denied, "권한 실패가 그 밖의 실패와 안 갈렸다")
        XCTAssertTrue(seen.get()!.message.contains("권한"), "사람이 읽을 한 줄이 이유를 안 든다")
    }

    /// ★ **끝나기 전에** 말한다. 이 시험이 겨누는 것이 QA 가 본 그 25분이다 —
    /// 그때 앱은 멈춘 채로 **아무 말도 안 했다**.
    func testSlowWorkAnnouncesItselfBeforeItFinishes() throws {
        let io = VaultIO(store: VaultStore(vaultURL: try tempVault()),
                         callbackQueue: DispatchQueue(label: "vaultio.test.slow"),
                         slowAfter: 0.05)
        let gate = DispatchSemaphore(value: 0)
        io.queue.async { _ = gate.wait(timeout: .now() + 5) }   // 권한 창에 걸린 상태

        let said = expectation(description: "대기를 말했다")
        said.assertForOverFulfill = false
        let finished = UnfairBox(false)
        io.save(doc("느린 것")) { trouble in
            if trouble == .slow {
                XCTAssertFalse(finished.get(), "끝난 **뒤에** 말하면 아무 소용이 없다")
                said.fulfill()
            }
        } completion: { _ in finished.set(true) }
        wait(for: [said], timeout: 5)
        XCTAssertFalse(finished.get(), "아직 안 끝났는데도 말했어야 한다")
        gate.signal()

        XCTAssertTrue(VaultIO.Trouble.slow.message.contains("권한"),
                      "대기 안내가 「무엇을 눌러야 하나」를 안 든다")
    }

    func testSuccessDoesNotAnnounceTrouble() throws {
        let io = makeIO(try tempVault(), slowAfter: 5)
        let done = expectation(description: "saved")
        let troubles = UnfairBox(0)
        io.save(doc("잘 된 것")) { _ in troubles.set(troubles.get() + 1) } completion: { error in
            XCTAssertNil(error); done.fulfill()
        }
        wait(for: [done], timeout: 10)
        XCTAssertEqual(troubles.get(), 0, "잘 된 저장이 띠를 띄우면 그건 알림이 아니라 소음이다")
    }

    // MARK: - 리비전 저장과 충돌 전달 (#84 P1)

    func testVersionedLoadAndSaveReturnTheNextRevisionOffTheCallingThread() throws {
        let vault = try tempVault()
        let io = makeIO(vault)
        let loadedBox = UnfairBox<VersionedLoadResult?>(nil)
        let loaded = expectation(description: "versioned load")
        io.loadVersioned { result in loadedBox.set(result); loaded.fulfill() }
        wait(for: [loaded], timeout: 5)

        let session = try XCTUnwrap(loadedBox.get())
        let savedBox = UnfairBox<VaultSaveResult?>(nil)
        let saved = expectation(description: "conditional save")
        io.save(doc("조건부"), expecting: session.revision, completion: { result in
            if case .success(let value) = result { savedBox.set(value) }
            saved.fulfill()
        })
        wait(for: [saved], timeout: 5)

        XCTAssertEqual(savedBox.get()?.paths["f-1"], "조건부.md")
        XCTAssertNotEqual(savedBox.get()?.revision, session.revision)
    }

    func testVersionedSaveClassifiesConflictAndReturnsRecoverableError() throws {
        let vault = try tempVault()
        let path = vault.appendingPathComponent("공동.md")
        try "---\nid: f-1\ntitle: 공동\n---\n처음\n"
            .write(to: path, atomically: true, encoding: .utf8)
        let io = makeIO(vault)
        let loadedBox = UnfairBox<VersionedLoadResult?>(nil)
        let loaded = expectation(description: "loaded")
        io.loadVersioned { result in loadedBox.set(result); loaded.fulfill() }
        wait(for: [loaded], timeout: 5)
        let session = try XCTUnwrap(loadedBox.get())
        var attempted = session.result.document
        attempted.fragments[0].body = "앱 편집"
        try "---\nid: f-1\ntitle: 공동\n---\n외부 편집\n"
            .write(to: path, atomically: true, encoding: .utf8)

        let troubleBox = UnfairBox<VaultIO.Trouble?>(nil)
        let errorBox = UnfairBox<VaultConflictError?>(nil)
        let done = expectation(description: "conflict")
        io.save(attempted, expecting: session.revision, onTrouble: { trouble in
            troubleBox.set(trouble)
        }) { result in
            if case .failure(let error) = result { errorBox.set(error as? VaultConflictError) }
            done.fulfill()
        }
        wait(for: [done], timeout: 5)

        guard case .conflict(let conflict)? = troubleBox.get() else {
            return XCTFail("충돌이 구조화된 Trouble로 전달되지 않았다")
        }
        XCTAssertEqual(conflict, errorBox.get())
        XCTAssertEqual(conflict.attemptedDocument.fragments[0].body, "앱 편집")
        XCTAssertTrue(try String(contentsOf: path, encoding: .utf8).contains("외부 편집"))
    }

    // MARK: - 씨앗 (#74 A — 새 볼트에 앱 파일을 안 심는다)

    /// **빈 볼트를 열어도 질문 사이드카가 안 생긴다.**
    ///
    /// ⚠ 씨앗 질문을 심는 것은 **화면(JS)** 이었다 (`ChatHTML.swift` 의 `STD`·`seed()` →
    /// `saveDocument`). Swift 쪽엔 그 목록이 원래 없다 — 이 시험이 잠그는 것은
    /// **읽기가 스스로 파일을 만들지 않는다**는 쪽이다. 화면이 씨앗을 그만 심으면
    /// (#74 A) 새 볼트의 `.clonie/` 에 남는 것이 없어야 하고, 그 판정을 여기서 잰다.
    /// 이게 깨지면 남의 볼트를 **열어보기만 해도** 앱 파일이 앉는다.
    func testOpeningAFreshVaultCreatesNoQuestionSidecar() throws {
        let vault = try tempVault()
        let io = makeIO(vault)
        let done = expectation(description: "loaded")
        io.load { _ in } completion: { result in
            XCTAssertEqual(result?.document.questions.count, 0, "Swift 가 질문을 심었다")
            XCTAssertEqual(result?.document.fragments.count, 0)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        XCTAssertFalse(FileManager.default.fileExists(atPath: io.store.documentJSONURL.path),
                       "빈 볼트를 열기만 했는데 \(io.store.documentJSONURL.lastPathComponent) 이 생겼다")
    }

    // MARK: - 화면으로 가는 짐 (#79 — 입력 기록이 같이 실린다)

    /// ⚠ 짐은 `CueDocument` 가 **아니라** `DocumentPayload` 다 — 문서에 칸을 더해도 여기 안 실린다.
    /// 안 실리면 화면은 기록을 못 보고, 화면이 못 본 기록은 다음 저장에 **덮여 사라진다.**
    func testPayloadCarriesAsked() throws {
        let doc = CueDocument(asked: [AskedEntry(id: "a-1", text: "왜 우리 회사인가",
                                                 source: .sun, at: t, color: "g")])
        let json = VaultIO.documentPayloadJSON(LoadResult(document: doc))
        XCTAssertTrue(json?.contains("\"asked\"") == true, json ?? "nil")
        XCTAssertTrue(json?.contains("왜 우리 회사인가") == true, json ?? "nil")
    }

    /// `nil` 은 화면에 **빈 배열**로 간다 — 화면은 옵셔널을 몰라도 된다.
    func testPayloadTurnsMissingAskedIntoEmptyArray() throws {
        let json = VaultIO.documentPayloadJSON(LoadResult(document: CueDocument()))
        XCTAssertTrue(json?.contains("\"asked\"") == true, json ?? "nil")
    }

    // MARK: - 실패 판정

    func testPermissionErrorShapesAreAllRecognised() {
        // ⚠ 코드로만 본다 — 글자로 가르면 시스템 언어가 바뀌는 순간 죽는다.
        for code in [NSFileWriteNoPermissionError, NSFileReadNoPermissionError,
                     NSFileWriteVolumeReadOnlyError] {
            XCTAssertTrue(VaultIO.isPermissionDenied(
                NSError(domain: NSCocoaErrorDomain, code: code)), "\(code)")
        }
        XCTAssertTrue(VaultIO.isPermissionDenied(
            NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))))
        // 진짜 이유가 `underlying` 에 숨는 경우 (`replaceItemAt` 이 그렇다)
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError,
                              userInfo: [NSUnderlyingErrorKey:
                                NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))])
        XCTAssertTrue(VaultIO.isPermissionDenied(wrapped))

        // 양성 대조의 반대쪽 — 아무 오류나 권한으로 읽으면 안내가 거짓말이 된다
        XCTAssertFalse(VaultIO.isPermissionDenied(
            NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)))
        XCTAssertEqual(VaultIO.trouble(for: NSError(domain: NSCocoaErrorDomain,
                                                    code: NSFileNoSuchFileError)),
                       .failed(NSError(domain: NSCocoaErrorDomain,
                                       code: NSFileNoSuchFileError).localizedDescription))
    }
}

/// 여러 스레드가 하나를 들여다보는 자리를 위한 아주 작은 상자.
/// (시험 안에서만 산다 — 제품 코드는 큐 하나로 도느라 이런 것이 필요 없다.)
private final class UnfairBox<T>: @unchecked Sendable {
    private var value: T
    private let lock = NSLock()
    init(_ v: T) { value = v }
    func get() -> T { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ v: T) { lock.lock(); value = v; lock.unlock() }
}
