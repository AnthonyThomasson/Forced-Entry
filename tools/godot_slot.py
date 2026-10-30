#!/usr/bin/env python3
"""The machine-wide pool of Godot slots tools/run_tests.sh shares between runs (worktrees, the pre-commit hook).

  python3 tools/godot_slot.py run [--notice-fd=N] -- COMMAND [ARG...]   take a slot, then become COMMAND
  python3 tools/godot_slot.py free                                       print the number of free slots
  python3 tools/godot_slot.py status                                     print "<taken> <size>"
  python3 tools/godot_slot.py annotate --ancestor=PID [--loaded]         filter a run's output (stdin to stdout)
  python3 tools/godot_slot.py quiet --ancestor=PID --max-load=X --timeout-min=M   wait for a quiet machine
  python3 tools/godot_slot.py stop --ancestor=PID                        end every process PID started

The pool has max(1, cores / 2) slots, each a lock file `slot<i>.lock` in $GAME_TEST_SLOT_DIR (default
$TMPDIR/forced-entry-godot-slots), taken with flock. `run` waits for a free one (saying so once, `waiting for a Godot
slot (<n> of <n> taken)`, on fd N, stderr by default; polls every $GAME_TEST_SLOT_POLL seconds, 0.5 by default), writes
its pid into the file and execs COMMAND on the same pid with the lock's file descriptor inherited: the slot is held by
the command itself, so it is freed when the command exits, however it ends. A process the command started that outlives
it (a Von server) keeps the lock held, but the file names the command's pid, which is dead: a lock file whose pid is
dead counts as free, and is replaced by a new file. Takers go one at a time (an flock on `slot-reclaim.lock` in the same
directory), so two never reclaim the same orphan; `free`, `status` and the wait notice only look (a shared lock that is let
go at once): they take no slot, write no pid and replace no file.

Every engine process tools/run_tests.sh starts holds a slot, the first-run import included; the lint's engine pass,
editors and played games take none.

The machine's state, for `--quiet` and the PERF lines of a run: the 1-minute load (`uptime`) and the number of other Godot
processes (`pgrep -i godot`: editors and played games too), those under the process PID (the run's own) left out.
`annotate` appends `(load <x>, <n> other Godot)` to every `PERF ` line it passes, `  load <x>` to every totals line and, with
--loaded, `  loaded` to every verdict line (`PASS    <id>  (<s>s sim, <ms> ms)`) and `"loaded": true` to every result of the `JSON:` line. `quiet` returns 0 once no other Godot runs and the load is under
--max-load, printing the load and the count at once and every minute ($GAME_TEST_QUIET_MINUTE seconds, 60 by default;
polled every $GAME_TEST_QUIET_POLL, 5 by default) while it waits, and 3 after --timeout-min minutes. `stop` sends SIGTERM to
every process PID started, directly or not (not itself), and SIGKILL to those still there $GAME_TEST_STOP_WAIT seconds
later (5 by default): what tools/run_tests.sh does when it is interrupted, before it cleans up.
"""
import contextlib
import fcntl
import json
import os
import re
import signal
import subprocess
import sys
import time
from pathlib import Path

# How long a lock file naming a dead pid is watched before it is called an orphan's.
RECLAIM_WAIT = 0.1
# The lock file that serialises the takers of a pool (it is not a slot).
GUARD = "slot-reclaim.lock"
VERDICT = re.compile(r"^(PASS|FAIL|TIMEOUT|SKIPPED|GAP)\s+\S+\s+\(")
TOTALS = re.compile(r"^\d+ passed, \d+ failed, \d+ timed out, \d+ skipped")


