import Foundation

/// 검색 자 — **화면 JS 의 쌍둥이다** (`Sources/Clonie/Resources/ChatHTML.swift` 의
/// `SIM_G_DIRECT` · `SIM_A` · `escore` · `eris`).
///
/// ## 왜 두 벌인가
///
/// 순위·색은 화면(JS)에 산다 — `AGENTS.md` 「화면 순수 함수」. Swift 로 옮기면 브라우저 단독
/// 동선이 죽는다. 그런데 MCP 의 소비자는 화면이 아니라 **Claude** 라 화면을 거칠 수 없다.
/// 그래서 **정본은 그대로 JS 에 두고** 여기에 같은 값을 한 벌 더 둔다 (ADR 0007).
///
/// ⚠ **두 벌은 `tests/mcp-thresholds.test.mjs` 가 잠근다** — 화면 값이 바뀌면 그 시험이 빨개진다.
///   여기 값을 먼저 고치면 안 된다: 정본은 저쪽이다.
public enum Thresholds {
    /// 초록선. 화면 `SIM_G_DIRECT`. 이 코사인이면 정규화 점수 1.0.
    public static let simGreenDirect: Double = 0.5415
    /// 주황선 — 초록선의 92.5%. 화면 `SIM_A`.
    public static let simAmber: Double = 0.925

    /// 코사인 → 초록선 눈금 (1.0 = 초록선). 화면 `escore` 의 마지막 나눗셈.
    public static func normalized(cosine: Double) -> Double { cosine / simGreenDirect }

    /// 정규화 점수 → 신호등. 화면 `eris` 그대로: `n>=1?"g":(n>=SIM_A?"a":"r")`.
    public static func light(normalized n: Double) -> String {
        n >= 1 ? "g" : (n >= simAmber ? "a" : "r")
    }
}
