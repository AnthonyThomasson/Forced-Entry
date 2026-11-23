#!/usr/bin/env bash
# Open the Godot editor on this checkout (--editor), or play the game (no argument), on the Godot tools/setup/lib.sh
# finds (GODOT, PATH, the setup's install folder, the usual per-OS places). The Herdr buttons run it through
# tools/godot_open.cmd (godot_open.ps1 is its Windows PowerShell twin). Playing a fresh clone first imports the project
# (.godot/ is untracked; without its class cache the scripts that name a class_name do not parse).
#   tools/godot_open.sh [--editor]
set -euo pipefail
source "$(dirname "$0")/setup/lib.sh"
fe_use_godot || exit $?
root="$(cd "$(dirname "$0")/.." && pwd)"
args=()
if [[ "${1:-}" == --editor ]]; then
  args+=(--editor)
elif [[ ! -f "$root/.godot/global_script_class_cache.cfg" ]]; then
  echo "importing the project (first run)..."
  "$GODOT" --headless --path "$root" --import >/dev/null 2>&1 || true
fi
exec "$GODOT" ${args[@]+"${args[@]}"} --path "$root"
