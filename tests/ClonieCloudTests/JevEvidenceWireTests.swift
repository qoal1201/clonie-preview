import XCTest
@testable import ClonieCloud

final class JevEvidenceWireTests: XCTestCase {
    func testRequestUsesOpaqueQuestionIDsAndResponseKeepsCandidateRevisionBinding() throws {
        let candidates = [
            JevEvidenceWire.Candidate(
                id: "folder/a.md#결정?",
                revision: "sha256:first",
                text: "첫 후보", title: "제품 의도"
            ),
            JevEvidenceWire.Candidate(
                id: "한글 공백 / [둘]",
                revision: "mtime:2026-09-20T01:02:03Z",
                text: "둘째 후보"
            )
        ]
        let prepared = try JevEvidenceWire.prepare(
            query: "왜 미뤘나요?",
            candidates: candidates,
            apiKey: "  secret-token  "
        )

        XCTAssertEqual(prepared.purpose, .evidence)
        XCTAssertEqual(Set(prepared.allowedLabels.map(\.rawValue)), evidenceLabelNames)
        XCTAssertEqual(prepared.urlRequest.url, JevEvidenceWire.endpoint)
        XCTAssertEqual(prepared.urlRequest.httpMethod, "POST")
        XCTAssertEqual(prepared.urlRequest.timeoutInterval, 30)
        XCTAssertEqual(prepared.urlRequest.value(forHTTPHeaderField: "Authorization"),
                       "Bearer secret-token")
        XCTAssertEqual(prepared.urlRequest.value(forHTTPHeaderField: "Content-Type"),
                       "application/json")

        let body = try XCTUnwrap(prepared.urlRequest.httpBody)
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("secret-token"))
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        XCTAssertEqual(json["model"] as? String, "jev-1.13.0")
        let state = try XCTUnwrap(json["state"] as? [String: Any])
        XCTAssertEqual(state["query"] as? String, "왜 미뤘나요?")
        let encodedCandidates = try XCTUnwrap(state["candidates"] as? [[String: Any]])
        XCTAssertEqual(encodedCandidates.map { $0["id"] as? String }, candidates.map(\.id))
        XCTAssertEqual(encodedCandidates.map { $0["title"] as? String }, candidates.map(\.title))
        XCTAssertEqual(encodedCandidates.map { $0["revision"] as? String },
                       candidates.map(\.revision))

        let questions = try XCTUnwrap(json["questions"] as? [String: Any])
        XCTAssertEqual(Set(questions.keys), ["q0", "q1"])
        XCTAssertTrue(Set(questions.keys).isDisjoint(with: Set(candidates.map(\.id))))
        for index in candidates.indices {
            let question = try XCTUnwrap(questions["q\(index)"] as? [String: Any])
            XCTAssertEqual(question["type"] as? String, "choice")
            XCTAssertTrue((question["instructions"] as? String)?.contains(
                "`candidates[\(index)].text`"
            ) == true)
            let criteria = try XCTUnwrap(question["criteria"] as? [String: Any])
            XCTAssertEqual(Set(criteria.keys), evidenceLabelNames)
        }