def size() -> int:
    return max(1, (os.cpu_count() or 2) // 2)


def slot_dir() -> Path:
    given = os.environ.get("GAME_TEST_SLOT_DIR")
    return Path(given) if given else Path(os.environ.get("TMPDIR", "/tmp")) / "forced-entry-godot-slots"


def alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def lock_pid(path: Path):
    """The pid the lock file at `path` names, None when it names none (yet) or the file is gone."""
    try:
        fd = os.open(path, os.O_RDONLY)
    except FileNotFoundError:
        return None
    try:
        text = os.pread(fd, 32, 0).decode().strip()
        return int(text) if text else None
    except (OSError, ValueError):
        return None
    finally:
        os.close(fd)


def is_at(fd: int, path: Path) -> bool:
    """Whether the open file `fd` is still the file at `path` (it was replaced or deleted otherwise)."""
    try:
        return os.fstat(fd).st_ino == path.stat().st_ino
    except FileNotFoundError:
        return False


def try_lock(path: Path):
    """The open file descriptor of the slot file at `path` with its lock held, None when another process holds it."""
    while True:
        fd = os.open(path, os.O_RDWR | os.O_CREAT, 0o644)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            os.close(fd)
            return None
        if is_at(fd, path):
            return fd
        os.close(fd)  # the file was replaced between the open and the lock: it is another slot's now


def orphaned(path: Path) -> bool:
    """Whether the lock held on the file at `path` is an orphan's: the file names a dead pid, for longer than the moment
    the winner of a slot holds the lock before it writes its own pid."""
    pid = lock_pid(path)
    if pid is None or alive(pid):
        return False
    time.sleep(RECLAIM_WAIT)
    return lock_pid(path) == pid


@contextlib.contextmanager
def guard(directory: Path):
    """One taker at a time judges, replaces and locks a slot file: two never both reclaim the same orphan."""
    fd = os.open(directory / GUARD, os.O_RDWR | os.O_CREAT, 0o644)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        os.close(fd)


def take(path: Path):
    """The open, locked file descriptor of the slot at `path`, or None when a live process holds it. A lock held by an
    orphan of a dead pid is dropped: the file is replaced and the new one locked."""
    with guard(path.parent):
        fd = try_lock(path)
        if fd is None and orphaned(path):
            fd = try_lock(path)  # whoever held it for a moment (a probe) may have let go meanwhile
            if fd is None:
                path.unlink(missing_ok=True)
                fd = try_lock(path)
        if fd is not None:
            os.ftruncate(fd, 0)
            os.pwrite(fd, str(os.getpid()).encode(), 0)
        return fd


def take_any():
    directory = slot_dir()
    directory.mkdir(parents=True, exist_ok=True)
    for i in range(size()):
        fd = take(directory / f"slot{i}.lock")
        if fd is not None:
            return fd
    return None


def held(path: Path) -> bool:
    """Whether a live process holds the slot at `path`. Probes with a shared lock: it takes no slot, writes no pid and
    makes no file."""
    try:
        fd = os.open(path, os.O_RDONLY)
    except FileNotFoundError:
        return False
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_SH | fcntl.LOCK_NB)
        except BlockingIOError:
            return not orphaned(path)
        return False
    finally:
        os.close(fd)


def taken() -> int:
    """How many slots a live process holds right now."""
    directory = slot_dir()
    return sum(held(directory / f"slot{i}.lock") for i in range(size()))


def one_minute_load() -> float:
    out = subprocess.run(["uptime"], capture_output=True, text=True, env=dict(os.environ, LC_ALL="C")).stdout
    m = re.search(r"load averages?: *([0-9.]+)", out)
    return float(m.group(1)) if m else 0.0


def under(pid: int) -> set:
    """The pids of the processes started, directly or not, by the process `pid`."""
    parent = {}
    for line in subprocess.run(["ps", "-A", "-o", "pid=", "-o", "ppid="], capture_output=True, text=True).stdout.splitlines():
        fields = line.split()
        if len(fields) == 2 and all(f.isdigit() for f in fields):
            parent[int(fields[0])] = int(fields[1])
    mine = set()
    for child in parent:
        node, seen = child, 0
        while node in parent and seen < 64:
            node, seen = parent[node], seen + 1
            if node == pid:
                mine.add(child)
                break
    return mine


def zombies() -> set:
    """The pids of the processes that have ended and are not yet reaped by their parent."""
    out = subprocess.run(["ps", "-A", "-o", "pid=", "-o", "stat="], capture_output=True, text=True).stdout
    return {int(f[0]) for f in (line.split() for line in out.splitlines()) if len(f) == 2 and f[0].isdigit() and f[1].startswith("Z")}


def other_godots(ancestor: int) -> int:
    """How many Godot processes run that the process `ancestor` did not start."""
    found = subprocess.run(["pgrep", "-i", "godot"], capture_output=True, text=True).stdout.split()
    pids = {int(p) for p in found if p.isdigit()} - {os.getpid()}
    return len(pids - under(ancestor))


