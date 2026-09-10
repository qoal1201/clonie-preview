import Foundation
import ClonieCore

/// 어느 볼트를 열까. **앱과 같은 볼트**를 여는 것이 둘째 문의 전제다.
///
/// 우선순위: `--vault` 인자 → 환경변수 `CLONIE_VAULT` → 새 앱이 저장한 자리
/// (`UserDefaults` 도메인 `com.local.clonie` 의 `vaultPath`) → 아직 이관하지 않은
/// 경우에만 이전 앱 자리(`com.local.ghostbar`) → `~/Documents/Clonie`.
///
/// ⚠ 빈 글자는 「안 줬다」다. `.mcpb` 의 폴더 칸을 비워 두면 `--vault ""` 로 온다.
/// ⚠ 앱 도메인을 읽는 것은 **읽기만**이다 — 여기서 `set` 하지 않는다. 볼트를 고르는 창은 앱 하나다.
public enum VaultLocator {
    public static let environmentKey = "CLONIE_VAULT"
    public static let appDefaultsSuite = "com.local.clonie"
    public static let legacyAppDefaultsSuite = "com.local.ghostbar"
    public static let appDefaultsKey = "vaultPath"
    public static let migrationMarkerKey = InstallationIdentity.migrationMarkerKey

    public static func resolve(argument: String?,
                               environment: [String: String] = ProcessInfo.processInfo.environment,
                               defaults: UserDefaults? = UserDefaults(suiteName: appDefaultsSuite),
                               fileManager: FileManager = .default,
                               legacyDefaults: UserDefaults? = nil) throws -> URL {
        let candidates: [String?] = [argument,
                                     environment[environmentKey],
                                     defaults?.string(forKey: appDefaultsKey)]
        for c in candidates {
            guard let p = c?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty else { continue }
            // ⚠ `.mcpb` 의 폴더 칸을 비워 두면 Claude Desktop 이 그 칸을 **치환하지 않은
            //   자리표시자 글자 그대로**(`${user_config.vault}`) 넘길 수 있다 — 빈 글자와
            //   같은 「안 줬다」로 다룬다. 그러지 않으면 리터럴 `${...}` 이름의 폴더를 만든다.
            guard !p.hasPrefix("${") else { continue }
            return URL(fileURLWithPath: (p as NSString).expandingTildeInPath, isDirectory: true)
        }

        // 이관 marker가 있으면 사용자가 새 앱에서 지운 값을 이전 domain에서
        // 되살리지 않는다. `legacyDefaults`의 기본값은 nil이라 MCP의 기본 호출은
        // 실제 사용자 도메인을 읽지 않는다.
        let migrated = defaults?.object(forKey: InstallationIdentity.migrationMarkerKey) != nil
        if !migrated,
           let legacyPath = legacyDefaults?.string(forKey: appDefaultsKey),
           let path = usablePath(legacyPath) {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        return try VaultStore.defaultVaultURL(fileManager: fileManager)
    }

    private static func usablePath(_ value: String?) -> String? {
        guard let path = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty,
              !path.hasPrefix("${") else { return nil }
        return path
    }
}
