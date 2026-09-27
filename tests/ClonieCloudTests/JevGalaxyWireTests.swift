import XCTest
@testable import ClonieCloud

final class JevGalaxyWireTests: XCTestCase {
    func testBoundedExcerptsBatchQuestionsAndNoMatchKeepOriginalDocumentBinding() throws {
        let document = JevGalaxyWire.Document(id: "notes/검토", title: "정렬", text: String(repeating: "가", count: 2000))
        let prepared = try JevGalaxyWire.prepare(documents: [document], anchors: [document], apiKey: " secret ")
        XCTAssertEqual(prepared.request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: prepared.request.httpBody!) as? [String: Any])
        XCTAssertFalse(String(decoding: prepared.request.httpBody!, as: UTF8.self).contains("secret"))
        let state = try XCTUnwrap(json["state"] as? [String: Any])
        let docs = try XCTUnwrap(state["documents"] as? [[String: Any]])
        XCTAssertEqual(docs[0]["truncated"] as? Bool, true)
        XCTAssertLessThanOrEqual((docs[0]["excerpt"] as! String).utf8.count, 1800)
        let response = Data(#"{"model":"jev-1.13.0","answers":{"q0":{"type":"choice","choice":"none","probabilities":{"a0":0.1,"none":0.9},"confidence":0.8}}}"#.utf8)
        let rows = try JevGalaxyWire.parse(response, for: prepared)
        XCTAssertEqual(rows[0].documentID, document.id)
        XCTAssertEqual(rows[0].group, -1)
        XCTAssertEqual(rows[0].probabilities, [0.1, 0.9])
    }

    func testWrongQuestionIDsUnknownOptionsAndBrokenDistributionsAreRejected() throws {
        let document = JevGalaxyWire.Document(id: "a", title: "A", text: "본문")
        let request = try JevGalaxyWire.prepare(documents: [document], anchors: [document], apiKey: "key")
        let valid = #"{"model":"jev-1.13.0","answers":{"q0":{"type":"choice","choice":"a0","probabilities":{"a0":0.8,"none":0.2},"confidence":0.8}}}"#
        for broken in [valid.replacingOccurrences(of: "q0", with: "q1"),
                       valid.replacingOccurrences(of: "a0", with: "a9"),
                       valid.replacingOccurrences(of: "0.2", with: "0.8"),
                       valid.replacingOccurrences(of: "jev-1.13.0", with: "wrong-model")] {
            XCTAssertThrowsError(try JevGalaxyWire.parse(Data(broken.utf8), for: request))
        }
    }
}
