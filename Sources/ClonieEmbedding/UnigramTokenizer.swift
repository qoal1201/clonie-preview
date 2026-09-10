import Foundation

/// XLM-R 의 **Unigram(sentencepiece) 토크나이저**를 Swift 에서 돌린다 (#31).
///
/// 먹는 것 = `scripts/convert_e5_coreml.py` 가 `tokenizer.json` 에서 뽑아둔
/// `tokenizer-unigram.json`. 내는 것 = `<s> … </s>` 로 감싼 토큰 id 열.
///
/// ## 파이프라인 — 네 층이고 순서가 곧 정답이다
///
/// 1. **정규화** — `PrecompiledNormalizer`(charsmap) → 그다음 `" {2,}"` → `" "`
/// 2. **Metaspace** — 공백을 `▁` 로 바꾸고 **맨 앞에도 붙인다**(`prepend_scheme: always`),
///    그리고 `▁` 앞에서 **자른다**(`split: true`). 조각마다 따로 Viterbi 를 돌린다
/// 3. **Unigram Viterbi** — 점수 합이 최대인 분해. 어휘에 없는 글자는 `<unk>`
/// 4. **감싸기** — 앞에 `<s>`, 뒤에 `</s>`
///
/// ## 어디까지 확인했나 — 한계
///
/// - **추가 토큰(`<mask>` 등)을 입력에서 안 가른다.** 사용자 문장에 `<mask>` 리터럴이 들어오면
///   HF 는 특수 토큰으로 자르고 우리는 평범한 글자로 쪼갠다. **제품 입력(면접 질문·내 사연)에
///   그게 들어올 일이 없어서 안 짰다** — 필요해지면 여기가 그 자리다
/// - `byte_fallback` 은 이 모델이 끈 상태이고, 변환 스크립트가 켜져 있으면 죽는다
/// - `fuse_unk` 안 함 — 연속 `<unk>` 를 안 합친다. 이 모델 `tokenizer.json` 에 그 필드가
///   없어서 기본값(끔)이다. 기준면의 `emoji` 케이스가 이 자리를 때린다
public struct UnigramTokenizer: Sendable {

    public struct Config: Sendable {
        public var maxSequenceLength: Int
    }

    /// ★ **바이트로 키를 잡는다. `String` 으로 잡으면 안 된다.**
    ///
    /// Swift 의 `String` 동등성은 **유니코드 정준 동등성**이라 NFD `"한글"` 과 NFC `"한글"` 이
    /// `==` 이고 해시도 같다. 그래서 `[String: Int32]` 로 두면 자모로 분해된 입력이 조합된
    /// 어휘 조각에 **조용히 매치된다** — 파이썬은 분해된 채로 8토큰을 내는데 우리는 1토큰을 냈다
    /// (`실측 2026-08-30`, #31: `hangul_nfd` 케이스). 토크나이저는 바이트 수준 일치가 정답이다.
    private let pieceToID: [[UInt8]: Int32]
    private let scores: [Float]
    private let normalizer: PrecompiledNormalizer?
    private let collapsesSpaces: Bool
    private let unkID: Int32
    private let bosID: Int32
    private let eosID: Int32
    /// 어휘에서 가장 긴 조각의 **바이트 수**. Viterbi 가 여기까지만 앞을 본다.
    private let maxPieceBytes: Int
    /// `min(점수) - 10.0`. HF `Unigram::populate_nodes` 의 `unk_score` 와 같은 식이다.
    private let unkScore: Float

    public let maxSequenceLength: Int

    /// 모델이 아는 벡터 차원과 무관한, 토크나이저만의 사실들.
    public var vocabularySize: Int { pieceToID.count }

    // MARK: - 적재

