import Foundation

/// 전사기가 준 글자를 **검색에 넣기 전에** 한 번 거치는 자리.
///
/// 지금 여기 있는 것은 하나뿐이다 — **문장부호 걷기.**
/// `실측 2026-08-28`(#15 · `knowledge/audio-chain-latency.md`): 온디바이스 전사기는
/// 문장 끝에 `?`·`.` 를 붙여준다. 글자는 하나도 안 틀렸는데(CER 0%) 그 부호 하나 때문에
/// 정답 조각이 2위 → 3위로 밀렸다. 걷으면 평균 1.7위 → **1.3위**(텍스트를 손으로 넣었을 때와 동률).
///
/// ## 왜 Swift 쪽인가
///
/// 순위 계산은 화면(JS)이 한다 — 그래야 `cue.html` 이 브라우저에서 그대로 돈다.
/// 그런데 **부호를 붙이는 것은 전사기**고 전사기는 Swift 쪽이다. 그래서 걷는 자리도 여기다.
/// 사람이 손으로 친 글자는 안 거친다 — 사용자가 친 부호는 사용자의 뜻이다.
///
/// ⚠ **공백은 안 건드린다.** #15 가 잰 것이 `filter { !$0.isPunctuation }` 이고,
/// 어절 사이를 붙이면 한국어에서 색인이 달라진다. 양 끝만 다듬는다.
public enum TranscriptText {

    /// 검색에 넣을 모양으로 바꾼다. 부호를 걷고 양 끝 공백을 다듬는다.
    public static func forSearch(_ raw: String) -> String {
        String(raw.filter { !$0.isPunctuation })
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
