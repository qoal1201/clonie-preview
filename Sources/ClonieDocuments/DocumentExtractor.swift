import Foundation
import PDFKit
import AppKit
import UniformTypeIdentifiers
import Vision

/// 사용자가 던져 넣은 **파일 하나 → 평문 한 덩이** (#40).
///
/// 이 자리가 하는 것은 **평문까지**다. 문항으로 자르는 것도, 조각 초안을 뽑는 것도 여기가 아니다
/// (자르기 = 화면, 초안 = `FragmentDrafter`). 그래서 실패가 **덩이마다** 갈린다 —
/// 다섯 장 중 하나가 깨졌다고 넷을 버리지 않는다.
///
/// ⚠ **네트워크를 안 탄다** — `tests/check_interview_offline.py` 가 이 파일까지 따라온다
/// (브리지 `pickIngestFiles` 통로에서 닿는다). 여기 있는 것은 전부 로컬 파일·로컬 프로세스다.
/// **Vision OCR 도 온디바이스다** — `VNRecognizeTextRequest` 는 기기 안에서 돈다
/// (`FragmentDrafter` 가 FoundationModels 를 고른 것과 같은 이유: 자소서는 밖으로 안 나간다).
///
/// ⚠ **주 스레드에서 부르지 마라.** PDF·docx 를 여는 것은 파일 I/O 이고, 큰 문서 하나가
/// 창을 그대로 세운다. 부르는 쪽(`WKWebViewWrapper`)이 백그라운드 큐로 보낸다.
public enum DocumentExtractor {

    /// 뽑아낸 한 덩이. `name` 은 화면이 그대로 보여줄 파일 이름이다.
    public struct Extracted {
        public let name: String
        public let text: String
    }

    /// 못 뽑은 한 덩이. `why` 는 **사용자가 읽을 한국어 한 줄**이다 — 개발자 로그가 아니다.
    public struct Failure {
        public let name: String
        public let why: String
    }

    /// 이 자리가 받는 확장자. 화면의 파일 고르기 창(`NSOpenPanel`)과 **같은 목록**을 써야
    /// 「고를 수는 있는데 못 읽는」 파일이 안 생긴다.
    ///
    /// ⚠ `hwp` 는 **고를 수는 있는데 언제나 실패하는** 유일한 자리다 — 일부러다. 막아 두면
    /// 「왜 내 파일이 목록에 안 뜨나」로 끝나고, **한글에서 뭘 해야 하는지 말할 자리가 없다.**
    /// 사유는 `extractText` 의 `case "hwp"` 가 든다.
    public static let extensions = ["pdf", "docx", "hwpx", "hwp", "md", "markdown", "txt"]

    /// 파일 고르기 창에 걸 타입. ⚠ `hwpx`·`hwp`·`docx`·`md` 는 시스템 UTType 이 없거나 믿을 수 없어
    /// **확장자에서 만든다** — 없으면 조용히 빠지지 말고 그 자리만 건너뛴다.
    public static var contentTypes: [UTType] {
        var types: [UTType] = [.pdf, .plainText]
        for ext in ["docx", "hwpx", "hwp", "md", "markdown"] {
            // ⚠ `md` 와 `markdown` 은 **같은 타입 하나**로 풀린다(`net.daringfireball.markdown`).
            //   그대로 넣으면 목록에 중복이 앉는다.
            if let t = UTType(filenameExtension: ext), !types.contains(t) { types.append(t) }
        }
        return types
    }

