import XCTest
@testable import ClonieIndex

final class SearchCacheTests: XCTestCase {
    private let model = ContentIndexStore.ModelIdentity(id: "synthetic", revision: "r1", dimensions: 2,
                                                       passagePrefix: "passage: ", queryPrefix: "query: ")

    func testRepeatedPassageDoesNotRecompute() throws {
        let cache = ContentIndexer.SearchCache()
        cache.prepare(model: model, activeHashes: ["same-text"])
        var calls = 0
        func compute() -> [Float] { calls += 1; return [1, 0] }
        let first = cache.vector(hash: "same-text", preferred: nil, compute: compute)
        cache.prepare(model: model, activeHashes: ["same-text"])
        let again = cache.vector(hash: "same-text", preferred: nil, compute: compute)
        XCTAssertEqual(first, again)
        XCTAssertEqual(calls, 1, "같은 문단을 질의마다 다시 임베딩했다")
    }

    func testCurrentSidecarReplacesMemoryEvenWhenTextHashIsUnchanged() {
        let cache = ContentIndexer.SearchCache()
        cache.prepare(model: model, activeHashes: ["same-text"])
        _ = cache.vector(hash: "same-text", preferred: nil) { [1, 0] }
        let updated = cache.vector(hash: "same-text", preferred: [0, 1]) {
            XCTFail("현재 sidecar를 읽었는데 다시 임베딩했다"); return [0, 0]
        }
        let retained = cache.vector(hash: "same-text", preferred: nil) {
            XCTFail("갱신된 벡터를 보관하지 않았다"); return [0, 0]
        }
        XCTAssertEqual(updated, [0, 1])
        XCTAssertEqual(retained, updated)
    }

    func testChangedAndDeletedPassagesAreEvictedButUnchangedContentRemains() {
        let cache = ContentIndexer.SearchCache()
        var calls = 0
        func compute() -> [Float] { calls += 1; return [Float(calls), 0] }
        cache.prepare(model: model, activeHashes: ["old", "keep"])
        let old = cache.vector(hash: "old", preferred: nil, compute: compute)
        let keep = cache.vector(hash: "keep", preferred: nil, compute: compute)
        cache.prepare(model: model, activeHashes: ["new", "keep"])
        XCTAssertEqual(cache.vector(hash: "keep", preferred: nil, compute: compute), keep)
        _ = cache.vector(hash: "new", preferred: nil, compute: compute)
        XCTAssertEqual(calls, 3)
        cache.prepare(model: model, activeHashes: ["old", "keep"])
        XCTAssertNotEqual(cache.vector(hash: "old", preferred: nil, compute: compute), old,
                          "앞선 검색에서 사라진 본문 해시가 캐시에 남았다")
        cache.prepare(model: model, activeHashes: [])
        cache.prepare(model: model, activeHashes: ["keep"])
        XCTAssertNotEqual(cache.vector(hash: "keep", preferred: nil, compute: compute), keep)
        XCTAssertEqual(calls, 5)
    }

    func testEveryModelIdentityFieldSeparatesCachedVectors() {
        var variants = [ContentIndexStore.ModelIdentity]()
        var next = model; next.id = "different"; variants.append(next)
        next = model; next.revision = "r2"; variants.append(next)
        next = model; next.dimensions = 3; variants.append(next)
        next = model; next.passagePrefix = "document: "; variants.append(next)
        next = model; next.queryPrefix = "question: "; variants.append(next)
        for changed in variants {
            let cache = ContentIndexer.SearchCache()
            cache.prepare(model: model, activeHashes: ["same-text"])
            _ = cache.vector(hash: "same-text", preferred: nil) { [1, 0] }
            cache.prepare(model: changed, activeHashes: ["same-text"])
            var calls = 0
            let expected = [Float](repeating: 0.5, count: changed.dimensions)
            XCTAssertEqual(cache.vector(hash: "same-text", preferred: nil) { calls += 1; return expected }, expected)
            XCTAssertEqual(calls, 1, "다른 좌표계의 벡터가 재사용됐다: \(changed)")
        }
    }

