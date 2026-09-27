#!/bin/bash
# --check is read-only. The default mode reserves stdout for the MCP transport.
set -euo pipefail
clonie_check=false
case "${1:-}" in
  --check) clonie_check=true ;;
  '') ;;
  *) printf 'Usage: connection.sh [--check]\n' >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { printf 'Usage: connection.sh [--check]\n' >&2; exit 2; }

fail() { printf 'Clonie: %s\n' "$1" >&2; exit 1; }

if [[ ${CLONIE_APP_PATH+x} ]]; then
  clonie_app="$CLONIE_APP_PATH"
  clonie_app_source=environment
else
  clonie_app=$(/usr/bin/defaults read com.local.clonie mcpAppPath 2>/dev/null) || clonie_app=''
  clonie_app_source=last_launched_app
  if [[ "$clonie_app" != /* || ! -x "$clonie_app/Contents/MacOS/clonie-mcp" ]]; then
    clonie_app_source=applications
    if [[ -x /Applications/Clonie.app/Contents/MacOS/clonie-mcp ]]; then
      clonie_app=/Applications/Clonie.app
    else
      clonie_app="$HOME/Applications/Clonie.app"
    fi
  fi
fi
[[ "$clonie_app" == /* && -x "$clonie_app/Contents/MacOS/clonie-mcp" ]] ||
  fail '앱을 찾지 못했습니다. 설치한 Clonie를 한 번 여세요. 개발 빌드는 CLONIE_APP_PATH로 지정할 수 있습니다.'

# A public older app may exist at the same path and still write Markdown immediately.
# This command exits before selecting a vault or starting the MCP transport.
clonie_write_contract=$("$clonie_app/Contents/MacOS/clonie-mcp" --write-contract </dev/null 2>/dev/null) || clonie_write_contract=''
[[ "$clonie_write_contract" == proposal-v1 ]] ||
  fail '이 앱은 현재 플러그인의 승인 방식을 지원하지 않습니다. 플러그인과 함께 배포된 Clonie 앱으로 업데이트한 뒤 다시 연결하세요.'

if [[ ${CLONIE_VAULT+x} ]]; then
  clonie_vault="$CLONIE_VAULT"
  clonie_vault_source=environment
else
  clonie_vault=$(/usr/bin/defaults read com.local.clonie vaultPath 2>/dev/null) ||
    fail '연결한 저장소가 없습니다. Clonie에서 사용할 Markdown 폴더를 선택하세요.'
  clonie_vault_source=app_selection
fi
[[ "$clonie_vault" == /* && "$clonie_vault" != / && -d "$clonie_vault" ]] ||
  fail '저장소 폴더를 찾지 못했습니다. Clonie에서 폴더를 다시 선택하세요.'
# A symlink spelling of / must not broaden the selected repository to the disk root.
clonie_vault=$(cd -- "$clonie_vault" && pwd -P)
[[ "$clonie_vault" != / ]] || fail '저장소 폴더를 찾지 못했습니다. 디스크 루트는 연결할 수 없습니다.'

if $clonie_check; then
  printf 'status=ready_to_start\napp=%q\napp_source=%s\nvault=%q\nvault_source=%s\n' \
    "$clonie_app" "$clonie_app_source" "$clonie_vault" "$clonie_vault_source"
  printf 'live_connection=unverified\n'
  printf 'write_contract=%s\n' "$clonie_write_contract"
  exit 0
fi
exec "$clonie_app/Contents/MacOS/clonie-mcp" --vault "$clonie_vault"
