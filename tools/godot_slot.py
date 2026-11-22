#!/usr/bin/env python3
"""The machine-wide pool of Godot slots tools/run_tests.sh shares between runs (worktrees, the pre-commit hook).

  python3 tools/godot_slot.py run [--notice-fd=N] -- COMMAND [ARG...]   take a slot, then become COMMAND
  python3 tools/godot_slot.py free                                       print the number of free slots
  python3 tools/godot_slot.py status                                     print "<taken> <size>"
  python3 tools/godot_slot.py annotate --ancestor=PID [--loaded] [--busy-cpu=X --busy-sample=S]       filter a run's output (stdin to stdout)
  python3 tools/godot_slot.py quiet --ancestor=PID --max-load=X --timeout-min=M [--busy-cpu=X --busy-sample=S]  wait for a quiet machine
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

On Windows the lock is a byte-range lock (msvcrt) held by the `run` process itself, which cannot exec: it starts COMMAND as
its child, waits for it and exits with its status, the lock released when it exits (a handle is not inherited, so a Von
server the command leaves behind holds nothing: there are no orphaned locks there). There is no load average on Windows
(`uptime` is 0.0 in the lines and the quiet gate: only the busy-Godot count gates), and the process table (`stop`, the
busy count) comes from tools/proctree.py's Win32 snapshot.

Every engine process tools/run_tests.sh starts holds a slot, the first-run import included; the lint's engine pass,
editors and played games take none.

The machine's state, for `--quiet` and the PERF lines of a run: the 1-minute load (`uptime`) and the number of busy Godot
processes, those under the process PID (the run's own) left out. A Godot is an engine process (its executable's name starts
with godot: an editor, a test run, a played game; a godot-mcp server is a node process and is none) and busy when it burned at least
--busy-cpu percent (50 by default: an idle editor burns 16 to 23 on a Mac, a busy run 100 and more) of one core over a sample of --busy-sample seconds (2): two readings of its cpu time that far
apart, taken by `ps` ($GAME_TEST_BUSY_SAMPLE replaces the length, for tests). An idle editor is not busy. The wrapper passes both from tools/perf_quiet.conf.
`annotate` appends `(load <x>, <n> busy Godot)` to every `PERF ` line it passes (`n` a count it samples once at the start and
refreshes every 10 s in the background, never one per line; `?` and a note on stderr when `ps` cannot be read; `quiet` fails then), `  load <x>` to every totals line and, with
--loaded, `  loaded` to every verdict line (`PASS    <id>  (<s>s sim, <ms> ms)`) and `"loaded": true` to every result of the `JSON:` line. `quiet` returns 0 once no other Godot is busy and the load is under
--max-load, printing the load and the count at once and every minute ($GAME_TEST_QUIET_MINUTE seconds, 60 by default;
polled every $GAME_TEST_QUIET_POLL, 5 by default) while it waits, and 3 after --timeout-min minutes. `stop` sends SIGTERM to
every process PID started, directly or not (not itself, nor what it started), and SIGKILL to those still there
$GAME_TEST_STOP_WAIT seconds later (5 by default), and returns as soon as none is left: what tools/run_tests.sh does
when it is interrupted, before it cleans up.
"""
import contextlib
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path
from typing import Optional

ROOT = str(Path(__file__).resolve().parents[1])
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)  # `python3 -I tools/godot_slot.py` puts nothing of its own on the path
_bytecode = sys.dont_write_bytecode
sys.dont_write_bytecode = True  # a run of this tool leaves no tools/setup/__pycache__ in the checkout it is copied into
from tools.setup import fe_env, pidalive  # noqa: E402
sys.dont_write_bytecode = _bytecode

WINDOWS = sys.platform in ("win32", "cygwin", "msys")
if WINDOWS:
    import msvcrt
else:
    import fcntl

