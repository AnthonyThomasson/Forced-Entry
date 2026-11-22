#!/usr/bin/env bash
# Claude Code PreToolUse hook (matcher Bash|PowerShell): refuse killing processes by name (pkill, killall, taskkill /IM,
# Stop-Process -Name), so one worktree's agent never takes another's Von server down. The rules are in
# block_kill_by_name.py (exit 2 and the reason on stderr refuses the command); this shim only finds a Python for it, with
# no jq: $PYTHON, then python3 only if it really runs (on Windows it can be the Microsoft Store stub), then `py -3`, then
# python. Wired in .claude/settings.json (and .skillshare/config.yaml). Without any Python it still refuses a command
# that so much as names one of the forms.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)

# TODO(#213 resolvers job): swap this lookup for the shared Python resolver lib when it lands.
if [[ -n "${PYTHON:-}" ]]; then
  exec "$PYTHON" -I "$here/block_kill_by_name.py"
elif python3 -c 'import sys' >/dev/null 2>&1; then
  exec python3 -I "$here/block_kill_by_name.py"
elif py -3 -c 'import sys' >/dev/null 2>&1; then
  exec py -3 -I "$here/block_kill_by_name.py"
elif python -c 'import sys' >/dev/null 2>&1; then
  exec python -I "$here/block_kill_by_name.py"
fi

input=$(cat)
if grep -qiE 'pkill|killall|taskkill.*[/-]IM|Stop-Process.*-(n|ProcessName)' <<<"$input"; then
  echo "Refused: this looks like a kill by name (pkill, killall, taskkill /IM, Stop-Process -Name), and no Python is" \
    "here to check it closely. Stop one process by its pid: \`kill <pid>\`, or \`tools/von_stop.sh <game pid>\`." >&2
  exit 2
fi
exit 0
