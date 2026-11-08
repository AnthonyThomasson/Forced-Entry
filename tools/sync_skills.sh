#!/usr/bin/env bash
# Link the skills in .skillshare/skills/ into .claude/skills/ (gitignored symlinks) for this checkout. Run by
# tools/install_hooks.sh and .githooks/post-checkout; run it by hand after adding or removing a skill folder.
# Exits 1, naming where to get it, when the skillshare CLI is on neither PATH nor ~/go/bin.
set -euo pipefail
cd "$(dirname "$0")/.."
skillshare=$(command -v skillshare || true)
[[ -n "$skillshare" || ! -x "$HOME/go/bin/skillshare" ]] || skillshare="$HOME/go/bin/skillshare"
if [[ -z "$skillshare" ]]; then
  echo "skillshare not found, so .claude/skills/ was not linked: install it from https://github.com/runkids/skillshare" >&2
  exit 1
fi
"$skillshare" sync -p --quiet
