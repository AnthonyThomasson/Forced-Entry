"""Shared helpers for the coverage tool's tests: paths, finding Godot, temp git repos, the fixture project as a repo
with the tool copied in, the CLI, run folders and an independent tree digest.

Not a test module (unittest discovery only loads test*.py).

Environment:
  GODOT=/path/to/Godot  the engine, found as tools/run_tests.sh finds it (GODOT, then godot / godot4 on PATH, then
                        /Applications/Godot*.app); tests that need it are skipped when there is none.
  FE_SLOW_TESTS=1       also run the slow tests: the real tree instrumented and played with the Von server
                        (test_isolation_run.py) and the windowed fixture run.
"""
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
TOOL = ROOT / "tools" / "coverage.py"
PACKAGE = ROOT / "tools" / "coverage"
FIXTURES = Path(__file__).resolve().parent / "fixtures"
PROJECT = FIXTURES / "project"
EXPECTED = FIXTURES / "expected_hits.json"
RUN_FILES = ("hits.json", "meta.json", "map.json", "report.md", "report.json")


def godot_binary() -> str | None:
    """The Godot binary, looked up in tools/run_tests.sh's order."""
    if os.environ.get("GODOT"):
        return os.environ["GODOT"]
    for name in ("godot", "godot4"):
        found = shutil.which(name)
        if found:
            return found
    apps = sorted(Path("/Applications").glob("Godot*.app/Contents/MacOS/Godot"))
    return str(apps[0]) if apps else None


needs_godot = unittest.skipUnless(godot_binary(), "no Godot binary (set GODOT=/path/to/Godot)")
slow = unittest.skipUnless(os.environ.get("FE_SLOW_TESTS") == "1", "slow: set FE_SLOW_TESTS=1 to run it")


def clean_env(**extra: str) -> dict:
    """This process's environment without git's GIT_* variables, plus `extra`: what every git and every CLI run of a
    test gets. A test run from inside git (the pre-commit hook, `git rebase --exec`) inherits GIT_INDEX_FILE, GIT_DIR
    and the rest, and a git started with them acts on the repo they name, not on the throwaway repo it runs in."""
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    env.update(extra)
    return env


def env_with_godot(**extra: str) -> dict:
    env = clean_env(**extra)
    if godot_binary():
        env["GODOT"] = godot_binary()
    return env


def git(root: Path, *args: str) -> str:
    """Run git in `root` with a fixed identity; returns stdout."""
    env = clean_env(GIT_AUTHOR_NAME="Fixture", GIT_AUTHOR_EMAIL="fixture@example.invalid",
                    GIT_COMMITTER_NAME="Fixture", GIT_COMMITTER_EMAIL="fixture@example.invalid")
    return subprocess.run(["git", *args], cwd=root, env=env, check=True, capture_output=True, text=True).stdout


def commit_all(root: Path, message: str = "fixture") -> str:
    """Stage and commit everything in `root` (a repo); returns the new HEAD."""
    git(root, "add", "-A")
    git(root, "commit", "-q", "-m", message)
    return git(root, "rev-parse", "HEAD").strip()


def init_repo(root: Path) -> str:
    """Make `root` a git repo with everything in it committed; returns HEAD."""
    git(root, "init", "-q", "-b", "main")
    return commit_all(root, "initial")


# The throwaway folders (and the git repos the tests make in them) live in the system temp directory, outside this
# checkout, on purpose: a folder inside the checkout sits under its .git, so a test that ran git there before its own
# `git init` would silently act on this repo.
class TempDir:
    """A fresh directory for one test, removed afterwards: `with TempDir() as d:`."""

    def __init__(self, prefix: str = "coverage_test."):
        self.prefix = prefix

    def __enter__(self) -> Path:
        self.path = Path(tempfile.mkdtemp(prefix=self.prefix))
        return self.path

    def __exit__(self, *_exc):
        shutil.rmtree(self.path, ignore_errors=True)


def class_tempdir(cls, prefix: str = "coverage_test.") -> Path:
    """A fresh directory for a test class, removed after its tests (even when setUpClass fails)."""
    path = Path(tempfile.mkdtemp(prefix=prefix))
    cls.addClassCleanup(shutil.rmtree, path, True)
    return path


