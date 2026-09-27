import XCTest
@testable import ClonieCore

final class VaultProposalsTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("clonie-proposals-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }
    func fragment(_ id: String = "one") -> Fragment {
        Fragment(id: id, title: "원문", body: "보존할 내용", questionIds: [], createdAt: Date(), updatedAt: Date())
    }
    func testPendingInvisibleThenPartialApprovalAndRejection() throws {
        let store = VaultStore(vaultURL: root)
        let first = try store.propose(fragment: fragment(), before: nil, base: nil, path: "first.md", taskID: nil, taskTitle: "작업")
        let second = try store.propose(fragment: fragment("two"), before: nil, base: nil, path: "second.md", taskID: first.taskID, taskTitle: "")
        XCTAssertTrue(try store.load().document.fragments.isEmpty)
        XCTAssertEqual(try store.proposals().count, 2)
        XCTAssertEqual(second.taskTitle, "작업")
        try store.approveProposal(id: first.id, body: "사람이 수정한 내용")
        XCTAssertEqual(try store.load().document.fragments.first?.body, "사람이 수정한 내용")
        XCTAssertEqual(try store.proposals().map(\.id), [second.id])
        XCTAssertEqual(try store.proposals().first?.taskTitle, "작업")
        try store.rejectProposal(id: second.id)
        XCTAssertTrue(try store.proposals().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("second.md").path))
        XCTAssertTrue(try store.documentChanges().isEmpty)
    }
    func testDraftSurvivesReopenWithoutWritingMarkdownAndApprovalUsesDraft() throws {
        let store = VaultStore(vaultURL: root)
        let p = try store.propose(fragment: fragment(), before: nil, base: nil, path: "draft.md", taskID: nil, taskTitle: "작업")
        try store.saveProposalDraft(id: p.id, title: "고친 제목", body: "사람이 보완한 초안")
        let reopened = VaultStore(vaultURL: root)
        let saved = try XCTUnwrap(reopened.proposals().first)
        XCTAssertEqual(saved.draftBody, "사람이 보완한 초안")
        XCTAssertEqual(saved.fragment.body, "보존할 내용")
        XCTAssertTrue(try reopened.load().document.fragments.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("draft.md").path))
        try reopened.approveProposal(id: p.id)
        XCTAssertEqual(try reopened.load().document.fragments.first?.body, "사람이 보완한 초안")
        XCTAssertEqual(try reopened.load().document.fragments.first?.title, "고친 제목")
        XCTAssertThrowsError(try reopened.saveProposalDraft(id: p.id, title: "늦은 저장", body: "부활 금지"))
        XCTAssertTrue(try reopened.proposals().isEmpty)
    }
    func testEmptyDraftCanBeKeptButNotApproved() throws {
        let store = VaultStore(vaultURL: root)
        let p = try store.propose(fragment: fragment(), before: nil, base: nil, path: "draft.md", taskID: nil, taskTitle: "작업")
        try store.saveProposalDraft(id: p.id, title: "", body: "")
        XCTAssertEqual(try store.proposals().first?.draftBody, "")
        for (title, body) in [("   ", "본문"), ("제목", " \n ")] {
            XCTAssertThrowsError(try store.approveProposal(id: p.id, title: title, body: body)) { error in
                XCTAssertEqual(error as? VaultMutationError, .incompleteProposal)
                XCTAssertEqual(error.localizedDescription, "제안 제목과 본문을 모두 입력해 주세요.")
            }
            XCTAssertTrue(try store.load().document.fragments.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("draft.md").path))
            XCTAssertEqual(try store.proposals().map(\.id), [p.id])
            XCTAssertEqual(try store.proposals().first?.applying, false)
        }
        try store.rejectProposal(id: p.id)
        XCTAssertTrue(try store.proposals().isEmpty)
    }
    func testChangedOriginalBlocksApprovalAndPreservesPending() throws {
        let store = VaultStore(vaultURL: root)
        var doc = CueDocument()
        doc.fragments = [fragment()]
        try store.save(doc)
        let baseline = try store.loadVersioned()
        var proposed = doc.fragments[0]; proposed.body = "AI 제안"
        let p = try store.propose(fragment: proposed, before: doc.fragments[0], base: baseline.revision.files["one"],
                                  path: baseline.result.paths["one"], taskID: nil, taskTitle: "수정")
        doc.fragments[0].body = "새 외부 편집"
        try store.save(doc)
        XCTAssertThrowsError(try store.approveProposal(id: p.id))
        XCTAssertEqual(try store.load().document.fragments[0].body, "새 외부 편집")
        XCTAssertEqual(try store.proposals().count, 1)
    }
    func testTraversalAndSymlinkProposalDirectoryRejected() throws {
        let store = VaultStore(vaultURL: root)
        XCTAssertThrowsError(try store.propose(fragment: fragment(), before: nil, base: nil, path: "../escape.md", taskID: nil, taskTitle: ""))
        try FileManager.default.createDirectory(at: store.sidecarURL, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: store.proposalsURL, withDestinationURL: root)
        XCTAssertThrowsError(try store.propose(fragment: fragment(), before: nil, base: nil, path: "file.md", taskID: nil, taskTitle: ""))
    }
}
