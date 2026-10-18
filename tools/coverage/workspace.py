"""The throwaway copy of the repo the coverage tool instruments, the folder a run's hit shards go to, the tree hashes
that prove the real tree untouched, and cleanup.

Both folders are made directly in the repo's gitignored `artifacts/tmp/` (artifacts/.gdignore is written first, so
Godot never imports them), named `<prefix><owner pid>.<random>`: the pid of the process that made them, so a later
run can tell a folder whose run is gone from one whose run is still going.

  create(root) -> Path      a fresh `artifacts/tmp/fe-coverage-copy.<pid>.<random>/` holding the tracked files, the
                            untracked files git does not ignore, and `.godot/` (the import cache); nothing else (no
                            ignored file, no .git, nothing under artifacts/ even where git does not ignore it)
  hits_dir(root) -> Path    a fresh, empty `artifacts/tmp/fe-coverage-hits.<pid>.<random>/` for a run's shards
  copy_env(copy, env=None) -> dict
                            the environment of a process run in a copy: `env` (default this process's) without git's
                            GIT_* variables and with GIT_CEILING_DIRECTORIES at the copy's parent, so git in the copy
                            finds no repo, as in a copy outside any repo, never the one the copy sits in
  tree_hash(root) -> str    sha256 over the paths and bytes of everything under scenes/ and project.godot
  git_status(root) -> str   `git status --porcelain --untracked-files=all` of `root` ("" when clean)
  user_dir_name(copy) / user_dir(copy)
                            the copy's own Godot user:// folder (instrument.py names it in the copy's project.godot),
                            so a run never writes the developer's user://settings.json or Von log
  keep(folder)              marks a copy or hit folder kept (`coverage.py instrument`, `run --keep`): no sweep
                            removes it; it is deleted by hand
  cleanup(root, folder)     removes a copy or hit folder of `root`, a copy's user:// folder with it, and
                            artifacts/tmp/ once that is empty; refuses (raises ValueError, deletes nothing) anything
                            that is not a direct child of `root`'s artifacts/tmp/ named as this module names them,
                            or that is a symlink

`create` and `hits_dir` first sweep `root`'s artifacts/tmp/: they remove the folders whose owner process is gone (a
run killed with SIGKILL cannot clean up), never one whose owner is alive, in this process or another, and never a
kept one. The sweep never follows a symlink: one named as this module names its folders, its owner gone, is removed
alone, never what it points to. `create` also removes the user:// folders whose copy is gone (each records its copy's path), such as that
of a kept copy deleted by hand.
"""
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

TMP = Path("artifacts") / "tmp"
PREFIX = "fe-coverage-copy."
HITS_PREFIX = "fe-coverage-hits."
KEPT = ".fe-coverage-kept"           # in a kept folder
COPY_RECORD = ".fe-coverage-copy"    # in a copy's user:// folder: the copy's path
USER_DIRS = "fe-coverage"
HASHED = ("scenes", "project.godot")


def create(root) -> Path:
    """Copy the repo at `root` into a new folder in its artifacts/tmp/ and return it."""
    root = Path(root).resolve()
    listed = subprocess.run(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=root,
                            check=True, capture_output=True).stdout.decode()
    copy = new_folder(root, PREFIX)
    try:
        record = user_dir(copy) / COPY_RECORD
        record.parent.mkdir(parents=True, exist_ok=True)
        record.write_text(str(copy))
        sweep_user_dirs()
        for rel in sorted({p for p in listed.split("\0") if p}):
            if rel == "artifacts" or rel.startswith("artifacts/"):
                continue  # run folders and the tool's own scratch folders, this copy among them
            src = root / rel
            if not src.is_file():
                continue  # tracked but deleted in the working tree
            dest = copy / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dest)
        if (root / ".godot").is_dir():
            shutil.copytree(root / ".godot", copy / ".godot", symlinks=True)
    except BaseException:
        cleanup(root, copy)
        raise
    return copy


def hits_dir(root) -> Path:
    """A new, empty folder in `root`'s artifacts/tmp/ for a run's hit shards."""
    return new_folder(Path(root).resolve(), HITS_PREFIX)


def tmp_dir(root) -> Path:
    """`root`'s artifacts/tmp/, resolved: where artifacts/ or artifacts/tmp/ is a symlink, the folder it points to."""
    return (Path(root).resolve() / TMP).resolve()


def new_folder(root: Path, prefix: str) -> Path:
    """A new `<prefix><this pid>.<random>` folder in `root`'s artifacts/tmp/, after sweeping the folders left there by
    runs that are gone; artifacts/.gdignore is written first."""
    gdignore = root / "artifacts" / ".gdignore"
    gdignore.parent.mkdir(parents=True, exist_ok=True)
    if not gdignore.exists():
        gdignore.write_text("")
    sweep(root)
    while True:
        tmp_dir(root).mkdir(parents=True, exist_ok=True)
        try:
            return Path(tempfile.mkdtemp(prefix=f"{prefix}{os.getpid()}.", dir=tmp_dir(root)))
        except FileNotFoundError:
            continue  # another run's cleanup removed the empty artifacts/tmp/ in between


def copy_env(copy, env=None) -> dict:
    env = {k: v for k, v in (os.environ if env is None else env).items() if not k.startswith("GIT_")}
    env["GIT_CEILING_DIRECTORIES"] = str(Path(copy).resolve().parent)
    return env


