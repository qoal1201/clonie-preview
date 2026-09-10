import Foundation

enum BackendType: String {
    case ollama
    case openai
    case anthropic
    case openrouter
}

/// 설정 화면과 drafter가 공유하는 로컬 backend 설정이다.
/// 기존 UserDefaults 키를 유지해 업그레이드 뒤에도 저장된 선택을 읽는다.
struct BackendConfig {
    var type: BackendType
    var url: String
    var apiKey: String

    private enum Defaults {
        static let typeKey = "backendType"
        static let urlKey = "backendURL"
        static let apiKeyKey = "backendAPIKey"
        static let type = BackendType.ollama
        static let url = "http://localhost:11434"
        static let apiKey = ""
    }

    static var current: BackendConfig {
        get {
            let defaults = UserDefaults.standard
            let rawType = defaults.string(forKey: Defaults.typeKey)
            return BackendConfig(
                type: BackendType(rawValue: rawType ?? "") ?? Defaults.type,
                url: defaults.string(forKey: Defaults.urlKey) ?? Defaults.url,
                apiKey: defaults.string(forKey: Defaults.apiKeyKey) ?? Defaults.apiKey
            )
        }
        set {
            let defaults = UserDefaults.standard
            defaults.set(newValue.type.rawValue, forKey: Defaults.typeKey)
            defaults.set(newValue.url, forKey: Defaults.urlKey)
            defaults.set(newValue.apiKey, forKey: Defaults.apiKeyKey)
        }
    }
}
