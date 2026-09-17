import Foundation

/// Finds quantity mentions in a proposed session draft that are not grounded
/// in the cited source text. This is a narrow guard for numeric claims; it
/// does not validate source IDs, names, or the truth of a claim.
public enum SessionDraftGrounding {
    private struct Quantity {
        let raw: String
        let canonical: String?
        let range: NSRange
    }

    private static let malformedQuantityExpression = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\d])[\d][\d\p{Zs}\t,]*[^\d\p{Zs}\t\r\n\p{L},.\-+][\d\p{Zs}\t,]*(?:[\p{Zs}\t]*(?:만|천)[\p{Zs}\t]*원|[\p{Zs}\t]*(?:만원|천원)|[\p{Zs}\t]*(?:퍼센트|%|밀리초|ms|시간|분|초|원|개|명|번|년|월|일|층|도))"#,
        options: [.caseInsensitive]
    )
    private static let quantityExpression = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\d])[\d][\d\p{Zs}\t,]*(?:\.[\d]+)?(?:[\p{Zs}\t]*(?:만|천)[\p{Zs}\t]*원|[\p{Zs}\t]*(?:만원|천원)|[\p{Zs}\t]*(?:퍼센트|%|밀리초|ms|시간|분|초|원|개|명|번|년|월|일|층|도))?"#,
        options: [.caseInsensitive]
    )

    /// Returns the raw quantity mentions in `proposal` that have no matching
    /// quantity in `source`.
    ///
    /// Comparison deliberately stays narrow: whitespace inside a number,
    /// thousands separators, and the equivalent `만 원`/`만원` and
    /// `천 원`/`천원` spellings are normalized. Numeric values and unit
    /// families remain distinct, so `350만 원` does not match `320만 원`,
    /// `0.8%`, or an equivalent-value `천 원` expression. A proposal with no
    /// numeric quantity is allowed through; this helper does not prove that
    /// its non-numeric claims are grounded.
    ///
    /// Non-standard separators inside a number, such as the degree sign in
    /// `3°50만 원`, are conservatively rejected instead of being guessed as
    /// `350만 원`, even if the source contains the latter.
    public static func unsupportedQuantities(proposal: String, source: String) -> [String] {
        let sourceQuantities = quantities(in: source)
            .compactMap(\.canonical)
        let sourceSet = Set(sourceQuantities)
        var seen = Set<String>()
        var unsupported: [String] = []

        for quantity in quantities(in: proposal) {
            guard let canonical = quantity.canonical else {
                if seen.insert(quantity.raw).inserted {
                    unsupported.append(quantity.raw)
                }
                continue
            }
            guard !sourceSet.contains(canonical) else { continue }
            if seen.insert(quantity.raw).inserted {
                unsupported.append(quantity.raw)
            }
        }
        return unsupported
    }

    private static func quantities(in text: String) -> [Quantity] {
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard fullRange.length > 0 else { return [] }

        let malformed = malformedQuantityExpression.matches(in: text, range: fullRange)
            .map { match in
                Quantity(raw: rawText(text, range: match.range), canonical: nil, range: match.range)
            }
        let malformedRanges = malformed.map(\.range)
        let valid = quantityExpression.matches(in: text, range: fullRange).compactMap { match -> Quantity? in
            guard !malformedRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else {
                return nil
            }
            let raw = rawText(text, range: match.range)
            return Quantity(raw: raw, canonical: canonical(raw), range: match.range)
        }

        return (malformed + valid).sorted { $0.range.location < $1.range.location }
    }

    private static func rawText(_ text: String, range: NSRange) -> String {
        (text as NSString).substring(with: range)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func canonical(_ raw: String) -> String? {
        let compact = raw
            .replacingOccurrences(of: #"[\p{Zs}\t]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: ",", with: "")
            .lowercased()

        let units: [(suffix: String, key: String)] = [
            ("퍼센트", "%"), ("밀리초", "밀리초"), ("만원", "만"), ("천원", "천"),
            ("시간", "시간"), ("ms", "밀리초"), ("분", "분"), ("초", "초"),
            ("원", "원"), ("개", "개"), ("명", "명"), ("번", "번"),
            ("년", "년"), ("월", "월"), ("일", "일"), ("층", "층"), ("도", "도"),
            ("%", "%"), ("만", "만"), ("천", "천")
        ]

        var numberPart = compact
        var unit = ""
        for candidate in units {
            if compact.hasSuffix(candidate.suffix) {
                numberPart = String(compact.dropLast(candidate.suffix.count))
                unit = candidate.key
                break
            }
        }
        guard !numberPart.isEmpty,
              numberPart.range(of: #"^[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil,
              let normalizedNumber = normalizeNumber(numberPart) else {
            return nil
        }
        return normalizedNumber + "|" + unit
    }

    private static func normalizeNumber(_ number: String) -> String? {
        guard number.range(of: #"^[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil else {
            return nil
        }
        let parts = number.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }
        let integer = parts[0].drop(while: { $0 == "0" })
        let normalizedInteger = integer.isEmpty ? "0" : String(integer)
        guard parts.count == 2 else { return normalizedInteger }
        let fraction = parts[1].reversed().drop(while: { $0 == "0" }).reversed()
        guard !fraction.isEmpty else { return normalizedInteger }
        return normalizedInteger + "." + String(fraction)
    }
}
