import XCTest
@testable import GhostbarCore

/// md 규약이 **관용적인가**를 잰다 (ADR 0003 §1).
///
/// ⚠ 여기서 빨개지는 것은 「형식이 틀렸다」가 아니라 **「남의 md 를 거절했다」**다.
/// 이 파일의 케이스 대부분이 *우리가 안 쓴 파일*이고, 그게 요점이다.
final class MarkdownFragmentParseTests: XCTestCase {

    private let dates = (created: Date(timeIntervalSince1970: 1_700_000_000),
                         updated: Date(timeIntervalSince1970: 1_700_000_100))

    private func parse(_ text: String, path: String = "메모.md",
                       known: Set<String> = []) -> Fragment {
        MarkdownFragment.parse(text: text, relativePath: path,
                               fallbackDates: dates, knownQuestionIds: known).fragment
    }

    // MARK: - frontmatter 가 있는 것 (우리가 쓴 모양)

    func testFullFrontmatterIsRead() {
        let f = parse("""
        ---
        id: f-1
        title: 배포 스크립트를 갈아엎었다
        questions: [q-1, q-3]
        created: 2026-08-24T09:46:40Z
        updated: 2026-08-25T00:00:00Z
        ---

        매번 손으로 하던 것을 한 줄로 줄였다.
        """)
        XCTAssertEqual(f.id, "f-1")
        XCTAssertEqual(f.title, "배포 스크립트를 갈아엎었다")
        XCTAssertEqual(f.questionIds, ["q-1", "q-3"])
        XCTAssertEqual(f.body, "매번 손으로 하던 것을 한 줄로 줄였다.")
        XCTAssertEqual(Frontmatter.iso(f.createdAt), "2026-08-24T09:46:40Z")
        XCTAssertEqual(Frontmatter.iso(f.updatedAt), "2026-08-25T00:00:00Z")
    }

    /// 옵시디언은 블록 목록을 쓴다. 흐름 목록만 읽으면 남의 볼트가 반쯤 읽힌다.
    func testBlockListAndAliasKeysAreRead() {
        let f = parse("""
        ---
        title: 블록 목록
        question_ids:
          - q-1
          - q-2
        createdAt: 2026-08-24
        ---
        본문
        """)
        XCTAssertEqual(f.questionIds, ["q-1", "q-2"])
        XCTAssertEqual(f.title, "블록 목록")
        XCTAssertEqual(Frontmatter.iso(f.createdAt), "2026-08-24T00:00:00Z")
    }

    // MARK: - frontmatter 가 없는 것 (남의 md)

    func testNoFrontmatterUsesFirstHeading() {
        let f = parse("""
        # 첫 회사에서 배운 것

        사수가 없던 팀이었다.
        """, path: "notes/입사.md")
        XCTAssertEqual(f.title, "첫 회사에서 배운 것")
        XCTAssertEqual(f.body, "사수가 없던 팀이었다.")
        XCTAssertEqual(f.id, "notes/입사", "id 가 없으면 경로가 id 다")
        XCTAssertEqual(f.createdAt, dates.created, "날짜가 없으면 파일 속성이 선다")
    }

    func testNoFrontmatterNoHeadingUsesFileName() {
        let f = parse("그냥 줄글이다.\n두 번째 줄.", path: "메모/장바구니.md")
        XCTAssertEqual(f.title, "장바구니")
        XCTAssertEqual(f.body, "그냥 줄글이다.\n두 번째 줄.")
        XCTAssertTrue(f.questionIds.isEmpty)
    }

    func testEmptyFileIsAFragmentToo() {
        let f = parse("", path: "빈 것.md")
        XCTAssertEqual(f.title, "빈 것")
        XCTAssertEqual(f.body, "")
    }

    func testWhitespaceOnlyFileIsAFragmentToo() {
        let f = parse("\n\n   \n", path: "공백.md")
        XCTAssertEqual(f.title, "공백")
        XCTAssertEqual(f.body, "")
    }

