import Foundation

/// sentencepiece 의 **precompiled_charsmap** 을 Swift 에서 그대로 재현한다 (#31).
///
/// ## 왜 이걸 손으로 짜야 하나
///
/// XLM-R 토크나이저는 Unigram 앞에 **정규화기**를 세운다. 그게 전각→반각, 자모 결합(NFD→NFC),
/// 호환 문자 접기를 한다. 이걸 빼먹으면 대부분의 문장은 멀쩡히 나오고 **일부만 조용히 다른
/// 토큰**이 된다 — 점수만 어긋나고 아무것도 안 터진다. 그래서 여기 있다.
///
/// ## ⚠ 상류가 **둘**이다. 우리가 베끼는 것은 HuggingFace 쪽이다
///
/// 같은 charsmap 을 두 구현이 다르게 읽는다:
///
/// - `sentencepiece`(C++) — 입력 전체에 대해 common-prefix 검색하고 **가장 긴** 매치를 쓴다
/// - `tokenizers`(Rust/HF) — **자소 묶음(grapheme) 하나씩** 잘라 검색하고 **첫 번째** 매치를 쓴다
///
/// 우리 기준면(`tests/fixtures/embedding_reference.json`)은 파이썬
/// `AutoTokenizer`(= HF `tokenizers`)가 뜬 것이다. 그러니 **HF 쪽을 베낀다.**
/// HF 원문에도 *"Yes, this seems broken / No, I don't know why Google did this"* 라는
/// 주석이 붙어 있는 자리다 — 이상해 보여도 고치면 기준면과 갈린다.
/// (`정관 1조`: 상류 것을 그대로 쓴다. `정관 2조`: 적합성은 상류 원문으로 판정한다.)
///
/// ## 이게 꺼졌는지 어떻게 아나
///
/// `tests/fixtures/embedding_reference.json` 의 `tokenizer_cases` 에 **정규화기를 일부러
/// 때리는** 문자열들이 있다(전각·NFD 한글·중복 공백). 정규화기가 통째로 죽으면 그것들이 빨개진다.
/// 평범한 한글 문장만으로는 안 잡힌다 — 그게 케이스가 그렇게 생긴 이유다.
struct PrecompiledNormalizer {

    /// Darts-clone 이중 배열 트라이. 유닛 하나가 `UInt32` 다.
    private let units: [UInt32]
    /// NUL 로 끊긴 UTF-8 문자열들이 이어 붙은 덩어리. 트라이의 값이 여기 **바이트 오프셋**이다.
    private let normalized: [UInt8]

    /// - Parameter charsmap: `tokenizer.json` 의 `precompiled_charsmap` 을 base64 푼 것.
    ///   레이아웃 = `UInt32 트라이_바이트수`(LE) + 트라이 + 치환문자열 덩어리.
    init?(charsmap: [UInt8]) {
        guard charsmap.count >= 4 else { return nil }
        let trieBytes = Int(UInt32(charsmap[0]) | UInt32(charsmap[1]) << 8
                            | UInt32(charsmap[2]) << 16 | UInt32(charsmap[3]) << 24)
        guard trieBytes > 0, trieBytes % 4 == 0, 4 + trieBytes <= charsmap.count else { return nil }

        var u = [UInt32]()
        u.reserveCapacity(trieBytes / 4)
        var i = 4
        while i < 4 + trieBytes {
            u.append(UInt32(charsmap[i]) | UInt32(charsmap[i + 1]) << 8
                     | UInt32(charsmap[i + 2]) << 16 | UInt32(charsmap[i + 3]) << 24)
            i += 4
        }
        self.units = u
        self.normalized = Array(charsmap[(4 + trieBytes)...])
    }

    // ── Darts-clone 유닛 해석. 이 넷이 그 형식의 전부다 ────────────────────────
    @inline(__always) private static func hasLeaf(_ unit: UInt32) -> Bool { (unit >> 8) & 1 == 1 }
    @inline(__always) private static func value(_ unit: UInt32) -> UInt32 { unit & 0x7FFF_FFFF }
    @inline(__always) private static func label(_ unit: UInt32) -> UInt32 { unit & (0x8000_0000 | 0xFF) }
    @inline(__always) private static func offset(_ unit: UInt32) -> UInt32 {
        (unit >> 10) << ((unit & (1 << 9)) >> 6)
    }

    /// `key` 의 접두사 중 트라이에 있는 것들의 값을 **찾은 순서대로**(= 짧은 것부터) 돌려준다.
    ///
    /// ⚠ HF 는 이 중 **첫 번째**만 쓴다(`transform`). 그래서 여기서 정렬하거나 가장 긴 것을
    ///   고르지 않는다 — 그렇게 하면 sentencepiece C++ 쪽 동작이 되고 기준면과 갈린다.
    private func commonPrefixSearch(_ key: ArraySlice<UInt8>) -> UInt32? {
        guard !units.isEmpty else { return nil }
        var nodePos = 0
        var unit = units[nodePos]
        nodePos ^= Int(Self.offset(unit))
        for byte in key {
            guard nodePos >= 0, nodePos < units.count else { return nil }
            nodePos ^= Int(byte)
            guard nodePos >= 0, nodePos < units.count else { return nil }
            unit = units[nodePos]
            if Self.label(unit) != UInt32(byte) { return nil }
            nodePos ^= Int(Self.offset(unit))
            guard nodePos >= 0, nodePos < units.count else { return nil }
            if Self.hasLeaf(unit) {
                // 첫 매치에서 바로 끊는다 — HF 의 `results[0]` 과 같은 것이다
                return Self.value(units[nodePos])
            }
        }
        return nil
    }

    /// 트라이 값(치환문자열 덩어리 안의 오프셋) → NUL 까지의 문자열.
    private func replacement(at offset: UInt32) -> String? {
        var end = Int(offset)
        guard end < normalized.count else { return nil }
        while end < normalized.count && normalized[end] != 0 { end += 1 }
        return String(decoding: normalized[Int(offset)..<end], as: UTF8.self)
    }

    /// 조각 하나를 통째로 치환해본다. 매치가 없으면 `nil`.
    private func transform(_ chunk: some Sequence<UInt8>) -> String? {
        let bytes = Array(chunk)
        guard let v = commonPrefixSearch(bytes[...]) else { return nil }
        return replacement(at: v)
    }

    /// 문자열 하나를 정규화한다. **HF `Precompiled::normalize` 를 그대로 따른다.**
    ///
    /// 절차: 자소 묶음마다 ①  6바이트 미만이면 묶음 통째로 치환 시도 → 되면 채택 ·
    /// ② 안 되면 묶음 안의 **스칼라 하나씩** 치환 시도, 안 되는 것은 원문 그대로.
    ///
    /// ⚠ Swift 의 `Character` 가 곧 확장 자소 묶음(UAX #29)이라 HF 의 `graphemes(true)` 와
    ///   같은 단위다. 이 대응이 이 함수가 짧은 이유다.
    func normalize(_ input: String) -> String {
        var out = String()
        out.reserveCapacity(input.utf8.count)
        for grapheme in input {
            let bytes = Array(grapheme.utf8)
            if bytes.count < 6, let whole = transform(bytes) {
                out += whole
                continue
            }
            for scalar in grapheme.unicodeScalars {
                if let piece = transform(Array(String(scalar).utf8)) {
                    out += piece
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out
    }
}
