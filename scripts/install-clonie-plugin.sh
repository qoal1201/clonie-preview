#!/bin/bash
# Explicit host installation, invoked from the README or by the user's AI.
set -euo pipefail
case "${1:-}" in
  codex|claude) clonie_host="$1" ;;
  *) printf 'Usage: /bin/bash install.sh codex|claude\n' >&2; exit 2 ;;
esac
[[ $# -eq 1 ]] || { printf 'Choose one AI host per invocation.\n' >&2; exit 2; }
clonie_marketplace=$(cd -- "$(dirname -- "$0")" && pwd -P)
# In the development checkout this script lives one directory below the marketplace.
if [[ ! -f "$clonie_marketplace/.agents/plugins/marketplace.json" ]]; then
  clonie_marketplace=$(cd -- "$clonie_marketplace/.." && pwd -P)
fi
[[ -f "$clonie_marketplace/.agents/plugins/marketplace.json" &&
   -f "$clonie_marketplace/.claude-plugin/marketplace.json" &&
   -f "$clonie_marketplace/plugins/clonie/.codex-plugin/plugin.json" ]] || {
  printf 'Clonie plugin package is incomplete.\n' >&2; exit 1;
}
clonie_cli=$(command -v "$clonie_host" 2>/dev/null || true)
if [[ -z "$clonie_cli" && "$clonie_host" == codex ]]; then
  # A desktop-only user need not install a second CLI or change their shell PATH.
  # Support the current desktop bundle and its earlier Codex app layout.
  for clonie_apps in /Applications "$HOME/Applications"; do
    for clonie_name in ChatGPT Codex; do
      for clonie_relative in codex-cli/bin/codex codex; do
        clonie_candidate="$clonie_apps/$clonie_name.app/Contents/Resources/$clonie_relative"
        if [[ -x "$clonie_candidate" ]]; then
          clonie_cli="$clonie_candidate"
          break 3
        fi
      done
    done
  done
fi
[[ -n "$clonie_cli" ]] || {
  if [[ "$clonie_host" == codex ]]; then
    printf 'Codex CLI or its desktop app was not found. Install the desktop app in Applications, or add the Codex CLI to PATH.\n' >&2
  else
    printf '%s CLI is not installed or not on PATH.\n' "$clonie_host" >&2
  fi
  exit 1
}
"$clonie_cli" plugin marketplace add "$clonie_marketplace"
if [[ "$clonie_host" == codex ]]; then
  "$clonie_cli" plugin add clonie@clonie
else
  "$clonie_cli" plugin install clonie@clonie
fi
printf 'Clonie plugin installation finished. Verify vault_list.vaultPath in the AI host before using documents.\n'
