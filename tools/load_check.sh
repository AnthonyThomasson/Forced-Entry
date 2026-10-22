#!/usr/bin/env bash
# Headless start-up check: load the project's main scene and autoloads, run a few frames, quit. Exits 1 on ANY
# engine error or warning in the log (parse errors, failed loads, runtime script errors, shutdown errors),
# printing them; 0 when clean. Engine end-of-process leak lines are a NOTE unless --strict-exit.
# --import first imports the project with the same Godot (writes each new script's .uid and the class cache; headless
# runs never import), failing before the check when the import does; its progress_dialog noise is not a failure.
#   tools/load_check.sh [--import] [--strict-exit] [--windowed]
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$( command -v godot || command -v godot4 \
  || ls /Applications/Godot*.app/Contents/MacOS/Godot 2>/dev/null | head -1 )}"
[[ -n "$GODOT" ]] && command -v "$GODOT" >/dev/null \
  || { echo "Godot binary not found (set GODOT=/path/to/Godot)" >&2; exit 2; }
HEADLESS=--headless; STRICT=; IMPORT=
for a in "$@"; do
  case "$a" in
    --windowed) HEADLESS= ;;
    --strict-exit) STRICT=--strict-exit ;;
    --import) IMPORT=1 ;;
  esac
done
out=$(mktemp -d "${TMPDIR:-/tmp}/load_check.XXXXXX")
if [[ -n "$IMPORT" ]]; then
  if ! "$GODOT" --headless --path . --import >"$out/import.txt" 2>&1; then
    tail -20 "$out/import.txt"
    echo "FAIL: import failed ($GODOT --headless --path . --import; log: $out/import.txt)"
    exit 1
  fi
  echo "Imported (log: $out/import.txt)"
fi
"$GODOT" $HEADLESS --path . --quit-after 30 --log-file "$out/godot.log" >"$out/stdout.txt" 2>&1
code=$?
python3 tools/scan_godot_log.py "$out/godot.log" $STRICT || code=1
[[ $code -eq 0 ]] && echo "PASS: project loads and runs with no errors or warnings" || echo "FAIL (log: $out/godot.log)"
exit $code
