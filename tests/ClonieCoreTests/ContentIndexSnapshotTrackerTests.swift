import XCTest
@testable import ClonieCore

final class ContentIndexSnapshotTrackerTests: XCTestCase {
    private func document(id: String = "a", body: String = "본문",
                          asked: [AskedEntry]? = nil) -> CueDocument {
        CueDocument(
            questions: [Question(id: "q", text: "질문")],
            fragments: [Fragment(id: id, title: "제목", body: body, questionIds: ["q"],
                                 createdAt: Date(timeIntervalSince1970: 1),
                                 updatedAt: Date(timeIntervalSince1970: 2))],
            asked: asked)
    }

    func testAskedOnlyChangeReusesPendingAndReadySnapshot() {
        var tracker = ContentIndexSnapshotTracker()
        let original = ContentIndexSnapshot(document: document())
        let askedOnly = ContentIndexSnapshot(document: document(asked: []))

        XCTAssertTrue(tracker.begin(original))
        XCTAssertFalse(tracker.begin(askedOnly), "같은 입력을 색인 중인데 asked 저장이 중복 요청했다")
        tracker.markReady(original)
        XCTAssertFalse(tracker.begin(askedOnly), "준비된 입력인데 asked 저장이 다시 색인했다")
    }

    func testFragmentAndQuestionChangesStartNewIndex() {
        var tracker = ContentIndexSnapshotTracker()
        let original = ContentIndexSnapshot(document: document())
        XCTAssertTrue(tracker.begin(original))
        tracker.markReady(original)

        let changedBody = ContentIndexSnapshot(document: document(body: "바뀐 본문"))
        XCTAssertTrue(tracker.begin(changedBody))
        tracker.markReady(changedBody)

        var changedQuestion = document(body: "바뀐 본문")
        changedQuestion.questions[0].text = "바뀐 질문"
        XCTAssertTrue(tracker.begin(ContentIndexSnapshot(document: changedQuestion)))

        tracker.markFailed(ContentIndexSnapshot(document: changedQuestion))
        XCTAssertTrue(tracker.begin(ContentIndexSnapshot(document: document(id: "옮겨진-경로", body: "바뀐 본문"))))
    }

    func testFailedSnapshotRetriesAndResetInvalidatesReadySnapshot() {
        var tracker = ContentIndexSnapshotTracker()
        let snapshot = ContentIndexSnapshot(document: document())

        XCTAssertTrue(tracker.begin(snapshot))
        tracker.markFailed(snapshot)
        XCTAssertTrue(tracker.begin(snapshot), "실패한 입력을 다시 시도하지 않았다")
        tracker.markReady(snapshot)
        XCTAssertFalse(tracker.begin(snapshot))
        tracker.reset()
        XCTAssertTrue(tracker.begin(snapshot), "볼트 재연결 뒤 이전 ready 입력을 재사용했다")
    }

    func testDifferentPendingSnapshotSupersedesAnOlderReadySnapshot() {
        var tracker = ContentIndexSnapshotTracker()
        let old = ContentIndexSnapshot(document: document())
        let changed = ContentIndexSnapshot(document: document(body: "새 본문"))

        XCTAssertTrue(tracker.begin(old))
        tracker.markReady(old)
        XCTAssertTrue(tracker.begin(changed))
        tracker.markFailed(changed)
        XCTAssertTrue(tracker.begin(old), "새 입력 실패 뒤 비워진 옛 입력 벡터를 다시 만들지 않았다")
    }
}
