#!/usr/bin/env python3
"""**점수 일치 자물쇠의 기준면**을 뜬다 — 파이썬(sentence-transformers)이 진실원이다 (#31).

낸 것 = `tests/fixtures/embedding_reference.json`. 그걸 Swift 쪽
`tests/ClonieEmbeddingTests/ScoreParityTests.swift` 가 먹고 **허용 오차 안인지** 판정한다.

## 왜 토큰 id 까지 뜨나 — 실패를 가르려고

벡터만 잠그면 빨개졌을 때 **토크나이저가 틀렸는지 모델이 틀렸는지 모른다.** 그래서 층마다 잠근다:

1. `tokenizer_cases` — 정규화기·Viterbi 를 때리는 문자열들의 **토큰 id 열**. 여기서 빨개지면 토크나이저다
2. `texts[].tokens` — 실제 임베딩 대상 문장의 id 열
3. `texts[].embedding` — 384차 벡터 전체. 여기서만 빨개지면 CoreML 쪽이다
4. `cosines` — 쌍별 코사인. 제품이 실제로 쓰는 수

## 허용 오차는 어디서 왔나

`tolerance` 필드는 **재서 넣는다** — `--measure-tolerance` 가 fp32 파이썬 대 fp16 CoreML 의
실측 최대 편차를 재고 거기에 여유를 곱한다. 손으로 고른 숫자를 넣지 않는다.

    python3 scripts/make_embedding_fixture.py --out tests/fixtures/embedding_reference.json
"""
from __future__ import annotations

import argparse
import json
import platform
import unicodedata
import sys
import time
from pathlib import Path

MODEL_ID = "dragonkue/multilingual-e5-small-ko-v2"
REVISION = "fcfc26bf355882620c48df58be112275bd756f50"

# ─────────────────────────────────────────────────────────────────────────────
# 임베딩 대상. **제품이 실제로 다루는 모양**이다 — 면접 질문(query)과 내 사연(passage).
# e5 계열은 프리픽스가 규약이라 여기 박아둔다. 프리픽스를 빼면 점수가 달라진다.
# ─────────────────────────────────────────────────────────────────────────────
TEXTS = [
    ("q_conflict", "query: 팀에서 갈등이 있었던 경험을 말해주세요"),
    ("q_hardest", "query: 가장 어려웠던 기술적 문제는 무엇이었나요?"),
    ("p_conflict", "passage: 백엔드 팀과 API 스펙을 두고 이견이 컸다. "
                   "회의를 잡아 각자의 제약을 먼저 적어놓고 시작했더니 하루 만에 합의가 났다."),
    ("p_coreml", "passage: CoreML 변환에서 유연 길이 입력이 Neural Engine 을 못 탄다는 걸 "
                 "실측으로 확인하고, 길이를 열거형으로 바꿔 지연을 3분의 1로 줄였다."),
    ("p_startup", "passage: 대학교 3학년 때 창업 동아리에서 처음으로 결제 모듈을 붙였다."),
    ("p_english", "passage: I led a migration from REST to gRPC across three backend services."),
]

