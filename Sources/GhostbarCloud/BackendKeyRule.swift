import Foundation

/// 저장된 API 키가 **다음 저장에도 살아남나** — 판정 하나 (#65 ③ 잔여).
///
/// ★ **왜 앱 타깃이 아니라 여기인가.** 이 판정이 살던 자리(`WKWebViewWrapper.saveBackend`)와
/// 그 값이 앉는 자리(`Config/BackendConfig.swift`)는 둘 다 executable(`Sources/Ghostbar`)
/// 안이라 **`swift test` 가 못 부른다** — `GhostbarCore`(#8)·`GhostbarEmbedding`(#31)·
/// `GhostbarIndex`(#32)·`CloudDraftWire`(#51) 를 뽑은 것과 **똑같은 이유**다.
/// 걷으면 무슨 일이 다시 일어나나: **「이 키가 누구 것인가」가 검사 밖으로 나가고**,
/// 사다리에서 조건 하나가 조용히 빠져도 아무것도 안 빨개진다. 그때 새는 것은 사용자의 키다.
///
/// ⚠ **`BackendConfig` 를 안 든다.** 받는 것은 글자뿐이다 — 들면 이 타깃이 앱 타깃에
/// 의존하게 된다(`CloudDraftWire.Provider` 가 rawValue 만 받는 것과 같은 규율).
public enum BackendKeyRule {

    /// 다음에 **저장될** 키를 정한다. 사다리 셋이고 **순서가 뜻이다**:
    ///
    /// 1. `clearRequested` — 사람이 「키 지우기」를 눌렀다. 무조건 빈다.
    /// 2. `typed` 가 비어 있지 않다 — 새 키를 방금 쳤다. 그것이 이긴다.
    /// 3. **목적지가 갈렸다** — 키는 제공자에 속한다. 주인이 없어졌으니 버린다.
    ///    아니면 그대로 둔다: 화면은 저장된 키를 되읽지 못하므로(`saveBackend` 머리글),
    ///    빈 칸은 「지워라」가 아니라 **「안 바꾼다」**다.
    ///
    /// ⚠ **목적지 = `type` 하나가 아니다** (#65 ③ 잔여). `BackendType` 은 넷인데 화면의
    /// 프리셋은 여덟이라 **다섯이 전부 `openai`** 다 — 그 다섯 사이를 오가면 `type` 이 안 갈리고,
    /// 앞 제공자의 키가 **새 주소로 나간다.** 회신은 `hasKey: true` 라 새 제공자 화면이
    /// 「저장돼 있어요」라고 거짓말까지 한다.
    ///
    /// ⚠ **왜 「화면이 전환 시 `clearKey` 를 싣는다」를 안 골랐나.** 그 길은 프리셋 전환
    /// 하나만 막는다 — 사람이 **주소 칸을 손으로 고치는 길**(`url.onchange`)이 그대로 열려 있고
    /// 거기서도 키는 남의 주소로 나간다. 그리고 화면은 WebView 라 우리가 못 믿는 자리다.
    /// 저장을 실제로 하는 자는 이 줄 하나뿐이고, 마지막 문은 거기여야 새는 길이 0 이 된다.
    public static func nextKey(saved: String,
                               typed: String?,
                               clearRequested: Bool,
                               oldType: String, newType: String,
                               oldURL: String, newURL: String) -> String {
        if clearRequested { return "" }
        if let t = typed, !t.isEmpty { return t }
        if newType != oldType || newURL != oldURL { return "" }
        return saved
    }
}
