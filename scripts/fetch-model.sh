#!/bin/bash
# 임베딩 모델을 받아 **CoreML 로 구워 캐시에 앉힌다** (#31, ADR 0003 §5).
#
# ⚠ **`build.sh` 는 이 스크립트를 안 부른다. 일부러다.**
#   `.app` 빌드는 12초인데 이건 470MB 를 받고 변환까지 한다 — 묶으면 빌드가 그 비용을 늘 문다.
#   그리고 앱은 모델이 없어도 **명확한 상태를 내며** 뜬다(`EmbeddingModelStore`). 그러니
#   받는 것은 별도 행위다. `정관 9조`(작업 자체인 것만 산다) 를 어기는 것처럼 보이는데,
#   여기서 「작업」은 **앱 빌드가 아니라 임베딩을 쓰는 것**이고, 그건 이 스크립트가 곧 그 작업이다.
#
# ⚠ **네트워크를 타는 것은 이 레포에서 여기뿐이다.** 앱 런타임 코드에 URLSession 이 없다 —
#   `tests/check_interview_offline.py` 가 그 판정선을 잰다.
#
#     ./scripts/fetch-model.sh              # 없으면 받고, 있으면 아무것도 안 한다
#     ./scripts/fetch-model.sh --force      # 다시 받고 다시 굽는다
#     ./scripts/fetch-model.sh --precision fp32
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"

MODEL_ID="dragonkue/multilingual-e5-small-ko-v2"
# ★ 고정한 리비전. 기준면(tests/fixtures/embedding_reference.json)이 이 리비전으로 떠 있다 —
#   여기를 올리면 기준면도 같이 다시 떠야 하고, 안 그러면 점수 일치 자물쇠가 빨개진다.
REVISION="fcfc26bf355882620c48df58be112275bd756f50"
OUT="${CLONIE_MODEL_DIR:-$HOME/Library/Application Support/Clonie/models/multilingual-e5-small-ko-v2}"
PRECISION="fp16"
FORCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    --out) OUT="$2"; shift 2 ;;
    --precision) PRECISION="$2"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "모르는 인자: $1" >&2; exit 2 ;;
  esac
done

# ── 이미 있나 ────────────────────────────────────────────────────────────────
if [ "$FORCE" -eq 0 ] && [ -f "$OUT/manifest.json" ]; then
  HAVE=$(/usr/bin/python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('revision',''))" \
         "$OUT/manifest.json" 2>/dev/null || echo "")
  if [ "$HAVE" = "$REVISION" ]; then
    echo "✓ 이미 있다 — $OUT"
    echo "  다시 받으려면: $0 --force"
    exit 0
  fi
  echo "→ 캐시에 다른 리비전이 있다 ('${HAVE:0:12}' ≠ '${REVISION:0:12}') — 다시 굽는다"
fi

# ── 받을 것과 그 체크섬 ──────────────────────────────────────────────────────
# ⚠ **체크섬을 여기 박는 이유**: 상류가 같은 리비전에서 파일을 바꿔치기해도, 받다 끊겨도,
#   여기서 빨개진다. 체크섬 없이 받으면 **깨진 모델로 조용히 이상한 점수**를 내게 된다.
#   값은 `shasum -a 256` 실측(2026-08-30)이다.
FILES=(
  "config.json d99cc57db7529a5b6921f38d899dafad5bb829e21078900c8ba2c4ae9d141acb"
  "tokenizer.json cd98e5698b201ba914efb8c18b6709fa8735ab71dcad8d2b431e52e8bf68d932"
  "tokenizer_config.json 088b1b60e1fbc7fbdbb3d4bc84922b388692c7089d4607a9909b46a549ebd57e"
  "special_tokens_map.json 38d989b0fdad0fec0c67c14b1f3c8b68184022cf6d4adc5444526ced8653f738"
  "sentence_bert_config.json ec8e29d6dcb61b611b7d3fdd2982c4524e6ad985959fa7194eacfb655a8d0d51"
  "modules.json 84e40c8e006c9b1d6c122e02cba9b02458120b5fb0c87b746c41e0207cf642cf"
  "config_sentence_transformers.json 7e91538623973218cf7894dea35429cad353cb0470a7932dc3b16845596fc6a2"
  "1_Pooling/config.json a19c83805e1ce4174f3fbfec4ac8d3b8dbae0c958f8fd51b80937eb33e0c5335"
  "model.safetensors 9794f247caf80caf54b5a04d391c932ba6260cf20bd16fba3892ce2d8f5784ec"
)

