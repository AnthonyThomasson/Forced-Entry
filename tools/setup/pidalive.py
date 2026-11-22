"""Whether a process with a given pid is running, on macOS, Linux and Windows.

`os.kill(pid, 0)` is the POSIX probe, and on Windows it is no probe at all: any signal but Ctrl-C/Ctrl-Break makes
`os.kill` call TerminateProcess, so asking whether a pid lives would end it. On Windows the question goes to the Win32
API instead (OpenProcess, then the exit code: a process that ended stays openable while anything holds a handle to it,
and its exit code is then not STILL_ACTIVE).

  from tools.setup.pidalive import alive    # the repo root on sys.path (tools/godot_slot.py puts it there itself)

A pid of another user's process counts as running (it exists, it only will not be signalled by this user). This module
tells nothing about process trees: tools/proctree.py does.
"""
import os
import sys

WINDOWS = sys.platform in ("win32", "cygwin", "msys")
ACCESS_DENIED = 5            # OpenProcess on a process of another user or a protected one: it exists
STILL_ACTIVE = 259
QUERY_LIMITED_INFORMATION = 0x1000


def alive(pid: int) -> bool:
    """Whether the process `pid` is running (a zombie still counts on POSIX, as it does for `os.kill(pid, 0)`)."""
    if pid <= 0:
        return False
    return alive_windows(pid) if WINDOWS else alive_posix(pid)


def alive_posix(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def alive_windows(pid: int) -> bool:
    import ctypes
    from ctypes import wintypes

    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.OpenProcess.restype = wintypes.HANDLE
    kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel.GetExitCodeProcess.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD)]
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    handle = kernel.OpenProcess(QUERY_LIMITED_INFORMATION, False, pid)
    if not handle:
        return ctypes.get_last_error() == ACCESS_DENIED
    try:
        code = wintypes.DWORD()
        return not kernel.GetExitCodeProcess(handle, ctypes.byref(code)) or code.value == STILL_ACTIVE
    finally:
        kernel.CloseHandle(handle)
