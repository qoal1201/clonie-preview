import Foundation

/// 조각 1장 = .md 1장. **이 파일이 그 규약의 정본이다** (ADR 0003 §1).
///
/// ## 관용이 규약이다
///
/// frontmatter 는 **선택**이고 요구 양식이 없다. 어떤 md 든 읽힌다 —
/// 다르면 오류가 아니라 **덜 풍부하게** 읽힐 뿐이다. 옵시디언 볼트를 그대로 연결하는 것이
/// 이 조항의 목적이라, *"이건 우리 형식이 아니다"* 로 거절하는 경로가 여기 **없다.**
///
/// ```
/// 제목  = frontmatter `title` → 첫 제목줄(`# …`) → 파일명
/// 본문  = 나머지 전부 (제목줄로 쓴 줄은 뺀다)
/// id    = frontmatter `id` → 볼트 기준 상대경로(확장자 뺀 것)
/// 날짜  = frontmatter `created`/`updated` → 파일 속성(생성·수정 시각)
/// 질문  = frontmatter `questions` ∪ (`tags` 중 **이미 있는 질문 id** 와 같은 것)
/// ```
///
/// ## 우리가 안 쓰는 키는 **글자 그대로 보존한다**
///
/// `tags`·`aliases`·`cssclass` 같은 것은 우리 모델에 자리가 없다. 그래서 **파싱만 하고
/// 다시 쓸 때 원문 줄을 그대로 되돌려 놓는다** — 우리가 모르는 것을 지우면 사용자의 볼트가
/// 우리 앱을 한 번 거칠 때마다 깎여나간다.
///
/// # 한계
///
/// - YAML 을 **다 파싱하지 않는다.** 평평한 `key: value`, 흐름 목록 `[a, b]`, 블록 목록
///   `- a` 까지다. 그 밖(중첩 맵·블록 스칼라 `|`·앵커)은 **원문 줄로만** 다룬다 —
///   값으로 읽지 않고, 되쓸 때 그대로 되돌린다. 값으로 안 읽히는 것이 손실은 아니다.
/// - 스칼라의 `#` 주석을 안 걷는다. 걷으면 제목에 든 `#` 이 잘린다 — 덜 읽는 쪽을 골랐다.
public enum MarkdownFragment {

    // MARK: - 우리가 소유하는 키

    /// 다시 쓸 때 **우리가 채우는** 키들. 나머지는 손대지 않는다.
    /// 별칭은 읽기만 하고, 되쓸 때는 정식 이름 하나로 모인다 (같은 뜻이 두 줄로 남지 않게).
    public static let ownedKeys: Set<String> = [
        "id",
        "title",
        "questions", "question_ids", "questionids",
        "created", "createdat", "created_at", "date",
        "updated", "updatedat", "updated_at", "modified",
        // ★ 씨앗 표식. **우리가 쓴 것만 우리가 읽는다** — 남의 볼트에 `seed: true` 가 있을 리
        //   없고, 있더라도 하는 일은 「그 한 장을 라이브 순위에서 뺀다」뿐이다.
        "seed",
    ]

    // MARK: - 읽기

    /// md 한 장을 조각으로 읽는다. **던지지 않는다** — 어떤 글자든 조각이 된다.
    ///
    /// - Parameters:
    ///   - text: 파일 내용 그대로.
    ///   - relativePath: 볼트 기준 상대경로 (`메모/배포.md`). id 와 파일명 제목의 뿌리다.
    ///   - fallbackDates: frontmatter 에 날짜가 없을 때 쓸 값 (파일 속성).
    ///   - knownQuestionIds: `tags` 가 질문 칩으로 읽히는 유일한 조건 — **이미 있는 질문 id** 와 같을 때.
    public static func parse(text: String,
                             relativePath: String,
                             fallbackDates: (created: Date, updated: Date),
                             knownQuestionIds: Set<String> = []) -> ParsedFile {
        let split = Frontmatter.split(text)
        let fm = split.frontmatter

        let stem = (relativePath as NSString).deletingPathExtension
        let fileName = (stem as NSString).lastPathComponent

        var title = fm.scalar(forAnyOf: ["title"])?.trimmingCharacters(in: .whitespaces) ?? ""
        var bodySource = split.body
        if title.isEmpty {
            let heading = firstHeading(in: bodySource)
            if let h = heading {
                title = h.text
                bodySource = h.rest
            } else {
                title = fileName
            }
        }
        if title.isEmpty { title = fileName }

        let id = fm.scalar(forAnyOf: ["id"])?.trimmingCharacters(in: .whitespaces).nonEmpty ?? stem

        var questionIds = fm.list(forAnyOf: ["questions", "question_ids", "questionIds"])
        // 태그가 질문 칩이 되는 자리. **이미 있는 질문 id 와 같을 때만이다** —
        // 아무 태그나 칩으로 승격하면 남의 볼트가 우리 색인을 오염시킨다.
        for tag in fm.list(forAnyOf: ["tags", "tag"]) where knownQuestionIds.contains(tag) {
            if !questionIds.contains(tag) { questionIds.append(tag) }
        }

        let created = fm.date(forAnyOf: ["created", "createdAt", "created_at", "date"])
            ?? fallbackDates.created
        let updated = fm.date(forAnyOf: ["updated", "updatedAt", "updated_at", "modified"])
            ?? fallbackDates.updated

        // 씨앗 표식. **참일 때만 든다** — 없으면 `nil` 이라 옛 파일이 그대로 읽히고,
        // 되쓸 때도 키가 안 생긴다(`render` 가 `true` 에서만 쓴다).
        let seed = Frontmatter.truthy(fm.scalar(forAnyOf: ["seed"])) ? true : nil

        let fragment = Fragment(
            id: id,
            title: title,
            body: bodySource.trimmingCharacters(in: .whitespacesAndNewlines),
            questionIds: questionIds,
            createdAt: created,
            updatedAt: updated,
            seed: seed)

        return ParsedFile(fragment: fragment,
                          relativePath: relativePath,
                          preservedFrontmatter: fm.rawLines(excluding: ownedKeys),
                          hadFrontmatterID: fm.scalar(forAnyOf: ["id"])?.nonEmpty != nil)
    }

