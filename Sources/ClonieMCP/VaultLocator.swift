import Foundation
import ClonieCore

/// 어느 볼트를 열까. **앱과 같은 볼트**를 여는 것이 둘째 문의 전제다.
///
/// 우선순위: `--vault` 인자 → 환경변수 `CLONIE_VAULT` → Clonie의 `vaultPath` → `~/Documents/Clonie`.
///
/// ⚠ 빈 글자는 「안 줬다」다. `.mcpb` 의 폴더 칸을 비워 두면 `--vault ""` 로 온다.
/// ⚠ 앱 도메인을 읽는 것은 **읽기만**이다 — 여기서 `set` 하지 않는다. 볼트를 고르는 창은 앱 하나다.
public enum VaultLocator {
    public static let environmentKey = "CLONIE_VAULT"
    public static let appDefaultsSuite = "com.local.clonie"
    public static let appDefaultsKey = "vaultPath"

    public static func resolve(argument: String?,
                               environment: [String: String] = ProcessInfo.processInfo.environment,
                               defaults: UserDefaults? = .standard,
                               defaultsDomain: String = appDefaultsSuite,
                               fileManager: FileManager = .default) throws -> URL {
        // 앱에 동봉된 MCP는 Clonie와 같은 bundle identifier를 가진다. 자기 앱 ID로
        // UserDefaults(suiteName:)을 만들면 macOS가 거부하므로 저장된 앱 도메인을 직접 읽는다.
        // MCP 실행 폴더나 다른 호스트의 기본 설정은 저장소 선택에 관여하지 않는다.
        let appVault = defaults?.persistentDomain(forName: defaultsDomain)?[appDefaultsKey] as? String
        let candidates: [String?] = [argument,
                                     environment[environmentKey],
                                     appVault]
        for c in candidates {
            guard let p = c?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty else { continue }
            // ⚠ `.mcpb` 의 폴더 칸을 비워 두면 Claude Desktop 이 그 칸을 **치환하지 않은
            //   자리표시자 글자 그대로**(`${user_config.vault}`) 넘길 수 있다 — 빈 글자와
            //   같은 「안 줬다」로 다룬다. 그러지 않으면 리터럴 `${...}` 이름의 폴더를 만든다.
            guard !p.hasPrefix("${") else { continue }
            return URL(fileURLWithPath: (p as NSString).expandingTildeInPath, isDirectory: true)
        }

        return try VaultStore.defaultVaultURL(fileManager: fileManager)
    }

}
