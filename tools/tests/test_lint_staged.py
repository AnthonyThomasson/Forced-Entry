"""tools/lint_staged.sh: the lint of what a commit holds, which the pre-commit hook and `tools/run_tests.sh --changed
--staged` both run. It gives tools/lint.sh the staged scripts the lint reads (added, copied, modified or renamed, not
deleted: a .gd outside addons/ and the coverage tool's fixtures), or no path (the whole tree) when a file that governs
every script is staged (project.godot, gdstyle.toml, tools/gdstyle.sh, tools/lint_gdstyle.py, a file of the project
lint rules: tools/lint_rules/ but its tests); with nothing to lint it
runs nothing and says so (silent with --quiet); a finding in a script the commit does not hold is labelled
`not in this commit: <path>`.

Each case is a temp git repo holding a copy of the helper and tools/lint_label.py, and a fake tools/lint.sh that logs
its arguments (and, with FAKE_LINT_FOREIGN=<path>, reports a finding in that script). The pre-commit hook's and the
runner's own tests (tools/tests/test_pre_commit.py, tools/test_log_gate.py) cover it as they call it.
"""
import shutil
import subprocess
import unittest
from pathlib import Path

from tools.coverage.tests.support import TempDir, clean_env, git

ROOT = Path(__file__).resolve().parents[2]

FAKE_LINT = """#!/usr/bin/env bash
echo "lint $*" >> "$LINT_LOG"
if [[ -n "${FAKE_LINT_FOREIGN:-}" ]]; then
  echo "== GDScript analyzer (engine) =="
  echo "res://$FAKE_LINT_FOREIGN  (1)"
  exit 1
fi
exit 0
"""
FILES = ("sandboxes/a_sandbox.gd", "sandboxes/b_sandbox.gd", "addons/plugin/p.gd",
         "tools/coverage/tests/fixtures/project/f.gd", "project.godot", "gdstyle.toml", "docs/notes.md",
         "tools/lint_rules/rules/a_rule.py", "tools/lint_rules/walk.py", "tools/lint_rules/tests/test_a_rule.py")


class Repo:
    def __init__(self, root: Path):
        self.root = root
        self.log = root.parent / "lint.log"
        git(root.parent, "init", "-q", root.name)
        (root / "tools").mkdir()
        for name in ("lint_staged.sh", "lint_label.py"):
            shutil.copy2(ROOT / "tools" / name, root / "tools" / name)
        (root / "tools" / "lint.sh").write_text(FAKE_LINT)
        (root / "tools" / "lint.sh").chmod(0o755)
        for rel in FILES:
            (root / rel).parent.mkdir(parents=True, exist_ok=True)
            (root / rel).write_text("x\n")
        git(root, "add", "-A")
        git(root, "commit", "-q", "-m", "base")

    def stage(self, *rels: str) -> None:
        for rel in rels:
            with open(self.root / rel, "a") as f:
                f.write("changed\n")
        git(self.root, "add", *rels)

    def lint(self, *args: str, **env: str) -> tuple[subprocess.CompletedProcess, list[str]]:
        """The helper's run, and each tools/lint.sh call it made (its arguments)."""
        self.log.write_text("")
        r = subprocess.run(["bash", str(self.root / "tools" / "lint_staged.sh"), *args], cwd=self.root,
                           env=clean_env(LINT_LOG=str(self.log), **env), capture_output=True, text=True, timeout=60)
        return r, self.log.read_text().splitlines()


class LintStagedTests(unittest.TestCase):
    def test_it_lints_the_staged_scripts_the_lint_reads(self):
        with TempDir("lint_staged_test.") as d:
            repo = Repo(d / "repo")
            git(repo.root, "rm", "-q", "sandboxes/b_sandbox.gd")
            repo.stage("sandboxes/a_sandbox.gd", "addons/plugin/p.gd", "tools/coverage/tests/fixtures/project/f.gd",
                       "docs/notes.md")
            r, calls = repo.lint("--quiet")
            self.assertEqual((r.returncode, r.stdout, r.stderr), (0, "", ""))
            self.assertEqual(calls, ["lint --quiet sandboxes/a_sandbox.gd"])

    def test_a_staged_file_that_governs_every_script_lints_the_whole_tree(self):
        for governing in ("project.godot", "gdstyle.toml", "tools/lint_rules/rules/a_rule.py",
                          "tools/lint_rules/walk.py"):
            with self.subTest(governing=governing), TempDir("lint_staged_test.") as d:
                repo = Repo(d / "repo")
                repo.stage("sandboxes/a_sandbox.gd", governing)
                r, calls = repo.lint()
                self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
                self.assertEqual(calls, ["lint "], "no path: every script")

    def test_a_lint_rules_test_alone_lints_nothing(self):
        with TempDir("lint_staged_test.") as d:
            repo = Repo(d / "repo")
            repo.stage("tools/lint_rules/tests/test_a_rule.py")
            r, calls = repo.lint("--quiet")
            self.assertEqual((r.returncode, calls), (0, []), r.stdout + r.stderr)

    def test_nothing_to_lint_runs_nothing_and_says_so_unless_quiet(self):
        with TempDir("lint_staged_test.") as d:
            repo = Repo(d / "repo")
            repo.stage("docs/notes.md", "addons/plugin/p.gd")
            r, calls = repo.lint()
            self.assertEqual((r.returncode, calls), (0, []), r.stdout + r.stderr)
            self.assertIn("lint skipped: the commit stages no script the lint reads", r.stderr)
            r, calls = repo.lint("--quiet")
            self.assertEqual((r.returncode, r.stdout, r.stderr, calls), (0, "", "", []))

    def test_a_finding_in_a_script_the_commit_does_not_hold_is_labelled(self):
        with TempDir("lint_staged_test.") as d:
            repo = Repo(d / "repo")
            repo.stage("sandboxes/a_sandbox.gd")
            r, _ = repo.lint("--quiet", FAKE_LINT_FOREIGN="sandboxes/b_sandbox.gd")
            self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
            self.assertIn("res://sandboxes/b_sandbox.gd  (1)  [not in this commit: sandboxes/b_sandbox.gd]", r.stdout)


if __name__ == "__main__":
    unittest.main()