    func testCapacityPlusOneScanReusesResidentPassagesAndFillsVacatedSlots() {
        let cache = ContentIndexer.SearchCache(maximumEntries: 2)
        cache.prepare(model: model, activeHashes: ["a", "b", "c"])
        var calls = 0
        func compute() -> [Float] { calls += 1; return [Float(calls), 0] }
        let a = cache.vector(hash: "a", preferred: nil, compute: compute)
        let b = cache.vector(hash: "b", preferred: nil, compute: compute)
        _ = cache.vector(hash: "c", preferred: nil, compute: compute)
        cache.prepare(model: model, activeHashes: ["a", "b", "c"])
        XCTAssertEqual(cache.vector(hash: "a", preferred: nil, compute: compute), a)
        XCTAssertEqual(cache.vector(hash: "b", preferred: nil, compute: compute), b)
        _ = cache.vector(hash: "c", preferred: nil, compute: compute)
        XCTAssertEqual(calls, 4, "상한보다 한 문단 많다는 이유로 매 검색마다 전체를 다시 임베딩했다")

        cache.prepare(model: model, activeHashes: ["b", "c"])
        let c = cache.vector(hash: "c", preferred: nil, compute: compute)
        XCTAssertEqual(cache.vector(hash: "c", preferred: nil, compute: compute), c)
        XCTAssertEqual(calls, 5, "삭제로 빈 자리가 생겼는데 새 문단을 보관하지 않았다")

        let disabled = ContentIndexer.SearchCache(maximumEntries: 0)
        disabled.prepare(model: model, activeHashes: ["same"])
        _ = disabled.vector(hash: "same", preferred: nil, compute: compute)
        _ = disabled.vector(hash: "same", preferred: nil, compute: compute)
        XCTAssertEqual(calls, 7)
    }

    func testSidecarOnlyHitsDoNotConsumeMemoryCapacity() {
        let cache = ContentIndexer.SearchCache(maximumEntries: 2)
        let diskHashes = (0..<100).map { "disk-\($0)" }
        cache.prepare(model: model, activeHashes: Set(diskHashes + ["a", "b"]))
        var calls = 0
        func compute() -> [Float] { calls += 1; return [Float(calls), 0] }
        let a = cache.vector(hash: "a", preferred: nil, compute: compute)
        for hash in diskHashes {
            XCTAssertEqual(cache.vector(hash: hash, preferred: [0, 1], compute: compute), [0, 1])
        }
        let b = cache.vector(hash: "b", preferred: nil, compute: compute)
        XCTAssertEqual(cache.vector(hash: "a", preferred: nil, compute: compute), a)
        XCTAssertEqual(cache.vector(hash: "b", preferred: nil, compute: compute), b)
        XCTAssertEqual(calls, 2, "디스크에서 재사용한 문단이 계산한 벡터의 메모리 자리를 차지했다")
    }

    func testInvalidPreferredVectorDoesNotLeaveAnOlderCachedValue() {
        let invalidVectors: [[Float]] = [[.nan, 0], [1, 0, 0]]
        for invalid in invalidVectors {
            let cache = ContentIndexer.SearchCache()
            cache.prepare(model: model, activeHashes: ["same"])
            _ = cache.vector(hash: "same", preferred: nil) { [1, 0] }
            _ = cache.vector(hash: "same", preferred: invalid) { XCTFail("preferred path"); return [] }
            var recomputed = false
            let value = cache.vector(hash: "same", preferred: nil) { recomputed = true; return [0, 1] }
            XCTAssertTrue(recomputed)
            XCTAssertEqual(value, [0, 1])
        }
    }

    func testFailedInferenceIsRetriedInsteadOfCachingAPlaceholder() throws {
        enum Failure: Error { case inference }
        let cache = ContentIndexer.SearchCache()
        cache.prepare(model: model, activeHashes: ["retry"])
        XCTAssertThrowsError(try cache.vector(hash: "retry", preferred: nil) { throw Failure.inference })
        var calls = 0
        let recovered = cache.vector(hash: "retry", preferred: nil) { calls += 1; return [1, 0] }
        let repeated = cache.vector(hash: "retry", preferred: nil) { calls += 1; return [0, 1] }
        XCTAssertEqual(recovered, repeated)
        XCTAssertEqual(calls, 1)
    }
}
