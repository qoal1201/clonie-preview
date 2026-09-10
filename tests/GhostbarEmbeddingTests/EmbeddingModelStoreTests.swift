import Foundation
import XCTest
@testable import GhostbarEmbedding

/// 동봉 모델은 개발자 개인 캐시와 별개로 탐색한다. 이 시험은 실제 캐시를 전혀 읽지 않고
/// 주입한 Resources 디렉터리만 써서 우선순위와 누락 상태를 잠근다.
final class EmbeddingModelStoreTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        try super.tearDownWithError()
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GhostbarEmbeddingModelStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory
    }

    /// 최소 구조만 만든다. `status` 는 여기서 CoreML을 열지 않으므로 실제 모델 바이트는 필요 없다.
    private func makeReadyBundle(in resources: URL) throws -> URL {
        let model = resources.appendingPathComponent(EmbeddingModelStore.bundledDirectoryName, isDirectory: true)
        let compiled = model.appendingPathComponent("Fixture.mlmodelc", isDirectory: true)
        try FileManager.default.createDirectory(at: compiled, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: model.appendingPathComponent("tokenizer-unigram.json"))
        let manifest: [String: Any] = [
            "model_dir": "Fixture.mlmodelc",
            "tokenizer_file": "tokenizer-unigram.json",
            "dimensions": 384,
            "model_id": "fixture-model",
            "revision": "fixture-revision",
            "precision": "fp16",
            "max_seq_length": 512,
            "enumerated_shapes": [32, 128, 512],
            "prefix_convention": ["query": "query: ", "passage": "passage: "]
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        try data.write(to: model.appendingPathComponent("manifest.json"))
        return model
    }

    func test_01_overrideIsTheOnlySearchPathEvenWhenBundleExists() throws {
        let resources = try temporaryDirectory()
        _ = try makeReadyBundle(in: resources)
        let override = resources.appendingPathComponent("missing-override", isDirectory: true)
        let environment = [EmbeddingModelStore.directoryOverrideKey: override.path]

        XCTAssertEqual(
            EmbeddingModelStore.searchPaths(environment: environment, bundleResourcesURL: resources),
            [override],
            "명시한 GHOSTBAR_MODEL_DIR가 있으면 번들과 기본 캐시로 물러서면 안 된다"
        )

        switch EmbeddingModelStore.status(environment: environment, bundleResourcesURL: resources) {
        case .missing(let searched):
            XCTAssertEqual(searched, [override])
        default:
            XCTFail("없는 override는 동봉 모델을 무시하고 missing이어야 한다")
        }
    }

    func test_02_bundledModelIsPreferredBeforeTheDefaultCache() throws {
        let resources = try temporaryDirectory()
        let bundled = try makeReadyBundle(in: resources)

        let paths = EmbeddingModelStore.searchPaths(environment: [:], bundleResourcesURL: resources)
        XCTAssertEqual(paths, [bundled, EmbeddingModelStore.defaultDirectory])

        switch EmbeddingModelStore.status(environment: [:], bundleResourcesURL: resources) {
        case .ready(let manifest):
            XCTAssertEqual(manifest.directory, bundled)
            XCTAssertEqual(manifest.modelID, "fixture-model")
            XCTAssertEqual(manifest.modelURL, bundled.appendingPathComponent("Fixture.mlmodelc", isDirectory: true))
            XCTAssertEqual(manifest.tokenizerURL, bundled.appendingPathComponent("tokenizer-unigram.json"))
        default:
            XCTFail("유효한 동봉 모델을 찾지 못했다")
        }
    }

    func test_03_emptyBundleSearchesBundleBeforeDefaultCache() throws {
        let resources = try temporaryDirectory()
        let expectedBundle = resources.appendingPathComponent(EmbeddingModelStore.bundledDirectoryName,
                                                               isDirectory: true)
        XCTAssertEqual(
            EmbeddingModelStore.searchPaths(environment: [:], bundleResourcesURL: resources),
            [expectedBundle, EmbeddingModelStore.defaultDirectory]
        )
    }
}