SNAP="${CLONIE_MODEL_SNAPSHOT:-$HOME/.cache/clonie/hf/$MODEL_ID/$REVISION}"
mkdir -p "$SNAP/1_Pooling"

echo "→ 원본 받는 중 (${MODEL_ID}@${REVISION:0:12})"
for entry in "${FILES[@]}"; do
  name="${entry%% *}"; want="${entry##* }"
  dest="$SNAP/$name"
  if [ -f "$dest" ]; then
    got=$(shasum -a 256 "$dest" | cut -d' ' -f1)
    [ "$got" = "$want" ] && { echo "  = $name (이미 있음)"; continue; }
    echo "  ! $name 체크섬이 다르다 — 다시 받는다"
  fi
  url="https://huggingface.co/$MODEL_ID/resolve/$REVISION/$name"
  echo "  ↓ $name"
  curl -fL --retry 3 --retry-delay 2 --progress-bar -o "$dest.part" "$url"
  got=$(shasum -a 256 "$dest.part" | cut -d' ' -f1)
  if [ "$got" != "$want" ]; then
    rm -f "$dest.part"
    echo "✗ 체크섬이 안 맞는다 — $name" >&2
    echo "  기대 $want" >&2
    echo "  받은 $got" >&2
    echo "  상류가 바뀌었거나 받다 끊겼다. 이 상태로 구우면 점수가 조용히 틀어진다." >&2
    exit 1
  fi
  mv "$dest.part" "$dest"
done

# ── 변환에 쓸 파이썬 ─────────────────────────────────────────────────────────
# ⚠ 변환은 coremltools·torch 를 쓴다. **버전이 고정이다** — 자유롭게 두면 조용히 깨진다:
#   transformers 5.x 는 `new_ones` 미구현으로 변환이 죽고, coremltools 9 가 확인한 torch 는 2.7 이다
#   (`실측 2026-08-30`, #31).
VENV="${CLONIE_CONVERT_VENV:-$HOME/.cache/clonie/convert-venv}"
PY="$VENV/bin/python"
if [ ! -x "$PY" ]; then
  echo "→ 변환용 파이썬 환경을 만든다 — $VENV"
  echo "  ⚠ 처음 한 번은 수 GB 를 받는다 (torch·coremltools). 모델을 구울 때만 쓴다."
  if command -v uv >/dev/null 2>&1; then
    uv venv --python 3.12 "$VENV"
    UV_LINK_MODE=copy uv pip install --python "$PY" \
      "coremltools==9.0" "torch==2.7.0" "transformers==4.52.4" \
      "sentence-transformers==4.1.0" "numpy<2"
  else
    /usr/bin/python3 -m venv "$VENV"
    "$PY" -m pip install --quiet --upgrade pip
    "$PY" -m pip install "coremltools==9.0" "torch==2.7.0" "transformers==4.52.4" \
      "sentence-transformers==4.1.0" "numpy<2"
  fi
fi

echo "→ CoreML 로 굽는 중 (precision=$PRECISION)"
"$PY" "$DIR/scripts/convert_e5_coreml.py" --snapshot "$SNAP" --out "$OUT" --precision "$PRECISION"

# ── 양성 대조: 정말 앉았나 ───────────────────────────────────────────────────
# `정관 10조` — 부재는 검사 못 한다. 「구웠다」고 말하기 전에 **읽어서 확인**한다.
if [ ! -f "$OUT/manifest.json" ] || [ ! -d "$OUT/E5SmallKoV2.mlmodelc" ]; then
  echo "✗ 구웠다는데 산출물이 없다 — $OUT" >&2
  exit 1
fi
echo
echo "✓ 준비됐다 — $OUT"
echo "  확인:  CLONIE_REQUIRE_EMBEDDING_MODEL=1 swift test --filter ClonieEmbeddingTests"
