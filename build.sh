#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

VERSION="1.0.4"
APP_NAME="Clonie"
APP_BUNDLE="Clonie.app"
BUNDLE_ID="com.local.clonie"
DMG_NAME="Clonie-v${VERSION}.dmg"
APP_ONLY=0
INCLUDE_MODEL=0

usage() {
  cat >&2 <<USAGE
Usage: $0 [--app-only] [--qa] [--include-model]

  --app-only       build and sign the app bundle without creating a DMG
  --qa             build ClonieQA.app with the QA bundle identifier
  --include-model  validate and include the prepared CoreML model bundle
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --app-only)
      APP_ONLY=1
      ;;
    --qa|--qa-app)
      APP_ONLY=1
      APP_NAME="ClonieQA"
      APP_BUNDLE="ClonieQA.app"
      BUNDLE_ID="com.local.clonie.qa"
      ;;
    --include-model)
      INCLUDE_MODEL=1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
  shift
done

APP_PATH="$ROOT_DIR/$APP_BUNDLE"
DMG_PATH="$ROOT_DIR/$DMG_NAME"
RELEASE_DIR="$ROOT_DIR/.build/release"
APP_BINARY="$RELEASE_DIR/Clonie"
MCP_BINARY="$RELEASE_DIR/clonie-mcp"

# The QA visibility gate belongs to WindowPrivacy. This build never exports it.
# The script only writes the repository-local bundle named above; it does not
# terminate, install, or remove an app from /Applications.
echo "→ Building Clonie targets..."
swift build -c release --product Clonie
swift build -c release --product clonie-mcp

[ -x "$APP_BINARY" ] || { echo "✗ missing $APP_BINARY" >&2; exit 1; }
[ -x "$MCP_BINARY" ] || { echo "✗ missing $MCP_BINARY" >&2; exit 1; }

# Replacing a repository-local build artifact is safe; the user's installed app
# is never addressed by this path.
echo "→ Creating $APP_BUNDLE..."
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$APP_BINARY" "$APP_PATH/Contents/MacOS/$APP_NAME"
cp "$MCP_BINARY" "$APP_PATH/Contents/MacOS/clonie-mcp"

copy_if_present() {
  local source="$1"
  local destination="$2"
  if [ -e "$source" ]; then
    mkdir -p "$(dirname "$destination")"
    cp -R "$source" "$destination"
  fi
}

copy_if_present "$ROOT_DIR/assets/branding/Clonie.icns" \
  "$APP_PATH/Contents/Resources/Clonie.icns"
copy_if_present "$ROOT_DIR/assets/branding/ClonieMenuTemplate.png" \
  "$APP_PATH/Contents/Resources/ClonieMenuTemplate.png"
copy_if_present "$ROOT_DIR/ThirdPartyNotices" \
  "$APP_PATH/Contents/Resources/ThirdPartyNotices"

if [ "$INCLUDE_MODEL" -eq 1 ]; then
  MODEL_SOURCE="${CLONIE_MODEL_DIR:-$HOME/Library/Application Support/Clonie/models/multilingual-e5-small-ko-v2}"
  echo "→ Validating and bundling model: $MODEL_SOURCE"
  python3 - "$MODEL_SOURCE" "$APP_PATH/Contents/Resources" <<'PY'
import hashlib
import json
import shutil
import sys
from pathlib import Path

source = Path(sys.argv[1]).expanduser()
resources = Path(sys.argv[2])


def fail(message: str) -> None:
    raise SystemExit(f"✗ --include-model: {message}")


def ensure_relative(value: object, key: str) -> Path:
    if not isinstance(value, str) or not value:
        fail(f"manifest.json의 {key}가 없다")
    path = Path(value)
    if path.is_absolute() or any(part in ("", ".", "..") for part in path.parts):
        fail(f"manifest.json의 {key}가 안전한 상대 경로가 아니다: {value!r}")
    return path


def files(root: Path) -> list[Path]:
    if root.is_symlink() or not root.is_dir():
        fail(f"모델 디렉터리가 아니다: {root}")
    found = []
    for path in root.rglob("*"):
        if path.is_symlink():
            fail(f"모델 산출물에 심볼릭 링크가 있다: {path}")
        if path.is_file():
            found.append(path)
        elif not path.is_dir():
            fail(f"모델 산출물을 읽을 수 없다: {path}")
    return found


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            result.update(chunk)
    return result.hexdigest()


def tree_digest(root: Path) -> str:
    result = hashlib.sha256()
    for path in sorted(files(root)):
        result.update(str(path.relative_to(root)).encode())
        result.update(digest(path).encode())
    return result.hexdigest()


def tree_bytes(root: Path) -> int:
    return sum(path.stat().st_size for path in files(root))


if source.is_symlink() or not source.is_dir():
    fail(f"모델 디렉터리가 없거나 심볼릭 링크다: {source}")
manifest_path = source / "manifest.json"
if manifest_path.is_symlink() or not manifest_path.is_file():
    fail(f"manifest.json이 없다: {manifest_path}")
try:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as error:
    fail(f"manifest.json을 읽지 못한다: {error}")
if not isinstance(manifest, dict):
    fail("manifest.json 최상위가 객체가 아니다")