    /// 첫 제목줄(`# …`)과 그 뒤 전부. 없으면 `nil`.
    private static func firstHeading(in text: String) -> (text: String, rest: String)? {
        var seen: [Substring] = []
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)[...]
        while let line = lines.first {
            lines = lines.dropFirst()
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { seen.append(line); continue }
            guard t.hasPrefix("#") else { return nil }   // 첫 알맹이가 제목줄이 아니면 없는 것이다
            let hashes = t.prefix { $0 == "#" }
            guard hashes.count <= 6 else { return nil }
            let rest = t.dropFirst(hashes.count)
            guard rest.first?.isWhitespace == true else { return nil }  // `#태그` 는 제목이 아니다
            let heading = rest.trimmingCharacters(in: .whitespaces)
            guard !heading.isEmpty else { return nil }
            return (heading, lines.joined(separator: "\n"))
        }
        return nil
    }

    // MARK: - 쓰기

    /// 조각을 md 글자로 만든다. `preserved` 는 우리가 모르는 frontmatter 줄 — **그대로 되돌려 놓는다.**
    public static func render(_ f: Fragment, preservedFrontmatter preserved: [String] = []) -> String {
        var head: [String] = []
        head.append("id: " + Frontmatter.emit(f.id))
        head.append("title: " + Frontmatter.emit(f.title))
        if !f.questionIds.isEmpty {
            head.append("questions: [" + f.questionIds.map(Frontmatter.emit).joined(separator: ", ") + "]")
        }
        head.append("created: " + Frontmatter.iso(f.createdAt))
        head.append("updated: " + Frontmatter.iso(f.updatedAt))
        // ⚠ **거짓일 때는 줄을 안 쓴다.** `seed: false` 를 남기면 사람이 고친 조각의 md 에
        //   우리 전용 키가 영영 남는다 — 표식을 뗀다는 것은 그 줄이 사라진다는 뜻이다.
        if f.seed == true { head.append("seed: true") }
        head.append(contentsOf: preserved)

        let body = f.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return "---\n" + head.joined(separator: "\n") + "\n---\n\n" + body + (body.isEmpty ? "" : "\n")
    }
}

/// md 한 장을 읽은 결과. 조각 말고도 **되쓸 때 필요한 것**을 같이 나른다.
public struct ParsedFile: Equatable, Sendable {
    public var fragment: Fragment
    /// 볼트 기준 상대경로. 되쓸 때 **같은 자리**에 쓰려고 든다 — 파일이 옮겨 다니면 안 된다.
    public var relativePath: String
    /// 우리가 안 쓰는 frontmatter 줄들 (원문 그대로).
    public var preservedFrontmatter: [String]
    /// frontmatter 가 id 를 갖고 있었나. 없으면 경로에서 만든 것이라 **파일을 옮기면 id 가 바뀐다.**
    public var hadFrontmatterID: Bool

    public init(fragment: Fragment, relativePath: String,
                preservedFrontmatter: [String] = [], hadFrontmatterID: Bool = false) {
        self.fragment = fragment
        self.relativePath = relativePath
        self.preservedFrontmatter = preservedFrontmatter
        self.hadFrontmatterID = hadFrontmatterID
    }
}

// MARK: - frontmatter (YAML 의 **아주 얕은** 부분집합)

