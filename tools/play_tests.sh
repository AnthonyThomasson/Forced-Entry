#!/usr/bin/env bash
# Open a game window that plays tests one after another (the test runner's queued run), for a person to watch.
#
#   tools/play_tests.sh                   the change's tests: every tests/**/*_test.gd added or modified since the
#                                         merge-base with origin/main (committed, uncommitted and untracked; not
#                                         deleted ones, helpers or sandboxes), by id
#   tools/play_tests.sh --base=REF        the same since the merge-base with REF
#   tools/play_tests.sh ID [ID...]        those test ids (e.g. general/keybinds_overrides), in the order given
#
# No tests to play: says so, exits 2 and opens nothing. The window opens maximized: the camera centres each test's
# bodies, so the points a test clicks sit well clear of the result banner at its top-left (a test whose premise needs
# the project's window size shows that size stretched over the window). The window is its own process on this
# checkout's test runner (`-- --queue=<id,id,…>`), named after the worktree directory (GAME_TICKET); a run first closes
# the test window an earlier run opened for this worktree (pid in $TMPDIR/play_tests_<worktree>.pid), never the editor
# or its game. The window owns its engine log, as a tools/run_tests.sh batch does: `--log-file <dir>/godot.log` and
# `--out=<dir>`, the dir $TMPDIR/play_tests_<worktree>/ emptied each run, so another Godot start (which rotates the
# shared user://logs/godot.log) cannot hide an error from it. It runs detached: the queued ids, its pid and that log
# (each verdict and a final `Queue done:` line) are printed and the script returns at once. The person closes the
# window.
set -euo pipefail

base="origin/main"; ids=()
for a in "$@"; do
  case "$a" in
    --base=*) base="${a#--base=}" ;;
    --*) echo "usage: tools/play_tests.sh [ID...] [--base=REF]" >&2; exit 2 ;;
    *) ids+=("$a") ;;
  esac
done
root="$(cd "$(dirname "$0")/.." && pwd)"
[[ -f "$root/project.godot" ]] || { echo "no project.godot in $root" >&2; exit 2; }
name="$(basename "$root")"
tmp="${TMPDIR:-/tmp}"; tmp="${tmp%/}"
pid_file="$tmp/play_tests_${name//[^A-Za-z0-9._-]/_}.pid"
dir="$tmp/play_tests_${name//[^A-Za-z0-9._-]/_}"

# No ids: the change's tests. `git diff <merge-base>` holds what was committed, staged and changed in the working tree
# since; untracked files are listed apart. Without renames, a moved test is its new path added.
if [[ ${#ids[@]} -eq 0 ]]; then
  if ! fork="$(git -C "$root" merge-base "$base" HEAD 2>/dev/null)"; then
    echo "no merge-base with $base (pass --base=REF, or test ids)" >&2; exit 2
  fi
  while IFS= read -r id; do
    ids+=("$id")
  done < <( { git -C "$root" -c core.quotepath=off diff --name-only --no-renames --diff-filter=AM "$fork" -- tests
              git -C "$root" -c core.quotepath=off ls-files --others --exclude-standard -- tests; } \
            | while IFS= read -r f; do
                [[ "$f" == tests/*_test.gd && -f "$root/$f" ]] || continue
                f="${f#tests/}"; echo "${f%_test.gd}"
              done | LC_ALL=C sort -u )
  if [[ ${#ids[@]} -eq 0 ]]; then
    echo "no tests added or changed since $base (merge-base ${fork:0:10}): nothing to play" >&2; exit 2
  fi
fi
queue="$(IFS=,; echo "${ids[*]}")"

GODOT="${GODOT:-$( command -v godot || command -v godot4 \
  || ls /Applications/Godot*.app/Contents/MacOS/Godot 2>/dev/null | head -1 )}"
[[ -n "$GODOT" ]] || { echo "Godot binary not found (set GODOT=/path/to/Godot)" >&2; exit 2; }

# One test window per worktree: close the one an earlier run opened, only if that pid is still our runner on this
# checkout (a pid is reused once its process is gone; the editor and the editor's game never run the runner scene).
scene="res://scenes/testing/test_runner.tscn"
if [[ -f "$pid_file" ]]; then
  old="$(cat "$pid_file")"
  if [[ "$old" =~ ^[0-9]+$ ]] \
      && ps -o command= -p "$old" 2>/dev/null | grep -qF -- "--path $root --log-file $dir/godot.log $scene -- --queue="; then
    kill "$old" 2>/dev/null || true
    for _ in {1..30}; do kill -0 "$old" 2>/dev/null || break; sleep 0.1; done
    kill -0 "$old" 2>/dev/null && kill -9 "$old" 2>/dev/null || true
    echo "closed the earlier test window (pid $old)"
  fi
  rm -f "$pid_file"
fi

# A fresh worktree has no class cache (.godot/ is untracked), and without it every test script fails to parse.
if [[ ! -f "$root/.godot/global_script_class_cache.cfg" ]]; then
  echo "importing $root (first run in this worktree)..."
  "$GODOT" --headless --path "$root" --import > /dev/null 2>&1 || true
fi

# The engine log is the runner's to watch (it follows <dir>/godot.log from --out); stdout echoes it, kept for a crash
# before the log opens.
rm -rf "$dir"
mkdir -p "$dir"
GAME_TICKET="$name" nohup "$GODOT" --maximized --path "$root" --log-file "$dir/godot.log" "$scene" -- "--queue=$queue" "--out=$dir" \
  > "$dir/stdout.log" 2>&1 < /dev/null &
pid=$!
echo "$pid" > "$pid_file"
echo "playing ${#ids[@]} test(s):"
printf '  %s\n' "${ids[@]}"
echo "test window pid $pid | log $dir/godot.log"