# How long a lock file naming a dead pid is watched before it is called an orphan's.
RECLAIM_WAIT = 0.1
# How long `stop` waits for the processes a SIGKILL was sent to.
KILL_WAIT = 2.0
# What counts as a busy engine when the wrapper passes no --busy-cpu / --busy-sample (tools/perf_quiet.conf's values).
BUSY_CPU = 50.0
BUSY_SAMPLE_S = 2.0
# How long the PERF annotation's busy count lives before it is sampled again (it is read, not sampled, per PERF line).
ANNOTATE_REFRESH = 10.0
# Windows: the lock is a byte-range lock (msvcrt) on this one byte, far past the pid text a slot file holds, so the pid
# stays readable by every process while the lock is held (a locked range cannot be read by another process).
LOCK_AT = 1 << 20
# What `stop` sends second: SIGKILL; Windows has none, and os.kill ends a process there whatever the signal.
SIGKILL = getattr(signal, "SIGKILL", signal.SIGTERM)
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
    return pidalive.alive(pid)


def open_flags() -> int:
    return getattr(os, "O_BINARY", 0)  # Windows: bytes as they are, no CRLF translation


def lock_try(fd: int, shared: bool = False) -> bool:
    """Take the lock of the open file `fd` at once, without waiting: whether it is held now. `shared` (a probe) is only a
    shared lock on a POSIX system; Windows has no shared byte-range lock here, and the probe takes the exclusive one."""
    if WINDOWS:
        os.lseek(fd, LOCK_AT, os.SEEK_SET)
        try:
            msvcrt.locking(fd, msvcrt.LK_NBLCK, 1)
        except OSError:
            return False
        finally:
            os.lseek(fd, 0, os.SEEK_SET)
        return True
    try:
        fcntl.flock(fd, (fcntl.LOCK_SH if shared else fcntl.LOCK_EX) | fcntl.LOCK_NB)
    except BlockingIOError:
        return False
    return True


def lock_wait(fd: int) -> None:
    """Take the exclusive lock of the open file `fd`, waiting for it."""
    if WINDOWS:
        while not lock_try(fd):
            time.sleep(0.005)
    else:
        fcntl.flock(fd, fcntl.LOCK_EX)


def unlock(fd: int) -> None:
    """Let go of a lock taken by lock_try on Windows (closing the file does it everywhere else)."""
    if WINDOWS:
        os.lseek(fd, LOCK_AT, os.SEEK_SET)
        try:
            msvcrt.locking(fd, msvcrt.LK_UNLCK, 1)
        except OSError:
            pass
        finally:
            os.lseek(fd, 0, os.SEEK_SET)


def lock_pid(path: Path):
    """The pid the lock file at `path` names, None when it names none (yet) or the file is gone."""
    try:
        fd = os.open(path, os.O_RDONLY | open_flags())
    except FileNotFoundError:
        return None
    try:
        text = os.read(fd, 32).decode().strip()
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
        fd = os.open(path, os.O_RDWR | os.O_CREAT | open_flags(), 0o644)
        if not lock_try(fd):
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
    fd = os.open(directory / GUARD, os.O_RDWR | os.O_CREAT | open_flags(), 0o644)
    try:
        lock_wait(fd)
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
                try:
                    path.unlink(missing_ok=True)
                except PermissionError:
                    return None  # Windows: a file that is open somewhere cannot be replaced, and its holder is live
                fd = try_lock(path)
        if fd is not None:
            os.ftruncate(fd, 0)
            os.lseek(fd, 0, os.SEEK_SET)
            os.write(fd, str(os.getpid()).encode())
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
        fd = os.open(path, os.O_RDONLY | open_flags())
    except FileNotFoundError:
        return False
    try:
        if not lock_try(fd, shared=True):
            return not orphaned(path)
        unlock(fd)
        return False
    finally:
        os.close(fd)


def taken() -> int:
    """How many slots a live process holds right now."""
    directory = slot_dir()
    return sum(held(directory / f"slot{i}.lock") for i in range(size()))


def find_program(name: str) -> Optional[str]:
    """The file `name` names on PATH, a script with no extension included (shutil.which finds none on Windows)."""
    if os.sep in name or "/" in name:
        return name if os.path.isfile(name) else None  # a path: as it is (a bare name is looked up on PATH only)
    for folder in os.environ.get("PATH", "").split(os.pathsep):
        for ext in ("", *os.environ.get("PATHEXT", "").split(os.pathsep)) if WINDOWS else ("",):
            candidate = os.path.join(folder, name + ext)
            if folder and os.path.isfile(candidate):
                return candidate
    return None


