import XCTest
import PDFKit
import AppKit
@testable import ClonieDocuments

final class DocumentExtractorTests: XCTestCase {
    func testTextPDFCanBeReadWithoutChangingOriginal() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 200))
        view.string = "Project decision: keep the original and organize a separate wiki."
        let data = view.dataWithPDF(inside: view.bounds)
        let url = dir.appendingPathComponent("decision.pdf")
        try data.write(to: url)
        let text = try DocumentExtractor.extractText(from: url)
        XCTAssertTrue(text.contains("keep the original"), text)
        XCTAssertEqual(try Data(contentsOf: url), data)
    }

    func testOneUnreadableFileDoesNotDropOtherFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let good = dir.appendingPathComponent("plan.txt")
        try "Next quarter we will revise the plan.".write(to: good, atomically: true, encoding: .utf8)
        let result = DocumentExtractor.extract(urls: [good, dir.appendingPathComponent("missing.pdf")])
        XCTAssertEqual(result.files.count, 1)
        XCTAssertEqual(result.files.first?.name, "plan.txt")
        XCTAssertEqual(result.errors.count, 1)
    }
}
