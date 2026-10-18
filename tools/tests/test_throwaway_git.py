"""The test helpers that run git in a throwaway repo ignore an outer git's GIT_* variables.

A tool test can run from inside git: the pre-commit hook, `git rebase --exec`. There git exports GIT_DIR,
GIT_INDEX_FILE and the rest, and a git started with them acts on the repo they name, not on the folder it runs in.
Each case sets those variables to a decoy repo, as git would for a hook running in it, then uses a helper on a
throwaway repo, and checks the decoy is untouched and the throwaway repo got the work:

  tools.coverage.tests.support: git / init_repo / commit_all, and env_with_godot (the environment of the CLI runs)
  tools.lint_rules.tests.support: clean_env (the environment of the runner and lint.sh runs)
  tools/test_play_tests.py: ScriptTests.git (its temporary repos), run as it is run, a standalone script
"""
import os
import subprocess
import sys
import unittest
from pathlib import Path
from unittest import mock

from tools.coverage.tests import support as coverage_support
from tools.lint_rules.tests import support as lint_support

PLAY_TESTS = coverage_support.ROOT / "tools" / "test_play_tests.py"
# A case of it that builds its temporary repo with the helper, commits there, and runs no other git
PLAY_TESTS_CASE = "ScriptTests.test_explicit_ids_are_queued_in_the_order_given"


def plain_git(root: Path, *args: str) -> str:
    """git in `root` with no GIT_* variable at all: the checks' own view of a repo."""
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    return subprocess.run(["git", *args], cwd=root, env=env, check=True, capture_output=True, text=True).stdout


class Decoy:
    """A committed repo, and the GIT_* variables git would hand a hook running in a worktree of it."""

    def __init__(self, root: Path):
        self.root = root
        root.mkdir()
        plain_git(root, "init", "-q")
        (root / "decoy.txt").write_text("decoy\n")
        plain_git(root, "add", "-A")
        plain_git(root, "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "-m", "decoy")
        self.env = {"GIT_DIR": str(root / ".git"), "GIT_INDEX_FILE": str(root / ".git" / "index"),
                    "GIT_WORK_TREE": str(root)}
        self.before = self.state()

    def state(self) -> tuple:
        return (plain_git(self.root, "log", "--all", "--format=%H %s"), plain_git(self.root, "ls-files", "--stage"),
                plain_git(self.root, "status", "--porcelain"))


class ThrowawayGitTests(unittest.TestCase):
    def test_init_repo_and_commit_all_work_in_the_throwaway_repo_only(self):
        with coverage_support.TempDir("throwaway_git_test.") as d:
            decoy = Decoy(d / "decoy")
            work = d / "work"
            work.mkdir()
            (work / "work.txt").write_text("work\n")
            with mock.patch.dict(os.environ, decoy.env):
                coverage_support.init_repo(work)
                (work / "more.txt").write_text("more\n")
                coverage_support.commit_all(work, "more")
            self.assertEqual(decoy.state(), decoy.before, "the decoy repo is untouched")
            self.assertEqual(plain_git(work, "log", "--format=%s").split(), ["more", "initial"])
            self.assertEqual(plain_git(work, "ls-files").split(), ["more.txt", "work.txt"])

    def test_the_play_tests_git_helper_works_in_its_temporary_repo_only(self):
        with coverage_support.TempDir("throwaway_git_test.") as d:
            decoy = Decoy(d / "decoy")
            # What git hands a hook run in a worktree: GIT_DIR and GIT_INDEX_FILE (no GIT_WORK_TREE: the work tree
            # is where git runs, here the helper's temporary repo)
            hook_env = {k: decoy.env[k] for k in ("GIT_DIR", "GIT_INDEX_FILE")}
            r = subprocess.run([sys.executable, str(PLAY_TESTS), PLAY_TESTS_CASE], cwd=coverage_support.ROOT,
                               env=dict(os.environ, **hook_env), capture_output=True, text=True, timeout=300)
            self.assertEqual(decoy.state(), decoy.before, "the decoy repo is untouched")
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_the_cli_environment_carries_no_git_variable(self):
        with coverage_support.TempDir("throwaway_git_test.") as d:
            decoy = Decoy(d / "decoy")
            with mock.patch.dict(os.environ, decoy.env):
                env = coverage_support.env_with_godot(EXTRA="1")
            self.assertEqual([k for k in env if k.startswith("GIT_")], [])
            self.assertEqual(env["EXTRA"], "1")

    def test_the_lint_helpers_environment_carries_no_git_variable(self):
        with coverage_support.TempDir("throwaway_git_test.") as d:
            decoy = Decoy(d / "decoy")
            with mock.patch.dict(os.environ, decoy.env):
                env = lint_support.clean_env(EXTRA="1")
            self.assertEqual([k for k in env if k.startswith("GIT_")], [])
            self.assertEqual(env["EXTRA"], "1")


if __name__ == "__main__":
    unittest.main()
