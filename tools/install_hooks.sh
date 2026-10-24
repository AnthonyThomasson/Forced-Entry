#!/usr/bin/env bash
# Point git at the tracked hooks in .githooks/ (the pre-commit checks: tool tests, lint, game tests; the commit-msg
# check: one Claude model in the branch's Co-Authored-By lines). Run once per clone.
set -euo pipefail
cd "$(dirname "$0")/.."
git config core.hooksPath .githooks
echo "git hooks enabled (core.hooksPath=.githooks)"