    /// `tokenizer-unigram.json` 을 읽는다.
    public init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EmbeddingError.tokenizerUnreadable(url, "최상위가 객체가 아니다")
        }
        try self.init(json: root, url: url)
    }

    init(json root: [String: Any], url: URL) throws {
        func fail(_ why: String) -> EmbeddingError { .tokenizerUnreadable(url, why) }

        guard let pieces = root["pieces"] as? [String],
              let rawScores = root["scores"] as? [Double],
              pieces.count == rawScores.count, !pieces.isEmpty else {
            throw fail("pieces/scores 가 없거나 길이가 다르다")
        }
        guard let unk = root["unk_id"] as? Int, let bos = root["bos_id"] as? Int,
              let eos = root["eos_id"] as? Int else {
            throw fail("unk_id/bos_id/eos_id 가 없다")
        }

        var map = [[UInt8]: Int32](minimumCapacity: pieces.count)
        var longest = 0
        for (i, p) in pieces.enumerated() {
            let key = Array(p.utf8)
            // ⚠ 중복 조각이 있으면 **먼저 나온 id 를 남긴다** — HF 의 `token_to_ids` 와 같다
            if map[key] == nil { map[key] = Int32(i) }
            longest = max(longest, key.count)
        }
        self.pieceToID = map
        self.scores = rawScores.map(Float.init)
        self.maxPieceBytes = longest
        self.unkID = Int32(unk)
        self.bosID = Int32(bos)
        self.eosID = Int32(eos)
        self.unkScore = (self.scores.min() ?? 0) - 10.0
        self.maxSequenceLength = (root["max_seq_length"] as? Int) ?? 512
        self.collapsesSpaces = (root["normalizer_collapses_spaces"] as? Bool) ?? true

        if let b64 = root["precompiled_charsmap"] as? String,
           let raw = Data(base64Encoded: b64) {
            self.normalizer = PrecompiledNormalizer(charsmap: Array(raw))
            if self.normalizer == nil { throw fail("precompiled_charsmap 을 못 읽었다") }
        } else {
            // ⚠ 조용히 넘어가지 않는다. 정규화기가 빠진 토크나이저는 **대부분 맞고 가끔 틀린다**
            throw fail("precompiled_charsmap 이 없다 — 정규화기 없이는 기준면과 갈린다")
        }
    }

    // MARK: - 정규화

    func normalize(_ text: String) -> String {
        var s = normalizer?.normalize(text) ?? text
        if collapsesSpaces {
            // `" {2,}"` → `" "`. 정규식을 안 쓰는 이유는 하나 — 이게 더 빠르고 같기 때문이다
            var out = String()
            out.reserveCapacity(s.utf8.count)
            var runningSpace = false
            for ch in s {
                if ch == " " {
                    if runningSpace { continue }
                    runningSpace = true
                } else {
                    runningSpace = false
                }
                out.append(ch)
            }
            s = out
        }
        return s
    }

    // MARK: - 토큰화

    /// 특수 토큰 **없이** 조각 문자열들로만 쪼갠다. 진단용 — 자물쇠가 어디서 갈렸는지 볼 때 쓴다.
    public func pieces(of text: String) -> [String] {
        segments(of: normalize(text)).flatMap { seg in viterbi(seg).map(\.piece) }
    }

    /// `<s> … </s>` 로 감싼 토큰 id 열. **모델에 넣는 것이 이것**이다.
    public func encode(_ text: String) -> [Int32] {
        var ids: [Int32] = [bosID]
        let budget = maxSequenceLength - 2      // 특수 토큰 둘의 자리를 먼저 뗀다
        outer: for seg in segments(of: normalize(text)) {
            for node in viterbi(seg) {
                if ids.count - 1 >= budget { break outer }
                ids.append(node.id)
            }
        }
        ids.append(eosID)
        return ids
    }

    /// `▁` 의 UTF-8 세 바이트. 이것으로 자른다.
    private static let meta: [UInt8] = [0xE2, 0x96, 0x81]

    /// Metaspace: 공백을 `▁` 로 바꾸고, **필요하면** 맨 앞에 붙인 뒤, `▁` 앞에서 자른다.
    ///
    /// ⚠ **「필요하면」이 핵심이다.** `prepend_scheme: always` 인데도 HF 는
    ///   *치환한 뒤 이미 `▁` 로 시작하면 안 붙인다*(`Metaspace::pre_tokenize`).
    ///   무조건 붙이면 공백으로 시작하는 입력에서 `▁` 토큰이 하나 더 생긴다
    ///   (`실측 2026-08-30`, #31: `edge_space` 케이스).
    ///
    /// ⚠ **문자열이 아니라 바이트로 돌려준다.** `String` 을 거치면 Foundation 치환·정준 동등성이
    ///   끼어들 자리가 생긴다 — 위 `pieceToID` 주석과 같은 이유다.
    ///
    /// 조각마다 **따로** Viterbi 를 돌리는 것이 HF `split: true` 의 뜻이다.
    private func segments(of normalized: String) -> [[UInt8]] {
        if normalized.isEmpty { return [] }
        let meta = Self.meta

        var body: [UInt8] = []
        body.reserveCapacity(normalized.utf8.count + 3)
        for scalar in normalized.unicodeScalars {
            if scalar == " " { body.append(contentsOf: meta) }
            else { UTF8.encode(scalar) { body.append($0) } }
        }
        if !body.starts(with: meta) { body.insert(contentsOf: meta, at: 0) }

        var out: [[UInt8]] = []
        var start = 0
        var i = 0
        while i < body.count {
            if i + 3 <= body.count, body[i] == meta[0], body[i + 1] == meta[1], body[i + 2] == meta[2] {
                if i > start { out.append(Array(body[start..<i])) }
                start = i
                i += 3
            } else {
                i += 1
            }
        }
        if start < body.count { out.append(Array(body[start...])) }
        return out
    }

    private struct Node { let id: Int32; let piece: String }

    /// 점수 합이 최대인 분해. HF `Lattice::viterbi` 와 **동점 처리까지** 맞춘다.
    ///
    /// - 위치마다 어휘에 있는 모든 접두사를 후보로 놓는다
    /// - 그 위치에서 **한 글자짜리 후보가 하나도 없으면** `<unk>` 한 글자를 넣는다
    ///   (없으면 경로가 끊긴다 — 어휘 밖 글자가 그 자리다)
    /// - 동점이면 **먼저 온 것**을 남긴다(`>` 비교). HF 가 그렇게 한다
    private func viterbi(_ bytes: [UInt8]) -> [Node] {
        let n = bytes.count
        if n == 0 { return [] }

        // UTF-8 글자 경계. 여기 없는 위치에서는 시작도 끝도 안 한다
        var isBoundary = [Bool](repeating: false, count: n + 1)
        isBoundary[n] = true
        for i in 0..<n where bytes[i] & 0xC0 != 0x80 { isBoundary[i] = true }

        var best = [Float](repeating: -Float.infinity, count: n + 1)
        var backStart = [Int](repeating: -1, count: n + 1)
        var backID = [Int32](repeating: -1, count: n + 1)
        best[0] = 0

        for start in 0..<n where isBoundary[start] && best[start] > -Float.infinity {
            // 이 위치에서 시작하는 한 글자의 바이트 길이
            var charLen = 1
            while start + charLen < n && !isBoundary[start + charLen] { charLen += 1 }

            var sawSingleChar = false
            let limit = min(n, start + maxPieceBytes)
            var end = start + 1
            while end <= limit {
                if isBoundary[end] {
                    // ⚠ 바이트로 찾는다. `String` 키로 찾으면 NFD/NFC 가 섞여 매치된다 — 위 주석
                    if let id = pieceToID[Array(bytes[start..<end])] {
                        let cand = best[start] + scores[Int(id)]
                        if cand > best[end] {
                            best[end] = cand; backStart[end] = start; backID[end] = id
                        }
                        if end - start == charLen { sawSingleChar = true }
                    }
                }
                end += 1
            }

            if !sawSingleChar {
                let e = start + charLen
                let cand = best[start] + unkScore
                if cand > best[e] { best[e] = cand; backStart[e] = start; backID[e] = unkID }
            }
        }

        // 되짚기. 경로가 끊겼으면(이론상 안 나온다) 통째로 <unk> 하나로 돌려준다
        guard best[n] > -Float.infinity else { return [Node(id: unkID, piece: "")] }
        var out: [Node] = []
        var pos = n
        while pos > 0 {
            let s = backStart[pos]
            guard s >= 0 else { return [Node(id: unkID, piece: "")] }
            out.append(Node(id: backID[pos],
                            piece: String(decoding: bytes[s..<pos], as: UTF8.self)))
            pos = s
        }
        return out.reversed()
    }
}