/// `---` 로 감싼 머리를 읽고 쓴다. 값으로 못 읽는 것은 **원문 줄로** 든다.
///
/// # 한계
/// YAML 파서가 아니다. 여기서 파싱하는 것은 평평한 `key: value`, `[a, b]`, `- a` 뿐이다.
/// 상류 규격(YAML 1.2)을 다 따르려면 의존을 하나 들여야 하는데, ADR 0003 이 요구하는 것은
/// **읽히면 읽고 아니면 덜 읽는 것**이라 그 값이 이 파일의 크기를 안 넘는다.
/// 다시 열 조건 = frontmatter 를 **값으로 편집**해야 할 때 (지금은 보존만 한다).
public struct Frontmatter: Equatable {

    public struct Entry: Equatable {
        public var key: String
        public var scalar: String?
        public var list: [String]?
        /// 이 항목이 차지한 원문 줄 **전부** (이어지는 목록 줄까지).
        public var raw: [String]
    }

    public var entries: [Entry] = []

    // MARK: 나누기

    /// 글자를 (frontmatter, 본문) 으로 가른다. 머리가 없으면 빈 frontmatter 와 글자 전부.
    public static func split(_ text: String) -> (frontmatter: Frontmatter, body: String) {
        // BOM 만 걷는다. 그 앞에 빈 줄이 있으면 frontmatter 가 아니다 (YAML 도 그렇게 본다).
        var t = text
        if t.hasPrefix("\u{FEFF}") { t.removeFirst() }
        let lines = t.split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = lines.first,
              first.trimmingCharacters(in: .whitespaces) == "---" else {
            return (Frontmatter(), text)
        }
        var end: Int?
        for i in 1..<lines.count {
            let l = lines[i].trimmingCharacters(in: .whitespaces)
            if l == "---" || l == "..." { end = i; break }
        }
        guard let close = end else { return (Frontmatter(), text) }  // 안 닫혔으면 머리가 아니다
        let head = lines[1..<close].map(String.init)
        let body = lines[(close + 1)...].joined(separator: "\n")
        return (Frontmatter(lines: head), body)
    }

    public init() {}

    /// frontmatter 줄들을 읽는다.
    public init(lines: [String]) {
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // 빈 줄·주석·목록 조각은 **앞 항목에 붙인다.** 붙일 앞이 없으면 떠도는 줄로 보존한다.
            guard let colon = topLevelColon(line), !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
                if entries.isEmpty {
                    entries.append(Entry(key: "", scalar: nil, list: nil, raw: [line]))
                } else {
                    entries[entries.count - 1].raw.append(line)
                }
                i += 1
                continue
            }
            let key = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            let rest = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            var entry = Entry(key: key, scalar: nil, list: nil, raw: [line])

