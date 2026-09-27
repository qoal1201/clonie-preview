#!/usr/bin/env python3
"""**개념 제안의 기준면**을 뜬다 (#33, ADR 0003 §3-②).

낸 것 = `tests/fixtures/chip_suggest.json`. 그걸 `tests/chip-suggest.test.mjs` 가 먹고,
**배포되는 화면 JS 의 제안 함수 그대로** top-3 을 다시 재서 성적이 아직 참인지 판정한다.

## 왜 이 파일이 `make_screen_vectors_fixture.py` 옆에 또 생겼나

**방향이 반대라서**다. 저쪽(#34)은 「면접관 질문 → 내 조각」이고 여기는 「내 조각 → 표준질문」이다.
후보 풀도 다르다 — 저쪽은 조각 6장, 여기는 표준질문 10개. 한 fixture 에 섞으면 어느 방향의
수인지 매번 되물어야 한다(`screen-vectors.test.mjs` 머리글이 파일을 가른 것과 같은 이유).

⚠ **말뭉치는 안 베꼈다.** 질문 10 · 조각 6 · 저장소 밖 6 은 `make_screen_vectors_fixture` 에서
**임포트**한다. 베끼면 한쪽이 조용히 낡는다(`정관 1조`).

## 말뭉치는 어디서 왔나 — 내가 짓지 않았다

`#23`·`#33` 프로브(`chipsuggest.py`)가 쓴 12장 그대로다:
  - f0~f5 : `make_screen_vectors_fixture.FRAGMENTS` 원문. 정답 칩 = 그 조각의 `questionIds`
  - g0~g5 : 그 프로브가 지은 여섯. **주제가 레포 밖**이다(학부·동아리·공모전·번역·발표) —
            f 여섯이 전부 이 레포 개발 이야기라 그것만으로는 「이 레포를 아는 모델」과
            「제안이 되는 모델」이 안 갈린다.
  ⚠ 정답 칩 넷(강점과 약점 · 왜 지원 · 자랑스러운 성과 · 피드백 반영)은 f 여섯이 안 물던 것이고,
    g4·g5 는 **이미 쓰인 칩에 다른 사연**을 붙였다(같은 칩에 조각이 둘인 실제 모양).
    그래서 12장이 표준질문 10개를 **전부** 덮는다.
  ⚠ 애매한 것은 애매하다고 적는다: g2(동아리 장부)는 「가장 자랑스러운 성과」로 정했지만
    「주도적으로 문제를 해결한 경험」으로도 읽힌다 — 그래서 **top-1 이 아니라 top-3 이 판정선**이다.

## 축이 셋 구워진다 — 왜 하나가 아닌가

`실측 2026-08-30`(#33 프로브, 원자료 `chipsuggest.json`)이 축마다 성적을 갈랐다. **출하 기본**
= 표준질문에 변형이 없는 판이다(`seed()` 가 심는 것이 그것이고, 변형 칸은 #34 가 걷었다):

    조각=passage / 질문=query        top-1   top-3   평균순위
      제목만                          1/12    1/12    6.00   ← **우연(3/12)보다 나쁘다**
      본문만                          5/12    8/12    3.17
      제목+본문                       3/12    8/12    3.75

배포되는 것은 **제목+본문**이다(`ContentIndexer.indexText` 와 같은 모양). 본문만 쪽이 top-1 은
높지만 **화면에 셋을 띄우므로 판정선은 top-3 이고 거기서는 8/12 로 같다** — 그래서 색인과
모양을 갈라 둘로 만드는 값이 없다. 세 축을 다 굽는 이유는 시험이 **그 비교를 다시 재서**
이 문단이 아직 참인지 판정하게 하려는 것이다(`정관 10조`: "이게 꺼졌는지 어떻게 아나").
⚠ 제목만 축이 우연보다 나쁜 것이 **본문 길이 문턱(`SUGGEST_MIN`)의 근거**다 — 제목만 찬
편집기에 제안을 띄우면 **동전보다 못한 것을 셋 띄우는 것**이다.

⚠ **성적표를 두 판으로 낸다** (`chiponly` · `variants`). 화면이 매기는 것은 그 질문의
**물음꼴 전부 중 최고**라(걷힌 `qforms` 와 같은 폭) 변형이 있는 옛 문서는 눈금이 다르다.
⚠ **#53 이 이 축을 화면에서 걷었다** (ADR 0005). 이 말뭉치는 안 지운다 — 걷은 근거와
「다시 열 조건」이 이 수들이고, `tests/chip-suggest.test.mjs` 가 그것을 다시 잰다.
`실측 2026-08-30`: 변형을 넣으면 제목만 축이 1/12 → 7/12 로 뛴다 — 변형 18개가 질문 열 중
여섯에만 붙어 있어서다. **출하 기본은 `chiponly` 쪽이고 판정선도 거기 건다.**

## 던져 넣기 축은 따로다 — 문항은 조각이 아니라 질문이다

걷힌 `chipFor`(#14·#29)가 받던 것은 자소서 **문항**이고 그건 물음이다. 물음↔물음은 **대칭** 과제라
양쪽 `query: ` 다(모델카드 §FAQ — `ContentIndexer` 의 질문 축과 같은 규약). 위 표는 조각↔질문
방향이라 여기에 그대로 못 쓴다. 그래서 `ingest` 벡터를 따로 굽는다:
  - 양성 = 질문 10개의 **말투 변형 18개**. 변형은 그 질문의 딴 표기라 정답이 자명하다.
  - 음성 = 저장소 밖 질의 6개. 어떤 표준질문도 이것의 답이 아니다 → **기본 켜짐 문턱의 근거**.

## 돌리는 법

    <sentence-transformers 가 있는 파이썬> scripts/make_chip_suggest_fixture.py

⚠ **손으로 고치지 마라.** 다시 뜨려면 이 스크립트를 돌려라.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
# ⚠ 말뭉치의 집은 저쪽이다. 여기서 다시 적지 않는다.
from make_screen_vectors_fixture import (  # noqa: E402
    MODEL_ID, REVISION, QUERY_PREFIX, PASSAGE_PREFIX,
    QUESTIONS, FRAGMENTS, OUT, index_text, b64,
)

# ── #33 프로브가 지은 여섯. (id, 정답 칩 원문, 제목, 본문) ──
#    칩은 `QUESTIONS` 의 text 원문이라야 한다 — 아래 단언이 그걸 잠근다.
NEW = [
    ("g0", "본인의 강점과 약점",
     "숫자에 강하고 사람 이름에 약하다",
     "표를 보면 이상한 칸이 먼저 눈에 들어온다. 반대로 처음 만난 사람의 이름은 세 번을 들어도 놓쳐서, "
     "만나기 전에 명단을 외워 가는 습관을 들였다."),
    ("g1", "왜 우리 회사에 지원했나",
     "쓰던 물건을 만든 곳에 이력서를 냈다",
     "2년 동안 매일 켜 두던 도구가 있었는데 불편한 곳을 적어 두다 보니 목록이 스무 개가 됐다. "
     "그 목록을 들고 만든 쪽에 가서 같이 고치고 싶어졌다."),
    ("g2", "가장 자랑스러운 성과",
     "동아리 회비 장부를 3년째 아무도 안 고친다",
     "엑셀 한 장으로 굴러가던 회계를 정리해 넘겼더니 후배들이 손을 안 대고 그대로 쓰고 있다. "
     "내가 나간 뒤에도 살아 있는 걸 처음 봤다."),
    ("g3", "피드백을 받았을 때 반영하는 법",
     "발표 녹화를 세 번 돌려보고 말버릇을 지웠다",
     "선배가 말끝을 흐린다고 지적했을 때 처음엔 잘 몰랐다. 녹화를 다시 보고 나서야 보였고, "
     "그 뒤로는 발표 전에 한 번씩 찍어서 확인한다."),
    ("g4", "실패했던 경험과 거기서 배운 것",
     "공모전 마감 전날 서버가 죽었는데 백업이 없었다",
     "제출 두 시간 전에 데이터가 통째로 날아가 결국 못 냈다. 그날 이후로는 무엇을 만들든 "
     "되돌릴 방법부터 만들어 두고 시작한다."),
    ("g5", "일정이 촉박할 때 우선순위를 정하는 법",
     "번역 마감이 겹쳐서 분량을 반으로 쪼갰다",
     "두 건이 같은 주에 몰렸을 때 먼저 각각의 진짜 마감을 물어봤다. 하루 여유가 있는 쪽을 뒤로 미루고 "
     "급한 쪽에 이틀을 몰아 넣었다."),
]

_QID = {text: qid for qid, text, _ in QUESTIONS}

# (id, 정답 질문 id, 제목, 본문) 12장.
ITEMS = ([(fid, chips[0], title, body) for fid, title, body, chips in FRAGMENTS]
         + [(iid, _QID[chip], title, body) for iid, chip, title, body in NEW])

assert all(c in _QID.values() for _, c, _, _ in ITEMS), "정답 칩이 질문 목록 밖이면 과제 정의가 흔들린다"
assert len({i for i, _, _, _ in ITEMS}) == 12, "말뭉치가 12장이 아니다"
assert len({c for _, c, _, _ in ITEMS}) == len(QUESTIONS), \
    "12장이 표준질문을 전부 덮지 않는다 — 방해 칩이 사라지면 과제가 쉬워진다"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path,
                    default=Path(__file__).resolve().parent.parent / "tests/fixtures/chip_suggest.json")
    a = ap.parse_args()

    try:
        import numpy as np
        from sentence_transformers import SentenceTransformer
    except ImportError as e:
        print(f"!! {e} — sentence-transformers 가 있는 인터프리터로 돌려라 (머리글 참조)", file=sys.stderr)
        return 2

    st = SentenceTransformer(MODEL_ID, revision=REVISION, device="cpu")
    dim = st.get_sentence_embedding_dimension()

    def enc(texts, prefix):
        v = st.encode([prefix + t for t in texts], batch_size=1, convert_to_numpy=True,
                      normalize_embeddings=True, show_progress_bar=False)
        return np.asarray(v, dtype=np.float32)

    ids = [i for i, _, _, _ in ITEMS]
    golds = [g for _, g, _, _ in ITEMS]
    titles = [t for _, _, t, _ in ITEMS]
    bodies = [b for _, _, _, b in ITEMS]
    joined = [index_text(t, b) for t, b in zip(titles, bodies)]

    # ── 양성 대조 먼저. 0건은 결론이 아니다 (`정관 6조`) ──
    same = enc([joined[0], joined[0]], PASSAGE_PREFIX)
    self_cos = float(same[0] @ same[1])
    # 질문 원문을 그대로 물음으로 던지면 그 질문이 1위여야 한다 — 대칭 축이 살아 있다는 증거.
    q_texts = [t for _, t, _ in QUESTIONS]
    QT = enc(q_texts, QUERY_PREFIX)
    q_self = int((np.argmax(QT @ QT.T, axis=1) == np.arange(len(q_texts))).sum())
    print(f"++ 양성대조 자기코사인={self_cos:.4f} 질문자기검색={q_self}/{len(q_texts)}")
    if q_self != len(q_texts) or abs(self_cos - 1.0) > 1e-3:
        print("!! 양성 대조 실패 — 아래 수는 결론이 아니다", file=sys.stderr)
        return 1

    # ── 조각 축 셋 ──
    AX = {"titlebody": enc(joined, PASSAGE_PREFIX),
          "body": enc(bodies, PASSAGE_PREFIX),
          "title": enc(titles, PASSAGE_PREFIX)}

    # ── 질문 축 — 물음꼴 전부(`ContentIndexer.questionText` 와 같은 폭) ──
    question_vectors, qforms = {}, {}
    for qid, text, variants in QUESTIONS:
        forms = [text] + list(variants)
        qforms[qid] = forms
        V = enc(forms, QUERY_PREFIX)
        question_vectors[qid] = [b64(V[i]) for i in range(len(forms))]

    # ── 성적표를 여기서도 한 번 낸다. 시험이 재는 것과 갈리면 둘 중 하나가 낡은 것이다 ──
    qmat = {qid: enc(f, QUERY_PREFIX) for qid, f in qforms.items()}
    order = [qid for qid, _, _ in QUESTIONS]

    def score_axis(M, with_variants):
        """`with_variants=False` 가 **출하 기본**이다 — `seed()` 가 심는 표준질문엔 변형이 없고,
        변형을 적는 칸은 #34 가 걷었다. `True` 는 그 칸이 살아 있던 때 적어 둔 옛 문서."""
        ranks = []
        for k in range(len(ids)):
            def best(q):
                V = qmat[q] if with_variants else qmat[q][:1]
                return float(np.max(V @ M[k]))
            s = sorted(((best(q), q) for q in order), key=lambda x: -x[0])
            ranks.append([q for _, q in s].index(golds[k]) + 1)
        return ranks

    grades = {}
    for with_variants in (False, True):
        tag = "variants" if with_variants else "chiponly"
        grades[tag] = {}
        for name, M in AX.items():
            r = score_axis(M, with_variants)
            grades[tag][name] = {"ranks": r,
                                 "top1": sum(1 for x in r if x == 1),
                                 "top3": sum(1 for x in r if x <= 3),
                                 "rank_avg": round(sum(r) / len(r), 4)}
            g = grades[tag][name]
            print(f"++ [{tag:8s}] 축 {name:10s} top1={g['top1']:2d}/12 "
                  f"top3={g['top3']:2d}/12 평균={g['rank_avg']:.2f}위")

    # ── 던져 넣기 축(대칭) — 양성 = 말투 변형, 음성 = 저장소 밖 질의 ──
    ingest_pos = [(v, qid) for qid, forms in qforms.items() for v in forms[1:]]
    ingest_texts = [v for v, _ in ingest_pos] + list(OUT)
    IV = enc(ingest_texts, QUERY_PREFIX)

    doc = {
        "_": "scripts/make_chip_suggest_fixture.py 가 썼다. 손으로 고치지 마라 — 다시 뜨려면 그 스크립트를 돌려라",
        "model_id": MODEL_ID,
        "revision": REVISION,
        "dimensions": dim,
        "vector_encoding": "float32-le-base64",
        "prefix_convention": {
            "draft": {"item": PASSAGE_PREFIX, "question": QUERY_PREFIX,
                      "why": "조각↔질문은 **비대칭** 과제(긴 글 대 짧은 물음)라 E5 규약 그대로. "
                             "`ContentIndexer` 의 조각 축·질문 축과 같은 프리픽스다"},
            "ingest": {"item": QUERY_PREFIX, "question": QUERY_PREFIX,
                       "why": "자소서 **문항**은 조각이 아니라 물음이다. 물음↔물음은 대칭 과제라 "
                              "양쪽 query: — 모델카드 §FAQ"},
        },
        "index_text_shape": 'title + "\\n" + body  — Sources/ClonieIndex/ContentIndexer.swift indexText 와 같아야 한다',
        "positive_control": {"self_cosine": round(self_cos, 6),
                             "question_selfsearch": f"{q_self}/{len(q_texts)}"},
        "shipped_axis": "titlebody",
        "chance": {"top1": round(1 / len(QUESTIONS), 4), "top3": round(3 / len(QUESTIONS), 4)},
        "grades_python": grades,
        "questions": [{"id": q, "text": t, "variants": list(v)} for q, t, v in QUESTIONS],
        # ★ `index_text` = **`items_titlebody` 벡터가 실제로 나온 글자**. Swift 시험이
        #   `ContentIndexer.indexText` 를 돌려 이것과 대조한다 — 두 언어의 모양이 갈리면
        #   아무것도 안 터지고 **다른 글자에서 나온 벡터**로 재게 된다.
        "items": [{"id": i, "gold": g, "title": t, "body": b, "index_text": index_text(t, b)}
                  for (i, g, t, b) in ITEMS],
        "ingest_positive": [{"text": v, "gold": q} for v, q in ingest_pos],
        "out": list(OUT),
        "vectors": {
            "items_titlebody": {ids[i]: b64(AX["titlebody"][i]) for i in range(len(ids))},
            "items_body": {ids[i]: b64(AX["body"][i]) for i in range(len(ids))},
            "items_title": {ids[i]: b64(AX["title"][i]) for i in range(len(ids))},
            "questions": question_vectors,
            "ingest": {ingest_texts[i]: b64(IV[i]) for i in range(len(ingest_texts))},
        },
    }
    a.out.parent.mkdir(parents=True, exist_ok=True)
    a.out.write_text(json.dumps(doc, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"✓ {a.out}  ({a.out.stat().st_size / 1024:.0f}KB · 조각 {len(ITEMS)} · "
          f"질문 {len(QUESTIONS)} · 던져넣기 질의 {len(ingest_texts)} · {dim}차)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
