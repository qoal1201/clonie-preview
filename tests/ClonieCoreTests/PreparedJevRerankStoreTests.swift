import XCTest
@testable import ClonieCore

final class PreparedJevRerankStoreTests: XCTestCase {
    private var vault: URL!

    override func setUpWithError() throws {
        vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("clonie-prepared-jev-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: vault)
    }

    func testSavesAndLoadsAfterReopeningStore() async throws {
        let store = PreparedJevRerankStore(vaultURL: vault)
        let record = try makeRecord(query: "전체 제품 흐름은?", sourceID: "intent",
                                    scope: "repository", fingerprint: "sha256:abc")

        try await store.save(record)

        let reopened = PreparedJevRerankStore(vaultURL: vault)
        let loaded = try await reopened.loadAll()
        XCTAssertEqual(loaded, [record])

        let url = await store.recordsURL
        XCTAssertEqual(url.lastPathComponent, "prepared-jev-reranks.json")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, ".clonie")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
    }

    func testReplacesExactContextAndKeepsNewestTwelveRecords() async throws {
        let store = PreparedJevRerankStore(vaultURL: vault)
        for index in 0..<13 {
            try await store.save(makeRecord(query: "질문 \(index)", score: Double(index) / 20))
        }
        var records = try await store.loadAll()
        XCTAssertEqual(records.count, 12)
        XCTAssertEqual(records.first?.query, "질문 1")
        XCTAssertEqual(records.last?.query, "질문 12")

        let replacement = try makeRecord(query: "질문 5", score: 0.99)
        try await store.save(replacement)
        records = try await store.loadAll()
        XCTAssertEqual(records.count, 12)
        XCTAssertEqual(records.last, replacement)
        XCTAssertEqual(records.filter { $0.query == "질문 5" }.count, 1)
    }

    func testTypedInitializersRejectUnsafePathsScoresAndCandidateOverflow() throws {
        XCTAssertThrowsError(try PreparedJevRerankCandidate(
            id: "doc", path: "../outside.md", revision: "rev", score: 0.5))
        XCTAssertThrowsError(try PreparedJevRerankCandidate(
            id: "doc", path: "doc.md", revision: "rev", score: .infinity))

        let nine = try (0..<9).map {
            try PreparedJevRerankCandidate(id: "doc-\($0)", path: "\($0).md",
                                           revision: "rev-\($0)", score: 0.5)
        }
        XCTAssertThrowsError(try PreparedJevRerankRecord(
            query: "질문", corpusFingerprint: "fingerprint", modelVersion: "jev-1",
            policyVersion: "policy-1", candidates: nine))
    }

    func testRejectsDecodedDuplicateCandidatesAndOutOfRangeScores() async throws {
        let store = PreparedJevRerankStore(vaultURL: vault)
        let url = await store.recordsURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let invalid = #"{"schemaVersion":1,"records":[{"query":"q","corpusFingerprint":"f","modelVersion":"m","policyVersion":"p","candidates":[{"id":"a","path":"a.md","revision":"r","score":0.5},{"id":"a","path":"b.md","revision":"r","score":2}]}]}"#
        try Data(invalid.utf8).write(to: url)

        do {
            _ = try await store.loadAll()
            XCTFail("invalid decoded values must fail")
        } catch let error as PreparedJevRerankStoreError {
            XCTAssertEqual(error, .invalidScore)
        }
    }

    func testCorruptAndOversizedMetadataIsRejectedWithoutBeingReplaced() async throws {
        let store = PreparedJevRerankStore(vaultURL: vault)
        let url = await store.recordsURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let corrupt = Data("{broken".utf8)
        try corrupt.write(to: url)

        await XCTAssertThrowsErrorAsync(try await store.loadAll())
        await XCTAssertThrowsErrorAsync(try await store.save(makeRecord(query: "새 질문")))
        XCTAssertEqual(try Data(contentsOf: url), corrupt)

        let oversized = Data(repeating: 0x61, count: PreparedJevRerankStore.maximumFileBytes + 1)
        try oversized.write(to: url)
        do {
            _ = try await store.loadAll()
            XCTFail("oversized file must fail before decoding")
        } catch let error as PreparedJevRerankStoreError {
            XCTAssertEqual(error, .metadataTooLarge)
        }
        XCTAssertEqual(try Data(contentsOf: url).count, oversized.count)
    }

    func testRejectsFutureSchemaAndSymbolicLinkSidecar() async throws {
        let store = PreparedJevRerankStore(vaultURL: vault)
        let url = await store.recordsURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(#"{"schemaVersion":2,"records":[]}"#.utf8).write(to: url)
        do {
            _ = try await store.loadAll()
            XCTFail("future schema must fail")
        } catch let error as PreparedJevRerankStoreError {
            XCTAssertEqual(error, .unknownSchemaVersion(2))
        }

        try FileManager.default.removeItem(at: url.deletingLastPathComponent())
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("clonie-prepared-jev-outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(
            at: url.deletingLastPathComponent(), withDestinationURL: outside)

        do {
            try await store.save(makeRecord(query: "질문"))
            XCTFail("symlink sidecar must fail")
        } catch let error as PreparedJevRerankStoreError {
            guard case .symbolicLinkPath = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path), [])
    }

    private func makeRecord(query: String,
                            sourceID: String? = nil,
                            scope: String? = nil,
                            fingerprint: String = "sha256:corpus",
                            score: Double = 0.8) throws -> PreparedJevRerankRecord {
        try PreparedJevRerankRecord(
            query: query, sourceID: sourceID, scope: scope,
            corpusFingerprint: fingerprint, modelVersion: "jev-1",
            policyVersion: "prepared-rerank-v1",
            candidates: [try PreparedJevRerankCandidate(
                id: "doc-a", path: "자료/A.md", revision: "sha256:a", score: score)])
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("expected error", file: file, line: line)
    } catch {}
}