            if rest.isEmpty {
                // 블록 목록이 이어지나 본다. `- a` 만 목록으로 읽는다 — 나머지는 원문만 든다.
                var items: [String] = []
                var j = i + 1
                while j < lines.count {
                    let t = lines[j].trimmingCharacters(in: .whitespaces)
                    if t.isEmpty { break }
                    if t.hasPrefix("- ") || t == "-" {
                        items.append(Frontmatter.unquote(String(t.dropFirst(1))
                            .trimmingCharacters(in: .whitespaces)))
                        entry.raw.append(lines[j])
                        j += 1
                        continue
                    }
                    if lines[j].first?.isWhitespace == true {   // 중첩 맵 — 값으로 안 읽고 줄만 든다
                        entry.raw.append(lines[j])
                        j += 1
                        continue
                    }
                    break
                }
                if !items.isEmpty { entry.list = items }
                i = j
            } else if rest.hasPrefix("["), rest.hasSuffix("]") {
                entry.list = Frontmatter.splitFlow(String(rest.dropFirst().dropLast()))
                i += 1
            } else {
                entry.scalar = Frontmatter.unquote(rest)
                i += 1
            }
            entries.append(entry)
        }
    }

    /// 맨 위 단계의 `:` 자리. 따옴표 안의 것은 안 센다.
    private static func topLevelColon(_ line: String) -> String.Index? { _topLevelColon(line) }
    private func topLevelColon(_ line: String) -> String.Index? { Frontmatter._topLevelColon(line) }
    private static func _topLevelColon(_ line: String) -> String.Index? {
        guard line.first?.isWhitespace != true, !line.hasPrefix("-") else { return nil }
        var quote: Character?
        var idx = line.startIndex
        while idx < line.endIndex {
            let c = line[idx]
            if let q = quote {
                if c == q { quote = nil }
            } else if c == "\"" || c == "'" {
                quote = c
            } else if c == ":" {
                return idx
            }
            idx = line.index(after: idx)
        }
        return nil
    }

    // MARK: 값 꺼내기 — 대소문자·별칭을 안 가린다 (읽기는 너그럽게)

    public func scalar(forAnyOf keys: [String]) -> String? {
        for k in keys.map({ $0.lowercased() }) {
            if let e = entries.first(where: { $0.key.lowercased() == k }) {
                if let s = e.scalar { return s }
                if let l = e.list, let f = l.first { return f }
            }
        }
        return nil
    }

    public func list(forAnyOf keys: [String]) -> [String] {
        for k in keys.map({ $0.lowercased() }) {
            guard let e = entries.first(where: { $0.key.lowercased() == k }) else { continue }
            if let l = e.list { return l.filter { !$0.isEmpty } }
            if let s = e.scalar, !s.isEmpty {
                // `tags: 하나, 둘` 처럼 쉼표로 적는 사람이 있다. 쉼표가 없으면 한 개다.
                return s.contains(",")
                    ? s.split(separator: ",").map {
                        Frontmatter.unquote($0.trimmingCharacters(in: .whitespaces)) }
                        .filter { !$0.isEmpty }
                    : [s]
            }
        }
        return []
    }

    public func date(forAnyOf keys: [String]) -> Date? {
        guard let raw = scalar(forAnyOf: keys)?.trimmingCharacters(in: .whitespaces), !raw.isEmpty
        else { return nil }
        return Frontmatter.parseDate(raw)
    }

    /// 우리가 안 쓰는 항목의 **원문 줄들**. 되쓸 때 그대로 되돌려 놓는다.
    public func rawLines(excluding owned: Set<String>) -> [String] {
        entries.filter { !owned.contains($0.key.lowercased()) }.flatMap(\.raw)
    }

    // MARK: 글자 다루기

    static func unquote(_ s: String) -> String {
        guard s.count >= 2 else { return s }
        if s.hasPrefix("\""), s.hasSuffix("\"") {
            let inner = String(s.dropFirst().dropLast())
            // JSON 과 같은 escape 다. 못 읽으면 안쪽 글자를 그대로 준다 (거절하지 않는다).
            if let d = "\"\(inner)\"".data(using: .utf8),
               let v = try? JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed]) as? String {
                return v
            }
            return inner
        }
        if s.hasPrefix("'"), s.hasSuffix("'") {
            return String(s.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        return s
    }

    static func splitFlow(_ s: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var quote: Character?
        for c in s {
            if let q = quote {
                cur.append(c)
                if c == q { quote = nil }
            } else if c == "\"" || c == "'" {
                quote = c
                cur.append(c)
            } else if c == "," {
                out.append(unquote(cur.trimmingCharacters(in: .whitespaces)))
                cur = ""
            } else {
                cur.append(c)
            }
        }
        let last = unquote(cur.trimmingCharacters(in: .whitespaces))
        if !last.isEmpty || !out.isEmpty { out.append(last) }
        return out.filter { !$0.isEmpty }
    }

    /// 값 하나를 YAML 스칼라로 낸다. **애매하면 따옴표를 친다** — 우리가 쓴 것은 우리가 다시 읽는다.
    public static func emit(_ s: String) -> String {
        let needsQuote = s.isEmpty
            || s != s.trimmingCharacters(in: .whitespaces)
            || s.contains(":") || s.contains("#") || s.contains("\n")
            || s.contains("[") || s.contains("]") || s.contains("{") || s.contains("}")
            || s.contains(",") || s.contains("\"") || s.contains("'")
            || "-?&*!|>%@`".contains(s.first ?? "x")
            || ["true", "false", "yes", "no", "null", "~", "on", "off"].contains(s.lowercased())
            || Double(s) != nil
        guard needsQuote else { return s }
        guard let d = try? JSONSerialization.data(withJSONObject: s, options: [.fragmentsAllowed]),
              let lit = String(data: d, encoding: .utf8) else { return "\"\"" }
        return lit
    }

    static let isoOut: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    public static func iso(_ d: Date) -> String { isoOut.string(from: d) }

    /// YAML 의 참. **읽기는 너그럽다** — `true`·`yes`·`on`·`1` 을 다 받는다(YAML 1.1 의 그 목록).
    /// 되쓸 때는 `true` 하나로 모인다(`render`). `nil`·그 밖은 전부 거짓이다.
    public static func truthy(_ raw: String?) -> Bool {
        guard let s = raw?.trimmingCharacters(in: .whitespaces).lowercased(), !s.isEmpty
        else { return false }
        return ["true", "yes", "on", "y", "1"].contains(unquote(s).lowercased())
    }

    /// 날짜를 **여러 모양으로** 받는다. 못 읽으면 `nil` 이고, 그러면 파일 속성이 대신 선다.
    public static func parseDate(_ raw: String) -> Date? {
        let s = unquote(raw)
        if let d = isoOut.date(from: s) { return d }
        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = frac.date(from: s) { return d }
        for fmt in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(secondsFromGMT: 0)
            df.dateFormat = fmt
            if let d = df.date(from: s) { return d }
        }
        return nil
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
