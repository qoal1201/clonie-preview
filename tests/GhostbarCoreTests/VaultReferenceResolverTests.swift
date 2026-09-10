import XCTest
@testable import GhostbarCore

final class VaultReferenceResolverTests: XCTestCase {
    private var parent: URL!
    private var vault: URL!
    private var resolver: VaultReferenceResolver!

    override func setUpWithError() throws {
        parent = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("clonie-reference-\(UUID().uuidString)", isDirectory: true)
        vault = parent.appendingPathComponent("vault", isDirectory: true)
        try FileManager.default.createDirectory(
            at: vault.appendingPathComponent("notes/sources", isDirectory: true),
            withIntermediateDirectories: true)
        try text("notes/current.md")
        resolver = VaultReferenceResolver(vaultURL: vault)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: parent) }

    private func text(_ relativePath: String, executable: Bool = false) throws {
        let url = vault.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try "test".write(to: url, atomically: true, encoding: .utf8)
        if executable { try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                               ofItemAtPath: url.path) }
    }

    func testResolvesSupportedFilesRelativeToTheMarkdownFile() throws {
        for ext in ["md", "markdown", "txt", "pdf", "docx", "hwpx"] {
            try text("notes/sources/evidence.\(ext)")
            let found = try resolver.resolve(reference: "./sources/evidence.\(ext)#section",
                                             from: "notes/current.md")
            XCTAssertEqual(found.path, vault.appendingPathComponent(
                "notes/sources/evidence.\(ext)").path)
        }
    }

    func testAllowsVaultRootSymlinkAndPercentEncodedSpace() throws {
        try text("notes/sources/my proof.pdf")
        let link = parent.appendingPathComponent("vault-link", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: vault)
        let linked = VaultReferenceResolver(vaultURL: link)
        let found = try linked.resolve(reference: "sources/my%20proof.pdf",
                                       from: "notes/current.md")
        XCTAssertEqual(found.path, vault.appendingPathComponent("notes/sources/my proof.pdf").path)
    }

    func testRejectsSchemesAbsolutePathsAndTraversalOutsideVault() throws {
        for reference in ["https://example.com/a.pdf", "file:///tmp/a.pdf", "/tmp/a.pdf",
                          "~/a.pdf", "../../outside.pdf", "..%2F..%2Foutside.pdf"] {
            XCTAssertThrowsError(try resolver.resolve(reference: reference,
                                                      from: "notes/current.md"), reference)
        }
    }

    func testRejectsHiddenUnsupportedMissingAndExecutableFiles() throws {
        try text("notes/.secret.pdf")
        try text("notes/run.txt", executable: true)
        try text("notes/archive.zip")
        for reference in [".secret.pdf", "run.txt", "archive.zip", "missing.pdf", "binary.hwp"] {
            XCTAssertThrowsError(try resolver.resolve(reference: reference,
                                                      from: "notes/current.md"), reference)
        }
    }

    func testRejectsSymlinkThatLeavesVaultButAllowsOneThatStaysInside() throws {
        let outside = parent.appendingPathComponent("outside.pdf")
        try "outside".write(to: outside, atomically: true, encoding: .utf8)
        try text("notes/sources/inside.pdf")
        try FileManager.default.createSymbolicLink(
            at: vault.appendingPathComponent("notes/outside.pdf"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(
            at: vault.appendingPathComponent("notes/inside.pdf"),
            withDestinationURL: vault.appendingPathComponent("notes/sources/inside.pdf"))

        XCTAssertThrowsError(try resolver.resolve(reference: "outside.pdf",
                                                  from: "notes/current.md"))
        XCTAssertEqual(try resolver.resolve(reference: "inside.pdf", from: "notes/current.md").path,
                       vault.appendingPathComponent("notes/sources/inside.pdf").path)
    }
}
