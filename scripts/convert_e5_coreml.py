#!/usr/bin/env python3
"""`dragonkue/multilingual-e5-small-ko-v2` 를 **CoreML 로 굽는다** — ADR 0003 §5 집행 (#31).

`scripts/fetch-model.sh` 가 이걸 부른다. 손으로 부를 일은 재변환뿐이다.

## 무엇이 나오나 — 산출물 셋

    <out>/E5SmallKoV2.mlmodelc/     ← 앱이 여는 것 (컴파일된 CoreML)
    <out>/tokenizer-unigram.json    ← Swift 토크나이저가 먹는 것
    <out>/manifest.json             ← 체크섬·출처·차원. 앱이 **먼저** 읽는다

## 왜 풀링까지 구워 넣나

sentence-transformers 의 이 모델은 세 모듈이다: Transformer → **Mean Pooling** → **L2 Normalize**
(`modules.json` 실측). 셋 중 뒤의 둘을 Swift 로 옮기면 **파이썬과 갈릴 자리가 둘 늘어난다.**
그래서 `nn.Module` 하나로 싸서 통째로 추적한다 — CoreML 이 뱉는 것이 이미 **정규화된 384차 벡터**다.
Swift 는 코사인을 낼 때 내적만 하면 된다.

⚠ **CLS 풀링이 아니다.** `1_Pooling/config.json` 이 `pooling_mode_mean_tokens: true` 다.
CLS 로 잘못 짜면 벡터가 그럴듯하게 나오는데 점수만 틀린다 — 조용히 죽는 모양이라 여기 적어둔다.

## 왜 .mlmodelc 까지 굽나

`.mlpackage` 를 앱이 열면 macOS 가 **실행 시점에** 컴파일한다(수 초). 그걸 캐시하는 코드를 우리가
또 짜야 한다. `xcrun coremlcompiler` 가 여기서 미리 구우면 앱은 **여는 것만** 한다.

## 정밀도

`--precision fp16`(기본)은 가중치를 반정밀도로 저장한다. 임베딩 표(250037×384)가 이 모델
부피의 대부분이라 fp32 대비 **디스크가 절반**이 된다. 코사인 오차 실측은
`tests/fixtures/embedding_reference.json` 의 `tolerance` 근거와 #31 보고에 있다.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path

MODEL_ID = "dragonkue/multilingual-e5-small-ko-v2"
# ★ 고정한 리비전. 이걸 안 박으면 상류가 움직일 때 **fixture 와 모델이 조용히 갈린다** —
#   점수 일치 자물쇠가 빨개지는데 원인이 우리 코드가 아니게 된다.
REVISION = "fcfc26bf355882620c48df58be112275bd756f50"
MAX_SEQ = 512


def sha256_file(p: Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def sha256_tree(root: Path) -> str:
    """디렉터리(.mlmodelc)의 체크섬 — 상대경로와 내용을 정렬해서 한 덩어리로 잰다."""
    h = hashlib.sha256()
    for p in sorted(x for x in root.rglob("*") if x.is_file()):
        h.update(str(p.relative_to(root)).encode())
        h.update(sha256_file(p).encode())
    return h.hexdigest()


# ─────────────────────────────────────────────────────────────────────────────
# 토크나이저 — 17MB tokenizer.json 에서 Swift 가 쓸 것만 뽑는다
# ─────────────────────────────────────────────────────────────────────────────
def derive_tokenizer(src: Path, dst: Path) -> dict:
    """`tokenizer.json` → Swift 가 먹는 납작한 형태.

    17MB 원본을 앱이 매번 파싱하지 않게 **필요한 것만** 옮긴다. 옮기는 것은 넷:

    - `pieces` / `scores` — Unigram 어휘. Viterbi 가 이걸로 돈다
    - `precompiled_charsmap` — sentencepiece 정규화기(그대로 base64). Swift 가 DARTS 로 읽는다
    - `unk_id` · 특수 토큰 id
    - `normalizer_collapses_spaces` — 원본 정규화기 두 번째 단계(` {2,}`→` `)가 실재하나

    ⚠ **원본 모양이 바뀌면 조용히 넘어가지 않고 여기서 죽는다.** 아래 assert 들이 그것이다 —
    상류가 BPE 로 갈아타거나 정규화기를 바꾸면 변환이 실패해야지, 틀린 토크나이저가 나오면 안 된다.
    """
    d = json.loads(src.read_text(encoding="utf-8"))

    model = d["model"]
    assert model["type"] == "Unigram", f"Unigram 이 아니다: {model['type']} — Swift 쪽 Viterbi 가 못 먹는다"
    assert not model.get("byte_fallback"), "byte_fallback 이 켜졌다 — Swift 가 그걸 구현 안 했다"

    pre = d["pre_tokenizer"]
    assert pre["type"] == "Metaspace", f"Metaspace 가 아니다: {pre['type']}"
    assert pre["replacement"] == "▁", "메타스페이스 문자가 ▁ 가 아니다"
    assert pre.get("prepend_scheme") == "always", "prepend_scheme 이 always 가 아니다 — 앞 공백 규약이 다르다"

    norm = d["normalizer"]
    assert norm["type"] == "Sequence", f"정규화기가 Sequence 가 아니다: {norm['type']}"
    kinds = [n["type"] for n in norm["normalizers"]]
    assert kinds == ["Precompiled", "Replace"], f"정규화기 구성이 바뀌었다: {kinds}"
    charsmap = norm["normalizers"][0]["precompiled_charsmap"]
    rep = norm["normalizers"][1]
    assert rep["pattern"]["Regex"] == " {2,}" and rep["content"] == " ", \
        f"공백 접기 규칙이 바뀌었다: {rep}"

    post = d["post_processor"]
    assert post["type"] == "TemplateProcessing", f"post_processor 가 바뀌었다: {post['type']}"
    # 문장 하나짜리 틀이 <s> A </s> 인가 — Swift 가 그렇게 감싼다
    single = post["single"]
    assert list(single[0].keys()) == ["SpecialToken"] and single[0]["SpecialToken"]["id"] == "<s>"
    assert list(single[-1].keys()) == ["SpecialToken"] and single[-1]["SpecialToken"]["id"] == "</s>"

    pieces = [p[0] for p in model["vocab"]]
    scores = [p[1] for p in model["vocab"]]
    ids = {t: i for i, t in enumerate(pieces)}

    out = {
        "_": "scripts/convert_e5_coreml.py 가 tokenizer.json 에서 뽑았다. 손으로 고치지 마라",
        "source": {"model_id": MODEL_ID, "revision": REVISION,
                   "tokenizer_json_sha256": sha256_file(src)},
        "unk_id": model["unk_id"],
        "bos_id": ids["<s>"],
        "eos_id": ids["</s>"],
        "pad_id": ids["<pad>"],
        "max_seq_length": MAX_SEQ,
        "normalizer_collapses_spaces": True,
        "precompiled_charsmap": charsmap,
        "pieces": pieces,
        "scores": scores,
    }
    dst.write_text(json.dumps(out, ensure_ascii=False), encoding="utf-8")
    raw = base64.b64decode(charsmap)
    print(f"  토크나이저: 조각 {len(pieces)}개 · charsmap {len(raw)}바이트 → {dst.name} "
          f"({dst.stat().st_size / 1e6:.1f}MB)")
    return out


# ─────────────────────────────────────────────────────────────────────────────
# 모델 — Transformer + MeanPool + L2Norm 을 하나로 추적한다
# ─────────────────────────────────────────────────────────────────────────────
def build_traced(snapshot: Path):
    import torch
    import types
    from transformers import AutoModel

    # ★ fp16 안전한 어텐션 마스크 바닥값.
    #
    # ⚠ **이걸 안 하면 벡터 384칸이 통째로 NaN 이 된다** (`실측 2026-08-30`, #31).
    #   HF 기본 구현은 `(1 - mask) * torch.finfo(dtype).min` 인데 그 상수가 -3.4e38 이다.
    #   CoreML 이 fp16 으로 구우면 그게 **-inf 로 넘치고**, 진짜 토큰 자리에서 `0 * -inf = NaN`
    #   이 나온다. 변환 로그의 `RuntimeWarning: overflow encountered in cast` 가 그 순간이다.
    # → -1e4 는 fp16 안에 있고 softmax 를 지나면 0 이라 **수치적으로 -inf 와 같다.**
    #   (BERT 원본이 쓰던 값이기도 하다 — 우리가 지어낸 상수가 아니다.)
    def _fp16_safe_extended_mask(self, attention_mask, input_shape, device=None, dtype=None):
        if dtype is None:
            dtype = self.dtype
        ext = attention_mask[:, None, None, :].to(dtype)
        return (1.0 - ext) * -1e4

    class Embedder(torch.nn.Module):
        """추적되는 것 전부. **여기 있는 것이 곧 파이썬과 일치해야 하는 것**이다."""

        def __init__(self, bert):
            super().__init__()
            self.bert = bert

        def forward(self, input_ids, attention_mask):
            hidden = self.bert(input_ids=input_ids,
                               attention_mask=attention_mask).last_hidden_state
            mask = attention_mask.unsqueeze(-1).to(hidden.dtype)
            summed = (hidden * mask).sum(dim=1)
            counts = mask.sum(dim=1).clamp(min=1e-9)
            mean = summed / counts
            return mean / mean.norm(p=2, dim=-1, keepdim=True).clamp(min=1e-12)

    # ⚠ `torch_dtype=` 다. transformers 5.x 는 `dtype=` 로 이름을 바꿨는데, 이 스크립트는
    #   **4.52.4 에 고정**돼 있다 — 5.16 에선 CoreML 변환이 `new_ones` 미구현으로 죽는다(#31 실측).
    bert = AutoModel.from_pretrained(snapshot, attn_implementation="eager",
                                     torch_dtype="float32").eval()
    # ⚠ `eager` 라야 이 메서드를 탄다 — sdpa 경로는 `_prepare_4d_attention_mask_for_sdpa` 로
    #   가서 이 덮어쓰기를 안 거친다(`modeling_bert.py:982` 대 `:988`).
    bert.get_extended_attention_mask = types.MethodType(_fp16_safe_extended_mask, bert)
    net = Embedder(bert).eval()

    ids = torch.randint(5, 1000, (1, 32), dtype=torch.int32)
    mask = torch.ones((1, 32), dtype=torch.int32)
    with torch.no_grad():
        traced = torch.jit.trace(net, (ids, mask), strict=False)
    return traced, net


def convert(traced, out_pkg: Path, precision: str, shapes: list[int]):
    import coremltools as ct
    import numpy as np

    # ★ 열거된 길이. RangeDim(유연 길이)이 아니라 이걸 쓰는 이유:
    #   유연 길이는 Neural Engine 을 못 타고 CPU 로 떨어진다. 열거형은 각 길이마다 미리
    #   컴파일돼 ANE 를 탄다. 대신 **여기 없는 길이는 위로 올림 패딩**을 Swift 가 한다.
    #   패딩된 자리는 attention_mask 가 0 이라 평균 풀링에 안 들어간다 — 값이 안 변한다.
    enum = ct.EnumeratedShapes(shapes=[[1, n] for n in shapes], default=[1, shapes[-1]])
    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="input_ids", shape=enum, dtype=np.int32),
                ct.TensorType(name="attention_mask", shape=enum, dtype=np.int32)],
        outputs=[ct.TensorType(name="embedding", dtype=np.float32)],
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16 if precision == "fp16" else ct.precision.FLOAT32,
        minimum_deployment_target=ct.target.macOS15,
    )
    mlmodel.short_description = (
        f"{MODEL_ID} @ {REVISION[:12]} — mean-pooled, L2-normalized sentence embedding (384-d). "
        f"Prefix convention: 'query: ' / 'passage: '.")
    mlmodel.input_description["input_ids"] = "XLM-R Unigram token ids, <s> … </s> wrapped"
    mlmodel.input_description["attention_mask"] = "1 for real tokens, 0 for padding"
    mlmodel.output_description["embedding"] = "L2-normalized 384-d vector; cosine = dot product"
    if out_pkg.exists():
        shutil.rmtree(out_pkg)
    mlmodel.save(str(out_pkg))
    return mlmodel


def compile_model(pkg: Path, out_dir: Path) -> Path:
    """`.mlpackage` → `.mlmodelc`. 앱이 실행 시점에 컴파일하지 않게 여기서 굽는다."""
    r = subprocess.run(["xcrun", "coremlcompiler", "compile", str(pkg), str(out_dir)],
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f"coremlcompiler 실패:\n{r.stdout}\n{r.stderr}")
    compiled = out_dir / (pkg.stem + ".mlmodelc")
    if not compiled.is_dir():
        raise SystemExit(f"컴파일 결과가 없다: {compiled}")
    return compiled


def du(p: Path) -> int:
    if p.is_file():
        return p.stat().st_size
    return sum(x.stat().st_size for x in p.rglob("*") if x.is_file())


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--snapshot", required=True, type=Path,
                    help="HF 스냅샷 디렉터리 (fetch-model.sh 가 넘긴다)")
    ap.add_argument("--out", required=True, type=Path, help="산출물이 앉을 캐시 디렉터리")
    ap.add_argument("--precision", choices=("fp16", "fp32"), default="fp16")
    ap.add_argument("--shapes", default="32,64,128,256,512",
                    help="열거할 시퀀스 길이들 (쉼표)")
    a = ap.parse_args()

    snapshot: Path = a.snapshot.expanduser().resolve()
    out: Path = a.out.expanduser()
    out.mkdir(parents=True, exist_ok=True)
    shapes = sorted(int(x) for x in a.shapes.split(","))
    if shapes[-1] > MAX_SEQ:
        raise SystemExit(f"{shapes[-1]} 는 모델 최대 길이 {MAX_SEQ} 를 넘는다")

    print(f"→ 토크나이저 뽑는 중  ({snapshot.name})")
    derive_tokenizer(snapshot / "tokenizer.json", out / "tokenizer-unigram.json")

    print("→ 추적 중 (Transformer + MeanPool + L2Norm)")
    traced, _ = build_traced(snapshot)

    print(f"→ CoreML 변환 중  precision={a.precision} shapes={shapes}")
    pkg = out / "E5SmallKoV2.mlpackage"
    convert(traced, pkg, a.precision, shapes)

    print("→ 컴파일 중 (.mlmodelc)")
    compiled = compile_model(pkg, out)
    shutil.rmtree(pkg)   # 컴파일본만 남긴다 — 앱은 .mlpackage 를 안 연다

    manifest = {
        "_": "scripts/convert_e5_coreml.py 가 썼다. 앱이 이걸 먼저 읽는다",
        "model_id": MODEL_ID,
        "revision": REVISION,
        "dimensions": 384,
        "precision": a.precision,
        "max_seq_length": MAX_SEQ,
        "enumerated_shapes": shapes,
        "pooling": "mean",
        "normalized": True,
        "prefix_convention": {"query": "query: ", "passage": "passage: "},
        "model_dir": compiled.name,
        "tokenizer_file": "tokenizer-unigram.json",
        "model_sha256": sha256_tree(compiled),
        "tokenizer_sha256": sha256_file(out / "tokenizer-unigram.json"),
        "bytes": {"model": du(compiled), "tokenizer": du(out / "tokenizer-unigram.json")},
    }
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
                                       encoding="utf-8")

    total = du(compiled) + du(out / "tokenizer-unigram.json")
    print(f"\n✓ {out}")
    print(f"  모델      {du(compiled) / 1e6:8.1f} MB   {compiled.name}")
    print(f"  토크나이저 {du(out / 'tokenizer-unigram.json') / 1e6:8.1f} MB")
    print(f"  합계      {total / 1e6:8.1f} MB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
