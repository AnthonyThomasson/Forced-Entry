#!/usr/bin/env python3
"""Process trees on macOS (ps) and Windows: find the descendants of a pid and stop a whole tree. Git Bash's own `ps`
does not see Windows processes, so on Windows the table comes from the Win32 API (`ctypes`: a Toolhelp32 snapshot, the
command lines of the processes asked about from NtQueryInformationProcess; no PowerShell to start, which can take many
seconds on a loaded machine) and, should that fail, from `Get-CimInstance Win32_Process` through Windows PowerShell
5.1 (`PROCTREE_CIM=1` forces it). A tree is stopped by ending each process of the table's tree
(TerminateProcess), then `taskkill /T /F /PID` for whatever still runs: taskkill's own tree walk goes through WMI,
which can take minutes on a loaded machine.

  python3 tools/proctree.py descendants PID
      one line per descendant of PID, `<pid> <ppid> <command line>`, children after their parent; none, exit 1, when
      PID has no descendant.
  python3 tools/proctree.py kill-tree PID
      stop PID and everything under it.
  python3 tools/proctree.py matching (REGEX | --project DIR) [--name REGEX]
      one line per process whose command line matches REGEX (a stand-in for `pgrep -f`, which Windows has not), `<pid>
      <ppid> <command line>`; none, exit 1, when nothing matches. This process and what it runs under never count.
      --project DIR matches the Godot started on exactly that folder (`--path DIR`, either slash, quoted or not; not
      `DIR-main`, not a subfolder, not another folder of the same name) instead of a REGEX: the finish skill's way
      to find the editors and games of one worktree. A relative `--path .` is not found.
      --name limits the search to the processes whose program matches it (case-insensitive) and is a speed-up, on
      Windows above all, where only those processes' command lines are read (the slow part). What --name is matched
      against differs: on POSIX the whole command line (`ps` gives no program name apart from it), on Windows the
      executable's name alone (`Godot_v4.4.1-stable_win64.exe`). So give a word that is in both, unanchored: `--name
      godot`, never `--name ^godot`, which on POSIX would have to start the whole command line.
      `matching --project "$PWD" --name godot`.
  python3 tools/proctree.py stop-matching PID [--match REGEX]
      stop only the branches of PID's descendants that hold a process whose command line matches REGEX (default
      VON_SERVER, a `von serve`): each branch from PID's direct child on down, so the shell or boot script that started
      the server goes with it. PID itself and its other children stay: PID must be the Godot process's own pid, not
      a wrapper's, and a branch whose own command line is Godot (GAME) is refused, not stopped. Exit 0 when something
      stopped, 1 when no descendant matches (the message says so) or one would not stop, 2 for bad usage.
      tools/von_stop.sh runs it.

Importable too (`from proctree import snapshot, descendants, kill_tree`): tools/godot_slot.py may reuse it.

A parent that is already dead still counts on Windows (a process keeps its ParentProcessId), as long as the child
started after it did, so a pid reused since is not mistaken for the parent. On macOS a dead parent re-parents its
children to launchd (pid 1): stop the server BEFORE the game, not after.
"""
import base64
import os
import re
import shutil
import signal
import subprocess
import sys
import time
from dataclasses import dataclass
from typing import Dict, List, Optional

WINDOWS = sys.platform in ("win32", "cygwin", "msys")
# A `von serve` command line: `von` and `serve` as whole words (`von serve`, `von.exe serve`, `-m von serve`).
VON_SERVER = r"(?i)(?<![A-Za-z0-9])von(?![A-Za-z0-9]).*(?<![A-Za-z0-9])serve(?![A-Za-z0-9])"
# A command line that runs Godot: the program (`Godot`, `Godot_v4.4.1-stable_win64.exe`, `godot.py` ...) is no server.
GAME = re.compile(r"(?i)(?:^|[\\/\"'])godot[^\\/\s\"']*(?=[\s\"']|$)")
# Seconds a stopped process gets to go (POSIX: SIGTERM first, SIGKILL after) before the stop is reported as failed.
GRACE = 5.0

WIN_TABLE = (
    "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8\n"
    "Get-CimInstance Win32_Process | ForEach-Object {\n"
    "  $t = 0; if ($_.CreationDate) { $t = $_.CreationDate.ToFileTimeUtc() }\n"
    "  $c = ''; if ($_.CommandLine) { $c = $_.CommandLine -replace '[\\r\\n]+', ' ' }\n"
    "  '{0}|{1}|{2}|{3}' -f $_.ProcessId, $_.ParentProcessId, $t, $c\n"
    "}\n"
)
WIN_LINE = re.compile(r"^(\d+)\|(\d+)\|(\d+)\|(.*)$")
POSIX_LINE = re.compile(r"^\s*(\d+)\s+(\d+)\s+(\S+)\s+(.*)$")


