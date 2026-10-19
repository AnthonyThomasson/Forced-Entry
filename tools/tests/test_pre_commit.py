""".githooks/pre-commit: when the commit stages anything under tools/, it runs the tool tests (Python unittest
discovery over tools/) and aborts the commit when one fails; otherwise it leaves them alone. It runs
`tools/run_tests.sh --changed …` when scenes/, tests/ or project.godot is staged, and only then. And it runs the lint
(`tools/lint.sh --quiet`) when the commit stages a script the lint holds to its rules that the game tests do not lint
for it: a .gd outside addons/ and the coverage tool's fixtures (sandboxes/, tools/ ...), or the gdstyle pass's own
files (gdstyle.toml, tools/gdstyle.sh, tools/lint_gdstyle.py). When the game tests run they lint first
(run_tests.sh), so the hook does not lint again.

Each case is a temp git repo holding a copy of this checkout's hook, a fake tools/run_tests.sh that logs its arguments
(and fails when FAKE_GAME_FAIL=1), a fake tools/lint.sh that does the same (and fails when FAKE_LINT_FAIL=1), and one
sentinel tool test, tools/tests/test_sentinel.py, that logs that it ran (and fails when SENTINEL_FAIL=1). Files are
staged, then the hook runs as git runs it (from the repo, no arguments).
Three cases commit through git itself: one shows a failure aborts the commit; one commits from a worktree of the
repo a tool test that makes and commits in a throwaway repo of its own, and shows the commit made is the staged one
alone (the hook runs the tool tests without git's GIT_* variables); one commits scenes/ and tools/ from a worktree and
shows the game tests keep git's GIT_DIR and GIT_INDEX_FILE (they act on this repo) while the tool tests get neither.
The fake runner and the sentinel both log the two variables they were given to `<log>.env`.

"Silent" means the hook prints nothing on stdout or stderr.
"""
import shutil
import subprocess
import unittest
from pathlib import Path

from tools.coverage.tests.support import TempDir, clean_env, git

ROOT = Path(__file__).resolve().parents[2]
HOOK = ROOT / ".githooks" / "pre-commit"

FAKE_RUN_TESTS = """#!/usr/bin/env bash
echo "run_tests $*" >> "$HOOK_TEST_LOG"
echo "run_tests GIT_DIR=${GIT_DIR-unset} GIT_INDEX_FILE=${GIT_INDEX_FILE-unset}" >> "$HOOK_TEST_LOG.env"
if [[ "${FAKE_GAME_FAIL:-}" == 1 ]]; then
  echo "FAIL  ai/fake_test  (1.0 sim, 10 ms)"
  echo "0 passed, 1 failed"
  exit 1
fi
echo "1 passed, 0 failed"
"""
FAKE_LINT = """#!/usr/bin/env bash
echo "lint $*" >> "$HOOK_TEST_LOG"
if [[ "${FAKE_LINT_FAIL:-}" == 1 ]]; then
  echo "== gdstyle check: style findings =="
  echo "sandboxes/thing_sandbox.gd:2:101: line too long (104 > 100) [format/max-line-length]"
  echo "FAIL"
  exit 1
fi
"""
SENTINEL = '''import os
import unittest


class SentinelTests(unittest.TestCase):
    def test_sentinel_tool_check(self):
        with open(os.environ["HOOK_TEST_LOG"], "a") as log:
            log.write("tool_tests\\n")
        with open(os.environ["HOOK_TEST_LOG"] + ".env", "a") as log:
            log.write(" ".join(["tool_tests"] + [f"{k}={os.environ.get(k, 'unset')}"
                                                 for k in ("GIT_DIR", "GIT_INDEX_FILE")]) + "\\n")
        self.assertNotEqual(os.environ.get("SENTINEL_FAIL"), "1", "the sentinel tool test was told to fail")
'''
# A tool test that makes a throwaway repo of its own and commits in it, running git with the environment it was given,
# as a test that does not guard itself would. Only the hook stands between it and the repo being committed.
INNER_GIT = '''import os
import shutil
import subprocess
import tempfile
import unittest


class InnerGitTests(unittest.TestCase):
    def test_commits_in_its_own_throwaway_repo(self):
        with open(os.environ["HOOK_TEST_LOG"], "a") as log:
            log.write("inner_git\\n")
        d = tempfile.mkdtemp(prefix="inner_git_test.")
        try:
            subprocess.run(["git", "init", "-q"], cwd=d, check=True)
            with open(os.path.join(d, "inner.txt"), "w") as f:
                f.write("inner\\n")
            subprocess.run(["git", "add", "inner.txt"], cwd=d, check=True)
            subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "-m",
                            "inner commit"], cwd=d, check=True)
        finally:
            shutil.rmtree(d, ignore_errors=True)
'''


