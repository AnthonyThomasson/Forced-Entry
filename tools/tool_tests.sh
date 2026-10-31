#!/usr/bin/env bash
# Run the tool tests (Python unittest over tools/: the lint rules, the coverage tool, the runner's and the hooks' own
# tests ...) and exit with unittest's status (2 on an unknown argument).
#   tools/tool_tests.sh            the whole discovery: python3 -m unittest discover -s tools -t .
#   tools/tool_tests.sh --staged   only the test modules the staged files can break, picked from the index by
#                                  tools/tool_tests_pick.py: a staged test module runs itself, a staged file every
#                                  module whose code names it (through the tools and the tests' helpers); a staged
#                                  shared test helper, or a tool file no test names, runs the whole discovery. A file
#                                  no test names outside tools/ and .githooks/ runs nothing. The pre-commit hook runs
#                                  this on every commit.
#   tools/tool_tests.sh --changed[=<ref>]
#                                  the same picks for what a branch changed: the paths of `git diff <ref>...` (the
#                                  commits since the branch left <ref>, default origin/main, else main), the working
#                                  tree's tracked changes and the untracked files. An unknown <ref>, or --staged too,
#                                  exits 2. Use it for the checks while working; the whole discovery runs once at the end.
# The first line says what runs: `tool tests: <module>, ...`, `tool tests: all (<why>)` or `tool tests: none (...)`.
# The tests run without git's GIT_* variables: git hands a hook GIT_INDEX_FILE (and in a worktree GIT_DIR), and every
# git a test runs in a throwaway repo of its own would obey them and act on this repo instead.
set -uo pipefail
cd "$(dirname "$0")/.."

staged=0
changed=0
ref=""
ref_given=0
for a in "$@"; do
  case "$a" in
    --staged) staged=1 ;;
    --changed) changed=1 ;;
    --changed=*) changed=1; ref_given=1; ref="${a#--changed=}" ;;
    *) echo "unknown argument: $a (tools/tool_tests.sh [--staged | --changed[=<ref>]])" >&2; exit 2 ;;
  esac
done
if [[ $staged -eq 1 && $changed -eq 1 ]]; then
  echo "--changed and --staged cannot be combined (tools/tool_tests.sh [--staged | --changed[=<ref>]])" >&2
  exit 2
fi

modules=()
if [[ $staged -eq 1 || $changed -eq 1 ]]; then
  # Paths as they are (core.quotePath off). Both sides of a rename (--no-renames lists the old path as deleted): a test
  # may name either.
  paths=()
  if [[ $staged -eq 1 ]]; then
    kind=staged
    # Read with git's own variables: they name the index being committed.
    while IFS= read -r p; do paths+=("$p"); done < <(git -c core.quotePath=false diff --cached --name-only --no-renames)
  else
    kind=changed
    if [[ $ref_given -eq 0 ]]; then
      ref=origin/main
      git rev-parse --verify -q "$ref^{commit}" >/dev/null || ref=main
    fi
    if ! git rev-parse --verify -q "$ref^{commit}" >/dev/null; then
      echo "unknown ref: $ref (tools/tool_tests.sh --changed[=<ref>])" >&2
      exit 2
    fi
    # What the branch changed since it left <ref>, what the working tree changed since HEAD, and the untracked files.
    # Each list is read on its own: a git that fails (no merge base with <ref>) stops the run, not just its own list.
    lists=""
    for list in "diff --name-only --no-renames $ref..." "diff --name-only --no-renames HEAD" \
        "ls-files --others --exclude-standard"; do
      out=$(git -c core.quotePath=false $list) || exit 1
      lists+="$out"$'\n'
    done
    while IFS= read -r p; do [[ -n "$p" ]] && paths+=("$p"); done < <(sort -u <<<"$lists")
  fi
  picked=""
  if [[ ${#paths[@]} -gt 0 ]]; then
    picked=$(python3 tools/tool_tests_pick.py "${paths[@]}") || exit 1
  fi
  if [[ -z "$picked" ]]; then
    echo "tool tests: none (no tool test names a $kind file)"
    exit 0
  elif [[ "$(head -1 <<<"$picked")" == all ]]; then
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
