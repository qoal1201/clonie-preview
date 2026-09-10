#!/bin/bash
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

VERSION="1.0.2"
APP="Ghostbar.app"
DMG="Ghostbar-v${VERSION}.dmg"

# ── --app-only (P10, 감사 2026-09-04) ───────────────────────────────────────
# 왜: QA 루프는 빌드마다 .app 만 있으면 되고, DMG(hdiutil 셋) 는 굽는 데 수십 초가 드는데
#   그 결과물을 QA 가 열어보지 않는다. 인자 없이 부르면 지금까지처럼 DMG 까지 만든다.
APP_ONLY=0
INCLUDE_MODEL=0
BUNDLE_ID="com.local.ghostbar"
EXECUTABLE="Ghostbar"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --app-only) APP_ONLY=1 ;;
    --qa-app) APP_ONLY=1; APP="GhostbarQA.app"; BUNDLE_ID="com.local.ghostbar.qa"; EXECUTABLE="GhostbarQA" ;;
    --include-model) INCLUDE_MODEL=1 ;;
    --help|-h)
      echo "Usage: $0 [--app-only] [--qa-app] [--include-model]" >&2
      exit 0
      ;;
    *) echo "Usage: $0 [--app-only] [--qa-app] [--include-model]" >&2; exit 2 ;;
  esac
  shift
done

# ── QA 노출 게이트 (#24 C 층) ────────────────────────────────────────────────
# ⚠ **이 스크립트는 QA 노출 환경변수를 절대 안 세운다.** 그 변수가 켜진 채 만들어진 빌드는
#   화면 공유에 창이 잡히고, 그게 이 제품의 최악의 실패다. `tests/check_qa_visible_gate.py`
#   가 이 파일을 훑어서 그것을 잰다 (주석은 걷고 보므로 이 설명은 안전하다).
#   QA 로 켜는 법은 `Sources/Ghostbar/UI/WindowPrivacy.swift` 머리글에 있다 — 알맹이를
#   직접 부르는 것이지 빌드가 굽는 것이 아니다.

echo "→ Building Ghostbar..."
swift build -c release 2>&1

BINARY=".build/release/Ghostbar"

echo "→ Creating .app bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BINARY" "$APP/Contents/MacOS/$EXECUTABLE"

# ★ 둘째 문 (ADR 0007) — 같은 빌드가 낸 MCP 서버를 앱 옆에 싣는다. 등록은 아래 안내 한 줄.
#   앱 바이너리와 **같은 codesign --deep** 에 든다(아래). 따로 서명하지 않는다.
MCP_BINARY=".build/release/clonie-mcp"
[ -f "$MCP_BINARY" ] || { echo "✗ $MCP_BINARY 가 없다 — swift build 가 둘째 타깃을 안 만들었다" >&2; exit 1; }
cp "$MCP_BINARY" "$APP/Contents/MacOS/clonie-mcp"

[ -f "$DIR/Ghostbar.icns" ] && cp "$DIR/Ghostbar.icns" "$APP/Contents/Resources/Ghostbar.icns"
if [ -d "$DIR/ThirdPartyNotices" ]; then
  cp -R "$DIR/ThirdPartyNotices" "$APP/Contents/Resources/ThirdPartyNotices"
fi

# 선택한 때에만 이미 변환·검증된 CoreML 산출물 셋을 앱에 싣는다. 내려받기·변환은 절대 여기서
# 하지 않는다. 기본 빌드는 이 갈래를 전혀 타지 않아, 새 클론의 기존 개발 흐름을 그대로 지킨다.
if [ "$INCLUDE_MODEL" -eq 1 ]; then
  MODEL_SOURCE="${GHOSTBAR_MODEL_DIR:-$HOME/Library/Application Support/Ghostbar/models/multilingual-e5-small-ko-v2}"
  echo "→ 동봉 임베딩 모델 검증·복사: $MODEL_SOURCE"
  python3 - "$MODEL_SOURCE" "$APP/Contents/Resources" <<'PYEOF'
import hashlib
import json
import shutil
import sys
from pathlib import Path

source = Path(sys.argv[1]).expanduser()
resources = Path(sys.argv[2])


def fail(message: str) -> None:
    raise SystemExit(f"✗ --include-model: {message}")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def tree_files(root: Path) -> list[Path]:
    if root.is_symlink():
        fail(f"model_dir가 심볼릭 링크다: {root}")
    files: list[Path] = []
    for path in root.rglob("*"):
        if path.is_symlink():
            fail(f"모델 산출물에 심볼릭 링크가 있다: {path}")
        if path.is_file():
            files.append(path)
        elif not path.is_dir():
            fail(f"모델 산출물에 읽을 수 없는 항목이 있다: {path}")
    return files