def tree_hash(root) -> str:
    """sha256 over the repo-relative paths and bytes of every file under scenes/ and project.godot, tracked or not
    (git-ignored files left out, as `create` leaves them out of a copy, so a copy hashes like its source)."""
    root = Path(root)
    h = hashlib.sha256()
    for rel in hashed_files(root):
        h.update(rel.encode() + b"\0" + (root / rel).read_bytes() + b"\0")
    return h.hexdigest()


def hashed_files(root: Path) -> list[str]:
    """The repo-relative paths `tree_hash` covers: git's view of a repo, every file of a copy (which has no .git)."""
    if (root / ".git").exists():
        listed = subprocess.run(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", *HASHED],
                                cwd=root, check=True, capture_output=True).stdout.decode()
        found = {p for p in listed.split("\0") if p}
    else:
        found = set()
        for part in HASHED:
            base = root / part
            if base.is_file():
                found.add(part)
            elif base.is_dir():
                found.update(p.relative_to(root).as_posix() for p in base.rglob("*") if p.is_file())
    return sorted(p for p in found if (root / p).is_file())  # a tracked file deleted from the tree is gone


def git_status(root) -> str:
    return subprocess.run(["git", "status", "--porcelain", "--untracked-files=all"], cwd=root, check=True,
                          capture_output=True, text=True).stdout


def user_dir_name(copy) -> str:
    """The copy's `application/config/custom_user_dir_name`: one folder per copy under the OS data folder."""
    return f"{USER_DIRS}/{Path(copy).name}"


def user_dir(copy) -> Path:
    """Where Godot puts the copy's user:// (`custom_user_dir_name` under the OS data folder, as Godot resolves it)."""
    return user_dirs_root() / Path(copy).name


def user_dirs_root() -> Path:
    if sys.platform == "darwin":
        data = Path.home() / "Library" / "Application Support"
    elif sys.platform.startswith("win"):
        data = Path(os.environ.get("APPDATA", Path.home() / "AppData" / "Roaming"))
    else:
        data = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local" / "share")
    return data / USER_DIRS


def sweep_user_dirs() -> None:
    """Remove the copies' user:// folders whose copy is gone, and those that record no copy once their owner (the pid
    in the name) is gone."""
    base = user_dirs_root()
    if not base.is_dir():
        return
    for d in base.iterdir():
        if not (d.is_dir() and d.name.startswith(PREFIX)):
            continue
        try:
            gone = not Path((d / COPY_RECORD).read_text().strip()).is_dir()
        except OSError:
            pid = owner(d)
            gone = pid is None or not alive(pid)
        if gone:
            shutil.rmtree(d, ignore_errors=True)


def owner(folder) -> int | None:
    """The pid of the process that made a copy or hit folder, from its name (None when it holds none)."""
    name = Path(folder).name
    for prefix in (PREFIX, HITS_PREFIX):
        if name.startswith(prefix):
            pid = name[len(prefix):].split(".", 1)[0]
            return int(pid) if pid.isdigit() else None
    return None


def alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True  # another user's process
    return True


def keep(folder) -> None:
    (Path(folder) / KEPT).write_text("")


def sweep(root) -> list[Path]:
    """Remove the copy and hit folders in `root`'s artifacts/tmp/ whose owner is gone and that are not kept; returns
    them."""
    tmp = tmp_dir(root)
    swept = []
    for folder in sorted(tmp.iterdir()) if tmp.is_dir() else []:
        if not folder.name.startswith((PREFIX, HITS_PREFIX)):
            continue
        pid = owner(folder)
        if pid is not None and alive(pid):
            continue
        if folder.is_symlink():
            folder.unlink()  # never made by this module: the link goes, never what it points to
            swept.append(folder)
            continue
        if not folder.is_dir() or (folder / KEPT).exists():
            continue
        cleanup(root, folder)
        swept.append(folder)
    return swept


def is_ours(root, path) -> bool:
    """Whether `path` is a copy or hit folder of `root`: a `fe-coverage-copy.*` / `fe-coverage-hits.*` folder directly
    in `root`'s artifacts/tmp/, never a symlink (the symlinks above it resolved)."""
    if Path(path).is_symlink():
        return False
    path = Path(path).resolve()
    return path.name.startswith((PREFIX, HITS_PREFIX)) and path.parent == tmp_dir(root)


def cleanup(root, folder) -> None:
    """Remove a copy or hit folder of `root` (a copy's user:// folder with it), then artifacts/tmp/ once empty."""
    if not is_ours(root, folder):
        raise ValueError(f"{folder} is not a folder the coverage workspace made in {tmp_dir(root)}: refusing to "
                         "delete it")
    folder = Path(folder).resolve()
    shutil.rmtree(folder, ignore_errors=True)
    if folder.name.startswith(PREFIX):
        shutil.rmtree(user_dir(folder), ignore_errors=True)
        try:
            user_dir(folder).parent.rmdir()  # the shared fe-coverage folder, once its last copy is gone
        except OSError:
            pass
    try:
        (Path(root).resolve() / TMP).rmdir()  # never a symlinked artifacts/tmp/ (rmdir refuses a symlink) or its target
    except OSError:
        pass