def write(root: Path, rel: str, text: str, executable: bool = False) -> None:
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    if executable:
        path.chmod(0o755)


class HookRepo:
    """A temp repo with the hook copy, the fake game runner and the sentinel tool test, committed."""

    def __init__(self, root: Path):
        self.root = root
        self.log = root.parent / "hook_test.log"
        self.log.write_text("")
        git(root.parent, "init", "-q", root.name)
        (root / ".githooks").mkdir()
        shutil.copy2(HOOK, root / ".githooks" / "pre-commit")
        write(root, "tools/run_tests.sh", FAKE_RUN_TESTS, executable=True)
        write(root, "tools/lint.sh", FAKE_LINT, executable=True)
        for rel in ("tools/__init__.py", "tools/tests/__init__.py"):
            write(root, rel, "")
        write(root, "tools/tests/test_sentinel.py", SENTINEL)
        write(root, "scenes/thing.gd", "extends Node\n")
        write(root, "docs/notes.md", "notes\n")
        write(root, "tools/helper.py", "VALUE = 1\n")
        write(root, "sandboxes/thing_sandbox.gd", "extends Node\n")
        write(root, "addons/plugin/thing.gd", "extends Node\n")
        write(root, "tools/gdunit_discover.gd", "extends SceneTree\n")
        write(root, "tools/coverage/probe.gd", "extends Node\n")
        write(root, "tools/coverage/tests/fixtures/project/scenes/bus.gd", "extends Node\n")
        write(root, "gdstyle.toml", "max_line_length = 100\n")
        write(root, "tools/gdstyle.sh", "#!/usr/bin/env bash\n")
        write(root, "tools/lint_gdstyle.py", "VALUE = 1\n")
        git(root, "add", "-A")
        git(root, "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "-m", "base")
        self.log.write_text("")

    def stage(self, *rels: str) -> None:
        for rel in rels:
            with open(self.root / rel, "a") as f:
                f.write("# changed\n" if rel.endswith((".gd", ".py")) else "changed\n")
        git(self.root, "add", *rels)

    def env(self, **extra: str) -> dict:
        return clean_env(HOOK_TEST_LOG=str(self.log), **extra)

    def hook(self, **env: str) -> subprocess.CompletedProcess:
        return subprocess.run(["bash", str(self.root / ".githooks" / "pre-commit")], cwd=self.root,
                              env=self.env(**env), capture_output=True, text=True, timeout=300)

    def ran(self) -> list[str]:
        """What ran, in order: "tool_tests" (the sentinel), "lint" and "run_tests" (the game tests)."""
        return [line.split(" ")[0] for line in self.log.read_text().splitlines()]

    def env_seen(self) -> dict[str, dict[str, str]]:
        """The GIT_DIR and GIT_INDEX_FILE that the game tests ("run_tests") and the tool tests ("tool_tests") were
        given, "unset" for one they were not."""
        seen = {}
        for line in Path(f"{self.log}.env").read_text().splitlines():
            who, *pairs = line.split(" ")
            seen[who] = dict(pair.split("=", 1) for pair in pairs)
        return seen


class PreCommitTests(unittest.TestCase):
    def repo(self, d: Path) -> HookRepo:
        return HookRepo(d / "repo")

    def test_staged_tools_run_the_tool_tests_silently_when_they_pass(self):
        with TempDir("pre_commit_test.") as d:
            repo = self.repo(d)
            repo.stage("tools/helper.py")
            r = repo.hook()
            self.assertEqual((r.returncode, r.stdout, r.stderr), (0, "", ""))
            self.assertEqual(repo.ran(), ["tool_tests"], "the tool tests ran, the game tests did not")

    def test_a_failing_tool_test_aborts_naming_it(self):
        with TempDir("pre_commit_test.") as d:
            repo = self.repo(d)
            repo.stage("tools/helper.py")
            r = repo.hook(SENTINEL_FAIL="1")
            self.assertEqual(r.returncode, 1)
            self.assertIn("test_sentinel_tool_check", r.stdout + r.stderr)
            self.assertEqual(repo.ran(), ["tool_tests"])

    def test_a_failing_tool_test_aborts_the_commit_through_git(self):
        with TempDir("pre_commit_test.") as d:
            repo = self.repo(d)
            repo.stage("tools/helper.py")
            head = git(repo.root, "rev-parse", "HEAD")
            r = subprocess.run(["git", "-c", "core.hooksPath=.githooks", "-c", "user.name=t", "-c",
                                "user.email=t@example.com", "commit", "-q", "-m", "change"], cwd=repo.root,
                               env=repo.env(SENTINEL_FAIL="1"), capture_output=True, text=True, timeout=300)
            self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertEqual(git(repo.root, "rev-parse", "HEAD"), head, "no commit was made")

    def test_a_tool_test_that_commits_in_its_own_repo_leaves_the_commit_through_git_alone(self):
        # Committed from a worktree, as this checkout is: there git hands the hook GIT_DIR and an absolute
        # GIT_INDEX_FILE, which every git the tool tests start obeys unless the hook removes them.
        with TempDir("pre_commit_test.") as d:
            repo = self.repo(d)
            wt = d / "wt"
            git(repo.root, "worktree", "add", "-q", "-b", "change", str(wt))
            head = git(wt, "rev-parse", "HEAD").strip()
            write(wt, "tools/tests/test_inner_git.py", INNER_GIT)
            git(wt, "add", "tools/tests/test_inner_git.py")
            staged = git(wt, "ls-files", "--stage")
            r = subprocess.run(["git", "-c", "core.hooksPath=.githooks", "-c", "user.name=t", "-c",
                                "user.email=t@example.com", "commit", "-q", "-m", "change"], cwd=wt,
                               env=repo.env(), capture_output=True, text=True, timeout=300)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertIn("inner_git", repo.ran(), "the inner tool test ran in the hook")
            self.assertEqual(git(wt, "rev-list", f"{head}..HEAD").split(), [git(wt, "rev-parse", "HEAD").strip()],
                             "exactly one new commit")
            self.assertEqual(git(wt, "log", "-1", "--format=%s%n%P").split(), ["change", head],
                             "the new commit is the staged one, on the old HEAD")
            self.assertEqual(git(wt, "ls-files", "--stage"), staged, "the index holds what was staged")
            self.assertEqual(git(wt, "diff", "--cached", "--name-only"), "", "and the commit holds the index")
            self.assertNotIn("inner commit", git(repo.root, "log", "--all", "--format=%s"),
                             "the inner test's commit is in its own repo only")

    def test_through_git_in_a_worktree_the_game_tests_keep_gits_variables_and_the_tool_tests_get_none(self):
        with TempDir("pre_commit_test.") as d:
            repo = self.repo(d)
            wt = d / "wt"
            git(repo.root, "worktree", "add", "-q", "-b", "change", str(wt))
            for rel in ("scenes/thing.gd", "tools/helper.py"):
                with open(wt / rel, "a") as f:
                    f.write("# changed\n")
            git(wt, "add", "scenes/thing.gd", "tools/helper.py")
            r = subprocess.run(["git", "-c", "core.hooksPath=.githooks", "-c", "user.name=t", "-c",
                                "user.email=t@example.com", "commit", "-q", "-m", "change"], cwd=wt,
                               env=repo.env(), capture_output=True, text=True, timeout=300)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertEqual(sorted(repo.ran()), ["run_tests", "tool_tests"])
            seen = repo.env_seen()
            worktree_git = Path(git(wt, "rev-parse", "--absolute-git-dir").strip()).resolve()
            game = seen["run_tests"]
            self.assertNotEqual(game["GIT_DIR"], "unset", f"the game tests keep git's GIT_DIR: {seen}")
            self.assertNotEqual(game["GIT_INDEX_FILE"], "unset", f"and its GIT_INDEX_FILE: {seen}")
            self.assertEqual((wt / game["GIT_DIR"]).resolve(), worktree_git, "both name this worktree's repo")
            self.assertEqual((wt / game["GIT_INDEX_FILE"]).resolve().parent, worktree_git)
            self.assertEqual(seen["tool_tests"], {"GIT_DIR": "unset", "GIT_INDEX_FILE": "unset"},
                             "the tool tests get neither")

    def test_docs_only_runs_nothing_and_is_silent(self):
        with TempDir("pre_commit_test.") as d:
            repo = self.repo(d)
            repo.stage("docs/notes.md")
            r = repo.hook(SENTINEL_FAIL="1", FAKE_GAME_FAIL="1", FAKE_LINT_FAIL="1")
            self.assertEqual((r.returncode, r.stdout, r.stderr), (0, "", ""))
            self.assertEqual(repo.ran(), [])

    def test_scenes_only_runs_the_game_tests_and_not_the_tool_tests(self):
        with TempDir("pre_commit_test.") as d:
            repo = self.repo(d)
            repo.stage("scenes/thing.gd")
            r = repo.hook(SENTINEL_FAIL="1")
            self.assertEqual((r.returncode, r.stdout, r.stderr), (0, "", ""))
            self.assertEqual(repo.ran(), ["run_tests"])
            self.assertIn("--changed", repo.log.read_text())

    def test_scenes_and_tools_run_both(self):
        with TempDir("pre_commit_test.") as d:
            repo = self.repo(d)
            repo.stage("scenes/thing.gd", "tools/helper.py")
            r = repo.hook()
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertEqual(sorted(repo.ran()), ["run_tests", "tool_tests"])

    def test_with_both_staged_a_failing_tool_test_fails_the_hook_when_the_game_tests_pass(self):
        with TempDir("pre_commit_test.") as d:
            repo = self.repo(d)
            repo.stage("scenes/thing.gd", "tools/helper.py")
            r = repo.hook(SENTINEL_FAIL="1")
            self.assertEqual(r.returncode, 1)
            self.assertIn("test_sentinel_tool_check", r.stdout + r.stderr)

    def assert_runs(self, rels: tuple[str, ...], expected: list[str]) -> None:
        with TempDir("pre_commit_test.") as d:
            repo = self.repo(d)
            repo.stage(*rels)
            r = repo.hook()
            self.assertEqual((r.returncode, r.stdout, r.stderr), (0, "", ""), f"staged {rels}")
            self.assertEqual(repo.ran(), expected, f"staged {rels}")
            if "lint" in expected:
                self.assertIn("lint --quiet\n", repo.log.read_text(), "the whole tree, quietly")

    def test_a_sandbox_script_only_runs_the_lint_silently_when_it_passes(self):
        self.assert_runs(("sandboxes/thing_sandbox.gd",), ["lint"])

    def test_a_tools_script_runs_the_tool_tests_and_the_lint(self):
        self.assert_runs(("tools/gdunit_discover.gd",), ["tool_tests", "lint"])

    def test_a_script_in_a_tools_subfolder_runs_the_tool_tests_and_the_lint(self):
        self.assert_runs(("tools/coverage/probe.gd",), ["tool_tests", "lint"])

    def test_the_gdstyle_config_only_runs_the_lint(self):
        self.assert_runs(("gdstyle.toml",), ["lint"])

    def test_the_gdstyle_wrapper_runs_the_tool_tests_and_the_lint(self):
        self.assert_runs(("tools/gdstyle.sh",), ["tool_tests", "lint"])

    def test_the_gdstyle_pass_runs_the_tool_tests_and_the_lint(self):
        self.assert_runs(("tools/lint_gdstyle.py",), ["tool_tests", "lint"])

    def test_a_script_staged_ahead_of_a_long_list_still_runs_the_lint(self):
        # Far more than a pipe holds after the script: a check that stops reading at the first match would fail.
        with TempDir("pre_commit_test.") as d:
            repo = self.repo(d)
            for i in range(3000):
                write(repo.root, f"zz/{i:04d}_{'x' * 60}.md", "x\n")
            git(repo.root, "add", "zz")
            repo.stage("sandboxes/thing_sandbox.gd")
            r = repo.hook()
            self.assertEqual((r.returncode, r.stdout, r.stderr), (0, "", ""))
            self.assertEqual(repo.ran(), ["lint"])

    def test_an_addons_script_only_runs_nothing(self):
        self.assert_runs(("addons/plugin/thing.gd",), [])

    def test_a_coverage_fixture_script_runs_the_tool_tests_and_not_the_lint(self):
        self.assert_runs(("tools/coverage/tests/fixtures/project/scenes/bus.gd",), ["tool_tests"])

    def test_with_the_game_tests_staged_too_the_lint_is_left_to_them(self):
        # tools/run_tests.sh lints the whole tree before it runs a test, so the hook does not lint it twice.
        self.assert_runs(("scenes/thing.gd", "sandboxes/thing_sandbox.gd", "gdstyle.toml"), ["run_tests"])

    def test_a_failing_lint_aborts_with_its_findings(self):
        with TempDir("pre_commit_test.") as d:
            repo = self.repo(d)
            repo.stage("sandboxes/thing_sandbox.gd")
            r = repo.hook(FAKE_LINT_FAIL="1")
            self.assertEqual(r.returncode, 1)
            self.assertIn("Lint failed; commit aborted (tools/lint.sh)", r.stderr)
            self.assertIn("sandboxes/thing_sandbox.gd:2:101: line too long", r.stderr, "the lint's findings")
            self.assertIn("tools/gdstyle.sh fmt", r.stderr, "and how to format a script")
            self.assertEqual(repo.ran(), ["lint"])

    def test_a_failing_lint_aborts_the_commit_through_git(self):
        with TempDir("pre_commit_test.") as d:
            repo = self.repo(d)
            repo.stage("gdstyle.toml")
            head = git(repo.root, "rev-parse", "HEAD")
            r = subprocess.run(["git", "-c", "core.hooksPath=.githooks", "-c", "user.name=t", "-c",
                                "user.email=t@example.com", "commit", "-q", "-m", "change"], cwd=repo.root,
                               env=repo.env(FAKE_LINT_FAIL="1"), capture_output=True, text=True, timeout=300)
            self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertIn("Lint failed; commit aborted", r.stderr)
            self.assertEqual(git(repo.root, "rev-parse", "HEAD"), head, "no commit was made")

    def test_a_failing_lint_fails_the_hook_when_the_tool_tests_pass(self):
        with TempDir("pre_commit_test.") as d:
            repo = self.repo(d)
            repo.stage("tools/gdunit_discover.gd")
            r = repo.hook(FAKE_LINT_FAIL="1")
            self.assertEqual(r.returncode, 1)
            self.assertIn("Lint failed; commit aborted", r.stderr)
            self.assertEqual(repo.ran(), ["tool_tests", "lint"])

    def test_a_failing_tool_test_and_a_failing_lint_are_both_reported(self):
        with TempDir("pre_commit_test.") as d:
            repo = self.repo(d)
            repo.stage("tools/gdunit_discover.gd")
            r = repo.hook(SENTINEL_FAIL="1", FAKE_LINT_FAIL="1")
            self.assertEqual(r.returncode, 1)
            self.assertIn("test_sentinel_tool_check", r.stderr)
            self.assertIn("Lint failed; commit aborted", r.stderr)


if __name__ == "__main__":
    unittest.main()
