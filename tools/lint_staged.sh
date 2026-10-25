#!/usr/bin/env bash
# Lint what the commit holds (the pre-commit hook and tools/run_tests.sh --changed --staged run it): tools/lint.sh on
# the staged scripts the lint reads (added, copied, modified or renamed, not deleted: a .gd outside addons/ and the
# coverage tool's fixtures), as they are on disk, or on the whole tree when a file that governs every script is staged
# (project.godot, a file of the gdstyle pass: gdstyle.toml, tools/gdstyle.sh, tools/lint_gdstyle.py, or of the project
# lint rules: tools/lint_rules/ but its tests). A finding in
# a script the commit does not hold (the engine pass reports one a staged script loads) is labelled
# `not in this commit: <path>` (tools/lint_label.py).
#   tools/lint_staged.sh [--quiet]
#     --quiet  passed to tools/lint.sh (nothing printed when clean), and no "lint skipped" line
# Exits as tools/lint.sh does, and 2 outside a git checkout. With no script to lint it runs nothing, says "lint skipped:
# the commit stages no script the lint reads" on stderr and exits 0.
set -uo pipefail
cd "$(dirname "$0")/.."
quiet=()
for a in "$@"; do
  case "$a" in
    --quiet) quiet=(--quiet) ;;
    *) echo "usage: tools/lint_staged.sh [--quiet]" >&2; exit 2 ;;
  esac
done
git rev-parse --git-dir >/dev/null || exit 2

governs='^(project\.godot|gdstyle\.toml|tools/gdstyle\.sh|tools/lint_gdstyle\.py'
governs+='|tools/lint_rules/(rules/)?[^/]+\.py)$'
# Paths as they are (core.quotePath off): git would quote a non-ASCII one, and no pattern would match it. Read to the
# end (no grep -q): under pipefail an early exit would fail the first grep on a long list (SIGPIPE).
lintable=$(git -c core.quotePath=false diff --cached --name-only --diff-filter=d \
  | grep -vE '^(addons/|tools/coverage/tests/fixtures/)' | grep -E "\.gd$|$governs")
paths=()
if ! grep -qE "$governs" <<<"$lintable"; then
  while IFS= read -r f; do [[ -n "$f" ]] && paths+=("$f"); done <<<"$lintable"
  if [[ ${#paths[@]} -eq 0 ]]; then
    [[ ${#quiet[@]} -eq 0 ]] && echo "lint skipped: the commit stages no script the lint reads" >&2
    exit 0
  fi
fi

out=$(tools/lint.sh ${quiet[@]+"${quiet[@]}"} ${paths[@]+"${paths[@]}"} 2>&1)
status=$?
if [[ $status -ne 0 ]]; then
  held=()
  while IFS= read -r f; do held+=("$f"); done < <(git -c core.quotePath=false diff --cached --name-only)
  out=$(python3 tools/lint_label.py ${held[@]+"${held[@]}"} <<<"$out")
fi
[[ -n "$out" ]] && echo "$out"
exit $status
