import Foundation

/// Exact quantities and product identifiers break close semantic ties. This is
/// ranking evidence, not an edit of ASR text or a claim that an answer is true.
public enum RetrievalAnchors {
    public static let maximumCosineBonus = 0.035
    private static let pattern = #"[A-Za-z]+[0-9]+|[0-9]+(?:,[0-9]{3})*(?:\.[0-9]+)?\s*(?:밀리초|퍼센트|시간|만원|천원|ms|분|초|원|개|명|%|번|년|월|일|층|도)?"#
    private static let expression = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    public static func tokens(_ text: String) -> Set<String> {
        let regex = expression
        let source = text as NSString
        return Set(regex.matches(in: text, range: NSRange(location: 0, length: source.length)).map { match in
            let raw = source.substring(with: match.range).lowercased().replacingOccurrences(of: " ", with: "")
            guard let first = raw.first, first.isNumber else { return raw }
            let digits = String(raw.prefix { $0.isNumber || $0 == "." || $0 == "," })
            var unit = String(raw.dropFirst(digits.count))
            var number = Double(digits.replacingOccurrences(of: ",", with: "")) ?? 0
            if unit == "만원" { number *= 10000; unit = "원" }
            if unit == "천원" { number *= 1000; unit = "원" }
            if unit == "퍼센트" { unit = "%" }
            if unit == "ms" { unit = "밀리초" }
            return String(format: "%.12g", locale: Locale(identifier: "en_US_POSIX"), number) + unit
        })
    }
    public static func coverage(query: String, source: String) -> Double {
        let expected = tokens(query)
        guard !expected.isEmpty else { return 0 }
        return Double(expected.intersection(tokens(source)).count) / Double(expected.count)
    }
    public static func orderScore(cosine: Double, query: String, source: String) -> Double {
        cosine + maximumCosineBonus * coverage(query: query, source: source)
    }
}
