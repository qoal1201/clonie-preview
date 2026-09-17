#!/bin/bash
set -euo pipefail

BRANDING_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/clonie-brand.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

DOCK_PNG="$BRANDING_DIR/ClonieDock.png"
MENU_SVG="$BRANDING_DIR/source/ClonieMenuTemplate.svg"
MARK_SVG="$BRANDING_DIR/source/ClonieSymbolCream.svg"
CHAT_HTML="$BRANDING_DIR/../../Sources/Clonie/Resources/ChatHTML.swift"
ICONSET="$WORK_DIR/Clonie.iconset"
mkdir -p "$ICONSET"

/usr/bin/sips -s format png "$MENU_SVG" --out "$WORK_DIR/ClonieMenuTemplate.png" >/dev/null
/usr/bin/sips -s format png "$MARK_SVG" --out "$WORK_DIR/ClonieMark-1024.png" >/dev/null
/usr/bin/sips -z 256 256 "$WORK_DIR/ClonieMark-1024.png" --out "$WORK_DIR/ClonieMark.png" >/dev/null

for SIZE in 16 32 128 256 512; do
  /usr/bin/sips -z "$SIZE" "$SIZE" "$DOCK_PNG" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
  RETINA_SIZE=$((SIZE * 2))
  /usr/bin/sips -z "$RETINA_SIZE" "$RETINA_SIZE" "$DOCK_PNG" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done

/usr/bin/iconutil -c icns "$ICONSET" -o "$WORK_DIR/Clonie.icns"
/bin/cp "$WORK_DIR/ClonieMenuTemplate.png" "$BRANDING_DIR/ClonieMenuTemplate.png"
/bin/cp "$WORK_DIR/ClonieMark.png" "$BRANDING_DIR/ClonieMark.png"
/bin/cp "$WORK_DIR/Clonie.icns" "$BRANDING_DIR/Clonie.icns"

BRAND_MARK_BASE64="$(/usr/bin/base64 < "$BRANDING_DIR/ClonieMark.png" | /usr/bin/tr -d '\n')" \
  /usr/bin/perl -0pi -e '
    my $prefix = q{const BRAND_MARK_DATA_URI="data:image/png;base64,};
    my $replacement = $prefix . $ENV{"BRAND_MARK_BASE64"} . q{";};
    my $count = s/\Q$prefix\E[^"]+";/$replacement/;
    die "expected one BRAND_MARK_DATA_URI\n" unless $count == 1;
  ' "$CHAT_HTML"