@dataclass(frozen=True)
class Proc:
    pid: int
    ppid: int
    cmd: str
    started: int = 0  # Windows only: creation time in ticks, 0 when unknown.
    state: str = ""  # POSIX only: ps's state letters; a zombie (`Z`) is dead for our purposes.


def powershell() -> str:
    return shutil.which("powershell.exe") or r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"


class Win32:
    """The few Win32 calls the process table needs, bound once."""

    def __init__(self):
        import ctypes
        from ctypes import wintypes

        self.ctypes, self.wintypes = ctypes, wintypes

        class Entry(ctypes.Structure):
            _fields_ = [("dwSize", wintypes.DWORD), ("cntUsage", wintypes.DWORD), ("th32ProcessID", wintypes.DWORD),
                        ("th32DefaultHeapID", ctypes.c_size_t), ("th32ModuleID", wintypes.DWORD),
                        ("cntThreads", wintypes.DWORD), ("th32ParentProcessID", wintypes.DWORD),
                        ("pcPriClassBase", ctypes.c_long), ("dwFlags", wintypes.DWORD),
                        ("szExeFile", ctypes.c_wchar * 260)]

        self.Entry = Entry
        self.kernel, self.ntdll = ctypes.WinDLL("kernel32", use_last_error=True), ctypes.WinDLL("ntdll")
        k = self.kernel
        k.CreateToolhelp32Snapshot.restype = wintypes.HANDLE
        k.CreateToolhelp32Snapshot.argtypes = [wintypes.DWORD, wintypes.DWORD]
        k.OpenProcess.restype = wintypes.HANDLE
        k.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
        k.CloseHandle.argtypes = [wintypes.HANDLE]
        k.Process32FirstW.argtypes = k.Process32NextW.argtypes = [wintypes.HANDLE, ctypes.POINTER(Entry)]
        k.GetProcessTimes.argtypes = [wintypes.HANDLE] + [ctypes.POINTER(wintypes.FILETIME)] * 4
        k.TerminateProcess.argtypes = [wintypes.HANDLE, wintypes.UINT]
        k.GetExitCodeProcess.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD)]
        self.ntdll.NtQueryInformationProcess.argtypes = [wintypes.HANDLE, ctypes.c_ulong, ctypes.c_void_p,
                                                         ctypes.c_ulong, ctypes.POINTER(ctypes.c_ulong)]

    def table(self) -> Dict[int, Proc]:
        """Every process by pid, with its parent pid and its executable's name: one Toolhelp32 snapshot."""
        ctypes = self.ctypes
        snap = self.kernel.CreateToolhelp32Snapshot(2, 0)  # TH32CS_SNAPPROCESS
        if snap in (None, self.wintypes.HANDLE(-1).value):
            raise RuntimeError("cannot list processes: CreateToolhelp32Snapshot failed")
        procs: Dict[int, Proc] = {}
        try:
            entry = self.Entry()
            entry.dwSize = ctypes.sizeof(self.Entry)
            more = self.kernel.Process32FirstW(snap, ctypes.byref(entry))
            while more:
                procs[entry.th32ProcessID] = Proc(entry.th32ProcessID, entry.th32ParentProcessID, entry.szExeFile)
                more = self.kernel.Process32NextW(snap, ctypes.byref(entry))
        finally:
            self.kernel.CloseHandle(snap)
        return procs

    def details(self, pid: int):
        """(creation time in 100 ns ticks, command line) of `pid`, (0, "") when it will not tell: the command line
        comes from NtQueryInformationProcess(ProcessCommandLineInformation), which a process of another user or a
        protected one refuses."""
        ctypes, wintypes = self.ctypes, self.wintypes
        handle = self.kernel.OpenProcess(0x1000, False, pid)  # PROCESS_QUERY_LIMITED_INFORMATION
        if not handle:
            return 0, ""
        try:
            created, other = wintypes.FILETIME(), [wintypes.FILETIME() for _ in range(3)]
            ok = self.kernel.GetProcessTimes(handle, ctypes.byref(created), *[ctypes.byref(t) for t in other])
            ticks = (created.dwHighDateTime << 32 | created.dwLowDateTime) if ok else 0
            size = ctypes.c_ulong(0)
            self.ntdll.NtQueryInformationProcess(handle, 60, None, 0, ctypes.byref(size))
            buf = ctypes.create_string_buffer(max(size.value, 16) + 2)
            if self.ntdll.NtQueryInformationProcess(handle, 60, buf, size.value, ctypes.byref(size)) != 0:
                return ticks, ""
            length = int.from_bytes(buf.raw[0:2], "little")  # UNICODE_STRING: Length, MaximumLength, [pad], Buffer
            offset = ctypes.sizeof(ctypes.c_void_p) * 2
            return ticks, buf.raw[offset:offset + length].decode("utf-16-le", "replace")
        finally:
            self.kernel.CloseHandle(handle)

    def running(self, pid: int) -> bool:
        """Whether `pid` still runs: a terminated process stays in the table while anything holds a handle to it (the
        game that started it), so its exit code, not its listing, says it is gone."""
        handle = self.kernel.OpenProcess(0x1000, False, pid)  # PROCESS_QUERY_LIMITED_INFORMATION
        if not handle:
            return False
        try:
            code = self.wintypes.DWORD()
            return not self.kernel.GetExitCodeProcess(handle, self.ctypes.byref(code)) or code.value == 259
        finally:
            self.kernel.CloseHandle(handle)

    def terminate(self, pids: List[int]) -> None:
        """End each process of `pids` at once (TerminateProcess); one that is gone or will not let us is skipped."""
        for pid in pids:
            handle = self.kernel.OpenProcess(0x0001, False, pid)  # PROCESS_TERMINATE
            if handle:
                self.kernel.TerminateProcess(handle, 1)
                self.kernel.CloseHandle(handle)