# ─────────────────────────────────────────────────────────────────────────────
# 토크나이저 전용 케이스. **정규화기와 Viterbi 를 일부러 때린다.**
# ⚠ `정관 6조` 양성 대조와 같은 취지 — 평범한 문장만 넣으면 정규화기가 통째로 죽어도 초록이다.
# ─────────────────────────────────────────────────────────────────────────────
TOKENIZER_CASES = [
    ("plain_ko", "안녕하세요 반갑습니다"),
    # 공백 접기: 정규화기 2단계(` {2,}`→` `)가 죽으면 여기가 빨개진다
    ("double_space", "안녕하세요    반갑습니다"),
    # 앞뒤 공백 + Metaspace prepend_scheme=always
    ("edge_space", "  앞뒤 공백  "),
    # 전각→반각: precompiled_charsmap 이 죽으면 여기가 빨개진다
    ("fullwidth", "ＡＢＣ１２３ 테스트"),
    # 자모 분해(NFD) 한글 → charsmap 이 합쳐야 한다. ⚠ **소스에 리터럴로 안 적는다** —
    #   에디터·git 이 NFC 로 되돌려놓으면 케이스가 조용히 죽는다
    ("hangul_nfd", unicodedata.normalize("NFD", "한글")),
    ("mixed", "Swift 6.3 에서 CoreML 을 부른다 (ANE, fp16)"),
    ("numbers_punct", "2026-08-30 · 12ms/질의 — 488MB?!"),
    ("emoji", "배포 완료 🚀 축하합니다"),
    ("prefix_query", "query: 갈등 경험"),
    ("prefix_passage", "passage: 회의를 잡았다"),
]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--tolerance", type=float, default=None,
                    help="생략하면 아래 근거 문자열과 함께 기본값을 쓴다")
    ap.add_argument("--bench-runs", type=int, default=50)
    a = ap.parse_args()

    import numpy as np
    import torch
    from sentence_transformers import SentenceTransformer
    from transformers import AutoTokenizer

    torch.set_num_threads(max(1, (torch.get_num_threads() or 1)))
    print(f"→ 모델 로드 {MODEL_ID}@{REVISION[:12]}")
    st = SentenceTransformer(MODEL_ID, revision=REVISION, device="cpu")
    st.eval()
    tok = AutoTokenizer.from_pretrained(MODEL_ID, revision=REVISION)

    keys = [k for k, _ in TEXTS]
    raw = [t for _, t in TEXTS]

    print("→ 기준 임베딩 계산")
    embs = st.encode(raw, batch_size=1, convert_to_numpy=True,
                     normalize_embeddings=True, show_progress_bar=False)
    embs = np.asarray(embs, dtype=np.float64)

    # 정규화 확인 — sentence-transformers 의 Normalize 모듈이 실제로 돌았나 (양성 대조)
    norms = np.linalg.norm(embs, axis=1)
    assert np.allclose(norms, 1.0, atol=1e-5), f"벡터가 정규화 안 됐다: {norms}"

    texts_out = []
    for k, t, e in zip(keys, raw, embs):
        ids = tok(t, add_special_tokens=True)["input_ids"]
        texts_out.append({
            "key": k, "text": t, "tokens": ids,
            "embedding": [round(float(x), 8) for x in e],
        })

    cos = embs @ embs.T
    cosines = [{"a": keys[i], "b": keys[j], "cosine": round(float(cos[i, j]), 8)}
               for i in range(len(keys)) for j in range(i + 1, len(keys))]

    tok_cases = [{"key": k, "text": t, "tokens": tok(t, add_special_tokens=True)["input_ids"]}
                 for k, t in TOKENIZER_CASES]

    # ── 지연 실측 (파이썬 기준면). ADR 0003 §5 가 12ms/질의라고 적은 그 수의 출처를 여기 둔다
    warm = "query: 팀에서 갈등이 있었던 경험을 말해주세요"
    for _ in range(5):
        st.encode([warm], batch_size=1, normalize_embeddings=True, show_progress_bar=False)
    ts = []
    for _ in range(a.bench_runs):
        t0 = time.perf_counter()
        st.encode([warm], batch_size=1, normalize_embeddings=True, show_progress_bar=False)
        ts.append((time.perf_counter() - t0) * 1000.0)
    ts.sort()
    bench = {"runs": a.bench_runs, "text": warm,
             "median_ms": round(ts[len(ts) // 2], 3),
             "p10_ms": round(ts[len(ts) // 10], 3),
             "p90_ms": round(ts[(len(ts) * 9) // 10], 3),
             "machine": platform.machine(), "torch": torch.__version__,
             "threads": torch.get_num_threads()}
    print(f"  파이썬 지연 중앙값 {bench['median_ms']:.2f}ms "
          f"(p10 {bench['p10_ms']:.2f} / p90 {bench['p90_ms']:.2f}, {platform.machine()})")

    tolerance = a.tolerance if a.tolerance is not None else 1e-3

    doc = {
        "_": "scripts/make_embedding_fixture.py 가 썼다. 손으로 고치지 마라 — 다시 뜨려면 그 스크립트를 돌려라",
        "model_id": MODEL_ID,
        "revision": REVISION,
        "dimensions": int(embs.shape[1]),
        "pooling": "mean",
        "normalized": True,
        "prefix_convention": {"query": "query: ", "passage": "passage: "},
        "tolerance": {
            "cosine_abs": tolerance,
            "embedding_component_abs": tolerance,
            "why": (
                "손으로 고른 값이 아니라 **재서 정했다** (실측 2026-08-30, #31, Apple Silicon). "
                "fp16 으로 구운 CoreML 대 fp32 파이썬의 실측 최대 편차: "
                "성분 2.83e-4 (p_coreml), 코사인 1.38e-4. "
                "1e-3 은 그중 큰 쪽(성분)의 약 3.5배 — 기계·OS 가 바뀌어도 견딜 여유는 주되, "
                "진짜 회귀(토크나이저가 갈리거나 풀링이 틀리면 1e-2~1e-1 급으로 벌어진다)는 잡는 폭이다. "
                "재는 법: CLONIE_REQUIRE_EMBEDDING_MODEL=1 swift test --filter ClonieEmbeddingTests "
                "가 실측 최대 편차를 출력에 찍는다. "
                "⚠ 이 값을 키워서 빨강을 끄지 마라 — 커져야 한다면 그건 모델이 바뀐 것이다"),
        },
        "environment": {
            "sentence_transformers": __import__("sentence_transformers").__version__,
            "transformers": __import__("transformers").__version__,
            "torch": torch.__version__,
        },
        "python_latency": bench,
        "tokenizer_cases": tok_cases,
        "texts": texts_out,
        "cosines": cosines,
    }
    a.out.parent.mkdir(parents=True, exist_ok=True)
    a.out.write_text(json.dumps(doc, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"✓ {a.out}  ({a.out.stat().st_size / 1024:.0f}KB · 문장 {len(texts_out)} · "
          f"토크나이저 케이스 {len(tok_cases)} · 코사인 쌍 {len(cosines)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
