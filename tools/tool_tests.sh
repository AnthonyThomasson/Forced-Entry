#!/usr/bin/env bash
# Run the tool tests (Python unittest over tools/: the lint rules, the coverage tool, the runner's and the hooks' own
# tests ...) and exit with unittest's status (2 on an unknown argument).
#   tools/tool_tests.sh            the whole discovery: python3 -m unittest discover -s tools -t .
#   tools/tool_tests.sh --staged   only the test modules the staged tools/ and .githooks/ files can break, picked
#                                  from the index by tools/tool_tests_pick.py: a staged test module runs itself, a
#                                  staged file every module whose code names it (through the tools and the tests'
#                                  helpers); a staged shared test helper, or a file no test names, runs the whole
#                                  discovery. None of those staged: nothing runs. The pre-commit hook runs this.
# The first line says what runs: `tool tests: <module>, ...`, `tool tests: all (<why>)` or `tool tests: none (...)`.
# The tests run without git's GIT_* variables: git hands a hook GIT_INDEX_FILE (and in a worktree GIT_DIR), and every
# git a test runs in a throwaway repo of its own would obey them and act on this repo instead.
set -uo pipefail
cd "$(dirname "$0")/.."

staged=0
for a in "$@"; do
  case "$a" in
    --staged) staged=1 ;;
    *) echo "unknown argument: $a (tools/tool_tests.sh [--staged])" >&2; exit 2 ;;
  esac
done

modules=()
if [[ $staged -eq 1 ]]; then
  # Paths as they are (core.quotePath off), read with git's own variables: they name the index being committed.
  paths=()
  while IFS= read -r p; do paths+=("$p"); done < <(git -c core.quotePath=false diff --cached --name-only \
    | grep -E '^(tools/|\.githooks/)')
  if [[ ${#paths[@]} -eq 0 ]]; then
    echo "tool tests: none (no tools/ or .githooks/ file staged)"
    exit 0
  fi
  picked=$(python3 tools/tool_tests_pick.py "${paths[@]}") || exit 1
  if [[ "$(head -1 <<<"$picked")" == all ]]; then
    echo "tool tests: all ($(sed -n 's/^# //p' <<<"$picked" | paste -sd ';' - | sed 's/;/; /g'))"
  else
    while IFS= read -r m; do modules+=("$m"); done <<<"$picked"
    echo "tool tests: $(paste -sd ',' - <<<"$picked" | sed 's/,/, /g')"
  fi
else
  echo "tool tests: all"
fi

while IFS= read -r var; do unset "$var"; done < <(compgen -e | grep '^GIT_')
if [[ ${#modules[@]} -gt 0 ]]; then
  python3 -m unittest "${modules[@]}"
else
  python3 -m unittest discover -s tools -t .
fi