WIN32: Optional[Win32] = None


def win32() -> Win32:
    global WIN32
    if WIN32 is None:
        WIN32 = Win32()
    return WIN32


def describe(procs: Dict[int, Proc], pids: List[int]) -> None:
    """Fill in the command line and start time of `pids` in `procs` where the table has only names (the Windows
    Toolhelp table: reading each process's command line is the slow part, so only the ones asked about are read)."""
    if not WINDOWS or os.environ.get("PROCTREE_CIM"):
        return
    for pid in pids:
        proc = procs.get(pid)
        if proc and not proc.started and pid:
            ticks, cmd = win32().details(pid)
            procs[pid] = Proc(pid, proc.ppid, cmd or proc.cmd, ticks, proc.state)


def snapshot_cim() -> Dict[int, Proc]:
    """The Windows process table from `Get-CimInstance Win32_Process`, through Windows PowerShell 5.1."""
    encoded = base64.b64encode(WIN_TABLE.encode("utf-16-le")).decode("ascii")
    run = subprocess.run([powershell(), "-NoProfile", "-NonInteractive", "-EncodedCommand", encoded],
                         capture_output=True, timeout=300, stdin=subprocess.DEVNULL)
    if run.returncode != 0:
        raise RuntimeError("cannot list processes: " + run.stderr.decode("utf-8", "replace").strip())
    procs: Dict[int, Proc] = {}
    for line in run.stdout.decode("utf-8", "replace").splitlines():
        m = WIN_LINE.match(line.rstrip("\r"))
        if m:
            procs[int(m[1])] = Proc(int(m[1]), int(m[2]), m[4], int(m[3]))
    return procs


def snapshot_ps() -> Dict[int, Proc]:
    """The macOS (or Linux) process table from `ps`."""
    run = subprocess.run(["ps", "-axo", "pid=,ppid=,stat=,command="], capture_output=True, timeout=30)
    if run.returncode != 0:
        raise RuntimeError("cannot list processes: " + run.stderr.decode("utf-8", "replace").strip())
    procs: Dict[int, Proc] = {}
    for line in run.stdout.decode("utf-8", "replace").splitlines():
        m = POSIX_LINE.match(line)
        if m:
            procs[int(m[1])] = Proc(int(m[1]), int(m[2]), m[4], state=m[3])
    return procs


def snapshot() -> Dict[int, Proc]:
    """Every process running now, by pid. On Windows a process has only its executable's name until `describe` (which
    `children` and `descendants` call for the processes they look at) reads its command line."""
    if not WINDOWS:
        return snapshot_ps()
    if os.environ.get("PROCTREE_CIM"):
        return snapshot_cim()
    try:
        return win32().table()
    except (OSError, RuntimeError, AttributeError):
        return snapshot_cim()