def command_for(program: str, args: list) -> list:
    """The command line that runs `program`: itself, or, on Windows (no shebang), through the bash that found it when it is
    a script (a fake `godot` or `uptime` of a test, a wrapper)."""
    if WINDOWS:
        with open(program, "rb") as f:
            if f.read(2) == b"#!":
                return [fe_env.find_bash() or "bash", program, *args]
    return [program, *args]


def one_minute_load() -> float:
    command = ["uptime"]
    if WINDOWS:
        # No load average there, and no uptime in Git Bash: 0.0, so the busy-Godot count alone gates. One on PATH answers.
        program = find_program("uptime")
        if program is None:
            return 0.0
        command = command_for(program, [])
    out = subprocess.run(command, capture_output=True, text=True, env=dict(os.environ, LC_ALL="C")).stdout
    m = re.search(r"load averages?: *([0-9.]+)", out)
    return float(m.group(1)) if m else 0.0


def windows_table() -> dict:
    """tools/proctree.py's Win32 process snapshot: pid -> Proc (parent pid, executable name in `cmd`). Git Bash's `ps` does
    not see Windows processes, and the process-tree code is proctree's alone."""
    bytecode = sys.dont_write_bytecode
    sys.dont_write_bytecode = True  # no tools/__pycache__ in a checkout this tool is copied into
    try:
        from tools import proctree
    finally:
        sys.dont_write_bytecode = bytecode
    return proctree.snapshot()


def processes() -> dict:
    """A snapshot of the process table: pid -> (parent pid, state). The `ps` that reads it is in it."""
    if WINDOWS:
        return {pid: (p.ppid, p.state) for pid, p in windows_table().items()}
    out = subprocess.run(["ps", "-A", "-o", "pid=", "-o", "ppid=", "-o", "stat="], capture_output=True, text=True).stdout
    table = {}
    for line in out.splitlines():
        fields = line.split()
        if len(fields) == 3 and fields[0].isdigit() and fields[1].isdigit():
            table[int(fields[0])] = (int(fields[1]), fields[2])
    return table


def under(pid: int, table: Optional[dict] = None) -> set:
    """The pids of the processes started, directly or not, by the process `pid` (in `table`, the process table by default)."""
    table = processes() if table is None else table
    mine = set()
    for child in table:
        node, seen = child, 0
        while node in table and seen < 64:
            node, seen = table[node][0], seen + 1
            if node == pid:
                mine.add(child)
                break
    return mine


def left_of(ancestor: int) -> set:
    """What `ancestor` started that still runs: its descendants but this process and what this process started (the `ps`
    that reads the table is one), and but those that have ended and are not yet reaped by their parent."""
    table = processes()
    me = os.getpid()
    ended = {pid for pid, (_, state) in table.items() if state.startswith("Z")}
    return under(ancestor, table) - under(me, table) - {me} - ended


def cpu_seconds(text: str) -> float:
    """The seconds a `ps -o time` reading names: [[dd-]hh:]mm:ss[.cc]."""
    days, _, clock = text.rpartition("-")
    seconds = 0.0
    for part in clock.split(":"):
        seconds = seconds * 60 + float(part)
    return seconds + (int(days) * 86400 if days else 0)


_KERNEL = None


def windows_kernel():
    """kernel32 with the prototypes this module calls, set up once."""
    global _KERNEL
    if _KERNEL is None:
        import ctypes
        from ctypes import wintypes

        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel.OpenProcess.restype = wintypes.HANDLE
        kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
        kernel.GetProcessTimes.argtypes = [wintypes.HANDLE] + [ctypes.POINTER(wintypes.FILETIME)] * 4
        kernel.CloseHandle.argtypes = [wintypes.HANDLE]
        _KERNEL = kernel
    return _KERNEL


def windows_cpu_seconds(pid: int) -> Optional[float]:
    """The cpu seconds (kernel plus user) a Windows process has burned so far, None when it will not tell or is gone."""
    import ctypes
    from ctypes import wintypes

    kernel = windows_kernel()
    handle = kernel.OpenProcess(0x1000, False, pid)  # PROCESS_QUERY_LIMITED_INFORMATION
    if not handle:
        return None
    try:
        times = [wintypes.FILETIME() for _ in range(4)]
        if not kernel.GetProcessTimes(handle, *[ctypes.byref(t) for t in times]):
            return None
        return sum(t.dwHighDateTime << 32 | t.dwLowDateTime for t in times[2:]) / 1e7  # kernel + user, 100 ns ticks
    finally:
        kernel.CloseHandle(handle)


