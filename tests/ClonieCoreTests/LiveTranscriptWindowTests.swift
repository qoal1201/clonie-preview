import XCTest
@testable import ClonieCore

final class LiveTranscriptWindowTests: XCTestCase {
    private func result(_ id: Int, _ revision: Int, _ text: String, final: Bool = false) -> SpeechTranscriptionResult {
        SpeechTranscriptionResult(segmentID: id, revision: revision, text: text, isFinal: final)
    }

    func testPartialCorrectionReplacesTextAndFinalDoesNotDuplicateIt() {
        var window = LiveTranscriptWindow()
        window.ingest(result(0, 1, "배포를 취소"))
        window.ingest(result(0, 2, "배포를 취소하지 않았습니다."))
        XCTAssertEqual(window.volatile, "배포를 취소하지 않았습니다.")
        XCTAssertEqual(window.query, "배포를 취소하지 않았습니다")
        window.ingest(result(0, 3, "배포를 취소하지 않았습니다.", final: true))
        XCTAssertEqual(window.confirmed, "배포를 취소하지 않았습니다.")
        XCTAssertEqual(window.volatile, "")
        XCTAssertEqual(window.text, "배포를 취소하지 않았습니다.")
    }

    func testDelayedRevisionAndRepeatedFinalDoNotReplaceCurrentText() {
        var window = LiveTranscriptWindow()
        window.ingest(result(0, 3, "결과는 15건"))
        XCTAssertFalse(window.ingest(result(0, 2, "결과는 50건")))
        window.ingest(result(0, 4, "결과는 15건입니다.", final: true))
        XCTAssertFalse(window.ingest(result(0, 4, "결과는 15건입니다.", final: true)))
        XCTAssertFalse(window.ingest(result(0, 5, "결과는 50건입니다.", final: true)))
        XCTAssertEqual(window.text, "결과는 15건입니다.")
    }

    func testSeveralModelSegmentsRemainOneSearchUtterance() {
        var window = LiveTranscriptWindow()
        window.ingest(result(0, 1, "일정을 조정했고", final: true))
        window.ingest(result(1, 1, "결정 로그"))
        window.ingest(result(1, 2, "결정 로그를 남겼습니다.", final: true))
        XCTAssertEqual(window.text, "일정을 조정했고 결정 로그를 남겼습니다.")
        XCTAssertEqual(window.query, "일정을 조정했고 결정 로그를 남겼습니다")
    }

    func testLateFinalAfterSilenceDoesNotBecomeTheNextQuestion() {
        var window = LiveTranscriptWindow()
        window.ingest(result(0, 1, "기존 일정"))
        window.closeUtterance()
        XCTAssertTrue(window.isEmpty)
        window.ingest(result(1, 1, "다음 결정"))
        XCTAssertFalse(window.ingest(result(0, 2, "기존 일정입니다.", final: true)))
        XCTAssertEqual(window.text, "다음 결정")
    }

    func testChannelsAndNewSessionsHaveIndependentSegmentIDs() {
        var them = LiveTranscriptWindow()
        var me = LiveTranscriptWindow()
        them.ingest(result(0, 1, "어떤 경험인가요?", final: true))
        them.closeUtterance()
        me.ingest(result(0, 1, "제가 맡은 일은", final: true))
        XCTAssertEqual(me.text, "제가 맡은 일은")
        var nextSession = LiveTranscriptWindow()
        XCTAssertTrue(nextSession.ingest(result(0, 1, "새 대화입니다.", final: true)))
        XCTAssertEqual(nextSession.text, "새 대화입니다.")
    }

    func testEmptyRevisionCanWithdrawAnUnconfirmedGuess() {
        var window = LiveTranscriptWindow()
        window.ingest(result(0, 1, "감사합니다"))
        window.ingest(result(0, 2, ""))
        XCTAssertTrue(window.isEmpty)
    }
}
