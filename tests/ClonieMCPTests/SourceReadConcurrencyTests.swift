import XCTest
import PDFKit
import AppKit
import CoreText
import ClonieCore
import ClonieDocuments
import MCP
@testable import ClonieMCP

final class SourceReadConcurrencyTests: XCTestCase {
    func testMeasureScannedPDFAndConcurrentList() async throws {
        guard ProcessInfo.processInfo.environment["CLONIE_MEASURE_SOURCE_READ"] == "1" else {
            throw XCTSkip("Opt-in real OCR measurement; deterministic concurrency/cancellation checks run by default")
        }
        let vault = try MCPTestSupport.makeVault("source-read-measure")
        defer { try? FileManager.default.removeItem(at: vault) }
        try VaultStore(vaultURL: vault).save(MCPTestSupport.sampleDocument())
        let raw = vault.appendingPathComponent("raw")
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
        let pdf = PDFDocument()
        let context = try XCTUnwrap(CGContext(data: nil, width: 700, height: 900,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 700, height: 900))
        for row in 0..<18 {
            context.textPosition = CGPoint(x: 30, y: 850 - row * 42)
            let text = NSAttributedString(string: "Clonie source read test. Keep Markdown originals. Row \(row).",
                attributes: [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.black])
            CTLineDraw(CTLineCreateWithAttributedString(text), context)
        }
        let image = NSImage(cgImage: try XCTUnwrap(context.makeImage()), size: NSSize(width: 700, height: 900))
        for index in 0..<6 { pdf.insert(try XCTUnwrap(PDFPage(image: image)), at: index) }
        XCTAssertTrue(pdf.write(to: raw.appendingPathComponent("scan.pdf")))
        XCTAssertTrue((pdf.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let tools = VaultTools(vaultURL: vault, environment: MCPTestSupport.noModelEnvironment)
        let start = Date()
        let reading = Task { try await tools.readSource(path: "raw/scan.pdf") }
        try await Task.sleep(for: .milliseconds(100))
        let listStart = Date()
        let listed = try await tools.list()
        let listElapsed = Date().timeIntervalSince(listStart)
        let result = try await reading.value
        XCTAssertEqual(listed.total, 3)
        XCTAssertFalse(result.text.isEmpty)
        print("SOURCE_READ_MEASUREMENT pages=6 listWaitSeconds=\(listElapsed) totalSeconds=\(Date().timeIntervalSince(start)) extractedCharacters=\(result.totalCharacters)")
    }

    func testProtocolListCompletesWhileSourceExtractionIsBlocked() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let entered = expectation(description: "source extraction entered")
        let blocked = BlockedRead(page: fixture.page, entered: entered)
        defer { blocked.release.signal() }
        let tools = VaultTools(vaultURL: fixture.vault, environment: MCPTestSupport.noModelEnvironment,
                               sourceRead: { _, _, _ in try blocked.read() })
        let server = await ToolServer.make(tools: tools)
        let pair = await InMemoryTransport.createConnectedPair()
        try await server.start(transport: pair.server)
        let client = Client(name: "source-concurrency-test", version: "0")
        _ = try await client.connect(transport: pair.client)
        let reading = Task { try await client.callTool(name: "vault_source_read", arguments: ["path": .string("raw/source.txt")]) }
        await fulfillment(of: [entered], timeout: 3)
        let listed = expectation(description: "list returns before extraction is released")
        let listing = Task {
            let result = try await client.callTool(name: "vault_list", arguments: [:])
            listed.fulfill()
            return result
        }
        await fulfillment(of: [listed], timeout: 2)
        blocked.release.signal()
        let (_, listError) = try await listing.value
        let (_, readError) = try await reading.value
        XCTAssertNotEqual(listError, true)
        XCTAssertNotEqual(readError, true)
        await client.disconnect()
        await server.stop()
    }

    func testCancellationReturnsBeforeActiveExtractionFinishesAndDropsLateResult() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let entered = expectation(description: "extraction entered")
        let blocked = BlockedRead(page: fixture.page, entered: entered)
        defer { blocked.release.signal() }
        let worker = SourceReadExecutor { _, _, _ in try blocked.read() }
        let reading = Task { try await worker.read(path: "raw/source.txt", offset: 0, limit: 100) }
        await fulfillment(of: [entered], timeout: 3)
        reading.cancel()
        let cancelled = expectation(description: "cancellation before release")
        let observer = Task {
            do { _ = try await reading.value; XCTFail("Cancelled request returned a successful page") }
            catch is CancellationError { cancelled.fulfill() }
            catch { XCTFail("Unexpected error: \(error)") }
        }
        await fulfillment(of: [cancelled], timeout: 2)
        blocked.release.signal()
        await observer.value
        let next = try await worker.read(path: "raw/source.txt", offset: 0, limit: 100)
        XCTAssertEqual(next.text, fixture.page.text)
        XCTAssertEqual(blocked.count, 2)
    }

    func testCancelledQueuedReadDoesNotRunExtraction() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let entered = expectation(description: "first extraction entered")
        let blocked = BlockedRead(page: fixture.page, entered: entered)
        defer { blocked.release.signal() }
        let worker = SourceReadExecutor { _, _, _ in try blocked.read() }
        let first = Task { try await worker.read(path: "raw/source.txt", offset: 0, limit: 100) }
        await fulfillment(of: [entered], timeout: 3)
        let queued = Task { try await worker.read(path: "raw/source.txt", offset: 1, limit: 100) }
        queued.cancel()
        do { _ = try await queued.value; XCTFail("Cancelled queued request succeeded") }
        catch is CancellationError {} // It must not occupy the extraction queue.
        blocked.release.signal()
        _ = try await first.value
        _ = try await worker.read(path: "raw/source.txt", offset: 0, limit: 100)
        XCTAssertEqual(blocked.count, 2)
    }

    func testAlreadyCancelledTaskDoesNotStartExtraction() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let worker = SourceReadExecutor { _, _, _ in
            XCTFail("Pre-cancelled operation ran")
            return fixture.page
        }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await worker.read(path: "raw/source.txt", offset: 0, limit: 100)
        }
        do { _ = try await task.value; XCTFail("Pre-cancelled read succeeded") }
        catch is CancellationError {}
    }

    private struct Fixture: Sendable {
        let vault: URL
        let page: SourceCatalog.Page
        init() throws {
            vault = try MCPTestSupport.makeVault("source-read")
            try VaultStore(vaultURL: vault).save(MCPTestSupport.sampleDocument())
            let raw = vault.appendingPathComponent("raw")
            try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
            try "보존할 원문".write(to: raw.appendingPathComponent("source.txt"), atomically: true, encoding: .utf8)
            page = try SourceCatalog(vaultURL: vault).read(path: "raw/source.txt")
        }
        func cleanup() { try? FileManager.default.removeItem(at: vault) }
    }

    private final class BlockedRead: @unchecked Sendable {
        private let lock = NSLock()
        private var calls = 0
        private let page: SourceCatalog.Page
        private let entered: XCTestExpectation
        let release = DispatchSemaphore(value: 0)
        var count: Int { lock.lock(); defer { lock.unlock() }; return calls }
        init(page: SourceCatalog.Page, entered: XCTestExpectation) { self.page = page; self.entered = entered }
        func read() throws -> SourceCatalog.Page {
            lock.lock()
            calls += 1
            let first = calls == 1
            lock.unlock()
            if first {
                entered.fulfill()
                guard release.wait(timeout: .now() + 5) == .success else { throw TestError.releaseTimedOut }
            }
            return page
        }
    }
    private enum TestError: Error { case releaseTimedOut }
}
