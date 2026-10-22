"""tools/stop_hook_checks.sh, the Claude Code Stop hook: it runs the lint and the load check (tools/lint.sh --quiet,
then tools/load_check.sh) when something the lint reads differs from HEAD, and runs nothing otherwise: anything under
scenes/, tests/, addons/ or sandboxes/, project.godot, any other .gd (tools/gdunit_discover.gd, tools/coverage/probe.gd
...) but the coverage tool's fixtures, and the gdstyle pass's own files (gdstyle.toml, tools/gdstyle.sh,
tools/lint_gdstyle.py), and the lint and the load check themselves (tools/lint.sh, anything under tools/lint_rules/,
tools/lint_report.py, tools/lint_scripts.gd / .tscn, tools/load_check.sh). addons/ counts because a lint rule
(coverage_isolation) checks it. A stop on the same changes as the last run runs nothing again.

Each case is a temp git repo holding a copy of this checkout's script, with a fake tools/lint.sh and
tools/load_check.sh that log that they ran, and one committed file in each place above, plus a coverage fixture
script, a lint rule, the lint's report and engine-pass scene, a tools/ Python script and a doc. A file is changed (or added), then the script runs as the Stop hook runs it,
with the hook's JSON on stdin. TMPDIR is the case's own temp folder, so the script's last-run fingerprint is the
case's and never the real one.
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
        write(root, "sandboxes/thing_sandbox.gd", "extends Node\n")
        write(root, "tools/gdunit_discover.gd", "extends SceneTree\n")
        write(root, "tools/coverage/probe.gd", "extends Node\n")
        write(root, "tools/coverage/tests/fixtures/project/scenes/bus.gd", "extends Node\n")
        write(root, "tools/helper.py", "VALUE = 1\n")
        write(root, "gdstyle.toml", "max_line_length = 100\n")
        write(root, "tools/gdstyle.sh", "#!/usr/bin/env bash\n")
        write(root, "tools/lint_gdstyle.py", "VALUE = 1\n")
        write(root, "tools/lint_rules/runner.py", "VALUE = 1\n")
        write(root, "tools/lint_rules/rules/some_rule.py", "VALUE = 1\n")
        write(root, "tools/lint_report.py", "VALUE = 1\n")
        write(root, "tools/lint_scripts.tscn", "[gd_scene format=3]\n")
        write(root, "docs/notes.md", "notes\n")
        git(root, "add", "-A")
        git(root, "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "-m", "base")

    def change(self, rel: str) -> None:
        with open(self.root / rel, "a") as f:
            f.write("# changed\n" if rel.endswith((".gd", ".sh", ".py")) else "changed\n")

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

    def assert_checks_run_for(self, rel: str) -> None:
        with TempDir("stop_hook_test.") as d:
            repo = self.repo(d)
            repo.change(rel)
            r = repo.hook()
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertEqual(repo.ran(), ["lint --quiet", "load_check"], f"a change only to {rel}")

    def assert_nothing_runs_for(self, rel: str) -> None:
        with TempDir("stop_hook_test.") as d:
            repo = self.repo(d)
            repo.change(rel)
            r = repo.hook()
            self.assertEqual((r.returncode, r.stdout, r.stderr), (0, "", ""), f"a change only to {rel}")
            self.assertEqual(repo.ran(), [], f"a change only to {rel}")

    def test_a_change_only_to_a_sandbox_script_runs_the_lint_and_the_load_check(self):
        self.assert_checks_run_for("sandboxes/thing_sandbox.gd")

    def test_a_new_sandbox_script_runs_the_lint_and_the_load_check(self):
        with TempDir("stop_hook_test.") as d:
            repo = self.repo(d)
            write(repo.root, "sandboxes/new_sandbox.gd", "extends Node\n")
            r = repo.hook()
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertEqual(repo.ran(), ["lint --quiet", "load_check"])

    def test_a_change_only_to_a_tools_script_runs_the_lint_and_the_load_check(self):
        self.assert_checks_run_for("tools/gdunit_discover.gd")

    def test_a_change_only_to_a_script_in_a_tools_subfolder_runs_the_lint_and_the_load_check(self):
        self.assert_checks_run_for("tools/coverage/probe.gd")

    def test_a_new_tools_script_runs_the_lint_and_the_load_check(self):
        with TempDir("stop_hook_test.") as d:
            repo = self.repo(d)
            write(repo.root, "tools/new_tool.gd", "extends SceneTree\n")
            r = repo.hook()
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertEqual(repo.ran(), ["lint --quiet", "load_check"])

    def test_a_change_only_to_the_gdstyle_config_runs_the_lint_and_the_load_check(self):
        self.assert_checks_run_for("gdstyle.toml")

    def test_a_change_only_to_the_gdstyle_wrapper_runs_the_lint_and_the_load_check(self):
        self.assert_checks_run_for("tools/gdstyle.sh")

    def test_a_change_only_to_the_gdstyle_pass_runs_the_lint_and_the_load_check(self):
        self.assert_checks_run_for("tools/lint_gdstyle.py")

    def test_a_change_only_to_the_lint_tooling_or_the_load_check_runs_the_lint_and_the_load_check(self):
        for rel in ("tools/lint.sh", "tools/lint_rules/runner.py", "tools/lint_rules/rules/some_rule.py",
                    "tools/lint_report.py", "tools/lint_scripts.tscn", "tools/load_check.sh"):
            with self.subTest(rel=rel):
                self.assert_checks_run_for(rel)

    def test_a_new_lint_rule_runs_the_lint_and_the_load_check(self):
        with TempDir("stop_hook_test.") as d:
            repo = self.repo(d)
            write(repo.root, "tools/lint_rules/rules/new_rule.py", "VALUE = 1\n")
            r = repo.hook()
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertEqual(repo.ran(), ["lint --quiet", "load_check"])

    def test_a_second_stop_on_the_same_lint_tooling_change_runs_nothing(self):
        with TempDir("stop_hook_test.") as d:
            repo = self.repo(d)
            repo.change("tools/lint_rules/runner.py")
            self.assertEqual(repo.hook().returncode, 0)
            r = repo.hook()
            self.assertEqual((r.returncode, r.stdout, r.stderr), (0, "", ""))
            self.assertEqual(repo.ran(), ["lint --quiet", "load_check"], "the second stop ran nothing")

    def test_a_change_only_to_a_coverage_fixture_script_runs_nothing(self):
        # The lint leaves the coverage tool's fixture project out (gdstyle.toml's excludes, the engine pass).
        self.assert_nothing_runs_for("tools/coverage/tests/fixtures/project/scenes/bus.gd")

    def test_a_change_only_to_a_tools_python_script_runs_nothing(self):
        self.assert_nothing_runs_for("tools/helper.py")

    def test_a_second_stop_on_the_same_changes_runs_nothing_and_a_further_change_runs_them_again(self):
        with TempDir("stop_hook_test.") as d:
            repo = self.repo(d)
            repo.change("sandboxes/thing_sandbox.gd")
            self.assertEqual(repo.hook().returncode, 0)
            r = repo.hook()
            self.assertEqual((r.returncode, r.stdout, r.stderr), (0, "", ""))
            self.assertEqual(repo.ran(), ["lint --quiet", "load_check"], "the second stop ran nothing")
            repo.change("tools/gdunit_discover.gd")
            self.assertEqual(repo.hook().returncode, 0)
            self.assertEqual(repo.ran(), ["lint --quiet", "load_check"] * 2, "a further change ran them again")
            write(repo.root, "tools/new_tool.gd", "extends SceneTree\n")
            self.assertEqual(repo.hook().returncode, 0)
            self.assertEqual(repo.ran(), ["lint --quiet", "load_check"] * 3, "so did a new script")

    def test_a_change_only_under_docs_runs_nothing_and_is_silent(self):
        with TempDir("stop_hook_test.") as d:
            repo = self.repo(d)
            repo.change("docs/notes.md")
            r = repo.hook()
            self.assertEqual((r.returncode, r.stdout, r.stderr), (0, "", ""))
            self.assertEqual(repo.ran(), [])


if __name__ == "__main__":
    unittest.main()
