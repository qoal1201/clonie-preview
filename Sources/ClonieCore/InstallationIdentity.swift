import Foundation

/// Clonie가 Ghostbar의 앱 설정을 처음 실행할 때 한 번만 이어 받는 경계.
///
/// 이관은 값의 의미를 해석하지 않고 UserDefaults의 persistent domain을 그대로
/// 복사한다. 따라서 빈 문자열, `false`, `0`도 "값이 없음"으로 취급하지 않으며,
/// 새 도메인에 이미 있는 키가 항상 우선한다.
public enum InstallationIdentity {
    public static let productionBundleIdentifier = "com.local.clonie"
    public static let qaBundleIdentifier = "com.local.clonie.qa"
    public static let legacyProductionBundleIdentifier = "com.local.ghostbar"
    public static let legacyQABundleIdentifier = "com.local.ghostbar.qa"

    /// 새 도메인에 이 키가 있으면 이관을 다시 시도하지 않는다.
    /// 값보다 키의 존재가 중요하므로 `false`나 빈 문자열이어도 marker로 본다.
    public static let migrationMarkerKey = "com.local.clonie.legacyPreferencesMigrated"
    public static let migrationMarker = migrationMarkerKey

    /// 앱 시작 시 호출하는 공개 진입점.
    ///
    /// `targetSuiteName`과 `legacySuiteName`은 테스트에서만 임의 도메인을
    /// 주입할 수 있게 한 선택 인자다. 둘 중 하나만 지정하면 아무 작업도 하지
    /// 않는다. 실제 앱 호출은 기본값을 사용해 번들 ID에 맞는 고정 도메인을 쓴다.
    public static func migrateLegacyPreferences(
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        defaults: UserDefaults = .standard,
        targetSuiteName: String? = nil,
        legacySuiteName: String? = nil
    ) {
        guard let bundleIdentifier,
              let domains = domains(for: bundleIdentifier) else { return }

        if (targetSuiteName == nil) != (legacySuiteName == nil) { return }
        migrateLegacyPreferences(
            defaults: defaults,
            targetSuiteName: targetSuiteName ?? domains.target,
            legacySuiteName: legacySuiteName ?? domains.legacy
        )
    }

    /// 지정한 두 persistent domain 사이에서 한 번만 이관한다.
    ///
    /// 이 메서드는 앱 번들 ID를 다시 검사하지 않는다. 공개 진입점이 번들 ID를
    /// 검사하고, 이 메서드는 테스트가 실제 사용자 도메인과 무관한 UUID 도메인을
    /// 주입할 수 있도록 데이터 경계를 맡는다.
    static func migrateLegacyPreferences(
        defaults: UserDefaults,
        targetSuiteName: String,
        legacySuiteName: String
    ) {
        let current = defaults.persistentDomain(forName: targetSuiteName) ?? [:]
        guard current[migrationMarkerKey] == nil else { return }

        let legacy = defaults.persistentDomain(forName: legacySuiteName) ?? [:]
        var merged = legacy
        // 이전 설치가 우연히 같은 marker 이름을 썼더라도, 이전 domain의 marker를
        // 새 설치의 완료 표식으로 복사하지 않는다.
        merged.removeValue(forKey: migrationMarkerKey)
        for (key, value) in current {
            merged[key] = value
        }
        merged[migrationMarkerKey] = true
        defaults.setPersistentDomain(merged, forName: targetSuiteName)
    }

    private struct Domains {
        let target: String
        let legacy: String
    }

    private static func domains(for bundleIdentifier: String) -> Domains? {
        switch bundleIdentifier {
        case productionBundleIdentifier:
            return Domains(target: productionBundleIdentifier,
                           legacy: legacyProductionBundleIdentifier)
        case qaBundleIdentifier:
            return Domains(target: qaBundleIdentifier,
                           legacy: legacyQABundleIdentifier)
        default:
            return nil
        }
    }
}
