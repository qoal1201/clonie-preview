import XCTest
import ClonieCore
import ClonieEmbedding
@testable import ClonieIndex
@testable import ClonieMCP

/// 도구 논리 — MCP 껍데기 없이 **actor 를 직접** 부른다. 껍데기는 `ToolServerTests` 가 잰다.
final class VaultToolsTests: XCTestCase {
    private var vault: URL!

    override func setUpWithError() throws {
        vault = try MCPTestSupport.makeVault()
        try VaultStore(vaultURL: vault).save(MCPTestSupport.sampleDocument())
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: vault) }

    private func tools() -> VaultTools {
        VaultTools(vaultURL: vault, environment: MCPTestSupport.noModelEnvironment)
    }

    func testMCPWritesExposeDurableChangesAndIdenticalUpdateIsNotRecorded() async throws {
        let t = tools()
        let store = VaultStore(vaultURL: vault)
        XCTAssertEqual(try store.documentChanges().count, 0)
        let created = try await t.write(title: "요청한 메모", body: "첫 본문", force: true, path: "notes/requested.md")
        XCTAssertTrue(created.written)
        let creation = try XCTUnwrap(store.documentChanges().first)
        XCTAssertEqual(creation.operation, .create)
        XCTAssertEqual(creation.path, "notes/requested.md")
        let read = try await t.read(id: created.id)
        let unchanged = try await t.write(title: read.title, body: read.body, id: read.id, revision: read.revision)
        XCTAssertEqual(unchanged.note, "unchanged")
        XCTAssertEqual(try store.documentChanges().count, 1)
        let reread = try await t.read(id: created.id)
        let updated = try await t.write(title: reread.title, body: "사용자가 요청한 수정", id: reread.id, revision: reread.revision)
        XCTAssertTrue(updated.written)
        let change = try XCTUnwrap(store.documentChanges().first)
        XCTAssertEqual(change.operation, .update)
        XCTAssertEqual(change.before?.body, "첫 본문")
        XCTAssertEqual(change.after.body, "사용자가 요청한 수정")
        _ = try store.restoreDocumentChange(id: change.id)
        let restored = try await t.read(id: created.id)
        XCTAssertEqual(restored.body, "첫 본문")
    }

    func testRevisionRejectsExternalOverwriteAndPreservesAttempt() async throws {
        let t = tools()
        let read = try await t.read(id: "f-fail")
        let store = VaultStore(vaultURL: vault)
        var external = try store.load().document
        external.fragments[external.fragments.firstIndex { $0.id == read.id }!].body = "외부에서 확인한 사실"
        try store.save(external)
        do {
            _ = try await t.write(title: read.title, body: "AI의 오래된 해석", id: read.id, revision: read.revision)
            XCTFail("읽은 뒤 바뀐 원본을 덮었다")
        } catch let error as VaultConflictError {
            XCTAssertEqual(error.conflicts.first?.diskFragment?.body, "외부에서 확인한 사실")
            XCTAssertNotNil(error.conflicts.first?.attemptedCopyURL)
        }
        XCTAssertEqual(try store.load().document.fragments.first { $0.id == read.id }?.body, "외부에서 확인한 사실")
        XCTAssertEqual(try store.documentChanges().count, 0)
    }

    func testWriteKeepsNewerQuestionsAndAskedAfterAnInterveningRead() async throws {
        let t = tools()
        let read = try await t.read(id: "f-fail")
        let store = VaultStore(vaultURL: vault)
        var external = try store.load().document
        external.questions.append(Question(id: "new-question", text: "최근 질문"))
        external.asked = [AskedEntry(id: "new-asked", text: "새 대화의 기록", source: .interview, at: Date())]
        try store.save(external)
        _ = try await t.list()
        let beforeHead = try Data(contentsOf: store.sidecarURL.appendingPathComponent("document.json"))
        let beforeAsked = try Data(contentsOf: store.sidecarURL.appendingPathComponent("asked.json"))
        _ = try await t.write(title: read.title, body: "새 본문", id: read.id, revision: read.revision)
        XCTAssertEqual(try Data(contentsOf: store.sidecarURL.appendingPathComponent("document.json")), beforeHead)
        XCTAssertEqual(try Data(contentsOf: store.sidecarURL.appendingPathComponent("asked.json")), beforeAsked)
        XCTAssertEqual(try store.load().document.fragments.first { $0.id == read.id }?.body, "새 본문")
    }

    func testWikiPathIsStableAndRawOriginalIsReadOnly() async throws {
        let t = tools()
        let raw = vault.appendingPathComponent("raw")
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
        try "# 원본\n\n원래 사실".write(to: raw.appendingPathComponent("source.md"), atomically: true, encoding: .utf8)
        let created = try await t.write(title: "정리", body: "[원본](../raw/source.md)", force: true, path: "wiki/overview.md")
        XCTAssertEqual(created.path, "wiki/overview.md")
        do {
            _ = try await t.write(title: "읽지 않은 정리본", body: "덮기", id: created.id)
            XCTFail("정리본을 읽지 않고 갱신했다")
        } catch let error as VaultToolError { XCTAssertEqual(error, .invalidRevision) }
        let read = try await t.read(id: created.id)
        let updated = try await t.write(title: "바뀐 제목", body: "수정한 해석", id: read.id, revision: read.revision)
        XCTAssertEqual(updated.path, "wiki/overview.md")
        let original = try await t.list().fragments.first { $0.path == "raw/source.md" }!
        do {
            _ = try await t.write(title: "덮기", body: "덮기", id: original.id)
            XCTFail("원본에 썼다")
        } catch let error as VaultToolError { XCTAssertEqual(error, .readOnlySource("raw/source.md")) }
        do {
            _ = try await t.write(title: "탈출", body: "본문", force: true, path: "raw/new.md")
            XCTFail("원본 폴더에 썼다")
        } catch let error as VaultToolError { XCTAssertEqual(error, .invalidOutputPath) }
    }

    // MARK: - list

    func testListReturnsEveryFragmentNewestFirst() async throws {
        let r = try await tools().list()
        XCTAssertEqual(r.total, 3)
        XCTAssertEqual(r.fragments.map(\.id), ["f-pasta", "f-fail", "f-deploy"])
        XCTAssertEqual(r.fragments[2].path, "배포 스크립트를 갈아엎었다.md")
    }

    func testListLimitCapsButTotalStays() async throws {
        let r = try await tools().list(limit: 1)
        XCTAssertEqual(r.total, 3)
        XCTAssertEqual(r.fragments.count, 1)
    }

    func testListSkipsSeedPlaceholder() async throws {
        var doc = MCPTestSupport.sampleDocument()
        doc.fragments.append(Fragment(id: "f-seed", title: "여기에 내 경험을 한 줄로 쓴다", body: "예시",
                                      questionIds: [], createdAt: Date(), updatedAt: Date(), seed: true))
        try VaultStore(vaultURL: vault).save(doc)
        let r = try await tools().list()
        XCTAssertFalse(r.fragments.contains { $0.id == "f-seed" }, "씨앗은 사람이 쓴 것이 아니다 — 목록에 안 낸다")
        XCTAssertEqual(r.total, 3)
    }

    // MARK: - read

    func testReadReturnsBodyAndPath() async throws {
        let r = try await tools().read(id: "f-fail")
        XCTAssertEqual(r.title, "장애를 놓친 날")
        XCTAssertTrue(r.body.contains("당번 규칙"))
        XCTAssertEqual(r.path, "장애를 놓친 날.md")
        XCTAssertEqual(r.questionIds, ["q-2"])
    }

    func testReadUnknownIdThrowsNotFound() async throws {
        do {
            _ = try await tools().read(id: "nope")
            XCTFail("없는 id 가 통과했다")
        } catch let e as VaultToolError {
            guard case .notFound("nope") = e else { return XCTFail("다른 오류: \(e)") }
        }
    }

    // MARK: - search (글자 폴백 — 모델 없이 언제나 돈다)

    func testSearchFallsBackToTextWhenModelMissing() async throws {
        let r = try await tools().search(query: "당번")
        XCTAssertEqual(r.mode, "text")
        XCTAssertEqual(r.hits.map(\.id), ["f-fail"])
        XCTAssertNil(r.hits[0].score)
        XCTAssertNil(r.hits[0].light)
        XCTAssertNotNil(r.note, "왜 글자로 찾았는지(모델이 없다)를 말해야 한다")
    }

    func testSearchEmptyQueryThrows() async throws {
        do { _ = try await tools().search(query: "  "); XCTFail("빈 질의가 통과했다") }
        catch let e as VaultToolError { XCTAssertEqual(e, .emptyQuery) }
    }

    // MARK: - search (뜻 — 모델이 있을 때만 잰다)

    func testMeaningSearchRanksDeployFragmentFirstAndLightsIt() async throws {
        guard MCPTestSupport.modelOrAnnounceMissing() != nil else { return }
        let t = VaultTools(vaultURL: vault)   // 진짜 환경 — 모델을 찾는다
        let r = try await t.search(query: "배포 자동화 경험", limit: 3)
        XCTAssertEqual(r.mode, "meaning")
        XCTAssertEqual(r.hits.first?.id, "f-deploy")
        XCTAssertNotNil(r.hits.first?.score)
        XCTAssertEqual(r.hits.first?.light, Thresholds.light(normalized: r.hits.first!.score!))
        // 파스타는 대조군 — 1위가 아니어야 자가 산 것이다.
        XCTAssertNotEqual(r.hits.first?.id, "f-pasta")
    }

    func testMeaningSearchReusesSidecarVectorsAndNeverWritesThem() async throws {
        guard MCPTestSupport.modelOrAnnounceMissing() != nil else { return }
        let t = VaultTools(vaultURL: vault)
        _ = try await t.search(query: "배포")
        let sidecar = VaultStore(vaultURL: vault).sidecarURL
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecar.appendingPathComponent("embeddings.json").path),
                       "MCP 가 색인 사이드카를 썼다 — ADR 0007 위반")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecar.appendingPathComponent("links.json").path))
        // 둘째 검색은 캐시로 — 시간을 재지 않고 결과가 같은지만 본다 (시간은 환경에 묶인다).
        let again = try await t.search(query: "배포")
        let third = try await t.search(query: "배포")
        XCTAssertEqual(again.hits.map(\.id), third.hits.map(\.id))
    }

    /// ★ 사이드카 재사용의 양성 대조 — 파스타 조각에 **질의 벡터 그 자체**를 심어 두면, 사이드카를
    ///   정말 읽을 때만 파스타가 1위(코사인 ≈ 1)가 된다. 안 읽으면 예전처럼 빨강이다.
    func testMeaningSearchConsumesSidecarVectorWhenHashMatches() async throws {
        guard let manifest = MCPTestSupport.modelOrAnnounceMissing() else { return }
        let embedder = try TextEmbedder(manifest: manifest)
        let qv = try embedder.embed(query: "배포 자동화 경험")
        let pasta = MCPTestSupport.sampleDocument().fragments.first { $0.id == "f-pasta" }!
        let sidecarURL = vault.appendingPathComponent(".clonie")
        let passage = ContentIndexer(sidecarURL: sidecarURL, embedder: embedder).passages(for: pasta)[0]
        let sidecar = ContentIndexStore(sidecarURL: sidecarURL)
        try sidecar.savePassages(["f-pasta": [.init(id: passage.id, startUTF16: passage.startUTF16,
                                                  endUTF16: passage.endUTF16, hash: passage.hash,
                                                  vector: ContentIndexStore.encode(vector: qv))]],
                                model: ContentIndexStore.ModelIdentity(manifest))
        let r = try await VaultTools(vaultURL: vault).search(query: "배포 자동화 경험", limit: 3)
        XCTAssertEqual(r.hits.first?.id, "f-pasta", "사이드카 벡터가 안 읽혔다: \(r.hits.map { "\($0.id) \($0.score ?? -1)" })")
        XCTAssertEqual(r.hits.first?.score ?? 0, 1.0 / Thresholds.simGreenDirect, accuracy: 0.01)
    }

    /// 해시가 안 맞으면 사이드카를 **안 믿는다** — 재계산으로 떨어져 파스타는 여전히 빨강.
    func testMeaningSearchIgnoresSidecarVectorWhenHashStale() async throws {
        guard let manifest = MCPTestSupport.modelOrAnnounceMissing() else { return }
        let embedder = try TextEmbedder(manifest: manifest)
        let qv = try embedder.embed(query: "배포 자동화 경험")
        let sidecar = ContentIndexStore(sidecarURL: vault.appendingPathComponent(".clonie"))
        try sidecar.saveVectors(["f-pasta": .init(hash: "sha256:stale", vector: ContentIndexStore.encode(vector: qv))],
                                model: ContentIndexStore.ModelIdentity(manifest))
        let r = try await VaultTools(vaultURL: vault).search(query: "배포 자동화 경험", limit: 3)
        XCTAssertEqual(r.hits.first?.id, "f-deploy")
        XCTAssertNotEqual(r.hits.first?.id, "f-pasta")
    }

    // MARK: - write

    func testSessionNoteUsesExistingTopicFolderAndReadRevisionForUpdates() async throws {
        let topic = vault.appendingPathComponent("프로젝트/Clonie", isDirectory: true)
        try FileManager.default.createDirectory(at: topic, withIntermediateDirectories: true)
        let t = tools()
        let path = "프로젝트/Clonie/세션에서 확인한 결정.md"
        let created = try await t.write(title: "세션에서 확인한 결정", body: "확인한 새 사실과 그 근거.", path: path)
        XCTAssertTrue(created.written)
        XCTAssertEqual(created.path, path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent(path).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent("wiki").path))
        do {
            _ = try await t.write(title: "읽지 않고 수정", body: "옛 내용을 추정한 수정", id: created.id)
            XCTFail("폴더가 달라졌다고 읽은 버전 확인을 건너뛰었다")
        } catch let error as VaultToolError { XCTAssertEqual(error, .invalidRevision) }
        let read = try await t.read(id: created.id)
        let updated = try await t.write(title: "확인 뒤 제목 수정", body: "명시적으로 요청한 수정.",
                                        id: read.id, revision: read.revision)
        XCTAssertEqual(updated.path, path)
        let back = try VaultStore(vaultURL: vault).load()
        XCTAssertEqual(back.document.fragments.count, 4)
        XCTAssertEqual(back.document.fragments.first { $0.id == created.id }?.body, "명시적으로 요청한 수정.")
    }

    func testSessionNoteCannotReplaceExistingPathOrWriteOriginalAndMetadataFolders() async throws {
        let topic = vault.appendingPathComponent("프로젝트", isDirectory: true)
        try FileManager.default.createDirectory(at: topic, withIntermediateDirectories: true)
        let existing = topic.appendingPathComponent("기존 기록.md")
        let original = Data("# 기존 기록\n\n사용자가 쓴 원문.\n".utf8)
        try original.write(to: existing)
        let t = tools()
        do {
            _ = try await t.write(title: "새 세션 기록", body: "덮어쓰면 안 되는 본문", force: true,
                                  path: "프로젝트/기존 기록.md")
            XCTFail("경로만 지정한 새 쓰기가 기존 파일을 덮었다")
        } catch let error as VaultPathError { XCTAssertEqual(error, .occupied("프로젝트/기존 기록.md")) }
        XCTAssertEqual(try Data(contentsOf: existing), original)
        for path in ["raw/new.md", "RAW/new.md", ".clonie/new.md", "프로젝트/../new.md"] {
            do {
                _ = try await t.write(title: "잘못된 위치", body: "본문", force: true, path: path)
                XCTFail("보호 대상이나 상위 경로에 썼다: \(path)")
            } catch let error as VaultToolError { XCTAssertEqual(error, .invalidOutputPath) }
        }
        XCTAssertEqual(try Data(contentsOf: existing), original)
    }

    func testWriteRejectsLegacyAndImportedOriginalMarkdownWithoutChangingBytes() async throws {
        let originals = [
            "raw/source.md",
            "자료/원본/source.md",
            "자료/원본/보관/source.md",
        ]
        var expectedBytes: [String: Data] = [:]
        for (index, path) in originals.enumerated() {
            let url = vault.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let bytes = Data("# 원본 \(index)\n\n사용자가 가져온 내용 \(index).\n".utf8)
            try bytes.write(to: url)
            expectedBytes[path] = bytes
        }

        let t = tools()
        let listed = try await t.list()
        for path in originals {
            guard let original = listed.fragments.first(where: { $0.path == path }) else {
                return XCTFail("원본 Markdown을 목록에서 찾지 못했다: \(path)")
            }
            do {
                _ = try await t.write(title: "원본 수정", body: "바뀌면 안 되는 내용", id: original.id)
                XCTFail("원본 Markdown을 수정했다: \(path)")
            } catch let error as VaultToolError {
                XCTAssertEqual(error, .readOnlySource(path))
            }
            XCTAssertEqual(try Data(contentsOf: vault.appendingPathComponent(path)), expectedBytes[path])
        }

        for path in ["raw/new.md", "자료/원본/new.md", "자료/원본/보관/new.md"] {
            do {
                _ = try await t.write(title: "원본 위치의 새 문서", body: "생성되면 안 되는 내용",
                                      force: true, path: path)
                XCTFail("원본 경로에 새 Markdown을 만들었다: \(path)")
            } catch let error as VaultToolError {
                XCTAssertEqual(error, .invalidOutputPath)
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent(path).path))
        }

        let allowedPath = "자료/지식/새 기록.md"
        let allowed = try await t.write(title: "새 기록", body: "일반 지식 경로에는 기록할 수 있다.",
                                        force: true, path: allowedPath)
        XCTAssertEqual(allowed.path, allowedPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent(allowedPath).path))
        for path in originals {
            XCTAssertEqual(try Data(contentsOf: vault.appendingPathComponent(path)), expectedBytes[path])
        }
    }

    func testWriteCreatesMarkdownWithMintedIdAndKeepsOthers() async throws {
        let r = try await tools().write(title: "MCP 가 쓴 조각", body: "Claude 가 대화에서 건진 한 문단.")
        XCTAssertTrue(r.written)
        XCTAssertTrue(r.id.hasPrefix("mcp-"), r.id)
        XCTAssertEqual(r.path, "MCP 가 쓴 조각.md")
        XCTAssertEqual(r.note, "created")
        let back = try VaultStore(vaultURL: vault).load()
        XCTAssertEqual(back.document.fragments.count, 4)
        XCTAssertEqual(back.document.fragments.first { $0.id == r.id }?.body, "Claude 가 대화에서 건진 한 문단.")
    }

    func testWriteWithExistingIdUpdatesInPlace() async throws {
        let t = tools()
        let read = try await t.read(id: "f-fail")
        let r = try await t.write(title: "장애를 놓친 날 (고침)", body: "새 본문", id: read.id,
                                  revision: read.revision)
        XCTAssertTrue(r.written)
        XCTAssertEqual(r.id, "f-fail")
        XCTAssertEqual(r.note, "updated")
        let back = try VaultStore(vaultURL: vault).load()
        XCTAssertEqual(back.document.fragments.count, 3, "수정이 새 조각을 만들었다")
        let f = back.document.fragments.first { $0.id == "f-fail" }!
        XCTAssertEqual(f.title, "장애를 놓친 날 (고침)")
        XCTAssertEqual(f.questionIds, ["q-2"], "question_ids 를 안 줬으면 칩은 그대로다")
    }

    func testWriteKeepsOnlyKnownQuestionIds() async throws {
        let r = try await tools().write(title: "칩 시험", body: "본문", questionIds: ["q-1", "q-없음"])
        let back = try VaultStore(vaultURL: vault).load()
        XCTAssertEqual(back.document.fragments.first { $0.id == r.id }?.questionIds, ["q-1"])
    }

    /// F2 — 고칠 때 준 `question_ids` 가 **전부 모르는 id** 면(빈 목록이 됐으면) 칩을 안 지운다.
    /// 그 통로는 「지우기」가 아니라 「모르는 것은 버린다」다 — 모델이 다 걸러졌다고 기존 칩까지
    /// 비우면 아는 것을 지우는 셈이 된다.
    func testWriteUpdateWithOnlyUnknownQuestionIdsLeavesExistingChipsAlone() async throws {
        let t = tools()
        let read = try await t.read(id: "f-fail")
        let r = try await t.write(title: "장애를 놓친 날 (고침)", body: "새 본문",
                                  questionIds: ["q-없음"], id: read.id, revision: read.revision)
        XCTAssertTrue(r.written)
        let back = try VaultStore(vaultURL: vault).load()
        XCTAssertEqual(back.document.fragments.first { $0.id == "f-fail" }?.questionIds, ["q-2"],
                       "모르는 id 만 왔는데 칩이 지워졌다")
    }

    func testWriteRejectsEmptyTitleOrBody() async throws {
        do { _ = try await tools().write(title: " ", body: "x"); XCTFail() } catch let e as VaultToolError { XCTAssertEqual(e, .emptyTitle) }
        do { _ = try await tools().write(title: "x", body: "\n"); XCTFail() } catch let e as VaultToolError { XCTAssertEqual(e, .emptyBody) }
    }

    func testWriteWithUnknownIdThrowsNotFoundInsteadOfCreating() async throws {
        do {
            _ = try await tools().write(title: "유령", body: "본문", id: "f-없음")
            XCTFail("없는 id 로 새 조각이 생겼다")
        } catch let e as VaultToolError {
            XCTAssertEqual(e, .notFound("f-없음"))
        }
        let back = try VaultStore(vaultURL: vault).load()
        XCTAssertEqual(back.document.fragments.count, 3, "거절했는데 파일이 늘었다")
    }

    /// ★ 둘째 문은 입력 기록을 모른다 — 그래서 **안 지워야** 한다 (#79, `CueDocument.asked == nil` 규율).
    ///
    /// ⚠ 이건 양성 대조가 아니라 **회귀 자물쇠**다. `write` 는 `load()` 한 문서를 그대로 `save()` 해서
    /// 지금은 저절로 통과한다. 언젠가 `write` 가 문서를 손으로 짜기 시작하면 그때 빨개진다 —
    /// 그 순간이 사람의 면접 기록 한 판이 조용히 사라지는 자리다.
    func testWriteNeverErasesTheAskedLog() async throws {
        let store = VaultStore(vaultURL: vault)
        try FileManager.default.createDirectory(at: store.sidecarURL, withIntermediateDirectories: true)
        let asked = #"{"schemaVersion":1,"entries":[{"id":"a-1","text":"왜 우리 회사인가","source":"sun","at":"2026-09-04T00:00:00Z"}]}"#
        try Data(asked.utf8).write(to: store.askedJSONURL)

        _ = try await tools().write(title: "MCP 가 쓴 조각", body: "Claude 가 대화에서 건진 한 문단.")

        XCTAssertTrue(FileManager.default.fileExists(atPath: store.askedJSONURL.path),
                      "둘째 문 저장이 asked.json 을 지웠다")
        XCTAssertEqual(try VaultStore(vaultURL: vault).load().document.asked?.map(\.id), ["a-1"])
    }

    func testWriteNeverTouchesIndexSidecar() async throws {
        _ = try await tools().write(title: "아무거나", body: "본문")
        let sidecar = VaultStore(vaultURL: vault).sidecarURL
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecar.appendingPathComponent("embeddings.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecar.appendingPathComponent("links.json").path))
    }

    /// 중복 문지기 — 모델이 있을 때만 잰다. 같은 글을 다시 쓰면 안 쓰고 비슷한 것을 돌려준다.
    func testWriteRefusesNearDuplicateUnlessForced() async throws {
        guard MCPTestSupport.modelOrAnnounceMissing() != nil else { return }
        let t = VaultTools(vaultURL: vault)
        let dup = try await t.write(title: "배포 스크립트를 갈아엎었다",
                                    body: "매번 손으로 하던 배포를 스크립트 한 줄로 줄였다. 실수가 사라졌다.")
        XCTAssertFalse(dup.written)
        XCTAssertEqual(dup.duplicates.first?.id, "f-deploy")
        XCTAssertNil(dup.duplicates.first?.light, "신호등은 순간의 측정이다 — 중복 문턱을 넘었다는 사실 자체는 언제나 g 라 신호가 아니다")
        XCTAssertNotNil(dup.note)
        let forced = try await t.write(title: "배포 스크립트를 갈아엎었다",
                                       body: "매번 손으로 하던 배포를 스크립트 한 줄로 줄였다. 실수가 사라졌다.",
                                       force: true)
        XCTAssertTrue(forced.written)
        XCTAssertNotEqual(forced.path, "배포 스크립트를 갈아엎었다.md", "같은 이름을 덮어쓰면 안 된다 — uniqueRelativePath")
    }
}
