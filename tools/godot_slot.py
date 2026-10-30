#!/usr/bin/env python3
"""The machine-wide pool of Godot slots tools/run_tests.sh shares between runs (worktrees, the pre-commit hook).

  python3 tools/godot_slot.py run [--notice-fd=N] -- COMMAND [ARG...]   take a slot, then become COMMAND
  python3 tools/godot_slot.py free                                       print the number of free slots
  python3 tools/godot_slot.py status                                     print "<taken> <size>"

The pool has max(1, cores / 2) slots, each a lock file `slot<i>.lock` in $GAME_TEST_SLOT_DIR (default
$TMPDIR/forced-entry-godot-slots), taken with flock. `run` waits for a free one (saying so once, `waiting for a Godot
slot (<n> of <n> taken)`, on fd N, stderr by default; polls every $GAME_TEST_SLOT_POLL seconds, 0.5 by default), writes
its pid into the file and execs COMMAND on the same pid with the lock's file descriptor inherited: the slot is held by
the command itself, so it is freed when the command exits, however it ends. A process the command started that outlives
it (a Von server) keeps the lock held, but the file names the command's pid, which is dead: a lock file whose pid is
dead counts as free, and is replaced by a new file.
"""
import fcntl
import os
import sys
import time
from pathlib import Path


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


def lock_pid(fd: int):
    """The pid a lock file names, None when it names none (yet)."""
    try:
        text = os.pread(fd, 32, 0).decode().strip()
        return int(text) if text else None
    except (OSError, ValueError):
        return None


def take(path: Path):
    """The open, locked file descriptor of the slot at `path`, or None when a live process holds it. A lock held by an
    orphan of a dead pid is dropped: the file is replaced and the new one locked."""
    for _ in range(3):
        fd = os.open(path, os.O_RDWR | os.O_CREAT, 0o644)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            pid = lock_pid(fd)
            same_file = os.fstat(fd).st_ino == (path.stat().st_ino if path.exists() else None)
            os.close(fd)
            if pid is None or alive(pid) or not same_file:
                return None
            try:
                path.unlink()
            except FileNotFoundError:
                pass
            continue
        if not path.exists() or os.fstat(fd).st_ino != path.stat().st_ino:
            os.close(fd)  # the file was replaced between open and lock: it is another slot's now
            continue
        os.ftruncate(fd, 0)
        os.pwrite(fd, str(os.getpid()).encode(), 0)
        return fd
    return None


def take_any():
    directory = slot_dir()
    directory.mkdir(parents=True, exist_ok=True)
    for i in range(size()):
        fd = take(directory / f"slot{i}.lock")
        if fd is not None:
            return fd
    return None


def taken() -> int:
    """How many slots a live process holds right now."""
    directory = slot_dir()
    directory.mkdir(parents=True, exist_ok=True)
    count = 0
    for i in range(size()):
        fd = take(directory / f"slot{i}.lock")
        if fd is None:
            count += 1
        else:
            os.close(fd)
    return count


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
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