model_rel = ensure_relative(manifest.get("model_dir"), "model_dir")
tokenizer_rel = ensure_relative(manifest.get("tokenizer_file"), "tokenizer_file")
model = source / model_rel
tokenizer = source / tokenizer_rel
if model.is_symlink() or not model.is_dir():
    fail(f"model_dir가 디렉터리가 아니다: {model}")
if tokenizer.is_symlink() or not tokenizer.is_file():
    fail(f"tokenizer_file이 파일이 아니다: {tokenizer}")
for key in ("model_id", "revision", "dimensions", "model_sha256", "tokenizer_sha256", "bytes"):
    if key not in manifest:
        fail(f"manifest.json의 {key}가 없다")
if not isinstance(manifest["bytes"], dict):
    fail("manifest.json의 bytes가 객체가 아니다")

model_sha = tree_digest(model)
tokenizer_sha = digest(tokenizer)
model_size = tree_bytes(model)
tokenizer_size = tokenizer.stat().st_size
if manifest["model_sha256"] != model_sha:
    fail("model_dir SHA-256이 manifest와 다르다")
if manifest["tokenizer_sha256"] != tokenizer_sha:
    fail("tokenizer SHA-256이 manifest와 다르다")
if manifest["bytes"].get("model") != model_size or manifest["bytes"].get("tokenizer") != tokenizer_size:
    fail("산출물 바이트 수가 manifest와 다르다")

bundle = resources / "EmbeddingModel"
if bundle.is_symlink():
    fail(f"대상 모델 번들이 심볼릭 링크다: {bundle}")
if bundle.exists():
    shutil.rmtree(bundle)
bundle.mkdir(parents=True)
shutil.copy2(manifest_path, bundle / "manifest.json")
(bundle / tokenizer_rel).parent.mkdir(parents=True, exist_ok=True)
(bundle / model_rel).parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(tokenizer, bundle / tokenizer_rel)
shutil.copytree(model, bundle / model_rel)
if tree_digest(bundle / model_rel) != model_sha or digest(bundle / tokenizer_rel) != tokenizer_sha:
    fail("복사한 모델의 SHA-256이 원본과 다르다")
if tree_bytes(bundle / model_rel) != model_size or (bundle / tokenizer_rel).stat().st_size != tokenizer_size:
    fail("복사한 모델의 바이트 수가 원본과 다르다")
print(f"  {manifest['model_id']}@{str(manifest['revision'])[:12]} · model sha256:{model_sha}")
PY
fi

cat > "$APP_PATH/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleIconFile</key><string>Clonie</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSMicrophoneUsageDescription</key><string>Clonie uses the microphone to transcribe your speech on this Mac.</string>
  <key>NSScreenCaptureUsageDescription</key><string>Clonie uses screen recording access to transcribe system audio during interviews.</string>
  <key>NSAppTransportSecurity</key>
  <dict><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict>
</plist>
PLIST

SIGN_ID="${CLONIE_SIGN_ID:-}"
if [ -z "$SIGN_ID" ]; then
  SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null | awk '/\)/ {print $2; exit}')"
fi
SIGN_ID="${SIGN_ID:--}"
echo "→ Signing $APP_BUNDLE as $SIGN_ID..."
ENTITLEMENTS="$ROOT_DIR/.build/clonie.entitlements.plist"
mkdir -p "$(dirname "$ENTITLEMENTS")"
cat > "$ENTITLEMENTS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.security.app-sandbox</key><false/></dict></plist>
PLIST
codesign --force --deep --sign "$SIGN_ID" --identifier "$BUNDLE_ID" \
  --entitlements "$ENTITLEMENTS" "$APP_PATH"
rm -f "$ENTITLEMENTS"
echo "→ Designated requirement: $(codesign -d -r- "$APP_PATH" 2>&1 | grep 'designated' || true)"

if [ "$APP_ONLY" -eq 0 ]; then
  echo "→ Creating $DMG_NAME..."
  DMG_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/clonie-dmg.XXXXXX")"
  mkdir -p "$DMG_STAGE/Clonie"
  cp -R "$APP_PATH" "$DMG_STAGE/Clonie/"
  ln -s /Applications "$DMG_STAGE/Clonie/Applications"
  if [ -f "$ROOT_DIR/assets/branding/Clonie.icns" ]; then
    cp "$ROOT_DIR/assets/branding/Clonie.icns" "$DMG_STAGE/Clonie/.VolumeIcon.icns"
    xcrun SetFile -a C "$DMG_STAGE/Clonie"
  fi
  hdiutil create -volname "Clonie" -srcfolder "$DMG_STAGE/Clonie" \
    -ov -format UDZO "$DMG_PATH" >/dev/null
  rm -rf "$DMG_STAGE"
fi

echo
echo "✓ Done"
echo "  App: $APP_PATH"
if [ "$APP_ONLY" -eq 0 ]; then
  echo "  DMG: $DMG_PATH"
fi
if [ "$BUNDLE_ID" = "com.local.clonie.qa" ]; then
  echo "→ QA 실행 전 CLONIE_QA_SESSION과 CLONIE_QA_VAULT를 명시하세요."
else
  echo "→ MCP: $APP_PATH/Contents/MacOS/clonie-mcp"
fi
