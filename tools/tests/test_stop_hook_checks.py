"""tools/stop_hook_checks.sh, the Claude Code Stop hook: it runs the lint and the load check (tools/lint.sh --quiet,
then tools/load_check.sh) when something under scenes/, tests/, addons/ or project.godot differs from HEAD, and runs
nothing otherwise. addons/ counts because a lint rule (coverage_isolation) checks it.

Each case is a temp git repo holding a copy of this checkout's script, with a fake tools/lint.sh and
tools/load_check.sh that log that they ran, and one committed file under each of scenes/, addons/ and docs/. A file
is changed (or added), then the script runs as the Stop hook runs it, with the hook's JSON on stdin. TMPDIR is the
case's own temp folder, so the script's last-run fingerprint is the case's and never the real one.
"""
import shutil
import subprocess
import unittest
from pathlib import Path

from tools.coverage.tests.support import TempDir, clean_env, git

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "stop_hook_checks.sh"

FAKE_CHECK = """#!/usr/bin/env bash
echo "{name} $*" >> "$HOOK_TEST_LOG"
"""
STOP_INPUT = '{"session_id": "s", "stop_hook_active": false}'


def write(root: Path, rel: str, text: str, executable: bool = False) -> None:
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    if executable:
        path.chmod(0o755)


class StopHookRepo:
    """A temp repo with the script copy and the fake checks, committed."""

    def __init__(self, root: Path):
        self.root = root
        self.tmp = root.parent / "tmp"
        self.tmp.mkdir()
        self.log = root.parent / "hook_test.log"
        self.log.write_text("")
        git(root.parent, "init", "-q", root.name)
        (root / "tools").mkdir()
        shutil.copy2(SCRIPT, root / "tools" / "stop_hook_checks.sh")
        write(root, "tools/lint.sh", FAKE_CHECK.format(name="lint"), executable=True)
        write(root, "tools/load_check.sh", FAKE_CHECK.format(name="load_check"), executable=True)
        write(root, "scenes/thing.gd", "extends Node\n")
        write(root, "addons/plugin/thing.gd", "extends Node\n")
        write(root, "docs/notes.md", "notes\n")
        git(root, "add", "-A")
        git(root, "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "-m", "base")

    def change(self, rel: str) -> None:
        with open(self.root / rel, "a") as f:
            f.write("# changed\n" if rel.endswith(".gd") else "changed\n")

    def hook(self) -> subprocess.CompletedProcess:
        return subprocess.run(["bash", str(self.root / "tools" / "stop_hook_checks.sh")], cwd=self.root,
                              input=STOP_INPUT, env=clean_env(HOOK_TEST_LOG=str(self.log), TMPDIR=str(self.tmp)),
                              capture_output=True, text=True, timeout=60)

    def ran(self) -> list[str]:
        """What ran, in order, with its arguments: "lint --quiet", "load_check"."""
        return [line.strip() for line in self.log.read_text().splitlines()]


class StopHookChecksTests(unittest.TestCase):
    def repo(self, d: Path) -> StopHookRepo:
        return StopHookRepo(d / "repo")

    def test_a_change_only_under_addons_runs_the_lint_and_the_load_check(self):
        with TempDir("stop_hook_test.") as d:
            repo = self.repo(d)
            repo.change("addons/plugin/thing.gd")
            r = repo.hook()
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertEqual(repo.ran(), ["lint --quiet", "load_check"])

    def test_a_new_file_only_under_addons_runs_the_lint_and_the_load_check(self):
        with TempDir("stop_hook_test.") as d:
            repo = self.repo(d)
            write(repo.root, "addons/plugin/new.gd", "extends Node\n")
            r = repo.hook()
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertEqual(repo.ran(), ["lint --quiet", "load_check"])

    def test_a_change_under_scenes_runs_the_lint_and_the_load_check(self):
        with TempDir("stop_hook_test.") as d:
            repo = self.repo(d)
            repo.change("scenes/thing.gd")
            r = repo.hook()
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertEqual(repo.ran(), ["lint --quiet", "load_check"])

    def test_a_change_only_under_docs_runs_nothing_and_is_silent(self):
        with TempDir("stop_hook_test.") as d:
            repo = self.repo(d)
            repo.change("docs/notes.md")
            r = repo.hook()
            self.assertEqual((r.returncode, r.stdout, r.stderr), (0, "", ""))
            self.assertEqual(repo.ran(), [])


if __name__ == "__main__":
    unittest.main()
