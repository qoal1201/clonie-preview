import XCTest
@testable import ClonieDocuments

final class DoclingRuntimeTests: XCTestCase {
    private func fixture() throws -> (URL, URL, DoclingRuntime) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("clonie-runtime-cache-" + UUID().uuidString)
        let resources = base.appendingPathComponent("resources")
        let root = base.appendingPathComponent("runtime")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("python/bin"), withIntermediateDirectories: true)
        try """
        #!/bin/bash
        printf 'prepare:%s\\n' "${3:-normal}" >> "$1/calls"
        """.write(to: resources.appendingPathComponent("bootstrap.sh"), atomically: true, encoding: .utf8)
        let python = root.appendingPathComponent("python/bin/python3")
        try """
        #!/bin/bash
        echo convert >> "$4/calls"
        if [[ -f "$4/fail" ]]; then exit 41; fi
        printf '{"markdown":"converted text","partial":false,"warnings":[]}' > "$6"
        """.write(to: python, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: python.path)
        return (base, root, DoclingRuntime(runtimeRoot: root, resourceDirectory: resources))
    }

    func testEachNewDocumentValidatesWithoutDuplicatingExplicitPrepare() async throws {
        let (base, root, runtime) = try fixture()
        defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appendingPathComponent("document.pdf")
        try await runtime.prepare()
        _ = try await runtime.convert(source)
        _ = try await runtime.convert(source)
        let calls = try String(contentsOf: root.appendingPathComponent("calls"), encoding: .utf8)
        XCTAssertEqual(calls.split(separator: "\n").map(String.init),
                       ["prepare:normal", "convert", "prepare:normal", "convert"])
    }

    func testFailedConversionRequestsDeepValidationOnNextRetry() async throws {
        let (base, root, runtime) = try fixture()
        defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appendingPathComponent("document.pdf")
        try Data().write(to: root.appendingPathComponent("fail"))
        do { _ = try await runtime.convert(source); XCTFail("Expected conversion failure") }
        catch is DoclingRuntime.RuntimeError { }
        try FileManager.default.removeItem(at: root.appendingPathComponent("fail"))
        let result = try await runtime.convert(source)
        XCTAssertEqual(result.markdown, "converted text")
        let calls = try String(contentsOf: root.appendingPathComponent("calls"), encoding: .utf8)
        XCTAssertEqual(calls.split(separator: "\n").map(String.init),
                       ["prepare:normal", "convert", "prepare:--deep", "convert"])
    }
}
