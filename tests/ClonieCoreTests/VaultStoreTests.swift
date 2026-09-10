import XCTest
@testable import ClonieCore

/// 볼트가 **폴더 하나**로 도는가 (ADR 0003 §1·2). 밖에서 보이는 것만 잰다 —
/// 파일 이름 규칙 같은 내부는 안 잠근다.
final class VaultStoreTests: XCTestCase {
    private var dir: URL!
    private var store: VaultStore!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("clonie-vault-\(UUID().uuidString)", isDirectory: true)
        // 폴더를 미리 만든다 — 「이미 있는 볼트를 연결한다」가 이 레포의 기본 동선이다.
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store = VaultStore(vaultURL: dir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func sample() -> CueDocument {
        let t = Date(timeIntervalSince1970: 1_756_000_000)
        return CueDocument(
            questions: [Question(id: "q-1", text: "주도적으로 문제를 해결한 경험"),
                        Question(id: "q-2", text: "실패했던 경험과 거기서 배운 것", variants: ["말투 변형"])],
            fragments: [Fragment(id: "f-1", title: "배포 스크립트를 갈아엎었다",
                                 body: "매번 손으로 하던 것을 한 줄로 줄였다.",
                                 questionIds: ["q-1"], createdAt: t, updatedAt: t)])
    }

    private func mdFiles() throws -> [String] { try store.markdownRelativePaths() }

    // MARK: - 왕복

    func testSaveThenLoadReturnsSameDocument() throws {
        let doc = sample()
        try store.save(doc)
        let back = try store.load()
        XCTAssertNil(back.quarantined)
        // ⚠ `asked` 한 칸만 갈린다 — 저장이 보낸 `nil` 은 「기록을 안 건드린다」이고, 읽기는 **언제나**
        //   기록을 채운다(파일이 없으면 빈 것). 그 한 칸을 맞춰 놓고 나머지 전부를 잰다 (#79).
        var expected = doc
        expected.asked = []
        XCTAssertEqual(back.document, expected)
    }

    func testFragmentBecomesOneMarkdownFile() throws {
        try store.save(sample())
        XCTAssertEqual(try mdFiles(), ["배포 스크립트를 갈아엎었다.md"],
                       "조각 1장 = md 1장이 ADR 0003 §1 이다")
        let text = try String(contentsOf: dir.appendingPathComponent("배포 스크립트를 갈아엎었다.md"),
                              encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("---\n"))
        XCTAssertTrue(text.contains("매번 손으로 하던 것을 한 줄로 줄였다."))
    }

    /// 질문은 사이드카에 산다 — 사용자 볼트에 앱 전용 md 가 생기면 안 된다.
    func testQuestionsLiveInTheSidecarNotInTheVault() throws {
        try store.save(sample())
        let files = try mdFiles()
        XCTAssertEqual(files.count, 1, "질문이 md 로 새어 나왔다: \(files)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.documentJSONURL.path))
        XCTAssertEqual(try store.load().document.questions[1].variants, ["말투 변형"],
                       "옵셔널 필드가 사이드카를 못 건넜다")
    }

    func testLoadOfEmptyFolderIsEmptyDocument() throws {
        let r = try store.load()
        // 빈 볼트에도 기록 칸은 **채워져서** 온다 — 빈 배열이다 (#79). `.empty` 는 `nil` 이라 그 한 칸만 다르다.
        XCTAssertEqual(r.document, CueDocument(asked: []))
        XCTAssertNil(r.quarantined)
    }

    /// 둘째 문(ADR 0007)의 전제 — 조각만 더한 저장이 `.clonie/document.json` 을 다시 쓰면
    /// 앱과 MCP 가 그 파일을 두고 마지막-쓴-쪽이 이기는 경주를 한다. 질문이 안 바뀌었으면 안 건드린다.
    func testSaveLeavesDocumentJSONAloneWhenQuestionsUnchanged() throws {
        var doc = sample()
        try store.save(doc)
        _ = try store.load()
        try Data("  ".utf8).write(to: store.documentJSONURL)   // 내용을 일부러 비틀어 둔다
        doc.fragments.append(Fragment(id: "f-2", title: "둘째", body: "본문", questionIds: [],
                                      createdAt: Date(), updatedAt: Date()))
        try store.save(doc)
        XCTAssertEqual(try Data(contentsOf: store.documentJSONURL), Data("  ".utf8),
                       "질문이 그대로인데 document.json 이 다시 쓰였다")
    }

    /// S4 — 격리는 「읽은 것이 없다」다. 격리했는데 `lastHead` 를 채우면, 그다음 저장이
    /// (질문이 빈 문서 그대로라) 「안 바뀌었다」로 읽혀 `document.json` 을 영영 다시 안 만든다.
    func testQuarantinedDocumentJSONIsRecreatedByTheNextSave() throws {
        _ = try store.load()   // 첫 열기 — 사이드카 폴더를 만든다
        try Data(#"{"schemaVersion":"x"#.utf8).write(to: store.documentJSONURL)   // 깨진 JSON
        let loaded = try store.load()
        XCTAssertNotNil(loaded.quarantined, "이 시험의 전제(격리가 실제로 걸리나)가 깨졌다")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.documentJSONURL.path),
                       "격리가 원본을 옮겼어야 하는데 옛 자리에 남아 있다")
        try store.save(CueDocument())
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.documentJSONURL.path),
                      "격리 뒤 저장이 document.json 을 다시 안 만들었다 — lastHead 가 격리를 안 지웠다")
    }

    // MARK: - 아무 md 나 던져도 오류 0 (인수 조건)

    func testForeignMarkdownIsReadWithoutError() throws {
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("메모"),
                                                withIntermediateDirectories: true)
        let files: [(String, String)] = [
            ("옵시디언.md", "---\ntags: [일기]\naliases:\n  - 별명\n---\n# 진짜 제목\n\n본문이다."),
            ("머리없음.md", "# 첫 회사에서 배운 것\n\n사수가 없었다."),
            ("줄글.md", "제목줄도 없다. 그냥 글."),
            ("빈 것.md", ""),
            ("메모/깊은 것.md", "---\ntitle: 하위 폴더\n---\n본문"),
            ("사진.png", "PNG 인 척"),
            ("설정.json", "{}"),
        ]
        for (name, body) in files {
            try body.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }

        let doc = try store.load().document
        XCTAssertEqual(doc.fragments.count, 5, "md 5장이 조각 5장이어야 한다 — 비-md 는 안 든다")
        XCTAssertTrue(doc.fragments.contains { $0.title == "진짜 제목" })
        XCTAssertTrue(doc.fragments.contains { $0.title == "첫 회사에서 배운 것" })
        XCTAssertTrue(doc.fragments.contains { $0.title == "줄글" })
        XCTAssertTrue(doc.fragments.contains { $0.title == "하위 폴더" })
        XCTAssertTrue(doc.fragments.contains { $0.title == "빈 것" })
    }

    /// ★ 안 고친 남의 파일은 **한 바이트도 안 바뀐다.** 볼트를 열 때마다 통째로 다시 쓰이면
    /// 옵시디언 볼트를 연결한 사람의 git diff 가 매번 폭발한다.
    func testUntouchedForeignFilesAreNotRewritten() throws {
        let path = dir.appendingPathComponent("남의 것.md")
        let original = "---\ntags: [일기]\n---\n# 남의 제목\n\n본문이다.\n"
        try original.write(to: path, atomically: true, encoding: .utf8)

        let doc = try store.load().document
        try store.save(doc)                                  // 화면이 문서 전체를 되보낸 셈
        XCTAssertEqual(try String(contentsOf: path, encoding: .utf8), original,
                       "안 고친 파일이 다시 쓰였다")

        try store.save(doc)                                  // 두 번째 저장도 마찬가지
        XCTAssertEqual(try String(contentsOf: path, encoding: .utf8), original)
    }

    /// 고치면 그 파일**만** 바뀌고, 남의 frontmatter 는 남는다.
    func testEditingAFragmentRewritesOnlyThatFile() throws {
        try "---\ntags: [일기]\n---\n# 남의 제목\n\n본문\n"
            .write(to: dir.appendingPathComponent("남의 것.md"), atomically: true, encoding: .utf8)
        try "# 안 건드릴 것\n\n그대로\n"
            .write(to: dir.appendingPathComponent("옆의 것.md"), atomically: true, encoding: .utf8)
        let untouchedBefore = try String(contentsOf: dir.appendingPathComponent("옆의 것.md"),
                                         encoding: .utf8)

        var doc = try store.load().document
        let i = try XCTUnwrap(doc.fragments.firstIndex { $0.title == "남의 제목" })
        doc.fragments[i].body = "내가 고쳤다"
        try store.save(doc)

        let edited = try String(contentsOf: dir.appendingPathComponent("남의 것.md"), encoding: .utf8)
        XCTAssertTrue(edited.contains("내가 고쳤다"))
        XCTAssertTrue(edited.contains("tags: [일기]"), "남의 frontmatter 가 지워졌다:\n\(edited)")
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("옆의 것.md"), encoding: .utf8),
                       untouchedBefore, "안 고친 옆 파일이 같이 다시 쓰였다")
        XCTAssertEqual(try store.load().document.fragments.first { $0.title == "남의 제목" }?.body,
                       "내가 고쳤다")
    }

    // MARK: - 낙관적 리비전과 외부 편집 충돌 (#84 P1)

    func testExternalEditOfTheSameFilePreservesDiskAndAttemptedContent() throws {
        let path = dir.appendingPathComponent("함께 쓰는 것.md")
        let original = "---\nid: f-shared\ntitle: 함께 쓰는 것\ntags: [보존]\n---\n처음\n"
        try original.write(to: path, atomically: true, encoding: .utf8)

        let loaded = try store.loadVersioned()
        var attempted = loaded.result.document
        attempted.fragments[0].body = "앱에서 고친 내용"
        let external = "---\nid: f-shared\ntitle: 함께 쓰는 것\ntags: [보존]\n---\n밖에서 고친 내용\n"
        try external.write(to: path, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try store.save(attempted, expecting: loaded.revision)) { error in
            guard let conflict = error as? VaultConflictError else {
                return XCTFail("리비전 충돌이 아닌 오류다: \(error)")
            }
            XCTAssertEqual(conflict.conflicts.count, 1)
            XCTAssertEqual(conflict.conflicts[0].fragmentID, "f-shared")
            XCTAssertEqual(conflict.conflicts[0].relativePath, "함께 쓰는 것.md")
            XCTAssertEqual(conflict.conflicts[0].diskState, .modified)
            XCTAssertEqual(conflict.attemptedDocument.fragments[0].body, "앱에서 고친 내용",
                           "실패 뒤 복구할 사용자 편집이 오류에서 사라졌다")
            guard let copy = conflict.conflicts[0].attemptedCopyURL else {
                return XCTFail("앱 편집의 충돌 사본 경로가 없다")
            }
            XCTAssertTrue((try? String(contentsOf: copy, encoding: .utf8)
                .contains("앱에서 고친 내용")) == true,
                "앱 편집의 충돌 사본이 디스크에 남지 않았다")
        }
        XCTAssertEqual(try String(contentsOf: path, encoding: .utf8), external,
                       "외부 편집을 앱 내용으로 덮었다")
    }

    func testExternalDeletionOfTheSameFilePreservesAttemptedContent() throws {
        let path = dir.appendingPathComponent("사라진 것.md")
        try "---\nid: f-gone\ntitle: 사라진 것\n---\n처음\n"
            .write(to: path, atomically: true, encoding: .utf8)
        let loaded = try store.loadVersioned()
        var attempted = loaded.result.document
        attempted.fragments[0].body = "앱에서 고친 내용"
        try FileManager.default.removeItem(at: path)

        XCTAssertThrowsError(try store.save(attempted, expecting: loaded.revision)) { error in
            let conflict = error as? VaultConflictError
            XCTAssertEqual(conflict?.conflicts.first?.diskState, .deleted)
            XCTAssertEqual(conflict?.attemptedDocument.fragments.first?.body, "앱에서 고친 내용")
            let copy = conflict?.conflicts.first?.attemptedCopyURL
            XCTAssertTrue(copy.map { FileManager.default.fileExists(atPath: $0.path) } == true)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path),
                       "외부에서 지운 파일을 오래된 앱 내용으로 되살렸다")
    }

    func testExternalEditOfAnotherFileDoesNotBlockOrOverwriteThisSave() throws {
        let a = dir.appendingPathComponent("a.md")
        let b = dir.appendingPathComponent("b.md")
        try "---\nid: f-a\ntitle: A\n---\nA 처음\n".write(to: a, atomically: true, encoding: .utf8)
        try "---\nid: f-b\ntitle: B\n---\nB 처음\n".write(to: b, atomically: true, encoding: .utf8)
        let loaded = try store.loadVersioned()
        var attempted = loaded.result.document
        attempted.fragments[try XCTUnwrap(attempted.fragments.firstIndex { $0.id == "f-a" })].body = "A 앱 편집"
        let externalB = "---\nid: f-b\ntitle: B\n---\nB 외부 편집\n"
        try externalB.write(to: b, atomically: true, encoding: .utf8)

        let saved = try store.save(attempted, expecting: loaded.revision)

        XCTAssertTrue(try String(contentsOf: a, encoding: .utf8).contains("A 앱 편집"))
        XCTAssertEqual(try String(contentsOf: b, encoding: .utf8), externalB,
                       "별도 파일의 외부 편집을 오래된 문서로 덮었다")
        XCTAssertEqual(saved.paths["f-a"], "a.md")
        XCTAssertEqual(saved.paths["f-b"], "b.md")
    }

    func testOldRevisionStillConflictsAfterAWatcherStyleReload() throws {
        let path = dir.appendingPathComponent("다시 읽은 것.md")
        try "---\nid: f-reload\ntitle: 다시 읽은 것\n---\n처음\n"
            .write(to: path, atomically: true, encoding: .utf8)
        let editingSession = try store.loadVersioned()
        var attempted = editingSession.result.document
        attempted.fragments[0].body = "아직 저장하지 않은 앱 편집"
        try "---\nid: f-reload\ntitle: 다시 읽은 것\n---\n밖에서 고침\n"
            .write(to: path, atomically: true, encoding: .utf8)

        _ = try store.loadVersioned() // VaultWatcher가 reload를 요청한 상황

        XCTAssertThrowsError(try store.save(attempted, expecting: editingSession.revision)) { error in
            XCTAssertEqual((error as? VaultConflictError)?.attemptedDocument.fragments.first?.body,
                           "아직 저장하지 않은 앱 편집")
        }
        XCTAssertTrue(try String(contentsOf: path, encoding: .utf8).contains("밖에서 고침"))
    }

    func testLegacySaveAlsoRejectsAnExternalEditOfTheFileItChanges() throws {
        let path = dir.appendingPathComponent("기존 API.md")
        try "---\nid: f-legacy\ntitle: 기존 API\n---\n처음\n"
            .write(to: path, atomically: true, encoding: .utf8)
        var attempted = try store.load().document
        attempted.fragments[0].body = "앱 편집"
        try "---\nid: f-legacy\ntitle: 기존 API\n---\n외부 편집\n"
            .write(to: path, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try store.save(attempted)) { error in
            XCTAssertNotNil(error as? VaultConflictError)
        }
        XCTAssertTrue(try String(contentsOf: path, encoding: .utf8).contains("외부 편집"))
    }

    // MARK: - 새 정리 문서의 명시 경로 (#84 P2 최소 기반)

    func testNewFragmentCanBeSavedAtAValidatedNestedPath() throws {
        let loaded = try store.loadVersioned()
        let t = Date(timeIntervalSince1970: 1_756_000_000)
        let doc = CueDocument(fragments: [
            Fragment(id: "wiki-topic", title: "주제", body: "정리", questionIds: [],
                     createdAt: t, updatedAt: t)
        ])

        let saved = try store.save(doc, expecting: loaded.revision,
                                   newPaths: ["wiki-topic": "wiki/topic.md"])

        XCTAssertEqual(saved.paths["wiki-topic"], "wiki/topic.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("wiki/topic.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("주제.md").path))
    }

    func testExplicitNewPathRejectsTraversalAbsoluteCollisionAndExistingFragmentMove() throws {
        let t = Date(timeIntervalSince1970: 1_756_000_000)
        try "---\nid: existing\ntitle: 기존\n---\n본문\n"
            .write(to: dir.appendingPathComponent("existing.md"), atomically: true, encoding: .utf8)
        try "이미 있음".write(to: dir.appendingPathComponent("occupied.md"),
                           atomically: true, encoding: .utf8)
        let loaded = try store.loadVersioned()
        var doc = loaded.result.document
        doc.fragments.append(Fragment(id: "new", title: "새것", body: "본문", questionIds: [],
                                      createdAt: t, updatedAt: t))

        for bad in ["../outside.md", "/tmp/outside.md", ".clonie/secret.md", "occupied.md"] {
            XCTAssertThrowsError(try store.save(doc, expecting: loaded.revision,
                                                newPaths: ["new": bad]), "거부해야 하는 경로: \(bad)") { error in
                XCTAssertNotNil(error as? VaultPathError)
            }
        }
        XCTAssertThrowsError(try store.save(doc, expecting: loaded.revision,
                                            newPaths: ["existing": "wiki/moved.md"])) { error in
            XCTAssertEqual(error as? VaultPathError, .pathForExistingFragment("existing"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath:
            dir.deletingLastPathComponent().appendingPathComponent("outside.md").path))
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("occupied.md"), encoding: .utf8),
                       "이미 있음")
    }

    func testExplicitNewPathRejectsSymlinkEscape() throws {
        let outside = dir.deletingLastPathComponent()
            .appendingPathComponent("clonie-outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("wiki"),
                                                    withDestinationURL: outside)
        let loaded = try store.loadVersioned()
        let t = Date(timeIntervalSince1970: 1_756_000_000)
        let doc = CueDocument(fragments: [
            Fragment(id: "escape", title: "탈출", body: "안 됨", questionIds: [],
                     createdAt: t, updatedAt: t)
        ])

        XCTAssertThrowsError(try store.save(doc, expecting: loaded.revision,
                                            newPaths: ["escape": "wiki/escape.md"])) { error in
            XCTAssertEqual(error as? VaultPathError, .outsideVault("wiki/escape.md"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("escape.md").path))
    }

    func testExplicitNewPathWorksWhenTheVaultItselfIsASymlink() throws {
        let target = dir.deletingLastPathComponent()
            .appendingPathComponent("clonie-target-\(UUID().uuidString)", isDirectory: true)
        let link = dir.deletingLastPathComponent()
            .appendingPathComponent("clonie-link-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        defer {
            try? FileManager.default.removeItem(at: link)
            try? FileManager.default.removeItem(at: target)
        }
        let linkedStore = VaultStore(vaultURL: link)
        let loaded = try linkedStore.loadVersioned()
        let t = Date(timeIntervalSince1970: 1_756_000_000)
        let doc = CueDocument(fragments: [
            Fragment(id: "linked", title: "연결", body: "본문", questionIds: [],
                     createdAt: t, updatedAt: t)
        ])

        let saved = try linkedStore.save(doc, expecting: loaded.revision,
                                         newPaths: ["linked": "wiki/linked.md"])

        XCTAssertEqual(saved.paths["linked"], "wiki/linked.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("wiki/linked.md").path))
    }

    func testExplicitNewPathsRejectCaseFoldedDuplicatesBeforeWriting() throws {
        let loaded = try store.loadVersioned()
        let t = Date(timeIntervalSince1970: 1_756_000_000)
        let doc = CueDocument(fragments: [
            Fragment(id: "upper", title: "위", body: "위", questionIds: [], createdAt: t, updatedAt: t),
            Fragment(id: "lower", title: "아래", body: "아래", questionIds: [], createdAt: t, updatedAt: t),
        ])

        XCTAssertThrowsError(try store.save(doc, expecting: loaded.revision,
                                            newPaths: ["upper": "wiki/Topic.md",
                                                       "lower": "wiki/topic.md"])) { error in
            XCTAssertEqual(error as? VaultPathError, .occupied("wiki/Topic.md"))
        }
        XCTAssertEqual(try store.markdownRelativePaths(), [], "충돌을 찾기 전에 일부 파일을 썼다")
    }

    func testExplicitNewPathIsReservedBeforeDefaultNamesAreChosen() throws {
        let loaded = try store.loadVersioned()
        let t = Date(timeIntervalSince1970: 1_756_000_000)
        let doc = CueDocument(fragments: [
            Fragment(id: "automatic", title: "topic", body: "자동", questionIds: [],
                     createdAt: t, updatedAt: t),
            Fragment(id: "explicit", title: "명시", body: "명시", questionIds: [],
                     createdAt: t, updatedAt: t),
        ])

        let saved = try store.save(doc, expecting: loaded.revision,
                                   newPaths: ["explicit": "topic.md"])

        XCTAssertEqual(saved.paths["explicit"], "topic.md")
        XCTAssertNotEqual(saved.paths["automatic"]?.lowercased(), "topic.md")
        XCTAssertEqual(try store.markdownRelativePaths().count, 2)
        XCTAssertTrue(try String(contentsOf: dir.appendingPathComponent("topic.md"), encoding: .utf8)
            .contains("명시"), "자동 파일이 명시 경로를 먼저 차지했다")
    }

    func testCreateOnlyAtomicWriteNeverReplacesADestinationThatAppearedAfterValidation() throws {
        let path = dir.appendingPathComponent("race.md")
        try "외부에서 먼저 쓴 내용".write(to: path, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try store.writeNewAtomically("앱이 쓰려던 내용", to: path,
                                                          relativePath: "race.md")) { error in
            XCTAssertEqual(error as? VaultPathError, .occupied("race.md"))
        }
        XCTAssertEqual(try String(contentsOf: path, encoding: .utf8), "외부에서 먼저 쓴 내용")
    }

    // MARK: - 지우기는 옮기기다

    func testDeletedFragmentGoesToTrashNotToNothing() throws {
        try store.save(sample())
        var doc = try store.load().document
        doc.fragments.removeAll()
        try store.save(doc)

        XCTAssertEqual(try mdFiles(), [], "볼트에서는 사라진다")
        let trash = try FileManager.default.contentsOfDirectory(atPath: store.trashURL.path)
        XCTAssertEqual(trash.count, 1, "쓰레기통에 없다 — 사용자 파일을 지웠다: \(trash)")
        XCTAssertTrue(try String(contentsOf: store.trashURL.appendingPathComponent(trash[0]),
                                 encoding: .utf8).contains("한 줄로 줄였다"))
    }

    /// ★ **읽은 적 없는 저장소는 아무것도 안 치운다.** 읽기가 실패하면 화면은 빈 문서를 받고
    /// 씨앗 하나를 저장한다 — 그때 「문서에 없는 것 = 지운 것」으로 셈하면 볼트 전체가 날아간다.
    func testSaveWithoutAPriorLoadNeverTrashesAnything() throws {
        try "# 남의 글\n\n본문\n".write(to: dir.appendingPathComponent("남의 글.md"),
                                    atomically: true, encoding: .utf8)
        let fresh = VaultStore(vaultURL: dir)          // load() 를 한 번도 안 불렀다
        let t = Date(timeIntervalSince1970: 1_756_000_000)
        try fresh.save(CueDocument(fragments: [
            Fragment(id: "f-seed", title: "씨앗", body: "b", questionIds: [], createdAt: t, updatedAt: t)]))

        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("남의 글.md").path),
                      "안 읽은 파일을 지웠다")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.trashURL.path),
                       "쓰레기통이 생겼다 — 못 읽은 것을 치우는 길이 열려 있다")
        XCTAssertEqual(try store.load().document.fragments.count, 2)
    }

    // MARK: - 마이그레이션 (인수 조건: 왕복 자물쇠)

    func testLegacyJSONMigratesToMarkdownAndTheOriginalIsKept() throws {
        let legacyDir = dir.deletingLastPathComponent()
            .appendingPathComponent("clonie-legacy-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: legacyDir) }
        let legacy = legacyDir.appendingPathComponent("cue.json")
        let before = sample()
        try FragmentStore(url: legacy).save(before)

        let vault = VaultStore(vaultURL: dir, legacyJSONURL: legacy)
        let after = try vault.load()

        XCTAssertNil(after.quarantined)
        // ⚠ 옮긴 문서는 기록 칸이 채워져서(빈 것) 온다 — 옛 JSON 엔 그 칸이 아예 없다 (#79).
        var expected = before
        expected.asked = []
        XCTAssertEqual(after.document, expected, "옛 문서와 옮긴 문서가 다르다 — 왕복이 안 닫혔다")
        XCTAssertEqual(try vault.markdownRelativePaths().count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path),
                       "원본이 제자리에 남으면 정본이 둘이 된다")
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.migratedBackupURL.path),
                      "원본이 보존 자리에 없다")
        XCTAssertEqual(try FragmentStore(url: vault.migratedBackupURL).load().document, before,
                       "보존한 원본이 원본이 아니다")
    }

    func testMigrationHappensOnlyOnce() throws {
        let legacyDir = dir.deletingLastPathComponent()
            .appendingPathComponent("clonie-legacy-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: legacyDir) }
        let legacy = legacyDir.appendingPathComponent("cue.json")
        try FragmentStore(url: legacy).save(sample())

        _ = try VaultStore(vaultURL: dir, legacyJSONURL: legacy).load()
        // 옛 자리에 파일이 다시 나타나도(옛 판 앱을 한 번 더 돌렸다) 두 번 옮기지 않는다.
        try FragmentStore(url: legacy).save(CueDocument(
            fragments: [Fragment(id: "f-9", title: "두 번째로 나타난 것", body: "b",
                                 questionIds: [], createdAt: Date(), updatedAt: Date())]))
        let second = try VaultStore(vaultURL: dir, legacyJSONURL: legacy).load()
        XCTAssertEqual(second.document.fragments.count, 1)
        XCTAssertEqual(second.document.fragments[0].id, "f-1")
    }

    /// 미래 판 문서는 **옮기지도 열지도** 않는다 — 반쯤 옮기면 알맹이가 사라진다.
    func testFutureSchemaLegacyIsRefusedAndLeftAlone() throws {
        let legacyDir = dir.deletingLastPathComponent()
            .appendingPathComponent("clonie-legacy-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: legacyDir) }
        try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        let legacy = legacyDir.appendingPathComponent("cue.json")
        let future = #"{"schemaVersion": 99, "questions": [], "fragments": []}"#
        try future.write(to: legacy, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try VaultStore(vaultURL: dir, legacyJSONURL: legacy).load())
        XCTAssertEqual(try String(contentsOf: legacy, encoding: .utf8), future)
    }

    // MARK: - 옵셔널 필드 (#22·#23 이 잰 것을 볼트에서도 잰다)

    func testInterviewMarkAndVariantsSurviveTheVault() throws {
        let doc = CueDocument(questions: [
            Question(id: "q-1", text: "사람이 고른 것"),
            Question(id: "q-2", text: "면접에서 온 것", fromInterview: true,
                     variants: ["다르게 말한 모양"]),
        ])
        try store.save(doc)
        let back = try store.load().document
        XCTAssertNil(back.questions[0].fromInterview)
        XCTAssertNil(back.questions[0].variants)
        XCTAssertEqual(back.questions[1].fromInterview, true)
        XCTAssertEqual(back.questions[1].variants, ["다르게 말한 모양"])

        let json = try String(contentsOf: store.documentJSONURL, encoding: .utf8)
        XCTAssertEqual(json.components(separatedBy: "fromInterview").count - 1, 1,
                       "nil 인데 키가 파일에 쓰였다:\n\(json)")
    }

    func testSchemaVersionDidNotMove() {
        XCTAssertEqual(CueDocument.currentSchemaVersion, 1, "볼트 이사는 스키마 판을 안 올린다")
    }

    // MARK: - 이름 충돌

    func testTwoFragmentsWithTheSameTitleDoNotOverwriteEachOther() throws {
        let t = Date(timeIntervalSince1970: 1_756_000_000)
        try store.save(CueDocument(fragments: [
            Fragment(id: "f-1", title: "같은 제목", body: "첫째", questionIds: [], createdAt: t, updatedAt: t),
            Fragment(id: "f-2", title: "같은 제목", body: "둘째", questionIds: [], createdAt: t, updatedAt: t),
        ]))
        XCTAssertEqual(try mdFiles().count, 2, "같은 제목이 서로를 덮어썼다")
        XCTAssertEqual(Set(try store.load().document.fragments.map(\.body)), ["첫째", "둘째"])
    }

    // MARK: - 폴더 자리 (#74 A — 「우주」의 항성이 볼트 폴더다)

    /// 조각이 **어느 폴더에서 왔는지**를 읽는 쪽이 알아야 한다. 지금까지 그 값은
    /// `ParsedFile.relativePath` 로 있다가 화면으로 넘기며 버려졌다 (#74 「Current State」).
    ///
    /// ⚠ **md frontmatter 에는 안 쓴다** — 경로는 파일이 있는 자리에서 나오는 **파생값**이라,
    /// 본문에 적으면 사람이 옵시디언에서 파일을 옮기는 순간 둘이 갈린다.
    func testLoadReportsTheVaultRelativePathOfEachFragment() throws {
        let sub = dir.appendingPathComponent("a/b", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "---\nid: f-deep\ntitle: 깊은 조각\n---\n본문이다.\n"
            .write(to: sub.appendingPathComponent("x.md"), atomically: true, encoding: .utf8)

        let loaded = try store.load()
        XCTAssertEqual(loaded.paths["f-deep"], "a/b/x.md")
        XCTAssertEqual(loaded.paths.count, loaded.document.fragments.count,
                       "조각마다 자리가 하나씩이다")
    }

    /// 하위 폴더의 조각을 고쳐 저장해도 **그 폴더에 남는다.** 이미 그렇게 돈다
    /// (`save` 가 스냅샷의 `relativePath` 로 되쓴다) — #74 가 경로를 화면에 주면서
    /// 이 성질이 **우주 그림의 전제**가 되므로 여기서 못 박는다.
    func testEditingAFragmentInASubfolderKeepsTheFileThere() throws {
        let sub = dir.appendingPathComponent("a/b", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "---\nid: f-deep\ntitle: 깊은 조각\n---\n본문이다.\n"
            .write(to: sub.appendingPathComponent("x.md"), atomically: true, encoding: .utf8)

        var doc = try store.load().document
        doc.fragments[0].body = "고친 본문이다."
        try store.save(doc)

        XCTAssertEqual(try mdFiles(), ["a/b/x.md"], "저장이 조각을 뿌리로 끌어올렸다")
        let text = try String(contentsOf: sub.appendingPathComponent("x.md"), encoding: .utf8)
        XCTAssertTrue(text.contains("고친 본문이다."))
        XCTAssertFalse(text.contains("path:"), "경로는 파생값이라 md 에 안 쓴다")
        XCTAssertEqual(try store.load().paths["f-deep"], "a/b/x.md")
    }

    // MARK: - 화면으로 가는 짐 (#74 A)

    /// `sendDocument` 가 보내는 JSON 에 `paths` 가 있고 **조각 수와 같다.**
    ///
    /// ⚠ 이 함수가 `WKWebViewWrapper` 가 아니라 여기 사는 이유: executable 타깃은
    /// `swift test` 가 못 부른다(`Package.swift` 그 주석). 짐을 만드는 것은 순수 함수라
    /// 코어에 두면 잴 수 있다.
    func testDocumentPayloadCarriesPathsForEveryFragment() throws {
        let sub = dir.appendingPathComponent("삼성 면접/프로젝트 X", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "---\nid: f-x\ntitle: X 개요\n---\n본문.\n"
            .write(to: sub.appendingPathComponent("X 개요.md"), atomically: true, encoding: .utf8)
        try "---\nid: f-root\ntitle: 메모\n---\n본문.\n"
            .write(to: dir.appendingPathComponent("메모.md"), atomically: true, encoding: .utf8)

        let loaded = try store.load()
        let json = try XCTUnwrap(VaultIO.documentPayloadJSON(loaded))
        let obj = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let paths = try XCTUnwrap(obj["paths"] as? [String: String])
        let fragments = try XCTUnwrap(obj["fragments"] as? [[String: Any]])
        XCTAssertEqual(paths.count, fragments.count)
        XCTAssertEqual(paths["f-x"], "삼성 면접/프로젝트 X/X 개요.md")
        XCTAssertEqual(paths["f-root"], "메모.md")
        XCTAssertNotNil(obj["questions"])
        XCTAssertEqual(obj["schemaVersion"] as? Int, CueDocument.currentSchemaVersion)
    }
}

// MARK: - 감시

/// 밖에서 고친 md 가 **신호를 내는가**. 다시 읽는 것은 부르는 쪽의 몫이라 여기서 안 잰다.
final class VaultWatcherTests: XCTestCase {

    func testIgnoresSidecarAndIncludesOrdinaryFiles() {
        let v = "/tmp/vault"
        XCTAssertTrue(VaultWatcher.isInteresting("/tmp/vault/메모.md", vaultPath: v))
        XCTAssertTrue(VaultWatcher.isInteresting("/tmp/vault/깊은/것.markdown", vaultPath: v))
        XCTAssertFalse(VaultWatcher.isInteresting("/tmp/vault/.clonie/document.json", vaultPath: v))
        XCTAssertFalse(VaultWatcher.isInteresting("/tmp/vault/.clonie/trash/옛것.md", vaultPath: v))
        XCTAssertTrue(VaultWatcher.isInteresting("/tmp/vault/사진.png", vaultPath: v))
        XCTAssertFalse(VaultWatcher.isInteresting("/tmp/vault/.메모.md.tmp-1", vaultPath: v))
    }

    /// 진짜 FSEvents 를 한 번 돌린다. **양성 대조가 목적이다** — 위의 순수 함수만 재면
    /// 스트림이 아예 안 켜졌을 때도 초록이다.
    func testRealFileChangeFires() throws {
        try XCTSkipUnless(VaultWatcher.isSupported)
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("clonie-watch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fired = expectation(description: "볼트가 바뀌었다")
        fired.assertForOverFulfill = false
        let watcher = VaultWatcher(vaultURL: dir, latency: 0.05) { fired.fulfill() }
        // NSTemporaryDirectory() 는 /var 별칭을 쓰지만 FSEvents 경로는
        // /private/var realpath 를 낸다. 실제 이벤트와 같은 경계를 잠근다.
        let eventPath = dir.path.replacingOccurrences(of: "/var/", with: "/private/var/",
                                                       range: dir.path.startIndex..<dir.path.endIndex)
            + "/밖에서.md"
        XCTAssertTrue(watcher.interesting([eventPath]))
        watcher.start()
        defer { watcher.stop() }

        // 스트림이 자리를 잡을 틈. FSEvents 는 `SinceNow` 라 켜지기 전 변경은 안 본다.
        Thread.sleep(forTimeInterval: 0.4)
        try "밖에서 쓴 글".write(to: dir.appendingPathComponent("밖에서.md"),
                             atomically: true, encoding: .utf8)
        wait(for: [fired], timeout: 20)
    }
}
