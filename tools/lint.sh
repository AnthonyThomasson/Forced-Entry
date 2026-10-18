#!/usr/bin/env bash
# Lint, headless and fast (a few seconds), in two passes; exits 1 when either fails, 0 when clean.
#   1. The GDScript analyzer: every script's warnings and errors the editor's Debugger > Errors tab would list
#      (UNUSED_VARIABLE, INTEGER_DIVISION, SHADOWED_GLOBAL_IDENTIFIER, ...), printed per file by tools/lint_report.py.
#      Like Godot, it skips a folder holding a .gdignore (artifacts/, where a coverage run keeps its copy).
#      The warning levels are the project's (Project Settings > GDScript > Warnings). Fix the code; silencing a warning
#      (@warning_ignore, a project setting) is a last resort, see the audit skill. A stale class cache (after pulling
#      new class_names) shows as a flood of "type not found" errors, and the report then says to run
#      `godot --headless --path . --import`.
#   2. The project lint rules (tools/lint_rules/rules/, one module per rule; tools/lint_rules/README.md): one section per
#      rule, listing what it found.
# tools/run_tests.sh runs it first, and the Stop hook runs it after a turn changed game code.
#   tools/lint.sh [--quiet] [--rule=a,b | --skip-rule=a,b | --list-rules] [PATH...]
#     --quiet          print nothing when clean
#     --list-rules     list the rules (name and description) and exit; no engine pass
#     --rule=a,b       run only those rules, and no engine pass
#     --skip-rule=a,b  run every rule but those (after the engine pass)
#     PATH...          scenes/x.gd, res://scenes/x.gd or a folder (scenes/ai): lint only those scripts (a folder's
#                      *.gd files, its hidden folders left out) and check only those paths
set -uo pipefail
cd "$(dirname "$0")/.."
flags=(); only=(); paths=(); rule_args=(); engine=1
for a in "$@"; do
  case "$a" in
    --list-rules) exec python3 tools/lint_rules/runner.py --list-rules ;;
    --rule=*) rule_args+=("$a"); engine=0 ;;
    --skip-rule=*) rule_args+=("$a") ;;
    --*) flags+=("$a") ;;
    *)
      p="${a#res://}"; p="${p%/}"; paths+=("$p")
      if [[ -d "$p" ]]; then
        # The engine pass loads each path it is given, so a folder becomes its scripts; the rules take the folder.
        while IFS= read -r f; do
          f="${f#./}"
          [[ "$f" != tools/lint_scripts.gd ]] && only+=("res://$f")
        done < <(find "$p" -mindepth 1 -name '.*' -prune -o -type f -name '*.gd' -print | sort)
      else
        only+=("res://$p")
      fi ;;
  esac
done
# Paths that hold no script leave the engine pass nothing to lint (an empty --only would lint every script).
[[ ${#paths[@]} -gt 0 && ${#only[@]} -eq 0 ]] && engine=0

status=0
if [[ $engine -eq 1 ]]; then
  GODOT="${GODOT:-$( command -v godot || command -v godot4 \
    || ls /Applications/Godot*.app/Contents/MacOS/Godot 2>/dev/null | head -1 )}"
  [[ -n "$GODOT" ]] || { echo "Godot binary not found (set GODOT=/path/to/Godot)" >&2; exit 2; }
  # A fresh checkout has no class cache, and without it every script that names a class_name fails to parse.
  if [[ ! -f .godot/global_script_class_cache.cfg ]]; then
    echo "importing the project (first run in this checkout)..." >&2
    "$GODOT" --headless --path . --import >/dev/null 2>&1 || true
  fi
  extra=(); [[ ${#only[@]} -gt 0 ]] && extra=(-- "--only=$(IFS=,; echo "${only[*]}")")
  out=$(mktemp -d "${TMPDIR:-/tmp}/lint.XXXXXX")
  # --debug is what makes the engine report analyzer warnings at all; stdin is closed so a script error does not
  # park the process at the debugger prompt.
  "$GODOT" --headless --debug --path . res://tools/lint_scripts.tscn ${extra[@]+"${extra[@]}"} </dev/null >"$out/lint.log" 2>&1
  report=$(GODOT="$GODOT" python3 tools/lint_report.py "$out/lint.log" ${flags[@]+"${flags[@]}"}) || status=1
  [[ -n "$report" ]] && printf '== GDScript analyzer (engine) ==\n%s\n' "$report"
fi
python3 tools/lint_rules/runner.py ${flags[@]+"${flags[@]}"} ${rule_args[@]+"${rule_args[@]}"} \
  ${paths[@]+"${paths[@]}"}
code=$?  # 2 = a usage error (an unknown rule), which wins over a plain failure
[[ $code -gt $status ]] && status=$code
exit $status
