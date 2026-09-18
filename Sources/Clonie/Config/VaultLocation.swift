import Foundation
import ClonieCore

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
           ProcessInfo.processInfo.environment["CLONIE_QA_FIRST_RUN"] != "1" { return qa.vaultURL }
        return nil
    }

    /// Initial location for the folder picker; never automatically connected.
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
        // A launch-time -vaultPath is only an initial selection. NSArgumentDomain
        // otherwise shadows every later choice saved by the native folder picker.
        var arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        if arguments.removeValue(forKey: key) != nil {
            UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        }
    }

    private static func isWithin(_ url: URL, root: URL) -> Bool {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let base = root.standardizedFileURL.resolvingSymlinksInPath().path
        return path == base || path.hasPrefix(base + "/")
    }

    static func makeStore() -> VaultStore? {
        selected.map { VaultStore(vaultURL: $0) }
    }
}
