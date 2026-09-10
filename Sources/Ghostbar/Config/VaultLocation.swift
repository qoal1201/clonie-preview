import Foundation
import GhostbarCore

/// The selected folder is remembered; first launch does not create a vault before the user chooses.
enum VaultLocation {
    private static var key: String {
        QASession.current.map { "qa.\($0.id).vaultPath" } ?? "vaultPath"
    }

    static var selected: URL? {
        if let path = UserDefaults.standard.string(forKey: key), !path.isEmpty {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            if let qa = QASession.current, !isWithin(url, root: qa.vaultURL) { return nil }
            return url
        }
        if let qa = QASession.current,
           ProcessInfo.processInfo.environment["GHOSTBAR_QA_FIRST_RUN"] != "1" { return qa.vaultURL }
        return nil
    }

    /// Initial location for the folder picker, also used to find an older default vault.
    static var current: URL {
        selected ?? QASession.current?.vaultURL
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Documents/Clonie", isDirectory: true)
    }

    static func set(_ url: URL) throws {
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        if let qa = QASession.current, !isWithin(canonical, root: qa.vaultURL) {
            throw NSError(domain: "ClonieQA", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "QA 자료 폴더 안에서 선택해 주세요."])
        }
        UserDefaults.standard.set(canonical.path, forKey: key)
    }

    private static func isWithin(_ url: URL, root: URL) -> Bool {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let base = root.standardizedFileURL.resolvingSymlinksInPath().path
        return path == base || path.hasPrefix(base + "/")
    }

    static var legacyDocument: URL? {
        guard !QASession.isQABundle else { return nil }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/Ghostbar/cue.json")
    }

    /// Preserve an older implicit default vault, without filesystem work on the UI thread.
    static func restorePreviousDefault(completion: @escaping () -> Void) {
        guard selected == nil, !QASession.isQABundle else { completion(); return }
        let candidate = current, legacy = legacyDocument
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let legacyExists = legacy.map { fm.fileExists(atPath: $0.path) } == true
            var directory: ObjCBool = false
            var exists = fm.fileExists(atPath: candidate.path, isDirectory: &directory) && directory.boolValue
            if !exists && legacyExists && !fm.fileExists(atPath: candidate.path) {
                do { try fm.createDirectory(at: candidate, withIntermediateDirectories: true); exists = true }
                catch { FileHandle.standardError.write(Data("[cue] 이전 볼트 복구 실패: \(error)\n".utf8)) }
            }
            let restored = exists
            DispatchQueue.main.async {
                if restored, selected == nil { try? set(candidate) }
                completion()
            }
        }
    }

    static func makeStore() -> VaultStore? {
        selected.map { VaultStore(vaultURL: $0, legacyJSONURL: legacyDocument) }
    }
}
