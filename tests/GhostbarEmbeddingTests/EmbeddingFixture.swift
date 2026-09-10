import Foundation
import XCTest
@testable import GhostbarEmbedding

/// `tests/fixtures/embedding_reference.json` 을 읽어 들이는 자리.
///
/// 그 파일은 **파이썬(sentence-transformers)이 뜬 기준면**이고
/// `scripts/make_embedding_fixture.py` 가 쓴다. 손으로 고치는 파일이 아니다.
struct EmbeddingFixture {

    struct Text {
        let key: String
        let text: String
        let tokens: [Int32]
        let embedding: [Double]
    }
    struct TokenizerCase {
        let key: String
        let text: String
        let tokens: [Int32]
    }
    struct CosinePair {
        let a: String
        let b: String
        let cosine: Double
    }

    let modelID: String
    let revision: String
    let dimensions: Int
    let queryPrefix: String
    let passagePrefix: String
    let cosineTolerance: Double
    let componentTolerance: Double
    let toleranceWhy: String
    let pythonMedianMs: Double
    let texts: [Text]
    let tokenizerCases: [TokenizerCase]
    let cosines: [CosinePair]

    /// 레포 안의 고정 위치. `#filePath` 에서 거슬러 올라간다 —
    /// `swift test` 의 작업 디렉터리에 기대면 부르는 자리마다 달라진다.
    static var url: URL {
        URL(fileURLWithPath: #filePath)          // tests/GhostbarEmbeddingTests/EmbeddingFixture.swift
            .deletingLastPathComponent()          // tests/GhostbarEmbeddingTests
            .deletingLastPathComponent()          // tests
            .appendingPathComponent("fixtures/embedding_reference.json")
    }

    static func load() throws -> EmbeddingFixture {
        let data = try Data(contentsOf: url)
        guard let j = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure("기준면 최상위가 객체가 아니다 — \(url.path)")
        }
        func req<T>(_ key: String, _ v: T?) throws -> T {
            guard let v else { throw Failure("기준면에 '\(key)' 가 없다 — \(url.path)") }
            return v
        }
        let tol = j["tolerance"] as? [String: Any] ?? [:]
        let prefixes = j["prefix_convention"] as? [String: String] ?? [:]
        let latency = j["python_latency"] as? [String: Any] ?? [:]

        let texts = try req("texts", j["texts"] as? [[String: Any]]).map { t in
            Text(key: t["key"] as? String ?? "?",
                 text: t["text"] as? String ?? "",
                 tokens: (t["tokens"] as? [Int] ?? []).map(Int32.init),
                 embedding: t["embedding"] as? [Double] ?? [])
        }
        let cases = (j["tokenizer_cases"] as? [[String: Any]] ?? []).map { c in
            TokenizerCase(key: c["key"] as? String ?? "?",
                          text: c["text"] as? String ?? "",
                          tokens: (c["tokens"] as? [Int] ?? []).map(Int32.init))
        }
        let pairs = (j["cosines"] as? [[String: Any]] ?? []).map { p in
            CosinePair(a: p["a"] as? String ?? "?", b: p["b"] as? String ?? "?",
                       cosine: p["cosine"] as? Double ?? .nan)
        }
        return EmbeddingFixture(
            modelID: try req("model_id", j["model_id"] as? String),
            revision: try req("revision", j["revision"] as? String),
            dimensions: try req("dimensions", j["dimensions"] as? Int),
            queryPrefix: prefixes["query"] ?? "query: ",
            passagePrefix: prefixes["passage"] ?? "passage: ",
            cosineTolerance: tol["cosine_abs"] as? Double ?? 1e-3,
            componentTolerance: tol["embedding_component_abs"] as? Double ?? 1e-3,
            toleranceWhy: tol["why"] as? String ?? "",
            pythonMedianMs: latency["median_ms"] as? Double ?? .nan,
            texts: texts, tokenizerCases: cases, cosines: pairs)
    }

    func text(_ key: String) -> Text? { texts.first { $0.key == key } }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ d: String) { description = d }
    }
}
