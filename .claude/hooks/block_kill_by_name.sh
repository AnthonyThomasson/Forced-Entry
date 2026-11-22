#!/usr/bin/env bash
# Claude Code PreToolUse hook (matcher Bash|PowerShell): refuse killing processes by name (pkill, killall, taskkill
# /IM, Stop-Process -Name), so one worktree's agent never takes another's Von server down. The rules are in
# block_kill_by_name.py (exit 2 and the reason on stderr refuses the command); this shim only finds a Python for it,
# with no jq, through the shared Python lookup of tools/setup/lib.sh. Wired in .claude/settings.json (and
# .skillshare/config.yaml). Without any Python the fallback at the bottom is COARSE and may over-refuse: it refuses any
# command that so much as names one of the forms, quoted or not (a `grep pkill` too), and knows none of the finer
# rules.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)

# The Python: tools/setup/lib.sh's lookup ($PYTHON, then python3 only if it really runs, then `py -3`, then python).
# shellcheck source=../../tools/setup/lib.sh
source "$here/../../tools/setup/lib.sh"
if py=$(fe_find_python); then
  exec "$py" -I "$here/block_kill_by_name.py"
fi

input=$(cat)
if grep -qiE 'pkill|killall|taskkill.*[/-]IM|Stop-Process.*-(n|ProcessName)' <<<"$input"; then
  echo "Refused: this looks like a kill by name (pkill, killall, taskkill /IM, Stop-Process -Name), and no Python is" \
    "here to check it closely. Stop one process by its pid: \`kill <pid>\`, or \`tools/von_stop.sh <game pid>\`." >&2
  exit 2
fi
exit 0
