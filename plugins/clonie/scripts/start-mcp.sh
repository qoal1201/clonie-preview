#!/bin/bash
# Keep the host entry point small; the init skill uses the same resolver.
set -euo pipefail
clonie_plugin_root=$(cd -- "$(dirname -- "$0")/.." && pwd)
exec /bin/bash "$clonie_plugin_root/skills/clonie-init/scripts/connection.sh" "$@"
