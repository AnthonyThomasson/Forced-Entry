#!/usr/bin/env python3
"""Run the engine pass of tools/lint.sh bounded: the engine's output goes to a log, and the engine, with everything it
started, is stopped when it has not finished in time, when it is stuck, and when this process is interrupted.

  python3 tools/lint_engine.py LOG [--timeout SECONDS] -- ENGINE-COMMAND...

The engine's exit code, 124 (as timeout(1)) when it was stopped, 2 for a bad command line; the reason it was stopped
is on stderr. SECONDS defaults to $LINT_ENGINE_TIMEOUT, else 900 (the pass takes ~14 s on a Mac).

Why: a script with a parse error puts a `--debug` Godot at its `debug>` prompt (lint.sh gives it no stdin, so a
script error cannot park it there). On Windows, Godot 4.4.1 then answers the closed stdin by breaking at the same
error again and again, a log of 561,000 lines in three minutes, and never exits; without a bound lint.sh waited for
ever and left the engine running (and its console wrapper's child, which only ending the whole tree stops).
"Stuck" is that: the same `Debugger Break, Reason: ...` STUCK_AFTER times in a row. The log keeps the first of them
(the reason) and nothing of the rest.
"""
import os
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path
from typing import List, Optional

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_slot  # noqa: E402  (find_program / command_for: a script as the engine, on Windows, runs through bash)
import proctree  # noqa: E402

TIMED_OUT = 124
DEFAULT_TIMEOUT = 900.0
STUCK_AFTER = 100
BREAK = b"Debugger Break, Reason:"
# The lines the engine prints after a break's reason line.
BANNER = (b"*Frame", b'Enter "help"', b"debug>")
# Lines of anything else allowed between two breaks of one loop (the banner is three; a stray line or two may come).
MAX_GAP = 8


def run(cmd: List[str], log: Path, timeout: float = DEFAULT_TIMEOUT, stuck_after: int = STUCK_AFTER,
        cwd: Optional[str] = None) -> int:
    """Run `cmd` with its output in `log`; its exit code, or TIMED_OUT after stopping it (the reason on stderr)."""
    stop = threading.Event()
    why: List[str] = []

    program = godot_slot.find_program(cmd[0])
    if program is None:
        print(f"lint_engine.py: {cmd[0]}: command not found", file=sys.stderr)
        return 127
    try:
        proc = subprocess.Popen(godot_slot.command_for(program, cmd[1:]), stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, cwd=cwd)
    except OSError as err:
        print(f"lint_engine.py: {cmd[0]}: {err}", file=sys.stderr)
        return 127

    def copy() -> None:
        last, repeats, gap = None, 0, 0  # gap: the lines since the last break line
        with open(log, "wb") as out:
            for line in proc.stdout:
                if line.startswith(BREAK):
                    repeats = repeats + 1 if line == last and gap <= MAX_GAP else 1
                    last, gap = line, 0
                    if repeats >= stuck_after:
                        why.append(f"it is stuck at the same debugger break ({line.decode(errors='replace').strip()})")
                        stop.set()
                        return
                else:
                    gap += 1
                    if gap > MAX_GAP:
                        last, repeats = None, 0  # the engine went on to something else
                if repeats > 1 and line.startswith((BREAK,) + BANNER):
                    continue  # a repeat of the break just logged: not written down
                out.write(line)
                out.flush()

    reader = threading.Thread(target=copy, daemon=True)
    reader.start()
    try:
        previous = signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))  # the finally below ends the engine
    except ValueError:  # not the main thread
        previous = None
    try:
        deadline = time.monotonic() + timeout
        while True:
            try:
                code = proc.wait(timeout=0.25)
                reader.join(10)
                return code
            except subprocess.TimeoutExpired:
                pass
            if stop.is_set() or time.monotonic() >= deadline:
                if not stop.is_set():
                    why.append(f"it did not finish within {timeout:g} s")
                print("lint engine stopped: " + why[0], file=sys.stderr)
                return TIMED_OUT
    finally:
        if previous is not None:
            signal.signal(signal.SIGTERM, previous)
        if proc.poll() is None:
            proctree.kill_tree(proc.pid)
            proc.wait()
        reader.join(10)
        proc.stdout.close()


def main(argv: List[str]) -> int:
    usage = "usage: lint_engine.py LOG [--timeout SECONDS] -- ENGINE-COMMAND..."
    if "--" not in argv:
        print(usage, file=sys.stderr)
        return 2
    head, cmd = argv[:argv.index("--")], argv[argv.index("--") + 1:]
    timeout = float(os.environ.get("LINT_ENGINE_TIMEOUT", DEFAULT_TIMEOUT))
    try:
        if len(head) == 3 and head[1] == "--timeout":
            timeout = float(head[2])
        elif len(head) != 1:
            raise ValueError(head)
    except ValueError:
        print(usage, file=sys.stderr)
        return 2
    if not cmd:
        print(usage, file=sys.stderr)
        return 2
    return run(cmd, Path(head[0]), timeout)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
