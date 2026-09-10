#!/bin/bash
# Install a pinned preview without Homebrew, sudo, or changes to user documents.
set -euo pipefail

CLONIE_VERSION="20260910-clonie1"
CLONIE_ARCHIVE_NAME="Clonie-preview-${CLONIE_VERSION}-arm64.zip"
CLONIE_SHA256="99cdaaeb78d9b5c888b5823b91a0f35c703a3e401273d743eaa6213ece5eea47"
CLONIE_URL="https://github.com/qoal1201/clonie-preview/releases/download/preview-${CLONIE_VERSION}/${CLONIE_ARCHIVE_NAME}"
CLONIE_APP_DIR="$HOME/Applications"
CLONIE_ARCHIVE=""
CLONIE_WORK=""
CLONIE_STAGE=""

usage() {
  cat <<'TEXT'
Usage: bash install.sh [--app-dir /absolute/path] [--archive /path/to/downloaded.zip]

Default: ~/Applications/Clonie.app
Requires: Apple Silicon, macOS 26 or later.
The release checksum and app signature are verified. Existing apps are never
overwritten, stopped, or deleted. Installation does not launch the app or
change security settings.
TEXT
}

fail() { printf 'Clonie: %s\n' "$1" >&2; exit 1; }
while [ "$#" -gt 0 ]; do
  case "$1" in
    --app-dir|--archive)
      [ "$#" -ge 2 ] || fail "Missing value for $1"
      case "$1" in
        --app-dir) CLONIE_APP_DIR="$2" ;;
        --archive) CLONIE_ARCHIVE="$2" ;;
      esac
      shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) usage >&2; fail "Unknown argument: $1" ;;
  esac
done

case "$CLONIE_APP_DIR" in /*) ;; *) fail "--app-dir must be an absolute path" ;; esac
CLONIE_TARGET="${CLONIE_APP_DIR%/}/Clonie.app"
CLONIE_LEGACY_TARGET="${CLONIE_APP_DIR%/}/Ghostbar.app"
for CLONIE_EXISTING in "$CLONIE_TARGET" "$CLONIE_LEGACY_TARGET"; do
  if [ -e "$CLONIE_EXISTING" ] || [ -L "$CLONIE_EXISTING" ]; then
    fail "Already exists: $CLONIE_EXISTING. Existing apps are preserved; choose another --app-dir or manage the existing installation first."
  fi
done
[ "$(uname -s)" = Darwin ] || fail "This preview requires macOS."
[ "$(uname -m)" = arm64 ] || fail "This preview requires Apple Silicon."
CLONIE_OS="$(sw_vers -productVersion)"
[ "${CLONIE_OS%%.*}" -ge 26 ] || fail "This preview requires macOS 26 or later."

cleanup() {
  [ -z "$CLONIE_STAGE" ] || rm -rf "$CLONIE_STAGE"
  [ -z "$CLONIE_WORK" ] || rm -rf "$CLONIE_WORK"
}
CLONIE_WORK="$(mktemp -d "${TMPDIR:-/tmp}/clonie-install.XXXXXX")"
trap cleanup EXIT

if [ -z "$CLONIE_ARCHIVE" ]; then
  CLONIE_ARCHIVE="$CLONIE_WORK/$CLONIE_ARCHIVE_NAME"
  printf 'Downloading Clonie preview %s...\n' "$CLONIE_VERSION"
  curl --fail --location --proto '=https' --tlsv1.2 --retry 2 \
    --output "$CLONIE_ARCHIVE" "$CLONIE_URL"
fi
[ -f "$CLONIE_ARCHIVE" ] || fail "Archive not found: $CLONIE_ARCHIVE"
CLONIE_ACTUAL="$(shasum -a 256 "$CLONIE_ARCHIVE")"
[ "${CLONIE_ACTUAL%% *}" = "$CLONIE_SHA256" ] || fail "Archive SHA-256 mismatch; nothing was installed."

ditto -x -k "$CLONIE_ARCHIVE" "$CLONIE_WORK/unpacked"
CLONIE_BUNDLE="$CLONIE_WORK/unpacked/Clonie-preview-${CLONIE_VERSION}-arm64/Clonie.app"
[ -d "$CLONIE_BUNDLE" ] || fail "Expected app is missing from the archive."
CLONIE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$CLONIE_BUNDLE/Contents/Info.plist")"
[ "$CLONIE_ID" = com.local.clonie ] || fail "Unexpected app bundle identifier."
codesign --verify --deep --strict "$CLONIE_BUNDLE"

mkdir -p "$CLONIE_APP_DIR"
CLONIE_STAGE="$(mktemp -d "${CLONIE_APP_DIR%/}/.clonie-install.XXXXXX")"
ditto "$CLONIE_BUNDLE" "$CLONIE_STAGE/Clonie.app"
# -n protects an installation created after the first existence check as well.
mv -n "$CLONIE_STAGE/Clonie.app" "${CLONIE_APP_DIR%/}/"
[ ! -e "$CLONIE_STAGE/Clonie.app" ] || fail "Destination appeared during installation; existing app preserved."
printf '\nInstalled: %s\n' "$CLONIE_TARGET"
printf 'Open this app in Finder. This preview is not notarized by Apple.\n'
printf 'If macOS blocks it, review its entry in System Settings > Privacy & Security.\n'
printf 'First launch and microphone/screen recording permissions require your approval.\n'
