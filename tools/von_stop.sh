#!/usr/bin/env bash
# Stop the Von decision server (`von serve`) a game process started, and only that one: the server that descends from
# <game pid>. Another worktree's game keeps its own server answering. Use it instead of killing Von by name (a `pkill`
# would take every worktree's server, and a hook refuses it): after a hard kill the game's `_exit_tree` never ran, so
# its server is orphaned on port 8000 and every decision fails.
#   tools/von_stop.sh <game pid>
# <game pid> is the Godot process's own pid, not a wrapper's (a script that launched Godot): the stop takes the
# branch of <game pid>'s children that holds the server, so with a wrapper's pid that branch is the game itself, and
# the script refuses it (exit 1, naming the pid to pass) instead of killing the game.
# Run it BEFORE `kill <game pid>`: once the game is gone macOS re-parents its server to launchd and nothing descends
# from the pid any more (Windows keeps the parent pid, so it still finds it). On Windows the server's branch is the
# boot script's PowerShell with the Python under it; both go, so no python.exe stays listening. The game itself and
# its other children are left alone.
# Exit 0 when a server stopped; 1 when no server descends from the pid (the message says so), one would not stop or
# the branch is the game; 2 for bad usage. The tree logic is tools/proctree.py (`stop-matching`).
# <game pid> is the one `kill` takes: in Git Bash a `$!` is an MSYS pid, mapped to its Windows pid through
# /proc/<pid>/winpid and said on stderr (PROCTREE_NATIVE_PID=1: it is a Windows pid already).
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)

if [[ $# -ne 1 || ! $1 =~ ^[0-9]+$ ]]; then
  echo "usage: tools/von_stop.sh <game pid>" >&2
  exit 2
fi
pid=$1
if [[ -z "${PROCTREE_NATIVE_PID:-}" && -r /proc/$pid/winpid ]]; then
  echo "MSYS pid $pid is Windows pid $(cat "/proc/$pid/winpid")" >&2
  pid=$(cat "/proc/$pid/winpid")
fi

# TODO(#213 resolvers job): swap this lookup for the shared Python resolver lib when it lands.
# $PYTHON, then python3 only if it really runs (on Windows it can be the Microsoft Store stub), then `py -3`, then
# python.
py=()
if [[ -n "${PYTHON:-}" ]]; then
  py=("$PYTHON")
elif python3 -c 'import sys' >/dev/null 2>&1; then
  py=(python3)
elif py -3 -c 'import sys' >/dev/null 2>&1; then
  py=(py -3)
elif python -c 'import sys' >/dev/null 2>&1; then
  py=(python)
else
  echo "no Python found (set PYTHON, or install python3, py or python)" >&2
  exit 1
fi

exec "${py[@]}" -I "$here/proctree.py" stop-matching "$pid"