def require_tool() -> None:
    """Fail (not skip) when the tool is not there yet."""
    missing = [str(p.relative_to(ROOT)) for p in (TOOL, PACKAGE / "workspace.py") if not p.exists()]
    if missing:
        raise AssertionError(f"the coverage tool is missing: {', '.join(missing)}")


def project_repo(dest: Path, edit=None) -> Path:
    """The fixture project alone as a git repo at `dest/repo` (no tool in it). `edit(repo)` may change the fixture
    before the commit."""
    repo = dest / "repo"
    shutil.copytree(PROJECT, repo, ignore=shutil.ignore_patterns(".godot", "*.uid", "__pycache__"))
    if edit is not None:
        edit(repo)
    init_repo(repo)
    return repo


def fixture_repo(dest: Path, edit=None) -> Path:
    """The fixture project as a git repo at `dest/repo`, with the coverage tool (tools/coverage.py and
    tools/coverage/, its tests left out) and tools/audit_scan.py copied in, so the repo's OWN tools/coverage.py works
    on it as the real one works on Forced-Entry. `edit(repo)` may change the fixture before the commit."""
    require_tool()

    def with_tool(repo: Path) -> None:
        (repo / "tools").mkdir(exist_ok=True)
        shutil.copy2(TOOL, repo / "tools" / "coverage.py")
        shutil.copy2(ROOT / "tools" / "audit_scan.py", repo / "tools" / "audit_scan.py")
        shutil.copytree(PACKAGE, repo / "tools" / "coverage", ignore=shutil.ignore_patterns("tests", "__pycache__"))
        if edit is not None:
            edit(repo)

    return project_repo(dest, with_tool)


def run_cli(repo: Path, *args: str, timeout: float = 600, **env: str) -> subprocess.CompletedProcess:
    """`python3 tools/coverage.py ARGS` run from `repo`, the repo's own copy of the tool."""
    return subprocess.run([sys.executable, str(repo / "tools" / "coverage.py"), *args], cwd=repo,
                          env=env_with_godot(**env), capture_output=True, text=True, timeout=timeout)


def run_folders(repo: Path, kind: str | None = None) -> list[Path]:
    """The run folders under `repo/artifacts/coverage/`, oldest first (by name, then mtime); only `kind`
    (matches / tests) when given."""
    base = repo / "artifacts" / "coverage"
    if not base.is_dir():
        return []
    found = [p for p in base.iterdir() if p.is_dir() and (kind is None or p.name.endswith(f"-{kind}"))]
    return sorted(found, key=lambda p: (p.stat().st_mtime, p.name))


def newest_run(repo: Path, kind: str) -> Path:
    found = run_folders(repo, kind)
    if not found:
        raise AssertionError(f"no {kind} run folder under {repo / 'artifacts' / 'coverage'}")
    return found[-1]


def read_json(path: Path):
    return json.loads(Path(path).read_text())


def tree_digest(root: Path, parts=("scenes", "project.godot")) -> str:
    """A sha256 over the paths and bytes of every file under `parts` of `root`: the test's own check that a tree is
    byte-identical, independent of the tool's workspace.tree_hash."""
    h = hashlib.sha256()
    for part in parts:
        base = Path(root) / part
        if base.is_file():
            files = [base]
        elif base.is_dir():
            files = sorted(p for p in base.rglob("*") if p.is_file())
        else:
            files = []
        for f in files:
            h.update(str(f.relative_to(root)).encode() + b"\0" + f.read_bytes() + b"\0")
    return h.hexdigest()


def git_status(root: Path) -> str:
    return git(root, "status", "--porcelain", "--untracked-files=all")


def expected() -> dict:
    return read_json(EXPECTED)


def statement_key(s: dict) -> tuple:
    return (s["file"], s["line"], s["kind"], s["function"], s["class"])


def wait_for(predicate, timeout: float, step: float = 0.2):
    """Poll `predicate` until it returns something truthy (returned) or `timeout` seconds pass (None)."""
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        value = predicate()
        if value:
            return value
        time.sleep(step)
    return None
