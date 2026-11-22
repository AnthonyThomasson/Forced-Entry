"""Where Forced-Entry's per-user setup lives and which Godot to use: the Python side of tools/setup/lib.sh.

The same lookups as lib.sh (and tools/setup/lib.ps1), in the same order; tools/tests/test_setup_resolvers.py checks
that bash and Python agree. Import it as `from tools.setup import fe_env` (the repo root on sys.path).

  home()               the per-user root: $FORCED_ENTRY_HOME, else Windows %LOCALAPPDATA%\\Forced-Entry, macOS
                       ~/Library/Application Support/Forced-Entry, Linux ${XDG_DATA_HOME:-~/.local/share}/Forced-Entry
  von_home()           <root>/von: the venv and checkpoints/von-1.2; Von is started with it as its working directory
  godot_dir(version)   <root>/godot/<version> (default: the manifest's GODOT_VERSION)
  manifest()           tools/setup/versions.env as a dict of strings
  find_godot()         the Godot binary as a str, or None: $GODOT; godot / godot4 on PATH; the install folder above;
                       the usual per-OS places (macOS /Applications/Godot*.app, mono or not; Windows
                       %LOCALAPPDATA%\\Programs, winget, Program Files, scoop)
"""
from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path

MANIFEST = Path(__file__).resolve().parent / "versions.env"


def os_name() -> str:
    """windows, macos or linux."""
    if sys.platform == "win32":
        return "windows"
    if sys.platform == "darwin":
        return "macos"
    return "linux"


def manifest() -> dict[str, str]:
    """The KEY=value lines of versions.env (a line starting with # and a line without = are skipped)."""
    values: dict[str, str] = {}
    for line in MANIFEST.read_text(encoding="utf-8").splitlines():
        line = line.rstrip("\r")
        if line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        values[key] = value
    return values


def home() -> Path:
    if os.environ.get("FORCED_ENTRY_HOME"):
        return Path(os.environ["FORCED_ENTRY_HOME"])
    system = os_name()
    if system == "windows":
        base = os.environ.get("LOCALAPPDATA") or str(Path.home() / "AppData" / "Local")
        return Path(base) / "Forced-Entry"
    if system == "macos":
        return Path.home() / "Library" / "Application Support" / "Forced-Entry"
    return Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local" / "share") / "Forced-Entry"


def von_home() -> Path:
    return home() / "von"


def godot_dir(version: str | None = None) -> Path:
    return home() / "godot" / (version or manifest()["GODOT_VERSION"])


def _first(patterns: list[tuple[Path, str]]) -> Path | None:
    """The first file any (folder, glob) pair matches, the folders and each glob's matches taken in order."""
    for folder, pattern in patterns:
        if folder.is_dir():
            for found in sorted(folder.glob(pattern)):
                if found.is_file():
                    return found
    return None


# What a folder (or .app bundle) holding a Godot may contain, best first: a Windows _console.exe (it writes to the
# terminal a script reads), then any Godot exe; a macOS bundle's binary, in the folder or a Godot*.app in it; a Linux file.
_IN_FOLDER = ("Godot*_console.exe", "godot*_console.exe", "Godot*.exe", "godot*.exe", "Contents/MacOS/Godot",
              "Godot*.app/Contents/MacOS/Godot", "Godot", "godot")


def _godot_in(folders: list[Path]) -> str | None:
    for folder in folders:
        found = _first([(folder, pattern) for pattern in _IN_FOLDER])
        if found:
            return str(found)
    return None


def _search_folders() -> list[Path]:
    system = os_name()
    folders: list[Path] = []
    if system == "macos":
        folders += sorted(Path("/Applications").glob("Godot*.app"))
        folders += sorted((Path.home() / "Applications").glob("Godot*.app"))
    elif system == "windows":
        local = Path(os.environ.get("LOCALAPPDATA") or Path.home() / "AppData" / "Local")
        files = Path(os.environ.get("PROGRAMFILES") or "C:/Program Files")
        folders += sorted((local / "Programs").glob("Godot*"))
        folders += sorted((local / "Microsoft" / "WinGet" / "Packages").glob("GodotEngine.GodotEngine_*"))
        folders += sorted(files.parent.glob(f"{files.name}/Godot*"))
        folders += sorted(files.parent.glob(f"{files.name} (x86)/Godot*"))
        folders += [Path.home() / "scoop" / "apps" / "godot" / "current",
                    Path.home() / "scoop" / "apps" / "godot-mono" / "current"]
    else:
        folders += sorted(Path("/opt").glob("godot*"))
        folders += [Path.home() / ".local" / "bin"]
    return folders


def find_godot() -> str | None:
    if os.environ.get("GODOT"):
        return os.environ["GODOT"]
    for name in ("godot", "godot4"):
        found = shutil.which(name)
        if found:
            return found
    return _godot_in([godot_dir()] + _search_folders())


def find_bash() -> str | None:
    """The bash that runs the repo's shell scripts: `bash` on PATH; on Windows Git Bash, never WSL's launcher in System32
    (or the WindowsApps stub), which cannot run a script by its Windows path."""
    found = shutil.which("bash")
    if os_name() != "windows":
        return found
    def wsl(path: str | None) -> bool:
        return path is None or any(part in path.lower() for part in ("\system32\\", "\windowsapps\\"))
    if not wsl(found):
        return found
    candidates = []
    git = shutil.which("git")
    if git:
        root = Path(git).resolve().parent.parent  # <Git>/cmd/git.exe or <Git>/mingw64/bin/git.exe
        candidates += [root / "bin" / "bash.exe", root / "usr" / "bin" / "bash.exe",
                       root.parent / "bin" / "bash.exe", root.parent / "usr" / "bin" / "bash.exe"]
    files = Path(os.environ.get("PROGRAMFILES") or "C:/Program Files")
    candidates += [files / "Git" / "bin" / "bash.exe", files / "Git" / "usr" / "bin" / "bash.exe"]
    for candidate in candidates:
        if candidate.is_file():
            return str(candidate)
    return None