        let result = try JevEvidenceWire.parseResponse(
            responseData(answers: [
                "q0": answer(choice: "direct", probabilities: probabilities(direct: 0.6)),
                "q1": answer(choice: "unrelated", probabilities: probabilities(unrelated: 0.6))
            ]),
            for: prepared
        )
        XCTAssertEqual(result.model, "jev-1.13.0")
        XCTAssertEqual(result.usage, .init(inputTokens: 44, outputTokens: 12))
        XCTAssertEqual(result.assessments.map(\.candidateID), candidates.map(\.id))
        XCTAssertEqual(result.assessments.map(\.revision), candidates.map(\.revision))
        XCTAssertEqual(result.assessments.map(\.label), [.direct, .unrelated])
    }

    func testSupplementRequestPreservesNoteUsesOwnLabelsAndKeepsCandidateBinding() throws {
        let note = "이 선택지는 아직 질문입니다. 다음 회의에서 A안을 검토할까요?\n원문 그대로 보냅니다."
        let candidates = [
            JevEvidenceWire.Candidate(
                id: "folder/decision.md#제안?",
                revision: "sha256:decision",
                text: "현재 B안이 승인된 결정이다.",
                title: "결정 기록"
            ),
            JevEvidenceWire.Candidate(
                id: "한글 공백 / 둘",
                revision: "mtime:second",
                text: "다음 회의 안건을 정리한다."
            )
        ]

        let prepared = try JevEvidenceWire.prepareSupplement(
            note: note,
            candidates: candidates,
            apiKey: "key"
        )

        XCTAssertEqual(prepared.purpose, .supplement)
        XCTAssertEqual(Set(prepared.allowedLabels.map(\.rawValue)), supplementLabelNames)
        let body = try XCTUnwrap(prepared.urlRequest.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let state = try XCTUnwrap(json["state"] as? [String: Any])
        XCTAssertEqual(state["note"] as? String, note)
        XCTAssertNil(state["query"])

        let encodedCandidates = try XCTUnwrap(state["candidates"] as? [[String: Any]])
        XCTAssertEqual(encodedCandidates.map { $0["id"] as? String }, candidates.map(\.id))
        XCTAssertEqual(encodedCandidates.map { $0["revision"] as? String },
                       candidates.map(\.revision))
        XCTAssertEqual(encodedCandidates.map { $0["text"] as? String }, candidates.map(\.text))

        let questions = try XCTUnwrap(json["questions"] as? [String: Any])
        XCTAssertEqual(Set(questions.keys), ["q0", "q1"])
        for index in candidates.indices {
            let question = try XCTUnwrap(questions["q\(index)"] as? [String: Any])
            let instructions = try XCTUnwrap(question["instructions"] as? String)
            XCTAssertTrue(instructions.contains("`note`"))
            XCTAssertTrue(instructions.contains("proposal"))
            XCTAssertTrue(instructions.contains("Never interpret"))
            let criteria = try XCTUnwrap(question["criteria"] as? [String: Any])
            XCTAssertEqual(Set(criteria.keys), supplementLabelNames)
            XCTAssertTrue((criteria["supplement"] as? String)?.contains("proposals") == true)
            XCTAssertTrue((criteria["conflict"] as? String)?.contains("SAME fact or decision") == true)
        }

        let result = try JevEvidenceWire.parseResponse(
            responseData(answers: [
                "q0": answer(
                    choice: "uncertain",
                    probabilities: supplementProbabilities(uncertain: 0.6)
                ),
                "q1": answer(
                    choice: "supplement",
                    probabilities: supplementProbabilities(supplement: 0.6)
                )
            ]),
            for: prepared
        )
        XCTAssertEqual(result.assessments.map(\.candidateID), candidates.map(\.id))
        XCTAssertEqual(result.assessments.map(\.revision), candidates.map(\.revision))
        XCTAssertEqual(result.assessments.map(\.label), [.uncertain, .supplement])
    }

    func testResponseRejectsLabelsAndProbabilitySetsFromAnotherPurpose() throws {
        let evidence = try makePrepared()
        assertError(.invalidChoice) {
            try JevEvidenceWire.parseResponse(
                responseData(answers: [
                    "q0": answer(
                        choice: "supplement",
                        probabilities: supplementProbabilities(supplement: 0.6)
                    )
                ]),
                for: evidence
            )
        }

        let supplement = try JevEvidenceWire.prepareSupplement(
            note: "새 정보",
            candidates: [.init(id: "doc", revision: "rev", text: "기존 정보")],
            apiKey: "key"
        )
        assertError(.invalidChoice) {
            try JevEvidenceWire.parseResponse(
                responseData(answers: [
                    "q0": answer(choice: "direct", probabilities: probabilities(direct: 0.6))
                ]),
                for: supplement
            )
        }
        assertError(.invalidProbabilities) {
            try JevEvidenceWire.parseResponse(
                responseData(answers: [
                    "q0": answer(choice: "unrelated", probabilities: probabilities(unrelated: 0.6))
                ]),
                for: supplement
            )
        }
    }

    func testRerankExcerptPreservesMultipleSourceSpansWithinKoreanByteBudget() throws {
        let parts = [String(repeating: "앞부분 ", count: 300),
                     "핵심 결정: " + String(repeating: "같은 저장소 ", count: 300),
                     "다음 활용: " + String(repeating: "다시 찾는다 ", count: 300)]
        let result = try XCTUnwrap(JevEvidenceWire.rerankExcerpt(body: parts.joined(separator: "\n\n"), excerpts: parts))
        XCTAssertLessThanOrEqual(result.utf8.count, 1_800)
        XCTAssertTrue(result.contains("핵심 결정:"))
        XCTAssertTrue(result.contains("다음 활용:"))
        XCTAssertEqual(result.components(separatedBy: "[omitted]").count, 3)
        XCTAssertNil(JevEvidenceWire.rerankExcerpt(body: parts[0], excerpts: parts))
        XCTAssertNil(JevEvidenceWire.rerankExcerpt(body: "본문", excerpts: []))
        XCTAssertNil(JevEvidenceWire.rerankExcerpt(body: "본문", excerpts: [""]))
        XCTAssertNil(JevEvidenceWire.rerankExcerpt(body: "본문", excerpts: Array(repeating: "본문", count: 4)))
    }

    func testRerankUsesScoreAndBindsNormalizedAssessmentsToCandidates() throws {
        let longSource = String(repeating: "원", count: 10_000)
        let candidates = [
            JevEvidenceWire.Candidate(id: "a", revision: "rev", text: "첫 후보", title: "A"),
            JevEvidenceWire.Candidate(id: "b", revision: "rev", text: "둘째 후보", title: "B")
        ]
        let prepared = try JevEvidenceWire.prepareRerank(
            query: "선택한 문서와 함께 읽을 자료",
            selectedSource: .init(id: "source", revision: "rev", text: longSource,
                                  title: "선택 원문"),
            candidates: candidates,
            apiKey: "key"
        )

        XCTAssertEqual(prepared.purpose, .rerank)
        XCTAssertTrue(prepared.allowedLabels.isEmpty)
        let body = try XCTUnwrap(prepared.urlRequest.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let state = try XCTUnwrap(json["state"] as? [String: Any])
        XCTAssertEqual(state["query"] as? String, "선택한 문서와 함께 읽을 자료")
        let source = try XCTUnwrap(state["source"] as? [String: Any])
        XCTAssertLessThanOrEqual(try XCTUnwrap(source["text"] as? String).utf8.count,
                               JevEvidenceWire.maximumRerankSourceTextBytes)
        XCTAssertEqual(source["truncated"] as? Bool, true)
        let encodedCandidates = try XCTUnwrap(state["candidates"] as? [[String: Any]])
        XCTAssertTrue(encodedCandidates.allSatisfy {
            ($0["text"] as? String)?.utf8.count ?? Int.max <=
                JevEvidenceWire.maximumRerankCandidateTextBytes
        })
        let questions = try XCTUnwrap(json["questions"] as? [String: Any])
        for index in candidates.indices {
            let question = try XCTUnwrap(questions["q\(index)"] as? [String: Any])
            XCTAssertEqual(question["type"] as? String, "score")
            XCTAssertEqual((question["criteria"] as? [Any])?.count, 5)
        }

        let result = try JevEvidenceWire.parseResponse(
            responseData(answers: [
                "q0": scoreAnswer(score: 3.2, confidence: 0.7),
                "q1": scoreAnswer(score: 0, confidence: 1)
            ]),
            for: prepared
        )
        XCTAssertEqual(result.assessments.map(\.candidateID), ["a", "b"])
        XCTAssertEqual(result.assessments.map(\.revision), ["rev", "rev"])
        XCTAssertEqual(try XCTUnwrap(result.assessments[0].score), 0.8, accuracy: 0.000_001)
        XCTAssertEqual(result.assessments[1].score, 0)
        XCTAssertEqual(result.assessments.map(\.confidence), [0.7, 1])
        XCTAssertTrue(result.assessments.allSatisfy { $0.label == nil })
    }

    func testRerankBoundsLongKoreanStateByUTF8WithoutChangingBindings() throws {
        let longKorean = String(repeating: "가나다라마바사", count: 1_500)
        let candidates = (0..<8).map {
            JevEvidenceWire.Candidate(id: "문서-\($0)", revision: "rev-\($0)",
                                      text: longKorean, title: longKorean)
        }
        let prepared = try JevEvidenceWire.prepareRerank(
            query: "제품 전체 흐름과 중요한 결정",
            selectedSource: .init(id: "기준", revision: "source-rev", text: longKorean,
                                  title: longKorean),
            candidates: candidates,
            apiKey: "key"
        )
        let body = try XCTUnwrap(prepared.urlRequest.httpBody)
        let request = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let state = try XCTUnwrap(request["state"] as? [String: Any])
        let stateData = try JSONSerialization.data(withJSONObject: state)
        XCTAssertLessThanOrEqual(stateData.count, JevEvidenceWire.maximumRerankStateBytes)
        let encodedCandidates = try XCTUnwrap(state["candidates"] as? [[String: Any]])
        XCTAssertEqual(encodedCandidates.count, 8)
        XCTAssertTrue(encodedCandidates.allSatisfy {
            ($0["text"] as? String)?.utf8.count ?? Int.max <=
                JevEvidenceWire.maximumRerankCandidateTextBytes &&
            ($0["title"] as? String)?.utf8.count ?? Int.max <=
                JevEvidenceWire.maximumRerankTitleBytes &&
            $0["truncated"] as? Bool == true
        })

        let result = try JevEvidenceWire.parseResponse(
            responseData(answers: Dictionary(uniqueKeysWithValues: (0..<8).map {
                ("q\($0)", scoreAnswer(score: Double($0 % 5)))
            })),
            for: prepared
        )
        XCTAssertEqual(result.assessments.map(\.candidateID), candidates.map(\.id))
        XCTAssertEqual(result.assessments.map(\.revision), candidates.map(\.revision))
    }

    func testRerankRejectsStateOverByteBudgetWithoutTruncatingQuery() throws {
        let candidates = (0..<8).map {
            JevEvidenceWire.Candidate(id: "d\($0)", revision: "r",
                                      text: String(repeating: "한", count: 4_000),
                                      title: String(repeating: "제", count: 1_000))
        }
        assertError(.rerankStateTooLong) {
            try JevEvidenceWire.prepareRerank(
                query: String(repeating: "🪐", count: JevEvidenceWire.maximumQueryLength),
                selectedSource: .init(id: "source", revision: "r",
                                      text: String(repeating: "원", count: 4_000),
                                      title: "원문"),
                candidates: candidates,
                apiKey: "key"
            )
        }
    }

    func testRerankRejectsMalformedScoreContractAndPurposeIsolation() throws {
        let rerank = try JevEvidenceWire.prepareRerank(
            query: "질문",
            candidates: [.init(id: "a", revision: "r", text: "후보")],
            apiKey: "key"
        )
        assertError(.invalidAnswerType) {
            try JevEvidenceWire.parseResponse(
                responseData(answers: [
                    "q0": answer(choice: "direct", probabilities: probabilities(direct: 0.6))
                ]), for: rerank)
        }
        assertError(.invalidScore) {
            try JevEvidenceWire.parseResponse(
                responseData(answers: ["q0": scoreAnswer(score: 4.01)]), for: rerank)
        }
        var badLegend = scoreAnswer(score: 2)
        badLegend["legend"] = ["0": "invented"]
        assertError(.invalidLegend) {
            try JevEvidenceWire.parseResponse(
                responseData(answers: ["q0": badLegend]), for: rerank)
        }
        var badProbabilities = scoreAnswer(score: 2)
        badProbabilities["probabilities"] = ["0": 0.5, "1": 0.5]
        assertError(.invalidProbabilities) {
            try JevEvidenceWire.parseResponse(
                responseData(answers: ["q0": badProbabilities]), for: rerank)
        }
        var inconsistentScore = scoreAnswer(score: 2)
        inconsistentScore["score"] = 3.5
        inconsistentScore["untrusted"] = "본문이나 서버 문구를 기록하면 안 됨"
        let inconsistentData = try responseData(answers: ["q0": inconsistentScore])
        let diagnostics = JevEvidenceWire.safeResponseDiagnostics(inconsistentData, for: rerank)
        XCTAssertTrue(diagnostics.contains("answers=1/1"))
        XCTAssertTrue(diagnostics.contains("score_types=1"))
        XCTAssertTrue(diagnostics.contains("unexpected_fields=1"))
        XCTAssertTrue(diagnostics.contains("prob_sum="))
        XCTAssertTrue(diagnostics.contains("weighted_delta="))
        XCTAssertFalse(diagnostics.contains("본문"))
        assertError(.invalidProbabilities) {
            try JevEvidenceWire.parseResponse(inconsistentData, for: rerank)
        }

        let evidence = try makePrepared()
        assertError(.invalidAnswerType) {
            try JevEvidenceWire.parseResponse(
                responseData(answers: ["q0": scoreAnswer(score: 4)]), for: evidence)
        }
    }

    func testRerankAcceptsOnlyTheoreticalTwoDecimalRoundingError() throws {
        let rerank = try JevEvidenceWire.prepareRerank(
            query: "질문",
            candidates: [.init(id: "a", revision: "r", text: "후보")],
            apiKey: "key"
        )
        var rounded = scoreAnswer(score: 2)
        rounded["probabilities"] = ["0": 0.0, "1": 0.0, "2": 0.94, "3": 0.05, "4": 0.0]
        let valid = try JevEvidenceWire.parseResponse(
            responseData(answers: ["q0": rounded]), for: rerank)
        XCTAssertEqual(valid.assessments.first?.score, 0.5)

        var badSum = rounded
        badSum["probabilities"] = ["0": 0.0, "1": 0.0, "2": 0.90, "3": 0.05, "4": 0.0]
        assertError(.invalidProbabilities) {
            try JevEvidenceWire.parseResponse(
                responseData(answers: ["q0": badSum]), for: rerank)
        }

        var badWeightedDelta = rounded
        badWeightedDelta["probabilities"] = ["0": 0.0, "1": 0.40, "2": 0.0, "3": 0.60, "4": 0.0]
        assertError(.invalidProbabilities) {
            try JevEvidenceWire.parseResponse(
                responseData(answers: ["q0": badWeightedDelta]), for: rerank)
        }
    }

    func testRequestRejectsInvalidBoundsInsteadOfTruncating() throws {
        let valid = JevEvidenceWire.Candidate(id: "a", revision: "r", text: "text")
        assertError(.queryTooLong) {
            try JevEvidenceWire.prepare(
                query: String(repeating: "q", count: 2_001),
                candidates: [valid],
                apiKey: "key"
            )
        }
        assertError(.invalidCandidateCount) {
            try JevEvidenceWire.prepare(query: "q", candidates: [], apiKey: "key")
        }
        assertError(.invalidCandidateCount) {
            try JevEvidenceWire.prepare(
                query: "q",
                candidates: Array(repeating: valid, count: 9),
                apiKey: "key"
            )
        }
        assertError(.emptyCandidateID) {
            try JevEvidenceWire.prepare(
                query: "q",
                candidates: [.init(id: " \n ", revision: "r", text: "text")],
                apiKey: "key"
            )
        }
        assertError(.duplicateCandidateID) {
            try JevEvidenceWire.prepare(
                query: "q",
                candidates: [valid, .init(id: "a", revision: "new", text: "different")],
                apiKey: "key"
            )
        }
        assertError(.candidateTextTooLong) {
            try JevEvidenceWire.prepare(
                query: "q",
                candidates: [.init(
                    id: "a",
                    revision: "r",
                    text: String(repeating: "x", count: 12_001)
                )],
                apiKey: "key"
            )
        }
        assertError(.candidateTextTooLong) {
            try JevEvidenceWire.prepare(query: "q", candidates: [.init(id: "a", revision: "r", text: "body", title: String(repeating: "t", count: 12_000))], apiKey: "key")
        }
        assertError(.emptyAPIKey) {
            try JevEvidenceWire.prepare(query: "q", candidates: [valid], apiKey: " \n ")
        }
        assertError(.noteTooLong) {
            try JevEvidenceWire.prepareSupplement(
                note: String(repeating: "n", count: JevEvidenceWire.maximumNoteLength + 1),
                candidates: [valid],
                apiKey: "key"
            )
        }
    }

    func testResponseRejectsMissingAndUnexpectedAnswers() throws {
        let prepared = try makePrepared(candidateCount: 2)
        assertError(.answerIDsMismatch) {
            try JevEvidenceWire.parseResponse(
                responseData(answers: [
                    "q0": answer(choice: "direct", probabilities: probabilities(direct: 0.6))
                ]),
                for: prepared
            )
        }
        assertError(.answerIDsMismatch) {
            try JevEvidenceWire.parseResponse(
                responseData(answers: [
                    "q0": answer(choice: "direct", probabilities: probabilities(direct: 0.6)),
                    "q1": answer(choice: "partial", probabilities: probabilities(partial: 0.6)),
                    "q2": answer(choice: "unrelated", probabilities: probabilities(unrelated: 0.6))
                ]),
                for: prepared
            )
        }
    }

    func testResponseRejectsInvalidProbabilityDistributions() throws {
        let prepared = try makePrepared()

        var incomplete = probabilities(direct: 0.6)
        incomplete.removeValue(forKey: "background")
        assertInvalidProbabilities(incomplete, choice: "direct", prepared: prepared)

        var outOfRange = probabilities(direct: 0.6)
        outOfRange["unrelated"] = -0.1
        assertInvalidProbabilities(outOfRange, choice: "direct", prepared: prepared)

        var wrongSum = probabilities(direct: 0.6)
        wrongSum["unrelated"] = 0.2
        assertInvalidProbabilities(wrongSum, choice: "direct", prepared: prepared)

        assertInvalidProbabilities(probabilities(direct: 0.6),
                                   choice: "partial",
                                   prepared: prepared)
    }

    func testResponseRejectsWrongTypeChoiceConfidenceModelAndUsage() throws {
        let prepared = try makePrepared()
        let validProbabilities = probabilities(direct: 0.6)

        assertError(.invalidAnswerType) {
            try JevEvidenceWire.parseResponse(
                responseData(answers: [
                    "q0": answer(type: "noul", choice: "direct",
                                 probabilities: validProbabilities)
                ]),
                for: prepared
            )
        }
        assertError(.invalidChoice) {
            try JevEvidenceWire.parseResponse(
                responseData(answers: [
                    "q0": answer(choice: "invented", probabilities: validProbabilities)
                ]),
                for: prepared
            )
        }
        assertError(.invalidConfidence) {
            try JevEvidenceWire.parseResponse(
                responseData(answers: [
                    "q0": answer(choice: "direct", probabilities: validProbabilities,
                                 confidence: 1.1)
                ]),
                for: prepared
            )
        }
        assertError(.emptyResponseModel) {
            try JevEvidenceWire.parseResponse(
                responseData(model: " \n ", answers: [
                    "q0": answer(choice: "direct", probabilities: validProbabilities)
                ]),
                for: prepared
            )
        }
        assertError(.invalidUsage) {
            try JevEvidenceWire.parseResponse(
                responseData(answers: [
                    "q0": answer(choice: "direct", probabilities: validProbabilities)
                ], inputTokens: -1),
                for: prepared
            )
        }
    }

    private func makePrepared(candidateCount: Int = 1) throws -> JevEvidenceWire.PreparedRequest {
        try JevEvidenceWire.prepare(
            query: "질문",
            candidates: (0..<candidateCount).map {
                .init(id: "doc-\($0)", revision: "rev-\($0)", text: "candidate \($0)")
            },
            apiKey: "key"
        )
    }

    private func probabilities(direct: Double = 0.1,
                               partial: Double = 0.1,
                               unresolved: Double = 0.1,
                               background: Double = 0.1,
                               unrelated: Double = 0.1) -> [String: Double] {
        [
            "direct": direct,
            "partial": partial,
            "unresolved": unresolved,
            "background": background,
            "unrelated": unrelated
        ]
    }

    private func supplementProbabilities(alreadyPresent: Double = 0.1,
                                         supplement: Double = 0.1,
                                         conflict: Double = 0.1,
                                         unrelated: Double = 0.1,
                                         uncertain: Double = 0.1) -> [String: Double] {
        [
            "already_present": alreadyPresent,
            "supplement": supplement,
            "conflict": conflict,
            "unrelated": unrelated,
            "uncertain": uncertain
        ]
    }

    private var evidenceLabelNames: Set<String> {
        ["direct", "partial", "unresolved", "background", "unrelated"]
    }

    private var supplementLabelNames: Set<String> {
        ["already_present", "supplement", "conflict", "unrelated", "uncertain"]
    }

    private func answer(type: String = "choice",
                        choice: String,
                        probabilities: [String: Double],
                        confidence: Double = 0.5) -> [String: Any] {
        [
            "type": type,
            "choice": choice,
            "probabilities": probabilities,
            "confidence": confidence
        ]
    }

    private func scoreAnswer(score: Double,
                             confidence: Double = 0.5) -> [String: Any] {
        let legend = [
            "0": "Unrelated: it does not help answer the query or explore the selected source.",
            "1": "Weakly related: it shares a broad topic but is unlikely to add useful understanding.",
            "2": "Related context: it adds some useful context, though the connection or value is limited.",
            "3": "Strongly useful: it materially helps answer the query or understand the selected source.",
            "4": "Directly useful: it is an especially strong next document for the query or selected-source exploration."
        ]
        let bounded = min(4, max(0, score))
        let lower = Int(floor(bounded))
        let upper = Int(ceil(bounded))
        var probabilities = Dictionary(uniqueKeysWithValues: (0...4).map { (String($0), 0.0) })
        if lower == upper {
            probabilities[String(lower)] = 1
        } else {
            probabilities[String(lower)] = Double(upper) - bounded
            probabilities[String(upper)] = bounded - Double(lower)
        }
        return [
            "type": "score",
            "score": score,
            "legend": legend,
            "probabilities": probabilities,
            "confidence": confidence
        ]
    }

    private func responseData(model: String = "jev-1.13.0",
                              answers: [String: [String: Any]],
                              inputTokens: Int = 44,
                              outputTokens: Int = 12) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "model": model,
            "answers": answers,
            "usage": ["input_tokens": inputTokens, "output_tokens": outputTokens]
        ])
    }

    private func assertInvalidProbabilities(_ probabilities: [String: Double],
                                            choice: String,
                                            prepared: JevEvidenceWire.PreparedRequest,
                                            file: StaticString = #filePath,
                                            line: UInt = #line) {
        assertError(.invalidProbabilities, file: file, line: line) {
            try JevEvidenceWire.parseResponse(
                responseData(answers: [
                    "q0": answer(choice: choice, probabilities: probabilities)
                ]),
                for: prepared
            )
        }
    }

    private func assertError<T>(_ expected: JevEvidenceWire.WireError,
                                file: StaticString = #filePath,
                                line: UInt = #line,
                                _ expression: () throws -> T) {
        do {
            _ = try expression()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as JevEvidenceWire.WireError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error type", file: file, line: line)
        }
    }
}
