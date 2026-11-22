#!/usr/bin/env bash
# Start the Von decision server, or check that it can start. It installs nothing: when the setup is missing or
# broken it exits fast with one cause line and the bootstrap command that fixes it. Windows has tools/von/boot.ps1,
# the same interface.
#
#   tools/von/boot.sh [--check] [--port N] [--host H] [--device D]
#     (no flag)    start `von serve --host H --port N --device D` (defaults 127.0.0.1, 8000, cpu) from <von home>, the
#                  folder Von reads checkpoints/von-1.2 from (it has no flag or variable for that). The script becomes
#                  the server (exec), so the caller stops it with a kill of this pid, and the server's output is this
#                  script's output.
#     --check      do not start: exit 0 when the setup is complete and `von --version` runs, else 3 with the cause
#   <von home> is tools/setup/lib.sh's fe_von_home (FORCED_ENTRY_HOME); the venv is <von home>/venv, the weights
#   <von home>/checkpoints/von-1.2 (tools/setup/bootstrap.sh builds both, pinned in tools/setup/versions.env).
# Exit codes: 0 --check passed (a started server exits with its own code); 2 a bad argument; 3 the setup is missing or
# broken. The cause is one line on stderr, `von: <cause>. Fix: <the bootstrap command>`, and --check says `von: ready`.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../setup/lib.sh"

CHECK=0 PORT=8000 HOST=127.0.0.1 DEVICE=cpu
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK=1 ;;
    --port) PORT="${2:-}"; shift ;;
    --host) HOST="${2:-}"; shift ;;
    --device) DEVICE="${2:-}"; shift ;;
    *) echo "von: unknown argument: $1 (tools/von/boot.sh [--check] [--port N] [--host H] [--device D])" >&2; exit 2 ;;
  esac
  shift
done
[[ "$PORT" =~ ^[0-9]+$ && -n "$HOST" && -n "$DEVICE" ]] || { echo "von: --port needs a number, --host and --device a value" >&2; exit 2; }

VON_HOME="$(fe_von_home)"
VENV="$VON_HOME/venv"
if [[ "$(fe_os)" == windows ]]; then VENV_BIN="$VENV/Scripts"; EXE=".exe"; else VENV_BIN="$VENV/bin"; EXE=""; fi
FIX="tools/setup/bootstrap.sh"
[[ "$(fe_os)" == windows ]] && FIX="powershell -ExecutionPolicy Bypass -File tools\setup\bootstrap.ps1"

broken() { echo "von: $1. Fix: $FIX" >&2; exit 3; }

[[ -d "$VENV" ]] || broken "no Von venv at $VENV"
home="$(sed -n 's/^home *= *//p' "$VENV/pyvenv.cfg" 2>/dev/null | head -n1 | tr -d '\r')"
[[ -z "$home" || -d "$(fe_posix_path "$home")" ]] || broken "the Von venv's base Python is gone (pyvenv.cfg home = $home)"
"$VENV_BIN/python$EXE" -c 'pass' >/dev/null 2>&1 || broken "the Von venv's Python does not run ($VENV_BIN/python$EXE)"
[[ -x "$VENV_BIN/von$EXE" ]] || broken "von-sdk is not installed in the Von venv ($VENV_BIN/von$EXE is missing)"
for f in config.json tokenizer.json calibration.json marker_calibration.json model.safetensors option_marker.pt; do
  [[ -s "$VON_HOME/checkpoints/von-1.2/$f" ]] || broken "the Von weights are missing ($VON_HOME/checkpoints/von-1.2/$f)"
done

if [[ $CHECK -eq 1 ]]; then
  "$VENV_BIN/von$EXE" --version >/dev/null 2>&1 || broken "'von --version' fails in the Von venv"
  echo "von: ready ($VON_HOME)"
  exit 0
fi

# The caller's PYTHONPATH (tools/setup/lib.sh's fe_use_python sets one on Windows) is not the server's business.
unset PYTHONPATH PYTHONHOME
export PYTHONUNBUFFERED=1
cd "$VON_HOME" || broken "cannot enter $VON_HOME"
exec "$VENV_BIN/von$EXE" serve --host "$HOST" --port "$PORT" --device "$DEVICE"