def sha256_tree(root: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(tree_files(root)):
        digest.update(str(path.relative_to(root)).encode())
        digest.update(sha256_file(path).encode())
    return digest.hexdigest()


def byte_count(root: Path) -> int:
    return sum(path.stat().st_size for path in tree_files(root))


def relative_name(value: object, key: str) -> Path:
    if not isinstance(value, str) or not value:
        fail(f"manifest.json의 {key}가 없다")
    path = Path(value)
    if path.is_absolute() or any(part in ("", ".", "..") for part in path.parts):
        fail(f"manifest.json의 {key}가 안전한 상대 경로가 아니다: {value!r}")
    return path

if not source.is_dir() or source.is_symlink():
    fail(f"변환 모델 디렉터리가 없거나 심볼릭 링크다: {source}")
manifest_path = source / "manifest.json"
if not manifest_path.is_file() or manifest_path.is_symlink():
    fail(f"manifest.json이 없다: {manifest_path}")
try:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as error:
    fail(f"manifest.json을 읽지 못한다: {error}")
if not isinstance(manifest, dict):
    fail("manifest.json 최상위가 객체가 아니다")

model_rel = relative_name(manifest.get("model_dir"), "model_dir")
tokenizer_rel = relative_name(manifest.get("tokenizer_file"), "tokenizer_file")
model = source / model_rel
tokenizer = source / tokenizer_rel
if not model.is_dir() or model.is_symlink():
    fail(f"manifest model_dir가 디렉터리가 아니다: {model}")
if not tokenizer.is_file() or tokenizer.is_symlink():
    fail(f"manifest tokenizer_file이 파일이 아니다: {tokenizer}")
for key in ("model_id", "revision", "dimensions", "model_sha256", "tokenizer_sha256", "bytes"):
    if key not in manifest:
        fail(f"manifest.json의 {key}가 없다")
if not isinstance(manifest["bytes"], dict):
    fail("manifest.json의 bytes가 객체가 아니다")

model_sha = sha256_tree(model)
tokenizer_sha = sha256_file(tokenizer)
model_bytes = byte_count(model)
tokenizer_bytes = tokenizer.stat().st_size
if manifest["model_sha256"] != model_sha:
    fail("model_dir SHA-256이 manifest와 다르다")
if manifest["tokenizer_sha256"] != tokenizer_sha:
    fail("tokenizer SHA-256이 manifest와 다르다")
if manifest["bytes"].get("model") != model_bytes or manifest["bytes"].get("tokenizer") != tokenizer_bytes:
    fail("산출물 바이트 수가 manifest와 다르다")

bundle = resources / "EmbeddingModel"
if bundle.is_symlink():
    fail(f"대상 번들 디렉터리가 심볼릭 링크다: {bundle}")
if bundle.exists():
    shutil.rmtree(bundle)
bundle.mkdir(parents=True)
shutil.copy2(manifest_path, bundle / "manifest.json")
shutil.copy2(tokenizer, bundle / tokenizer_rel)
shutil.copytree(model, bundle / model_rel)

# 복사한 파일도 같은 검증값인지 확인한다. 이 줄을 지나야 서명 단계로 간다.
if (sha256_tree(bundle / model_rel) != model_sha
        or sha256_file(bundle / tokenizer_rel) != tokenizer_sha
        or byte_count(bundle / model_rel) != model_bytes
        or (bundle / tokenizer_rel).stat().st_size != tokenizer_bytes):
    fail("복사한 동봉 모델의 검증값이 원본과 다르다")
print(f"  {manifest['model_id']}@{str(manifest['revision'])[:12]} · "
      f"model {model_bytes}B sha256:{model_sha} · tokenizer {tokenizer_bytes}B sha256:{tokenizer_sha}")
PYEOF
fi

# 판 번호는 위 셸 VERSION 한 곳에서만 읽는다(P9, 감사 2026-09-04) — pack-mcpb.sh 가
# manifest.json 을 바이너리 판에 맞추는 것과 같은 모양: 정본은 하나, 나머지는 거기서 채운다.
# 보간이 필요해 heredoc 을 unquoted 로 연다 — 본문에 $·`·\ 가 없어 안전하다.
cat > "$APP/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$EXECUTABLE</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$EXECUTABLE</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleIconFile</key><string>Ghostbar</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSMicrophoneUsageDescription</key><string>Clonie uses the microphone to transcribe your speech on this Mac.</string>
  <key>NSScreenCaptureUsageDescription</key><string>Clonie uses screen recording access to transcribe system audio during interviews.</string>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsArbitraryLoads</key><true/>
  </dict>
</dict>
</plist>
PLIST

# ── 서명 신원 (#21) ───────────────────────────────────────────────────────────
# ⚠ **ad-hoc(`-`) 로 서명하면 빌드마다 권한을 다시 승인해야 한다.**
#   `실측 2026-08-28`: ad-hoc 의 지정 요건은 `cdhash H"…"` 하나이고 코드가 한 줄만
#   바뀌어도 값이 달라진다. TCC 는 앱을 그 지정 요건으로 기억하므로 예전 허가가 무효가 된다.
#   그래서 아래 `tccutil reset` 두 줄이 있었다 — 리셋은 **원인이 아니라 대처**였다.
# → 진짜 인증서로 서명하면 지정 요건이 **인증서 기준**이 되어 재빌드해도 같다.
#   이 맥엔 `Apple Development: sunho park` 이 이미 있다.
# 신원을 직접 고르려면 `GHOSTBAR_SIGN_ID=<해시 또는 이름> ./build.sh`.
SIGN_ID="${GHOSTBAR_SIGN_ID:-$(security find-identity -v -p codesigning 2>/dev/null | awk '/\)/ {print $2; exit}')}"
if [ -z "$SIGN_ID" ]; then
  SIGN_ID="-"
  echo "→ 서명: ad-hoc (신원이 없다 — 빌드마다 권한을 다시 승인해야 한다)"
else
  echo "→ 서명: $SIGN_ID"
fi

echo "→ Signing..."
cat > /tmp/entitlements.plist << 'ENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key><false/>
</dict>
</plist>
ENT

codesign --force --deep --sign "$SIGN_ID" \
  --identifier "$BUNDLE_ID" \
  --entitlements /tmp/entitlements.plist \
  "$APP"

# 지정 요건을 찍어둔다 — 두 번 빌드해서 이 줄이 같으면 권한이 유지된다 (#21 판정선).
echo "→ 지정 요건: $(codesign -d -r- "$APP" 2>&1 | grep 'designated' || echo '?')"

if [ "$SIGN_ID" = "-" ]; then
  # ad-hoc 일 때만 리셋한다. 지문이 매번 바뀌어서, 안 지우면
  # 「허용된 것처럼 보이는데 실제로는 막힘」이라는 조용한 실패가 된다.
  echo "→ Resetting TCC permissions (ad-hoc signature changed)..."
  tccutil reset ScreenCapture "$BUNDLE_ID" 2>/dev/null || true
  tccutil reset Microphone    "$BUNDLE_ID" 2>/dev/null || true
fi

if [ "$APP_ONLY" -eq 1 ]; then
  echo "→ --app-only: DMG 건너뜀"
else
  echo "→ Creating DMG..."
  STAGING="$(mktemp -d)/Ghostbar"
  mkdir -p "$STAGING"
  cp -r "$APP" "$STAGING/"
  ln -s /Applications "$STAGING/Applications"

  # Create writable DMG, mount, set volume icon, unmount, convert
  TMP_DMG="$DIR/tmp_ghostbar.dmg"
  rm -f "$TMP_DMG" "$DMG"
  hdiutil create -volname "Ghostbar" -srcfolder "$STAGING" -ov -format UDRW "$TMP_DMG" > /dev/null

  MOUNT_DIR="$(mktemp -d)"
  hdiutil attach "$TMP_DMG" -mountpoint "$MOUNT_DIR" -nobrowse -quiet

  [ -f "$DIR/Ghostbar.icns" ] && cp "$DIR/Ghostbar.icns" "$MOUNT_DIR/.VolumeIcon.icns"

  # Set custom icon flag on the volume
  python3 - "$MOUNT_DIR" << 'PYEOF'
import subprocess, sys
path = sys.argv[1]
try:
    r = subprocess.run(['xattr', '-px', 'com.apple.FinderInfo', path], capture_output=True, text=True)
    d = bytearray.fromhex(r.stdout.replace(' ','').replace('\n','')) if r.returncode == 0 else bytearray(32)
    if len(d) < 32: d += bytearray(32 - len(d))
    d[8] |= 0x04  # kHasCustomIcon
    subprocess.run(['xattr', '-wx', 'com.apple.FinderInfo', d.hex(), path], check=True)
except Exception as e:
    print(f"  icon flag warning: {e}")
PYEOF

  hdiutil detach "$MOUNT_DIR" -quiet
  hdiutil convert "$TMP_DMG" -format UDZO -o "$DMG" > /dev/null
  rm -f "$TMP_DMG"
  rm -rf "$STAGING"
fi

echo ""
echo "✓ Done:"
echo "  App:  $DIR/$APP"
[ "$APP_ONLY" -eq 0 ] && echo "  DMG:  $DIR/$DMG"
echo ""
if [ "$BUNDLE_ID" = "com.local.ghostbar.qa" ]; then
  echo "→ QA 실행에는 GHOSTBAR_QA_SESSION과 GHOSTBAR_QA_VAULT를 명시하세요."
  echo "  세션별 신호만 사용합니다. 화면·음성 QA는 사용자와 시간을 맞춥니다."
  echo "  QA MCP에는 --vault <복사한 QA 볼트>가 필요합니다. 전역 등록에 사용하지 않습니다."
else
  echo "→ To run: "
  echo "    open $DIR/$APP"
  if [ "$APP_ONLY" -eq 0 ]; then
    echo "→ To install: "
    echo "    open $DIR/$DMG  (drag Ghostbar to Applications)"
    echo ""
  fi
  echo "→ Claude Code 에 볼트를 여는 둘째 문 등록 (한 번만):"
  echo "    claude mcp add --scope user clonie -- \"$DIR/$APP/Contents/MacOS/clonie-mcp\""
  echo "→ Claude Desktop 은 .mcpb 로: ./scripts/pack-mcpb.sh 가 만든 파일을 더블클릭"
  echo ""
fi
if [ "$APP_ONLY" -eq 0 ]; then
  echo "→ To release on GitHub:"
  echo "  git tag v${VERSION} && git push origin main --tags"
  echo "  # Then upload $DMG to the GitHub release"
fi