def cpu_table() -> dict:
    """A snapshot of the process table: pid -> (parent pid, cpu seconds burned so far, executable name). The name is the
    process's own (`ucomm` on macOS, where `comm` is a path and a node process may retitle itself: `npm exec godot-mcp`)."""
    if WINDOWS:
        table = {}
        for pid, p in windows_table().items():
            # Only an engine's cpu time is read (the busy count looks at no other process), one handle each: a process
            # table has hundreds of rows, and opening them all is what made a read take seconds.
            cpu = windows_cpu_seconds(pid) if is_engine(p.cmd) else 0.0
            if cpu is not None:
                table[pid] = (p.ppid, cpu, p.cmd)
        if os.getpid() not in table:
            raise RuntimeError("cannot read the process table (this process is not in it)")
        return table
    name = "ucomm" if sys.platform == "darwin" else "comm"
    ran = subprocess.run(["ps", "-A", "-o", "pid=", "-o", "ppid=", "-o", "time=", "-o", name + "="], capture_output=True,
                         text=True)
    table = {}
    for line in ran.stdout.splitlines():
        fields = line.split(None, 3)
        if len(fields) == 4 and fields[0].isdigit() and fields[1].isdigit():
            try:
                table[int(fields[0])] = (int(fields[1]), cpu_seconds(fields[2]), fields[3].strip())
            except ValueError:
                pass  # a time this does not read: the process is left out
    if ran.returncode != 0 or os.getpid() not in table:
        # Not a quiet machine, an unreadable one: a count of 0 from it would clear the gate.
        raise RuntimeError("cannot read the process table (ps exited %d: %s)" % (ran.returncode, ran.stderr.strip()[:200]))
    return table


def is_engine(name: str) -> bool:
    """Whether an executable name is a Godot engine's (Godot, godot.macos.editor.arm64, Godot_v4.4-stable_...): the name
    starts with godot. A godot-mcp server is a node process, an editor and a test run alike are engines."""
    return name.lower().startswith("godot")


def other_godots(ancestor: int, busy_cpu: float = BUSY_CPU, sample_s: float = BUSY_SAMPLE_S, snapshot=cpu_table,
                 sleep=time.sleep, clock=time.monotonic) -> int:
    """How many Godot engine processes the process `ancestor` did not start are busy: they burned `busy_cpu` percent or more
    of one core over `sample_s` seconds (two readings of their cpu time that far apart; at the threshold counts, since
    Linux `ps` reads cpu time in whole seconds, so a busy engine can read exactly 50 percent over 2 s). An idle editor, a
    godot-mcp server and a process that was not there at the first reading do not count. `snapshot`, `sleep` and `clock`
    are the machine's, for a test to replace."""
    first, started = snapshot(), clock()
    sleep(sample_s)
    second, elapsed = snapshot(), max(clock() - started, 1e-6)
    mine = under(ancestor, second) | {os.getpid()}
    count = 0
    for pid, (_, cpu, name) in second.items():
        if pid in mine or pid not in first or not is_engine(name):
            continue
        if (cpu - first[pid][1]) / elapsed * 100 >= busy_cpu:
            count += 1
    return count


def busy_options(argv: list) -> tuple:
    """(busy_cpu, busy_sample_s) from `--busy-cpu=` and `--busy-sample=` (tools/perf_quiet.conf's, passed by the wrapper);
    $GAME_TEST_BUSY_SAMPLE replaces the sample's length, as the tests scale the quiet gate's minute down."""
    sample = os.environ.get("GAME_TEST_BUSY_SAMPLE") or option(argv, "--busy-sample", BUSY_SAMPLE_S)
    return float(option(argv, "--busy-cpu", BUSY_CPU)), float(sample)