def is_child(child: Proc, parent_pid: int, procs: Dict[int, Proc]) -> bool:
    """Whether `child` hangs under `parent_pid`: its ppid names it, and, when the parent still runs and both start
    times are known, the child did not start before it (a reused pid is no parent)."""
    if child.ppid != parent_pid or child.pid == parent_pid:
        return False
    parent = procs.get(parent_pid)
    return not (parent and parent.started and child.started and child.started < parent.started)


def children(procs: Dict[int, Proc], pid: int) -> List[Proc]:
    named = sorted(p.pid for p in procs.values() if p.ppid == pid and p.pid != pid)
    describe(procs, [pid] + named)
    return [procs[p] for p in named if is_child(procs[p], pid, procs)]


def descendants(procs: Dict[int, Proc], pid: int) -> List[Proc]:
    """Everything under `pid`, not `pid` itself, each process before its own children."""
    found: List[Proc] = []
    seen = {pid}
    queue = children(procs, pid)
    while queue:
        proc = queue.pop(0)
        if proc.pid in seen:
            continue
        seen.add(proc.pid)
        found.append(proc)
        queue.extend(children(procs, proc.pid))
    return found


def ancestors(procs: Dict[int, Proc], pid: int) -> List[int]:
    """`pid` and the pids above it, nearest first."""
    chain: List[int] = []
    while pid in procs and pid not in chain and pid > 1:
        chain.append(pid)
        pid = procs[pid].ppid
    return chain


def alive(procs: Dict[int, Proc], pid: int) -> bool:
    proc = procs.get(pid)
    return proc is not None and not proc.state.startswith("Z")


def gone(tree: List[int]) -> bool:
    """Whether none of the pids `tree` is running now."""
    now = snapshot()
    return not any(alive(now, p) and still_running(p) for p in tree)


def still_running(pid: int) -> bool:
    """The Windows second opinion on a pid the table lists (see `Win32.running`); True wherever it cannot be asked."""
    if not WINDOWS or os.environ.get("PROCTREE_CIM"):
        return True
    try:
        return win32().running(pid)
    except (OSError, AttributeError):
        return True


def kill_tree(pid: int, procs: Optional[Dict[int, Proc]] = None) -> bool:
    """Stop `pid` and everything under it; whether all of it is gone."""
    procs = procs if procs is not None else snapshot()
    tree = [pid] + [p.pid for p in descendants(procs, pid)]
    taskkill_pending = WINDOWS  # taskkill /T /F is Windows's second try, for what TerminateProcess did not end.
    if WINDOWS:
        try:
            win32().terminate(tree)
        except (OSError, AttributeError):
            pass
        deadline = time.monotonic() + GRACE
    else:
        deadline = time.monotonic() + GRACE
        send(tree, signal.SIGTERM)
        while time.monotonic() < deadline and not gone(tree):
            time.sleep(0.1)
        now = snapshot()
        send([p for p in tree if alive(now, p)], signal.SIGKILL)
        deadline = time.monotonic() + GRACE
    while not gone(tree):
        if time.monotonic() > deadline:
            return gone(tree)  # a last look: on a loaded machine one snapshot can outlast the grace
        if taskkill_pending:
            taskkill_pending = False
            try:
                subprocess.run(["taskkill", "/T", "/F", "/PID", str(pid)], capture_output=True, timeout=300,
                               stdin=subprocess.DEVNULL)
            except (subprocess.TimeoutExpired, OSError):
                pass  # the loop's own checks say whether it is gone
        time.sleep(0.1)
    return True


def send(pids: List[int], sig: int) -> None:
    for pid in pids:
        try:
            os.kill(pid, sig)
        except OSError:
            pass


def branch_roots(procs: Dict[int, Proc], game: int, pattern: str) -> List[Proc]:
    """The direct children of `game` whose branch holds a process matching `pattern` (the process running this code,
    and what it runs under, never count)."""
    regex = re.compile(pattern)
    mine = set(ancestors(procs, os.getpid()))
    roots: Dict[int, Proc] = {}
    for proc in descendants(procs, game):
        if proc.pid in mine or not regex.search(proc.cmd):
            continue
        chain = ancestors(procs, proc.pid)
        top = [p for p in chain if is_child(procs[p], game, procs)]
        if top and top[0] not in mine:
            roots[top[0]] = procs[top[0]]
    return sorted(roots.values(), key=lambda p: p.pid)


