#!/usr/bin/env bash
# Fixture stand-in for tools/run_tests.sh: runs the fixture's test runner headless, split over --jobs=N processes
# (each given --shard=I/N, as the real wrapper does) and passes every other argument through to it. With
# FIXTURE_ARGS_FILE set, appends its own arguments to that file (one per line, then a `--end--` line), so a test can
# see what the coverage tool asked of it.
set -uo pipefail
cd "$(dirname "$0")/.."
if [[ -n "${FIXTURE_ARGS_FILE:-}" ]]; then
  { printf '%s\n' "$@"; echo "--end--"; } >> "$FIXTURE_ARGS_FILE"
fi
GODOT="${GODOT:-$( command -v godot || command -v godot4 \
  || ls /Applications/Godot*.app/Contents/MacOS/Godot 2>/dev/null | head -1 )}"
[[ -n "$GODOT" ]] || { echo "Godot binary not found (set GODOT=/path/to/Godot)" >&2; exit 2; }
jobs=1
pass=()
for a in "$@"; do
  case "$a" in
    --jobs=*) jobs="${a#--jobs=}" ;;
    *) pass+=("$a") ;;
  esac
done
[[ "$jobs" == "auto" ]] && jobs=2
pids=()
for ((i = 0; i < jobs; i++)); do
  "$GODOT" --headless --path . --fixed-fps 60 res://scenes/testing/test_runner.tscn -- \
    ${pass[@]+"${pass[@]}"} --shard="$i/$jobs" &
  pids+=($!)
done
status=0
for pid in "${pids[@]}"; do wait "$pid" || status=1; done
exit $status