    /// 여러 파일을 한 번에. **던지지 않는다** — 성공과 실패를 나눠 돌려준다.
    public static func extract(urls: [URL]) -> (files: [Extracted], errors: [Failure]) {
        var files: [Extracted] = []
        var errors: [Failure] = []
        for url in urls {
            let name = url.lastPathComponent
            do {
                let text = try extractText(from: url)
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    // ⚠ 「열렸다」와 「글자가 있다」는 다르다. 스캔한 PDF 가 여기로 온다 —
                    //   열리기는 열리는데 글자층이 없다. 그걸 빈 조각으로 넘기면 화면이 조용히 빈다.
                    errors.append(Failure(name: name, why: "글자를 못 찾았다 — 스캔한 이미지이거나 빈 문서다"))
                } else {
                    files.append(Extracted(name: name, text: trimmed))
                }
            } catch {
                errors.append(Failure(name: name, why: (error as? ExtractError)?.message ?? "읽지 못했다"))
            }
        }
        return (files, errors)
    }

    public enum ExtractError: Error {
        case unsupported(String)
        case unreadable(String)

        public var message: String {
            switch self {
            case .unsupported(let ext):
                return ext.isEmpty ? "확장자가 없어 무엇인지 모른다"
                                   : "아직 못 읽는 형식이다 (.\(ext))"
            case .unreadable(let detail):
                return detail
            }
        }
    }

    public static func extractText(from url: URL) throws -> String {
        switch url.pathExtension.lowercased() {
        case "pdf":               return try extractPDF(url)
        case "docx":              return try extractOfficeOpenXML(url)
        case "hwpx":              return try extractHWPX(url)
        case "hwp":
            // 바이너리 HWP 5.0 은 **CFB 안의 zlib 스트림**이라 hwpx(zip+XML)와 아무 관계가 없다.
            // 우리 파서를 짜지 않는다(`정관 1조`) — 대신 **사람이 30초에 할 수 있는 우회**를 말한다.
            throw ExtractError.unreadable(
                "바이너리 .hwp 는 아직 못 읽는다 — 한글에서 hwpx 나 PDF 로 저장해 다시 던져넣어라")
        case "md", "markdown", "txt", "":
            // 확장자가 없어도 평문으로 한 번 시도한다 — 실패하면 아래 `unreadable` 이 말한다.
            return try extractPlainText(url)
        default:
            throw ExtractError.unsupported(url.pathExtension.lowercased())
        }
    }

    // MARK: - PDF

    /// OCR 로 훑을 페이지 상한. **스캔 자소서는 몇 장이다** — 200장짜리 스캔본이 오면
    /// 창이 몇 분을 선다. 넘는 부분은 조용히 버리는 게 아니라 **앞 N장으로 초안을 낸다**
    /// (`FragmentDrafter.inputLimit` 이 긴 글을 앞부분으로 자르는 것과 같은 규율).
    static let ocrPageLimit = 20

    private static func extractPDF(_ url: URL) throws -> String {
        guard let doc = PDFDocument(url: url) else {
            throw ExtractError.unreadable("PDF 를 열지 못했다 — 손상됐거나 암호가 걸려 있다")
        }
        if doc.isLocked {
            throw ExtractError.unreadable("암호가 걸린 PDF 다")
        }
        let layer = doc.string ?? ""
        if !layer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return layer }
        // ★ 글자층이 0건이다 = **스캔한 PDF**. 여기서 물러서면 사용자가 할 수 있는 게 없다
        //   (자소서 원본이 없어서 스캔본을 던진 것이다). 그림에서 글자를 읽어 본다.
        //   ⚠ 그래도 0건이면 `extract(urls:)` 의 빈 판정이 기존 문구로 말한다 — 여긴 안 던진다.
        return ocrPDF(doc)
    }

    /// 스캔 PDF → 글자. **던지지 않는다** — 못 읽으면 빈 문자열이고, 그걸 부르는 쪽이 판정한다.
    ///
    /// ⚠ **페이지 하나가 실패해도 나머지를 버리지 않는다** — 이 파일 전체의 규율과 같다.
    private static func ocrPDF(_ doc: PDFDocument) -> String {
        var pages: [String] = []
        for i in 0..<min(doc.pageCount, ocrPageLimit) {
            guard let page = doc.page(at: i), let image = pageImage(page) else { continue }
            let text = recognizeText(image)
            if !text.isEmpty { pages.append(text) }
        }
        return pages.joined(separator: "\n\n")
    }

    /// 페이지 하나를 비트맵으로. **PDFKit 의 렌더러를 쓴다** — CoreGraphics 로 손수 그리지 않는다.
    ///
    /// ⚠ 72dpi 그대로 그리면 본문 글자가 OCR 문턱 아래로 떨어진다. **2배로 키운다**(≈144dpi).
    private static func pageImage(_ page: PDFPage) -> CGImage? {
        let box = page.bounds(for: .mediaBox)
        guard box.width > 1, box.height > 1 else { return nil }
        let size = NSSize(width: box.width * 2, height: box.height * 2)
        var rect = CGRect(origin: .zero, size: size)
        return page.thumbnail(of: size, for: .mediaBox)
            .cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    /// 그림 한 장에서 줄들을 읽는다. **온디바이스** — 네트워크를 안 탄다(이 파일 머리글).
    ///
    /// ⚠ 언어를 `ko-KR` 먼저 세운다. 순서가 우선순위다 — 영어를 앞에 두면 한글이
    /// 로마자로 뭉개진 후보가 1위로 올라온다.
    private static func recognizeText(_ image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ko-KR", "en-US"]
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do { try handler.perform([request]) } catch { return "" }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }

    // MARK: - docx

    /// `textutil` 이 쓰는 것과 **같은 Cocoa 리더**다 (`실측 2026-08-30`: 한국어 왕복 통과).
    /// 우리 파서를 짜지 않는다 — `정관 1조`.
    private static func extractOfficeOpenXML(_ url: URL) throws -> String {
        do {
            let attributed = try NSAttributedString(
                url: url,
                options: [.documentType: NSAttributedString.DocumentType.officeOpenXML],
                documentAttributes: nil)
            return attributed.string
        } catch {
            throw ExtractError.unreadable("Word 문서를 읽지 못했다 — 손상됐거나 우리가 모르는 판이다")
        }
    }

    // MARK: - hwpx

    /// hwpx 는 **zip 안의 XML** 이다. 본문은 `Contents/section0.xml`, `section1.xml` … 로 갈려 있고
    /// 글자는 `<hp:t>` 안에, 문단은 `<hp:p>` 로 끊긴다.
    ///
    /// ⚠ **완벽한 hwpx 파서가 아니다.** 표·각주·머리말의 순서는 보장하지 않는다 —
    /// 목표는 「본문 텍스트가 순서대로 나온다」까지다. 그 뒤는 사람이 화면에서 자른다.
    ///
    /// ⚠ zip 을 손으로 안 푼다 — `/usr/bin/unzip` 을 부른다 (`정관 1조`: 이미 있는 것을 쓴다).
    private static func extractHWPX(_ url: URL) throws -> String {
        let names = try zipEntryNames(url)
        // `Contents/section0.xml` … 숫자 순으로. 문자열 정렬이면 section10 이 section2 앞에 온다.
        let sections = names
            .filter { $0.lowercased().hasSuffix(".xml") && $0.lowercased().contains("section") }
            .sorted { sectionOrder($0) < sectionOrder($1) }
        guard !sections.isEmpty else {
            throw ExtractError.unreadable("hwpx 안에서 본문(section*.xml)을 못 찾았다")
        }
        var chunks: [String] = []
        for entry in sections {
            guard let data = try? zipEntryData(url, entry: entry) else { continue }
            let text = hwpxSectionText(data)
            if !text.isEmpty { chunks.append(text) }
        }
        if chunks.isEmpty {
            throw ExtractError.unreadable("hwpx 본문을 해석하지 못했다")
        }
        return chunks.joined(separator: "\n")
    }

    private static func sectionOrder(_ name: String) -> Int {
        guard let range = name.range(of: "[0-9]+(?=\\.[Xx][Mm][Ll]$)", options: .regularExpression) else {
            return Int.max
        }
        return Int(name[range]) ?? Int.max
    }

    /// zip 목록. `-Z1` 은 이름만 한 줄씩 낸다.
    private static func zipEntryNames(_ url: URL) throws -> [String] {
        let out = try runUnzip(["-Z1", url.path])
        return out.split(separator: "\n").map(String.init)
    }

    /// zip 안의 파일 하나를 **표준출력으로** 꺼낸다 — 임시 디렉터리를 안 만든다.
    private static func zipEntryData(_ url: URL, entry: String) throws -> Data {
        Data(try runUnzip(["-p", url.path, entry]).utf8)
    }

    private static func runUnzip(_ arguments: [String]) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch {
            throw ExtractError.unreadable("압축을 푸는 도구를 못 불렀다 (/usr/bin/unzip)")
        }
        // ⚠ 먼저 다 읽고 그다음에 기다린다. 순서를 뒤집으면 파이프가 차서 **서로 기다린다**.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        if task.terminationStatus != 0 && data.isEmpty {
            throw ExtractError.unreadable("zip 컨테이너를 열지 못했다 — hwpx 가 손상됐다")
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func hwpxSectionText(_ data: Data) -> String {
        let collector = HWPXTextCollector()
        let parser = XMLParser(data: data)
        parser.delegate = collector
        parser.parse()
        return collector.text()
    }

    // MARK: - md / txt

    private static func extractPlainText(_ url: URL) throws -> String {
        if let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        // ⚠ UTF-8 이 아닌 것이 실제로 온다 — 한국어 텍스트 파일은 아직 EUC-KR 이 살아 있다.
        var used: String.Encoding = .utf8
        if let s = try? String(contentsOf: url, usedEncoding: &used) { return s }
        if let data = try? Data(contentsOf: url),
           let s = String(data: data, encoding: String.Encoding(rawValue:
                            CFStringConvertEncodingToNSStringEncoding(
                                CFStringEncoding(CFStringEncodings.EUC_KR.rawValue)))) {
            return s
        }
        throw ExtractError.unreadable("글자 인코딩을 알아내지 못했다")
    }
}

/// hwpx 본문 XML 에서 **글자만** 줍는다. 문단(`hp:p`)이 끝나면 줄을 바꾼다.
///
/// ⚠ 이름공간 처리를 켜지 않는다 — 요소 이름이 `hp:t` 그대로 온다. 한글 판마다 접두사가
/// 다를 수 있어 **접미사로** 본다(`:t` 로 끝나나).
private final class HWPXTextCollector: NSObject, XMLParserDelegate {
    private var lines: [String] = []
    private var current = ""
    private var depth = 0        // `t` 요소 안인가

    func text() -> String {
        flush()
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func flush() {
        let line = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !line.isEmpty { lines.append(line) }
        current = ""
    }

    private static func isText(_ element: String) -> Bool {
        element == "t" || element.hasSuffix(":t")
    }

    private static func isParagraph(_ element: String) -> Bool {
        element == "p" || element.hasSuffix(":p")
    }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        if Self.isText(element) { depth += 1 }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard depth > 0 else { return }
        current += string
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?,
                qualifiedName: String?) {
        if Self.isText(element) { depth = max(0, depth - 1) }
        if Self.isParagraph(element) { flush() }
    }
}
