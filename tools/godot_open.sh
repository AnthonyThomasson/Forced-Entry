#!/usr/bin/env bash
# Open the Godot editor on this checkout (--editor), or play the game (no argument), on the Godot tools/setup/lib.sh
# finds (GODOT, PATH, the setup's install folder, the usual per-OS places). The Herdr buttons run it through
# tools/godot_open.cmd (godot_open.ps1 is its Windows PowerShell twin).
#   tools/godot_open.sh [--editor]
set -euo pipefail
source "$(dirname "$0")/setup/lib.sh"
fe_use_godot || exit $?
root="$(cd "$(dirname "$0")/.." && pwd)"
args=()
[[ "${1:-}" == --editor ]] && args+=(--editor)
exec "$GODOT" ${args[@]+"${args[@]}"} --path "$root"
