import XCTest
import ClonieCore
import ClonieEmbedding
import ClonieIndex
@testable import ClonieMCP

final class SearchCacheIntegrationTests: XCTestCase {
    private var vault: URL!

    override func setUpWithError() throws {
        vault = try MCPTestSupport.makeVault()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: vault)
    }

    func testExternalEditIgnoresWarmMemoryAndStaleSidecar() async throws {
        guard let manifest = MCPTestSupport.modelOrAnnounceMissing() else { return }
        let store = VaultStore(vaultURL: vault)
        try store.save(MCPTestSupport.sampleDocument())
        let embedder = try TextEmbedder(manifest: manifest)
        let indexer = ContentIndexer(sidecarURL: store.sidecarURL, embedder: embedder)
        let tools = VaultTools(vaultURL: vault)
        _ = try await tools.search(query: "배포 자동화 경험", limit: 3)
        _ = try indexer.reindex(fragments: store.load().document.fragments)
        let before = try Data(contentsOf: indexer.store.embeddingsURL)

        var edited = try store.load().document
        let i = try XCTUnwrap(edited.fragments.firstIndex { $0.id == "f-deploy" })
        edited.fragments[i].title = "사과 구매 기록"
        edited.fragments[i].body = "사과 6개를 9000원에 샀고 한 개에 1500원이었다. 배포와 서버 운영은 이 기록에 없다."
        try store.save(edited)
        let warm = try await tools.search(query: "사과 구매 가격", limit: 3)
        let fresh = try await VaultTools(vaultURL: vault).search(query: "사과 구매 가격", limit: 3)
        XCTAssertEqual(warm.hits, fresh.hits, "이전 본문 메모리/sidecar가 새 내용의 점수를 가렸다")
        XCTAssertTrue(warm.hits.first { $0.id == "f-deploy" }?.snippet.contains("1500원") == true)
        XCTAssertEqual(try Data(contentsOf: indexer.store.embeddingsURL), before,
                       "MCP 검색이 낡은 sidecar를 고쳐 썼다 — ADR 0007")
    }

    func testRenameAndDeletionUseCurrentIDsPathsAndSources() async throws {
        guard MCPTestSupport.modelOrAnnounceMissing() != nil else { return }
        let original = vault.appendingPathComponent("original.md")
        try "# 배포 자동화\n\n반복 배포를 스크립트로 자동화하고 복구 절차를 검토했다.\n".write(to: original, atomically: true, encoding: .utf8)
        try "# 과일 기록\n\n사과와 배를 냉장고에 보관했다.\n".write(to: vault.appendingPathComponent("other.md"), atomically: true, encoding: .utf8)
        let tools = VaultTools(vaultURL: vault)
        let first = try await tools.search(query: "배포 자동화", limit: 3)
        let firstHit = try XCTUnwrap(first.hits.first { $0.id == "original" })
        let directory = vault.appendingPathComponent("옮긴 폴더")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let renamed = directory.appendingPathComponent("renamed.md")
        try FileManager.default.moveItem(at: original, to: renamed)
        let after = try await tools.search(query: "배포 자동화", limit: 3)
        XCTAssertFalse(after.hits.contains { $0.id == "original" })
        let newHit = try XCTUnwrap(after.hits.first { $0.id == "옮긴 폴더/renamed" })
        XCTAssertEqual(newHit.path, "옮긴 폴더/renamed.md")
        XCTAssertEqual(newHit.score, firstHit.score)
        XCTAssertEqual(newHit.snippet, firstHit.snippet)

        try FileManager.default.removeItem(at: renamed)
        let deleted = try await tools.search(query: "배포 자동화", limit: 3)
        XCTAssertEqual(deleted.hits.map(\.id), ["other"])
        let sidecar = VaultStore(vaultURL: vault).sidecarURL
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecar.appendingPathComponent("embeddings.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecar.appendingPathComponent("links.json").path))
    }

    func testSidecarAppearingAndUpdatingOverridesWarmMemory() async throws {
        guard let manifest = MCPTestSupport.modelOrAnnounceMissing() else { return }
        let store = VaultStore(vaultURL: vault)
        try store.save(MCPTestSupport.sampleDocument())
        let tools = VaultTools(vaultURL: vault)
        let text = "배포 자동화 경험"
        let first = try await tools.search(query: text, limit: 3)
        XCTAssertNotEqual(first.hits.first?.id, "f-pasta")
        let embedder = try TextEmbedder(manifest: manifest)
        let qv = try embedder.embed(query: text)
        let indexer = ContentIndexer(sidecarURL: store.sidecarURL, embedder: embedder)
        let pasta = try XCTUnwrap(store.load().document.fragments.first { $0.id == "f-pasta" })
        let passage = try XCTUnwrap(indexer.passages(for: pasta).first)
        func publish(_ vector: [Float]) throws {
            try indexer.store.savePassages([pasta.id: [.init(id: passage.id, startUTF16: passage.startUTF16,
                endUTF16: passage.endUTF16, hash: passage.hash, vector: ContentIndexStore.encode(vector: vector))]],
                model: ContentIndexStore.ModelIdentity(manifest))
        }
        try publish(qv)
        let positive = try Data(contentsOf: indexer.store.embeddingsURL)
        let appeared = try await tools.search(query: text, limit: 3)
        XCTAssertEqual(appeared.hits.first?.id, pasta.id, "메모리가 나중에 생긴 sidecar를 가렸다")
        XCTAssertEqual(appeared.hits.first?.score ?? 0, 1 / Thresholds.simGreenDirect, accuracy: 0.002)
        XCTAssertEqual(try Data(contentsOf: indexer.store.embeddingsURL), positive)

        try publish(qv.map { -$0 })
        let negative = try Data(contentsOf: indexer.store.embeddingsURL)
        let updated = try await tools.search(query: text, limit: 3)
        let changedHit = try XCTUnwrap(updated.hits.first { $0.id == pasta.id })
        XCTAssertLessThan(changedHit.score ?? 0, 0, "같은 해시여도 sidecar의 최신 벡터를 선택해야 한다")
        XCTAssertEqual(try Data(contentsOf: indexer.store.embeddingsURL), negative)
    }
}
