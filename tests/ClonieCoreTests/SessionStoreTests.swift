import Foundation
import XCTest
@testable import ClonieCore

final class SessionStoreTests: XCTestCase {
    private var vault: URL!
    private var store: SessionStore!

    override func setUpWithError() throws {
        vault = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("clonie-session-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        store = SessionStore(vaultURL: vault)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: vault)
    }

    private func record(id: String = UUID().uuidString.lowercased(),
                        state: SessionState = .active,
                        startedAt: Double = 1_000) -> SessionRecord {
        SessionRecord(id: id, vaultPath: vault.path, startedAt: startedAt, state: state)
    }

    func testRoundTripPreservesRawRevisionsAndCorrection() async throws {
        var original = record()
        original.recordUtterance(
            id: "u-1", who: "them",
            revision: SessionTranscriptRevision(revision: 1, text: "원문", isFinal: false, time: 1.0,
                                                startTime: 0.5, endTime: 1.0),
            questionID: "q-1")
        original.recordUtterance(
            id: "u-1", who: "them",
            revision: SessionTranscriptRevision(revision: 2, text: "최종 원문", isFinal: true, time: 2.0))
        XCTAssertTrue(original.correctUtterance(id: "u-1", text: "사용자 정정", time: 3.0))

        try await store.save(original)
        let loaded = try await store.load(id: original.id)

        XCTAssertEqual(loaded, original)
        XCTAssertEqual(loaded.utterances[0].originalText, "최종 원문")
        XCTAssertEqual(loaded.utterances[0].text, "사용자 정정")
        XCTAssertEqual(loaded.utterances[0].revisions.count, 2)
        XCTAssertEqual(loaded.utterances[0].corrections.count, 1)
    }

    func testSameOrLowerRevisionDoesNotRewriteRawHistory() {
        var original = record()
        let first = SessionTranscriptRevision(revision: 2, text: "처음 받은 값", isFinal: false, time: 2)
        original.recordUtterance(id: "u-1", who: "me", revision: first)
        original.recordUtterance(id: "u-1", who: "me",
                                 revision: SessionTranscriptRevision(revision: 2, text: "중복", isFinal: true, time: 3))
        original.recordUtterance(id: "u-1", who: "me",
                                 revision: SessionTranscriptRevision(revision: 1, text: "늦은 낮은 값", isFinal: true, time: 4))
        original.recordUtterance(id: "u-1", who: "me",
                                 revision: SessionTranscriptRevision(revision: 3, text: "새 값", isFinal: true, time: 5))

        XCTAssertEqual(original.utterances[0].revisions, [first,
            SessionTranscriptRevision(revision: 3, text: "새 값", isFinal: true, time: 5)])
    }

    func testQuestionReviewAndRetrievalStateRoundTrip() async throws {
        var original = record(state: .completed)
        original.questionReviews = ["q-1": "done", "q-2": "open"]
        original.retrievals = [SessionRetrieval(id: "r-1", query: "예산", scope: "회의",
            questionID: "q-1", requestedAt: 1, completedAt: 2,
            status: "ready", displayedID: "doc-1", displayMode: "manual", how: "뜻")]
        try await store.save(original)
        let loaded = try await store.load(id: original.id)
        XCTAssertEqual(loaded, original)
        XCTAssertEqual(loaded.questionReviews["q-1"], "done")
        XCTAssertEqual(loaded.retrievals[0].displayedID, "doc-1")
        XCTAssertEqual(loaded.retrievals[0].how, "뜻")
    }

    func testQuestionEligibilityPreservesExistingLiveFillerGate() {
        XCTAssertFalse(SessionQuestionEligibility.isCandidate("네 알겠습니다"))
        XCTAssertFalse(SessionQuestionEligibility.isCandidate("네, 알겠습니다."))
        XCTAssertFalse(SessionQuestionEligibility.isCandidate("왜요"))
        XCTAssertFalse(SessionQuestionEligibility.isCandidate("예산"))
        XCTAssertTrue(SessionQuestionEligibility.isCandidate("예산은 얼마인가요"))
        XCTAssertTrue(SessionQuestionEligibility.isCandidate("네 예산은 얼마인가요"))
    }

    func testRecordReviewRoundTripPreservesCaptureAndExistingContent() async throws {
        var original = record(state: .interrupted)
        original.endedAt = 2_000
        original.recordUtterance(id: "q-1", who: "them",
            revision: SessionTranscriptRevision(revision: 1, text: "원문 질문", isFinal: true, time: 1))
        original.correctUtterance(id: "q-1", text: "정정 질문", time: 2)
        original.questionReviews = ["q-1": "done"]
        original.retrievals = [SessionRetrieval(id: "r-1", query: "질문", scope: "", requestedAt: 1)]
        original.drafts = [SessionDraft(id: "d-1", title: "초안", body: "작성 중", fragmentID: "f-1")]
        original.events = [SessionLifecycleEvent(kind: "captureFailed", time: 2)]
        for status in ["done", "open"] {
            original.reviewStatus = status
            try await store.save(original)
            let loaded = try await store.load(id: original.id)
            XCTAssertEqual(loaded, original)
            XCTAssertEqual(loaded.state, .interrupted)
            XCTAssertEqual(loaded.reviewStatus, status)
        }
    }

    func testOlderJSONDefaultsQuestionReviewAndRetrievalState() throws {
        let data = Data("""
        {"schemaVersion":1,"id":"legacy","vaultPath":"/vault","startedAt":1,"state":"completed",
         "retrievals":[{"id":"r-1","query":"예산","scope":"","requestedAt":1,"candidates":[]}]}
        """.utf8)
        let loaded = try JSONDecoder().decode(SessionRecord.self, from: data)
        XCTAssertNil(loaded.reviewStatus)
        XCTAssertNotEqual(loaded.reviewStatus, "done")
        XCTAssertEqual(loaded.questionReviews, [:])
        XCTAssertNil(loaded.retrievals[0].questionID)
        XCTAssertNil(loaded.retrievals[0].status)
        XCTAssertNil(loaded.retrievals[0].displayedID)
        XCTAssertNil(loaded.retrievals[0].displayMode)
        XCTAssertNil(loaded.retrievals[0].how)
    }

    func testWhitespaceCorrectionIsRejected() {
        var original = record()
        original.recordUtterance(id: "u-1", who: "me",
                                 revision: SessionTranscriptRevision(revision: 1, text: "원문", isFinal: true, time: 1))

        XCTAssertFalse(original.correctUtterance(id: "u-1", text: " \n\t", time: 2))
        XCTAssertEqual(original.utterances[0].corrections, [])
    }

    func testRecoveryMarksOnlyRestartStatesAndIsIdempotent() async throws {
        let recoverable: [SessionState] = [.preparing, .active, .paused, .finishing]
        for (offset, state) in recoverable.enumerated() {
            try await store.save(record(state: state, startedAt: Double(offset)))
        }
        try await store.save(record(state: .completed, startedAt: 10))
        try await store.save(record(state: .interrupted, startedAt: 11))

        let recoveredCount = try await store.recoverInterrupted()
        XCTAssertEqual(recoveredCount, recoverable.count)
        let loaded = try await store.list()
        XCTAssertEqual(loaded.filter { $0.state == .interrupted }.count, recoverable.count + 1)
        for session in loaded where session.startedAt < 10 {
            XCTAssertEqual(session.state, .interrupted)
            XCTAssertNotNil(session.endedAt)
            XCTAssertEqual(session.events.last?.kind, "interrupted")
        }
        let secondRecoveryCount = try await store.recoverInterrupted()
        XCTAssertEqual(secondRecoveryCount, 0)
    }

    func testListIsNewestFirstAndCorruptFileIsReportedWithoutBlockingValidRecords() async throws {
        let old = record(startedAt: 1)
        let newest = record(startedAt: 2)
        try await store.save(old)
        try await store.save(newest)
        let listed = try await store.list()
        XCTAssertEqual(listed.map(\.id), [newest.id, old.id])

        let corruptURL = vault.appendingPathComponent(".clonie/sessions/\(UUID().uuidString.lowercased()).json")
        let corrupt = Data("{깨진 JSON".utf8)
        try corrupt.write(to: corruptURL, options: .atomic)
        let result = try await store.listWithIssues()
        XCTAssertEqual(result.records.map(\.id), [newest.id, old.id])
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertEqual(URL(fileURLWithPath: result.issues[0].path).lastPathComponent,
                       corruptURL.lastPathComponent)
        XCTAssertFalse(result.issues[0].message.isEmpty)
        let tolerantList = try await store.list()
        XCTAssertEqual(tolerantList.map(\.id), [newest.id, old.id])
        XCTAssertEqual(try Data(contentsOf: corruptURL), corrupt)
    }

    func testCorruptFileDoesNotBlockInterruptedRecoveryAndRemainsUnchanged() async throws {
        let active = record(state: .active, startedAt: 2)
        let completed = record(state: .completed, startedAt: 1)
        try await store.save(active)
        try await store.save(completed)

        let corruptURL = vault.appendingPathComponent(".clonie/sessions/\(UUID().uuidString.lowercased()).json")
        let corrupt = Data("{unfinished".utf8)
        try corrupt.write(to: corruptURL, options: .atomic)

        let recoveredCount = try await store.recoverInterrupted()
        XCTAssertEqual(recoveredCount, 1)
        let result = try await store.listWithIssues()
        XCTAssertEqual(result.records.map(\.id), [active.id, completed.id])
        XCTAssertEqual(result.records.first { $0.id == active.id }?.state, .interrupted)
        XCTAssertEqual(result.records.first { $0.id == completed.id }?.state, .completed)
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertEqual(URL(fileURLWithPath: result.issues[0].path).lastPathComponent,
                       corruptURL.lastPathComponent)
        XCTAssertFalse(result.issues[0].message.isEmpty)
        XCTAssertEqual(try Data(contentsOf: corruptURL), corrupt)
    }

    func testVaultBindingAndCanonicalIDRejectPathTraversal() async throws {
        let wrongVault = record()
        var mismatched = wrongVault
        mismatched.vaultPath = vault.appendingPathComponent("other", isDirectory: true).path
        do {
            try await store.save(mismatched)
            XCTFail("a record bound to another vault must be rejected")
        } catch {
            // Expected.
        }

        var traversal = wrongVault
        traversal.id = "../outside"
        do {
            try await store.save(traversal)
            XCTFail("a traversal id must be rejected")
        } catch {
            // Expected.
        }

        let missingRoot = vault.appendingPathComponent("missing", isDirectory: true)
        let missingStore = SessionStore(vaultURL: missingRoot)
        do {
            try await missingStore.save(record(id: UUID().uuidString.lowercased()))
            XCTFail("a missing vault must not be created")
        } catch {
            // Expected.
        }
    }

    func testSymlinkedSessionsDirectoryAndRecordCannotWriteOutsideVault() async throws {
        let outside = vault.deletingLastPathComponent()
            .appendingPathComponent("clonie-session-outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }

        let metadata = vault.appendingPathComponent(".clonie", isDirectory: true)
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        let sessions = metadata.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: sessions, withDestinationURL: outside)
        let blocked = record()
        do {
            try await store.save(blocked)
            XCTFail("a symlinked sessions folder must be rejected")
        } catch {
            // Expected.
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path), [])

        try FileManager.default.removeItem(at: sessions)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let linkID = UUID().uuidString.lowercased()
        let target = outside.appendingPathComponent("target.json")
        try Data("outside".utf8).write(to: target)
        let link = sessions.appendingPathComponent("\(linkID).json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        do {
            try await store.save(record(id: linkID))
            XCTFail("a symlinked record must be rejected")
        } catch {
            // Expected.
        }
        XCTAssertEqual(try Data(contentsOf: target), Data("outside".utf8))
    }

    func testSessionSaveLeavesMarkdownUntouched() async throws {
        let markdown = vault.appendingPathComponent("note.md")
        let before = Data("사용자 문서\n".utf8)
        try before.write(to: markdown)

        var session = record(state: .completed)
        session.questionReviews = ["q-1": "done"]
        try await store.save(session)
        _ = try await store.recoverInterrupted()

        XCTAssertEqual(try Data(contentsOf: markdown), before)
    }
}