class BusyWatch:
    """The busy-engine count the PERF annotation reads, refreshed in the background: the first sample starts at once, the next
    `refresh` seconds after each one ends. `read()` returns (count, None) or (None, the error) and waits only for the first
    sample (never one per PERF line: annotate sits last in the engine's output pipe and must not stall it)."""

    def __init__(self, ancestor: int, busy_cpu: float, sample_s: float, refresh: float = ANNOTATE_REFRESH, count=other_godots,
                 sleep=time.sleep):
        self.value, self.error, self.ready = None, None, threading.Event()
        threading.Thread(target=self.loop, args=(ancestor, busy_cpu, sample_s, refresh, count, sleep), daemon=True).start()

    def loop(self, ancestor, busy_cpu, sample_s, refresh, count, sleep):
        while True:
            try:
                self.value, self.error = count(ancestor, busy_cpu, sample_s), None
            except Exception as e:  # noqa: BLE001 (whatever the machine did, the annotation says it could not tell)
                self.value, self.error = None, e
            self.ready.set()
            sleep(refresh)

    def read(self) -> tuple:
        self.ready.wait()
        return self.value, self.error


def option(argv: list, name: str, default=None):
    for a in argv:
        if a.startswith(name + "="):
            return a.split("=", 1)[1]
    return default


def mark_loaded(report: dict) -> dict:
    """`report` (a batch report) with every result marked `"loaded": true`."""
    for r in report.get("results", []):
        r["loaded"] = True
    return report


def annotate(argv: list) -> int:
    ancestor, loaded = int(option(argv, "--ancestor", os.getppid())), "--loaded" in argv
    watch, warned = BusyWatch(ancestor, *busy_options(argv)), False
    for line in sys.stdin:
        line = line.rstrip("\n")
        if line.startswith("PERF "):
            busy, error = watch.read()
            if error is not None and not warned:
                warned = True
                print("godot_slot.py annotate: %s: the PERF lines say '?' busy Godot" % error, file=sys.stderr, flush=True)
            line += " (load %.2f, %s busy Godot)" % (one_minute_load(), "?" if error is not None else busy)
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
    busy_cpu, sample_s = busy_options(argv)
    minute = float(os.environ.get("GAME_TEST_QUIET_MINUTE", "60"))
    poll = float(os.environ.get("GAME_TEST_QUIET_POLL", "5"))
    started, said = time.monotonic(), None
    while True:
        load, others = one_minute_load(), other_godots(ancestor, busy_cpu, sample_s)
        if others == 0 and load < max_load:
            return 0
        now = time.monotonic()
        if now - started >= minutes * minute:
            print("quiet gate timed out after %g min (load %.2f, %d busy Godot): running anyway, the results are marked loaded"
                  % (minutes, load, others), flush=True)
            return 3
        if said is None or now - said >= minute:
            said = now
            print("waiting for a quiet machine: load %.2f (under %g wanted), %d busy Godot (none wanted), %.1f of %g min"
                  % (load, max_load, others, (now - started) / minute, minutes), flush=True)
        time.sleep(poll)


def stop(argv: list) -> int:
    """End every process the --ancestor started: SIGTERM, then SIGKILL for what is left after the waits, returning as soon
    as nothing of them is left. Best effort: the exit code is 0 whatever survived."""
    ancestor = int(option(argv, "--ancestor", os.getppid()))
    wait = float(os.environ.get("GAME_TEST_STOP_WAIT", "5"))
    for sig, seconds in ((signal.SIGTERM, wait), (SIGKILL, KILL_WAIT)):
        sent, deadline = set(), time.monotonic() + seconds
        while True:
            left = left_of(ancestor)
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
            notice = f"waiting for a Godot slot ({taken()} of {size()} taken)\n".encode()
            try:
                os.write(notice_fd, notice)
            except OSError:
                os.write(2, notice)  # Windows: Git Bash's fd 3 does not reach a native program
            said = True
        time.sleep(poll)
        fd = take_any()
    if WINDOWS:
        return run_child(argv)  # no exec: this process holds the lock while the command runs, and exits with its status
    os.set_inheritable(fd, True)
    os.execvp(argv[0], argv)


def run_child(argv: list) -> int:
    """Windows: run `argv` as a child, the slot's lock held by this process meanwhile, and return its exit status."""
    program = find_program(argv[0])
    if program is None:
        print("godot_slot.py run: %s: command not found" % argv[0], file=sys.stderr)
        return 127
    child = subprocess.Popen(command_for(program, argv[1:]))
    while True:
        try:
            return child.wait()
        except KeyboardInterrupt:
            pass  # Ctrl-C reaches the child as well, on the same console: wait for it to end


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