def option(argv: list, name: str, default=None):
    for a in argv:
        if a.startswith(name + "="):
            return a.split("=", 1)[1]
    return default


def mark_loaded(report: dict) -> dict:
    for r in report.get("results", []):
        r["loaded"] = True
    return report


def annotate(argv: list) -> int:
    ancestor, loaded = int(option(argv, "--ancestor", os.getppid())), "--loaded" in argv
    for line in sys.stdin:
        line = line.rstrip("\n")
        if line.startswith("PERF "):
            line += " (load %.2f, %d other Godot)" % (one_minute_load(), other_godots(ancestor))
        elif TOTALS.match(line):
            line += "  load %.2f" % one_minute_load()
        elif loaded and VERDICT.match(line):
            line += "  loaded"
        elif loaded and line.startswith("JSON: "):
            try:
                line = "JSON: " + json.dumps(mark_loaded(json.loads(line[len("JSON: "):])), separators=(",", ":"))
            except ValueError:
                pass  # not the batch's line: passed as it is
        print(line, flush=True)
    return 0


def quiet(argv: list) -> int:
    ancestor, max_load = int(option(argv, "--ancestor", os.getppid())), float(option(argv, "--max-load", "6"))
    minutes = float(option(argv, "--timeout-min", "30"))
    minute = float(os.environ.get("GAME_TEST_QUIET_MINUTE", "60"))
    poll = float(os.environ.get("GAME_TEST_QUIET_POLL", "5"))
    started, said = time.monotonic(), None
    while True:
        load, others = one_minute_load(), other_godots(ancestor)
        if others == 0 and load < max_load:
            return 0
        now = time.monotonic()
        if now - started >= minutes * minute:
            print("quiet gate timed out after %g min (load %.2f, %d other Godot): running anyway, the results are marked loaded"
                  % (minutes, load, others), flush=True)
            return 3
        if said is None or now - said >= minute:
            said = now
            print("waiting for a quiet machine: load %.2f (under %g wanted), %d other Godot (none wanted), %.1f of %g min"
                  % (load, max_load, others, (now - started) / minute, minutes), flush=True)
        time.sleep(poll)


def stop(argv: list) -> int:
    ancestor = int(option(argv, "--ancestor", os.getppid()))
    wait = float(os.environ.get("GAME_TEST_STOP_WAIT", "5"))
    for sig, seconds in ((signal.SIGTERM, wait), (signal.SIGKILL, 2.0)):
        sent, deadline = set(), time.monotonic() + seconds
        while True:
            left = under(ancestor) - {os.getpid()} - zombies()
            if not left:
                return 0
            for pid in left - sent:
                try:
                    os.kill(pid, sig)
                except ProcessLookupError:
                    pass
            sent |= left
            if time.monotonic() >= deadline:
                break
            time.sleep(0.05)
    return 0


def run(argv: list) -> int:
    notice_fd = 2
    while argv and argv[0].startswith("--") and argv[0] != "--":
        if argv[0].startswith("--notice-fd="):
            notice_fd = int(argv[0].split("=", 1)[1])
        else:
            print(f"godot_slot.py: unknown option {argv[0]}", file=sys.stderr)
            return 2
        argv = argv[1:]
    if argv[:1] == ["--"]:
        argv = argv[1:]
    if not argv:
        print("godot_slot.py run: no command", file=sys.stderr)
        return 2
    poll = float(os.environ.get("GAME_TEST_SLOT_POLL", "0.5"))
    fd, said = take_any(), False
    while fd is None:
        if not said:
            os.write(notice_fd, f"waiting for a Godot slot ({taken()} of {size()} taken)\n".encode())
            said = True
        time.sleep(poll)
        fd = take_any()
    os.set_inheritable(fd, True)
    os.execvp(argv[0], argv)


def main(argv: list) -> int:
    if argv[:1] == ["run"]:
        return run(argv[1:])
    if argv[:1] == ["free"]:
        print(size() - taken())
        return 0
    if argv[:1] == ["status"]:
        print(taken(), size())
        return 0
    if argv[:1] == ["annotate"]:
        return annotate(argv[1:])
    if argv[:1] == ["quiet"]:
        return quiet(argv[1:])
    if argv[:1] == ["stop"]:
        return stop(argv[1:])
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
