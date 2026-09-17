import XCTest
@testable import ClonieDocuments

final class DocumentImporterTests: XCTestCase {
    private func fixture() throws -> (URL, URL, URL) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("clonie-import-" + UUID().uuidString)
        let vault = base.appendingPathComponent("vault")
        let inputs = base.appendingPathComponent("inputs")
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("자료"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: inputs, withIntermediateDirectories: true)
        return (base, vault, inputs)
    }
    private func put(_ text: String, _ url: URL) throws { try Data(text.utf8).write(to: url) }

    func testMarkdownCopiesExactBytesToRootAndDoesNotStartRuntime() async throws {
        let (base, vault, inputs) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let source = inputs.appendingPathComponent("노트.md")
        let data = Data("# 내 노트\r\n\r\n원래 내용\n".utf8); try data.write(to: source)
        let converter = FixtureConverter()
        let importer = DocumentImporter(vaultURL: vault, converter: converter)
        let results = await importer.importFiles(urls: [source], destination: "")
        XCTAssertEqual(results.first?.status, .success)
        XCTAssertEqual(results.first?.markdownPath, "노트.md")
        XCTAssertEqual(try Data(contentsOf: vault.appendingPathComponent("노트.md")), data)
        let calls = await converter.prepareCalls; XCTAssertEqual(calls, 0)
    }

    func testFailedConversionPreservesOriginalAndRelaunchRetryDoesNotDuplicate() async throws {
        let (base, vault, inputs) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let source = inputs.appendingPathComponent("회의 #1.pdf"); try put("pdf bytes", source)
        let failed = DocumentImporter(vaultURL: vault, converter: FixtureConverter(fail: true))
        let first = await failed.importFiles(urls: [source], destination: "자료")
        XCTAssertEqual(first.first?.status, .partial)
        XCTAssertEqual(first.first?.originalPath, "자료/원본/회의 #1.pdf")
        let fresh = DocumentImporter(vaultURL: vault, converter: FixtureConverter())
        let next = await fresh.importFiles(urls: [source], destination: "자료")
        XCTAssertEqual(next.first?.status, .success)
        XCTAssertEqual(next.first?.id, first.first?.id)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: vault.appendingPathComponent("자료/원본").path).count, 1)
        let text = try String(contentsOf: vault.appendingPathComponent(next[0].markdownPath!))
        XCTAssertTrue(text.contains("%23")); XCTAssertFalse(text.contains("file://"))
        XCTAssertEqual(try String(contentsOf: source), "pdf bytes")
    }

    func testRetryPreservesEditedMarkdownAndSameNamedExistingFiles() async throws {
        let (base, vault, inputs) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let source = inputs.appendingPathComponent("계획.docx"); try put("word bytes", source)
        try put("existing note", vault.appendingPathComponent("자료/계획.md"))
        let importer = DocumentImporter(vaultURL: vault, converter: FixtureConverter())
        let first = await importer.importFiles(urls: [source], destination: "자료")
        XCTAssertEqual(first.first?.markdownPath, "자료/계획 (2).md")
        let output = vault.appendingPathComponent(first[0].markdownPath!)
        try put("user edited this", output)
        let second = await importer.importFiles(urls: [source], destination: "자료")
        XCTAssertEqual(second.first?.markdownPath, first.first?.markdownPath)
        XCTAssertEqual(try String(contentsOf: output), "user edited this")
        XCTAssertEqual(try String(contentsOf: vault.appendingPathComponent("자료/계획.md")), "existing note")
        XCTAssertFalse(second[0].warnings.isEmpty)
    }

    func testDestinationsAndOriginalFolderSymlinksCannotEscapeVault() async throws {
        let (base, vault, inputs) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let source = inputs.appendingPathComponent("note.txt"); try put("safe", source)
        let importer = DocumentImporter(vaultURL: vault, converter: FixtureConverter())
        let traversal = await importer.importFiles(urls: [source], destination: "../inputs")
        XCTAssertEqual(traversal[0].status, .failed)
        try FileManager.default.createSymbolicLink(at: vault.appendingPathComponent("자료/원본"), withDestinationURL: inputs)
        let symlink = await importer.importFiles(urls: [source], destination: "자료")
        XCTAssertEqual(symlink[0].status, .failed)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: inputs.path), ["note.txt"])
    }

    func testOneFailureDoesNotDiscardOtherFilesAndOriginalNameCollisionIsSafe() async throws {
        let (base, vault, inputs) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let source = inputs.appendingPathComponent("note.txt"); try put("new text", source)
        let originals = vault.appendingPathComponent("자료/원본")
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        try put("old text", originals.appendingPathComponent("note.txt"))
        let importer = DocumentImporter(vaultURL: vault, converter: FixtureConverter())
        let results = await importer.importFiles(urls: [inputs.appendingPathComponent("missing.pdf"), source], destination: "자료")
        XCTAssertEqual(results.map(\.status), [.failed, .success])
        XCTAssertEqual(results[1].originalPath, "자료/원본/note (2).txt")
        XCTAssertEqual(try String(contentsOf: originals.appendingPathComponent("note.txt")), "old text")
    }

    func testEquivalentKoreanPathNormalizationsReuseOneJob() async throws {
        let (base, vault, inputs) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let source = inputs.appendingPathComponent("계획.txt"); try put("text", source)
        let importer = DocumentImporter(vaultURL: vault, converter: FixtureConverter())
        let first = await importer.importFiles(urls: [source], destination: "자료".precomposedStringWithCanonicalMapping)
        let second = await importer.importFiles(urls: [source], destination: "자료".decomposedStringWithCanonicalMapping)
        XCTAssertEqual(first[0].id, second[0].id)
        XCTAssertEqual(first[0].markdownPath, second[0].markdownPath)
        let history = await importer.history(); XCTAssertEqual(history.count, 1)
    }

    func testPartialConversionCanRetryUnlessUserEditedIt() async throws {
        let (base, vault, inputs) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let source = inputs.appendingPathComponent("report.pdf"); try put("pdf bytes", source)
        let partial = DocumentImporter(vaultURL: vault, converter: FixtureConverter(partial: true))
        let first = await partial.importFiles(urls: [source], destination: "자료")
        XCTAssertEqual(first[0].status, .partial)
        let fresh = DocumentImporter(vaultURL: vault, converter: FixtureConverter())
        let second = await fresh.importFiles(urls: [source], destination: "자료")
        XCTAssertEqual(second[0].status, .success)
        XCTAssertEqual(first[0].markdownPath, second[0].markdownPath)
    }

    func testPartialConversionDoesNotReplaceUserEditsOnRetry() async throws {
        let (base, vault, inputs) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let source = inputs.appendingPathComponent("report.pdf"); try put("pdf bytes", source)
        let partial = DocumentImporter(vaultURL: vault, converter: FixtureConverter(partial: true))
        let first = await partial.importFiles(urls: [source], destination: "자료")
        let markdown = vault.appendingPathComponent(try XCTUnwrap(first[0].markdownPath))
        try put("user corrected incomplete text", markdown)
        let fresh = DocumentImporter(vaultURL: vault, converter: FixtureConverter())
        let second = await fresh.retry(id: first[0].id)
        XCTAssertEqual(second.status, .partial)
        XCTAssertFalse(second.retryable)
        XCTAssertEqual(try String(contentsOf: markdown, encoding: .utf8), "user corrected incomplete text")
    }

    func testRuntimeCancellationStopsPreparationProcess() async throws {
        let (base, _, _) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let resources = base.appendingPathComponent("resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let runtimeRoot = base.appendingPathComponent("runtime")
        try put("""
        #!/bin/bash
        trap 'kill "$child" 2>/dev/null; exit 130' TERM INT
        /bin/sleep 30 & child=$!
        echo ready > "$1/started"
        wait "$child"
        """, resources.appendingPathComponent("bootstrap.sh"))
        let runtime = DoclingRuntime(runtimeRoot: runtimeRoot, resourceDirectory: resources)
        let task = Task { try await runtime.prepare() }
        for _ in 0..<200 {
            if FileManager.default.fileExists(atPath: runtimeRoot.appendingPathComponent("started").path) { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: runtimeRoot.appendingPathComponent("started").path))
        await runtime.cancel()
        do { try await task.value; XCTFail("Preparation should be cancelled") }
        catch is CancellationError { }
        catch { XCTFail("Unexpected cancellation error: \(error)") }
    }

    func testImportedOriginalsRemainReadableAlongsideLegacyRawFolder() async throws {
        let (base, vault, inputs) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("raw"), withIntermediateDirectories: true)
        let source = inputs.appendingPathComponent("note.txt"); try put("original text", source)
        let importer = DocumentImporter(vaultURL: vault, converter: FixtureConverter())
        let result = await importer.importFiles(urls: [source], destination: "자료")
        let catalog = SourceCatalog(vaultURL: vault)
        XCTAssertEqual(try catalog.list().map(\.path), [result[0].originalPath!])
        XCTAssertEqual(try catalog.read(path: result[0].originalPath!).text, "original text")
    }

    func testHistoryAndRetryUseStoredOriginalAfterExternalSourceDisappears() async throws {
        let (base, vault, inputs) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let source = inputs.appendingPathComponent("report.pdf"); try put("pdf bytes", source)
        // A collision must not make retry create a different job from the suffixed original.
        let originals = vault.appendingPathComponent("자료/원본")
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        try put("unrelated", originals.appendingPathComponent("report.pdf"))
        let failed = DocumentImporter(vaultURL: vault, converter: FixtureConverter(fail: true))
        let first = await failed.importFiles(urls: [source], destination: "자료")
        try FileManager.default.removeItem(at: source)
        let relaunched = DocumentImporter(vaultURL: vault, converter: FixtureConverter())
        let history = await relaunched.history()
        XCTAssertEqual(history.count, 1)
        let previous = try XCTUnwrap(history.first, "First result: \(first)")
        XCTAssertEqual(previous.name, "report.pdf")
        XCTAssertEqual(previous.originalPath, "자료/원본/report (2).pdf")
        let retried = await relaunched.retry(id: previous.id)
        XCTAssertEqual(retried.status, .success)
        XCTAssertEqual(retried.id, first[0].id)
        XCTAssertEqual(retried.markdownPath, "자료/report.md")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: originals.path).count, 2)
        let invalid = await relaunched.retry(id: "../../outside")
        XCTAssertEqual(invalid.status, .failed)
    }

    func testCancelPreservesOriginalAndCancelsQueuedFiles() async throws {
        let (base, vault, inputs) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let source = inputs.appendingPathComponent("report.pdf"); try put("pdf bytes", source)
        let second = inputs.appendingPathComponent("later.md"); try put("later", second)
        let converter = FixtureConverter(waitForCancel: true)
        let importer = DocumentImporter(vaultURL: vault, converter: converter)
        let task = Task { await importer.importFiles(urls: [source, second], destination: "자료") }
        while !(await converter.started) { try await Task.sleep(nanoseconds: 1_000_000) }
        await importer.cancel()
        let results = await task.value
        XCTAssertEqual(results.map(\.status), [.cancelled, .cancelled])
        XCTAssertEqual(results[0].originalPath, "자료/원본/report.pdf")
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent("자료/later.md").path))
    }
}

private actor FixtureConverter: DocumentConversionService {
    let fail: Bool
    let partial: Bool
    let waitForCancel: Bool
    var prepareCalls = 0
    var started = false
    var cancelled = false
    init(fail: Bool = false, partial: Bool = false, waitForCancel: Bool = false) {
        self.fail = fail; self.partial = partial; self.waitForCancel = waitForCancel
    }
    func prepare() async throws { prepareCalls += 1 }
    func convert(_ source: URL) async throws -> DocumentConversion {
        started = true
        while waitForCancel && !cancelled { try await Task.sleep(nanoseconds: 1_000_000) }
        if cancelled { throw CancellationError() }
        if fail { throw DoclingRuntime.RuntimeError.conversion }
        return .init(markdown: "# Converted\n\n| A | B |\n|---|---|\n| 1 | 2 |", partial: partial)
    }
    func cancel() async { cancelled = true }
}
