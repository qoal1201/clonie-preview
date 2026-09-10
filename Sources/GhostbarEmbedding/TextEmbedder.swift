import CoreML
import Foundation

/// **문장 하나 → 384차 벡터.** 이 레포에서 임베딩의 유일한 입구다 (#31, ADR 0003 §5).
///
/// ## 네트워크를 안 탄다
///
/// 이 파일에도, 이 타깃 어디에도 `URLSession` 이 없다. 모델은 `scripts/fetch-model.sh` 가
/// **빌드 밖에서** 받아두고, 앱은 디스크에서 열기만 한다. `tests/check_interview_offline.py`
/// 가 재는 판정선이 그것이다 — 면접 모드가 여는 어떤 통로도 바깥에 안 나간다.
///
/// ## ★ 프리픽스 규약 — e5 는 이걸 안 붙이면 점수가 달라진다
///
/// e5 계열은 **질의와 문서를 다르게 인코딩**한다. 그래서 이 API 는 프리픽스를 **선택지로 두지 않고
/// 메서드로 가른다**:
///
/// ```swift
/// let q = try embedder.embed(query: "팀에서 갈등이 있었던 경험")     // "query: " 를 앞에 붙인다
/// let p = try embedder.embed(passage: "백엔드 팀과 이견이 컸다…")   // "passage: " 를 앞에 붙인다
/// let score = TextEmbedder.cosine(q, p)
/// ```
///
/// 붙일지 말지를 부르는 쪽이 정하게 두면 **언젠가 한쪽이 빼먹고, 그때 아무것도 안 터진다.**
/// 프리픽스 문자열 자체는 `manifest.json` 이 든다 — 모델을 바꾸면 규약도 같이 온다.
/// 규약을 벗어나야 할 때만 ``embed(raw:)`` 를 쓴다(그 이름이 곧 경고다).
///
/// ## 벡터는 이미 정규화돼 있다
///
/// 평균 풀링과 L2 정규화를 **CoreML 안에 구워 넣었다**(`scripts/convert_e5_coreml.py`).
/// 그래서 코사인 = 내적이고, ``cosine(_:_:)`` 이 하는 일이 그것뿐이다.
public final class TextEmbedder {

    public let manifest: EmbeddingModelStore.Manifest
    public let tokenizer: UnigramTokenizer
    private let model: MLModel
    /// 미리 컴파일된 길이들(오름차순). 입력을 이 중 하나로 **올림 패딩**한다.
    private let shapes: [Int]

    public var dimensions: Int { manifest.dimensions }

    // MARK: - 열기

    /// 디스크에 있는 모델을 연다.
    ///
    /// 모델이 없거나 깨졌으면 **여기서 실패한다.** 반쯤 살아 있는 임베더를 만들지 않는 것이
    /// 이 설계의 요점이다 — 살아 있으면 부르는 쪽이 점수를 믿어도 된다.
    public convenience init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        computeUnits: MLComputeUnits = .all
    ) throws {
        let status = EmbeddingModelStore.status(environment: environment)
        guard let manifest = status.manifest else { throw EmbeddingError.modelUnavailable(status) }
        try self.init(manifest: manifest, computeUnits: computeUnits)
    }

    public init(manifest: EmbeddingModelStore.Manifest,
                computeUnits: MLComputeUnits = .all) throws {
        self.manifest = manifest
        self.tokenizer = try UnigramTokenizer(contentsOf: manifest.tokenizerURL)

        let config = MLModelConfiguration()
        config.computeUnits = computeUnits
        do {
            // ⚠ `.mlmodelc`(컴파일본)를 연다. `.mlpackage` 를 열면 macOS 가 실행 시점에
            //   컴파일하느라 몇 초를 쓴다 — 변환 스크립트가 미리 구워두는 이유다.
            self.model = try MLModel(contentsOf: manifest.modelURL, configuration: config)
        } catch {
            throw EmbeddingError.modelLoadFailed(manifest.modelURL, "\(error)")
        }

        let s = manifest.enumeratedShapes.sorted()
        self.shapes = s.isEmpty ? [manifest.maxSequenceLength] : s
    }

    // MARK: - 규약대로 부르는 자리

    /// 면접 질문·검색어처럼 **찾는 쪽**의 문장.
    public func embed(query text: String) throws -> [Float] {
        try embed(raw: manifest.queryPrefix + text)
    }

    /// 내가 쌓아둔 조각처럼 **찾히는 쪽**의 문장.
    public func embed(passage text: String) throws -> [Float] {
        try embed(raw: manifest.passagePrefix + text)
    }

    /// 프리픽스를 **안 붙이고** 그대로 넣는다. 기준면 재현·진단용이다.
    ///
    /// ⚠ 제품 코드에서 이걸 부르고 있으면 십중팔구 위의 둘 중 하나를 불렀어야 하는 자리다.
    public func embed(raw text: String) throws -> [Float] {
        let ids = tokenizer.encode(text)
        let padded = paddedLength(for: ids.count)

        guard let inputIDs = try? MLMultiArray(shape: [1, NSNumber(value: padded)], dataType: .int32),
              let mask = try? MLMultiArray(shape: [1, NSNumber(value: padded)], dataType: .int32) else {
            throw EmbeddingError.inferenceFailed("입력 배열을 못 만들었다 (길이 \(padded))")
        }
        // 패딩 자리는 mask 가 0 이라 평균 풀링에 안 들어간다 — 값이 안 변한다.
        inputIDs.withUnsafeMutableBufferPointer(ofType: Int32.self) { buf, _ in
            for i in 0..<padded { buf[i] = i < ids.count ? ids[i] : 0 }
        }
        mask.withUnsafeMutableBufferPointer(ofType: Int32.self) { buf, _ in
            for i in 0..<padded { buf[i] = i < ids.count ? 1 : 0 }
        }

        let provider: MLFeatureProvider
        do {
            provider = try MLDictionaryFeatureProvider(
                dictionary: ["input_ids": inputIDs, "attention_mask": mask])
        } catch {
            throw EmbeddingError.inferenceFailed("입력을 못 묶었다: \(error)")
        }

        let out: MLFeatureProvider
        do { out = try model.prediction(from: provider) }
        catch { throw EmbeddingError.inferenceFailed("\(error)") }

        guard let value = out.featureValue(for: "embedding")?.multiArrayValue else {
            throw EmbeddingError.inferenceFailed("출력에 'embedding' 이 없다 — 모델 서명이 바뀌었다")
        }
        let n = value.count
        guard n == manifest.dimensions else {
            throw EmbeddingError.dimensionMismatch(expected: manifest.dimensions, got: n)
        }
        var vec = [Float](repeating: 0, count: n)
        value.withUnsafeBufferPointer(ofType: Float.self) { buf in
            for i in 0..<n { vec[i] = buf[i] }
        }
        return vec
    }

    /// 모델이 미리 컴파일해둔 길이 중 **입력을 담을 수 있는 가장 짧은 것**.
    ///
    /// 이게 지연을 정한다 — 짧은 질의를 512 로 패딩하면 열 배를 더 계산한다.
    func paddedLength(for count: Int) -> Int {
        for s in shapes where s >= count { return s }
        return shapes[shapes.count - 1]
    }

    // MARK: - 점수

    /// 코사인 유사도. **두 벡터가 정규화돼 있다는 전제**라 내적이 곧 답이다.
    public static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        var s: Float = 0
        for i in 0..<a.count { s += a[i] * b[i] }
        return s
    }
}