def stop_matching(game: int, pattern: str) -> int:
    procs = snapshot()
    roots = branch_roots(procs, game, pattern)
    if not roots:
        print(f"no process matching /{pattern}/ descends from pid {game}: nothing stopped. (Run this before the game "
              "is killed: a killed game's children are re-parented on macOS and no longer descend from it.)",
              file=sys.stderr)
        return 1
    failed = 0
    for root in roots:
        if GAME.search(root.cmd):
            failed += 1
            print(f"refusing to stop pid {root.pid}, which is the game itself ({root.cmd[:120]}): pid {game} is a "
                  f"wrapper around it. Pass the Godot process's own pid ({root.pid}), not a wrapper's.",
                  file=sys.stderr)
            continue
        count = len(descendants(procs, root.pid)) + 1
        if kill_tree(root.pid, procs):
            print(f"stopped pid {root.pid} and {count - 1} below it: {root.cmd[:120]}")
        else:
            failed += 1
            print(f"could not stop pid {root.pid}: {root.cmd[:120]}", file=sys.stderr)
    return 1 if failed else 0


def matching(procs: Dict[int, Proc], pattern: str, name: Optional[str] = None) -> List[Proc]:
    """The processes whose command line matches `pattern`, by pid, but this process and those it runs under. `name`
    (a regex over the program) narrows the table before any command line is read."""
    regex = re.compile(pattern)
    named = re.compile(name, re.IGNORECASE) if name else None
    mine = set(ancestors(procs, os.getpid()))
    wanted = [p for p, proc in procs.items() if p > 1 and p not in mine and (not named or named.search(proc.cmd))]
    describe(procs, wanted)
    return sorted((procs[p] for p in wanted if regex.search(procs[p].cmd)), key=lambda proc: proc.pid)


def project_pattern(directory: str) -> str:
    """A regex for the command line of a Godot started on the project folder `directory`: `--path <directory>`, the
    folder given with `/` or `\\` (the same folder either way), with or without a closing slash or quotes, and nothing
    more of a path after it (so `<directory>-main`, another folder of the same name and a subfolder do not match). Case
    is ignored on Windows. A relative `--path .` cannot be told from any other and never matches."""
    full = os.path.abspath(directory)
    parts = [re.escape(part) for part in re.split(r"[\\/]+", full) if part]
    lead = "" if WINDOWS else r"[\\/]"  # a POSIX path starts at the root; a Windows one with its drive letter
    body = lead + r"[\\/]+".join(parts)
    return ("(?i)" if WINDOWS else "") + r"(?:^|\s)--path\s+[\"']?" + body + r"[\\/]*[\"']?(?:\s|$)"


def matching_args(rest: List[str]) -> Optional[tuple]:
    """`(regex, name)` from the words after `matching`: `REGEX` or `--project DIR`, then optionally `--name REGEX`; None
    when they are neither."""
    name = None
    if len(rest) >= 2 and rest[-2] == "--name":
        rest, name = rest[:-2], rest[-1]
    if len(rest) == 1 and rest[0] != "--project":
        return rest[0], name
    if len(rest) == 2 and rest[0] == "--project":
        return project_pattern(rest[1]), name
    return None


def parse_pid(text: str) -> int:
    if not text.isdigit() or int(text) < 2:
        raise ValueError(f"not a pid: {text!r}")
    return int(text)


def main(argv: List[str]) -> int:
    usage = ("usage: proctree.py descendants PID | kill-tree PID | stop-matching PID [--match REGEX]"
             " | matching (REGEX | --project DIR) [--name REGEX]")
    try:
        wanted = matching_args(argv[1:]) if argv[:1] == ["matching"] else None
        if wanted:
            found = matching(snapshot(), *wanted)
            for p in found:
                print(p.pid, p.ppid, p.cmd)
            return 0 if found else 1
        if len(argv) == 2 and argv[0] == "descendants":
            found = descendants(snapshot(), parse_pid(argv[1]))
            for p in found:
                print(p.pid, p.ppid, p.cmd)
            return 0 if found else 1
        if len(argv) == 2 and argv[0] == "kill-tree":
            pid = parse_pid(argv[1])
            if pid in ancestors(snapshot(), os.getpid()):
                print("refusing to stop the tree this command runs in", file=sys.stderr)
                return 1
            return 0 if kill_tree(pid) else 1
        if argv[:1] == ["stop-matching"] and (len(argv) == 2 or (len(argv) == 4 and argv[2] == "--match")):
            return stop_matching(parse_pid(argv[1]), argv[3] if len(argv) == 4 else VON_SERVER)
    except ValueError as err:
        print(f"{err}\n{usage}", file=sys.stderr)
        return 2
    print(usage, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