    /// `#태그` 는 제목이 아니다 — 띄어쓰기 없는 `#` 은 옵시디언에서 태그다.
    func testHashTagIsNotATitle() {
        let f = parse("#일기 오늘은 비가 왔다", path: "오늘.md")
        XCTAssertEqual(f.title, "오늘")
        XCTAssertEqual(f.body, "#일기 오늘은 비가 왔다")
    }

    func testUnclosedFrontmatterIsJustText() {
        let f = parse("---\ntitle: 안 닫았다\n\n본문", path: "깨진 머리.md")
        XCTAssertEqual(f.title, "깨진 머리", "안 닫힌 머리를 머리로 읽으면 본문이 사라진다")
        XCTAssertTrue(f.body.contains("title: 안 닫았다"))
    }

    // MARK: - 태그가 칩이 되는 자리

    func testTagBecomesQuestionOnlyWhenItIsAKnownQuestionId() {
        let text = """
        ---
        title: 태그 있는 글
        tags: [q-1, 일기, 회고]
        ---
        본문
        """
        XCTAssertEqual(parse(text, known: ["q-1"]).questionIds, ["q-1"])
        XCTAssertTrue(parse(text, known: []).questionIds.isEmpty,
                      "모르는 태그가 칩이 되면 남의 볼트가 우리 색인을 오염시킨다")
    }

    // MARK: - 다시 쓰기

    func testRenderThenParseRoundTrips() {
        let f = Fragment(id: "f-1", title: "제목: 콜론이 든 것", body: "본문\n\n둘째 문단",
                         questionIds: ["q-1"],
                         createdAt: Date(timeIntervalSince1970: 1_756_000_000),
                         updatedAt: Date(timeIntervalSince1970: 1_756_000_500))
        let text = MarkdownFragment.render(f)
        XCTAssertEqual(parse(text), f)
    }

    /// 우리가 모르는 키는 **글자 그대로** 살아남는다. 안 그러면 남의 볼트가 우리를 거칠 때마다 깎인다.
    func testUnknownFrontmatterKeysSurviveARewrite() {
        let parsed = MarkdownFragment.parse(text: """
        ---
        title: 남의 파일
        tags: [일기, 회고]
        aliases:
          - 별명
        cssclass: wide
        ---
        본문
        """, relativePath: "남.md", fallbackDates: dates)

        var edited = parsed.fragment
        edited.title = "내가 고친 제목"
        let out = MarkdownFragment.render(edited, preservedFrontmatter: parsed.preservedFrontmatter)

        XCTAssertTrue(out.contains("tags: [일기, 회고]"), "tags 가 사라졌다:\n\(out)")
        XCTAssertTrue(out.contains("aliases:"))
        XCTAssertTrue(out.contains("  - 별명"))
        XCTAssertTrue(out.contains("cssclass: wide"))
        XCTAssertEqual(out.components(separatedBy: "title:").count - 1, 1,
                       "제목이 두 줄이 됐다 — 우리 키와 남의 키가 겹쳤다:\n\(out)")
    }

    func testEmptyQuestionsKeyIsNotWritten() {
        let f = Fragment(id: "f-1", title: "제목", body: "본문", questionIds: [],
                         createdAt: Date(), updatedAt: Date())
        XCTAssertFalse(MarkdownFragment.render(f).contains("questions:"),
                       "빈 목록을 적으면 남의 볼트에 우리 흔적만 는다")
    }

    /// 화면이 넣는 id(`f-lx…`)와 제목의 특수문자가 다시 읽혀야 한다.
    func testAwkwardTitlesSurvive() {
        for title in ["true", "2026-08-30", "- 앞이 하이픈", "#해시로 시작", "따옴표 \" 든 것",
                      "[대괄호]", "끝에 콜론:", "123.45"] {
            let f = Fragment(id: "f-x", title: title, body: "b", questionIds: [],
                             createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 1))
            XCTAssertEqual(parse(MarkdownFragment.render(f)).title, title, "제목이 깨졌다: \(title)")
        }
    }
}
