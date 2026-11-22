#!/usr/bin/env bash
# Open a Godot editor on a worktree, named after it, unless one is already running there.
#
#   tools/editor.sh                       editor on this checkout, named after the worktree directory
#   tools/editor.sh --autorun             also presses Play once the editor is up
#   tools/editor.sh --port=9123           command-server port (default: 9080 + hash(name) % 500, moved up to the next free one)
#   tools/editor.sh /path/worktree        a different worktree (named after its directory)
#   tools/editor.sh NAME                  override the name (any argument that is not a directory)
#
# If an editor is already open on that worktree no editor is started: its pid, port and log are
# printed instead (the port is read from the running editor's GODOT_CMD_PORT). With --autorun and no
# game running on that port, the game window is opened on its own (same name and port) instead.
# The name travels as GAME_TICKET (the editor's game child inherits it; Main shows it atop the
# setup menu). The command server listens on GODOT_CMD_PORT, so worktrees don't collide:
#   python3 tools/gcmd.py --port <printed port> 'scene().name'
# The editor runs detached; its log path and pid are printed. The game its Play starts is given an engine log of its
# own, `$TMPDIR/game_<name>.engine.log` (GAME_LOG_FILE, which addons/ticket_autorun makes the game's `--log-file`): the
# test runner in it reads only its own process's errors, never another Godot's from the shared user://logs/godot.log.
set -euo pipefail

autorun=""; port=""; ticket=""; path="$(cd "$(dirname "$0")/.." && pwd)"
for a in "$@"; do
  case "$a" in
    --autorun) autorun=1 ;;
    --port=*) port="${a#--port=}" ;;
    --*) echo "usage: tools/editor.sh [NAME] [--autorun] [--port=N] [path]" >&2; exit 2 ;;
    *) if [[ -d "$a" ]]; then path="$(cd "$a" && pwd)"; else ticket="$a"; fi ;;
  esac
done
ticket="${ticket:-$(basename "$path")}"
[[ -f "$path/project.godot" ]] || { echo "no project.godot in $path" >&2; exit 2; }

source "$(dirname "$0")/setup/lib.sh"
fe_use_godot || exit $?
fe_use_python || exit $?

safe="${ticket//[^A-Za-z0-9._-]/_}"
log="${TMPDIR:-/tmp}/editor_$safe.log"
engine_log="${TMPDIR:-/tmp}/game_$safe.engine.log"

# Windows has no pgrep, `ps eww` or lsof (Git Bash's ps shows neither a command line nor an environment): an editor this
# script started is found through the pid file it wrote ("<pid> <command port>"), and a game window through a connect to
# the port. An editor started any other way is not found there.
pid_file="${TMPDIR:-/tmp}/editor_$safe.pid"
windows=""; [[ "$(fe_os)" == windows ]] && windows=1

# Sets `running` (the pid of an editor on this worktree, "" when none) and `recorded_port` (its command port).
find_editor() {
  running=""; recorded_port=""
  if [[ -n "$windows" ]]; then
    local pid="" cport=""
    if [[ -f "$pid_file" ]]; then read -r pid cport < "$pid_file" || true; fi
    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null && ps -p "$pid" 2>/dev/null | grep -qi godot; then
      running="$pid"; recorded_port="$cport"
    fi
  else
    running=$(pgrep -f -- "--editor --path $path( |\$)" | head -1 || true)
    if [[ -n "$running" ]]; then
      recorded_port="$(ps eww -p "$running" 2>/dev/null | tr ' ' '\n' | sed -n 's/^GODOT_CMD_PORT=//p' | head -1)"
    fi
  fi
}

# Whether something listens on TCP port $1 (the game window of the editor's command port).
port_listening() {
  if [[ -n "$windows" ]]; then
    "$PYTHON" -c 'import socket, sys; socket.create_connection(("127.0.0.1", int(sys.argv[1])), 1).close()' "$1" 2>/dev/null
  else
    lsof -nP -iTCP:"$1" -sTCP:LISTEN > /dev/null 2>&1
  fi
}

# Already open on this worktree? Report it instead of starting a second editor.
find_editor
if [[ -n "$running" ]]; then
  recorded_port="${recorded_port:-default (not started by this script)}"
  echo "editor already running | pid $running | name $ticket | command port $recorded_port | log $log"
  # --autorun with no game window open (nothing listening on the editor's command port): open the game on its own, with
  # the editor's name and port, since Play cannot be pressed in an editor that is already up.
  if [[ -n "$autorun" && "$recorded_port" =~ ^[0-9]+$ ]] && ! port_listening "$recorded_port"; then
    game_log="${TMPDIR:-/tmp}/game_$safe.log"
    GAME_TICKET="$ticket" GODOT_CMD_PORT="$recorded_port" nohup "$GODOT" --path "$path" \
      --log-file "$engine_log" > "$game_log" 2>&1 &
    echo "game window opened | pid $! | command port $recorded_port | log $game_log"
  fi
  exit 0
fi

# A fresh worktree has no import cache (.godot/ is untracked); import before the editor opens.
if [[ ! -d "$path/.godot" ]]; then
  echo "importing $path (first run in this worktree)..."
  "$GODOT" --headless --path "$path" --import > /dev/null 2>&1 || true
fi

# Port: hash of the ticket (stable per ticket), moved up to the next free one so worktrees never share.
if [[ -z "$port" ]]; then
  base=$(( 9080 + $(printf '%s' "$ticket" | cksum | cut -d' ' -f1) % 500 ))
  port=$("$PYTHON" - "$base" <<'PY'
import socket, sys
p = int(sys.argv[1])
while True:
    with socket.socket() as s:
        try:
            s.bind(("127.0.0.1", p)); break
        except OSError:
            p += 1
print(p)
PY
)
fi

export GAME_TICKET="$ticket" GODOT_CMD_PORT="$port" GAME_LOG_FILE="$engine_log"
[[ -n "$autorun" ]] && export GAME_AUTORUN=1
nohup "$GODOT" --editor --path "$path" > "$log" 2>&1 &
if [[ -n "$windows" ]]; then echo "$! $port" > "$pid_file"; fi
echo "editor pid $! | name $ticket | command port $port | log $log | game engine log $engine_log"
