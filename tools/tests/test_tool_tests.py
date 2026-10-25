"""tools/tool_tests.sh: the tool tests, the whole discovery or (--staged) only the test modules a commit can break, as
tools/tool_tests_pick.py picks them.

PickTests pin the mapping on this checkout's own tools: a hook-only commit picks the hook's test, a shared test helper
or a file no test names picks everything, a staged test module runs itself, and naming carries through the tools (a
change to tools/lint.sh picks the tests of what runs it) and through the helper symbols a test imports (not the rest
of the helper). This module names those files too, so it is among the picks: what it asserts is read from them.
ScriptTests run the script in a throwaway repo with two sentinel test modules, staged files and git.
"""
import os
import subprocess
import unittest
from pathlib import Path

from tools import tool_tests_pick
from tools.coverage.tests.support import TempDir, clean_env, git

ROOT = Path(__file__).resolve().parents[2]
SELF = "tools.tests.test_tool_tests"
# A tool file no test names: built here, so not even this module's code names it.
UNNAMED = f"tools/no_tool_{os.getpid()}.py"


class PickTests(unittest.TestCase):
    def modules(self, *paths):
        modules, why = tool_tests_pick.pick(list(paths))
        return "all" if why else modules

    def test_a_hook_only_commit_picks_the_hooks_test(self):
        self.assertEqual(self.modules(".githooks/pre-commit"), ["tools.tests.test_pre_commit", SELF])
        self.assertEqual(self.modules(".githooks/commit-msg"), ["tools.tests.test_commit_msg", SELF])

    def test_a_shared_test_helper_picks_everything(self):
        for helper in ("tools/coverage/tests/support.py", "tools/lint_rules/tests/support.py",
                       "tools/tests/__init__.py"):
            with self.subTest(helper=helper):
                modules, why = tool_tests_pick.pick([helper])
                self.assertEqual((modules, why), ([], [f"{helper} is a shared test helper"]))

    def test_a_file_no_test_names_picks_everything(self):
        modules, why = tool_tests_pick.pick([UNNAMED, ".githooks/pre-commit"])
        self.assertEqual((modules, why), ([], [f"no tool test names {UNNAMED}"]))

    def test_a_staged_test_module_runs_itself_and_its_importers(self):
        self.assertEqual(self.modules("tools/tests/test_gdstyle.py"),
                         ["tools.tests.test_gdstyle", "tools.tests.test_gdstyle_reflow", SELF])
        self.assertIn("tools.tests.test_load_check", self.modules("tools/tests/test_load_check.py"))

    def test_naming_carries_through_the_tools_that_run_a_file(self):
        picked = self.modules("tools/lint.sh")
        self.assertIn("tools.test_log_gate", picked, "it names tools/lint.sh itself")
        self.assertIn("tools.tests.test_lint_staged", picked, "tools/lint_staged.sh runs tools/lint.sh")
        self.assertNotIn("tools.tests.test_commit_msg", picked, "nothing the commit-msg hook runs uses tools/lint.sh")

    def test_a_helper_counts_by_the_symbols_a_test_imports(self):
        picked = self.modules("tools/coverage.py")
        self.assertIn("tools.coverage.tests.test_runner_cli", picked, "it runs the tool through support.run_cli")
        self.assertNotIn("tools.tests.test_pre_commit", picked,
                         "it imports only TempDir, clean_env and git from the coverage support: none runs the tool")

    def test_a_lint_rule_is_named_by_the_name_the_runner_loads_it_by(self):
        self.assertEqual(self.modules("tools/lint_rules/rules/timing_in_perf.py"),
                         ["tools.lint_rules.tests.test_timing_in_perf", SELF])

    def test_the_script_prints_the_picks_or_all_and_why(self):
        r = subprocess.run(["python3", str(ROOT / "tools" / "tool_tests_pick.py"), ".githooks/commit-msg"],
                           capture_output=True, text=True, check=True)
        self.assertEqual(r.stdout, f"tools.tests.test_commit_msg\n{SELF}\n")
        r = subprocess.run(["python3", str(ROOT / "tools" / "tool_tests_pick.py"), UNNAMED],
                           capture_output=True, text=True, check=True)
        self.assertEqual(r.stdout, f"all\n# no tool test names {UNNAMED}\n")


SENTINEL = '''import os
import unittest

# {names}


class SentinelTests(unittest.TestCase):
    def test_sentinel(self):
        with open(os.environ["TOOL_TESTS_LOG"], "a") as log:
            log.write("{name}\\n")
        self.assertNotEqual(os.environ.get("FAIL"), "{name}", "told to fail")
'''


class ScriptTests(unittest.TestCase):
    """A throwaway repo with tools/tool_tests.sh, the picker, tools/a.sh (named by test_a's code) and tools/b.sh (named
    by no test), two sentinel modules that log their name, committed."""

    def setUp(self):
        self.tmp = TempDir()
        d = Path(self.tmp.__enter__())
        self.addCleanup(self.tmp.__exit__, None, None, None)
        self.root = d / "repo"
        self.log = d / "ran.log"
        files = {
            "tools/__init__.py": "", "tools/tests/__init__.py": "", "tools/a.sh": "", "tools/b.sh": "",
            "tools/tests/test_a.py": SENTINEL.replace("{name}", "a").replace(
                "# {names}", 'TOOL = "tools/a.sh"'),
            "tools/tests/test_other.py": SENTINEL.replace("{name}", "other").replace("# {names}", ""),
            "docs/notes.md": "",
        }
        for rel, text in files.items():
            (self.root / rel).parent.mkdir(parents=True, exist_ok=True)
            (self.root / rel).write_text(text)
        for name in ("tool_tests.sh", "tool_tests_pick.py"):
            (self.root / "tools" / name).write_bytes((ROOT / "tools" / name).read_bytes())
        (self.root / "tools" / "tool_tests.sh").chmod(0o755)
        git(d, "init", "-q", "repo")
        git(self.root, "add", "-A")
        git(self.root, "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "-m", "base")

    def run_script(self, *args, **env):
        self.log.write_text("")
        r = subprocess.run(["bash", str(self.root / "tools" / "tool_tests.sh"), *args], cwd=self.root,
                           capture_output=True, text=True, timeout=120,
                           env=clean_env(TOOL_TESTS_LOG=str(self.log), **env))
        return r.returncode, r.stdout + r.stderr, self.log.read_text().split()

    def stage(self, *rels):
        for rel in rels:
            with open(self.root / rel, "a") as f:
                f.write("# changed\n")
        git(self.root, "add", *rels)

    def test_staged_runs_only_the_modules_that_name_what_is_staged_and_says_which(self):
        self.stage("tools/a.sh")
        code, out, ran = self.run_script("--staged")
        self.assertEqual(code, 0, out)
        self.assertEqual(ran, ["a"])
        self.assertIn("tool tests: tools.tests.test_a", out)

    def test_staged_runs_everything_for_a_file_no_test_names_and_says_why(self):
        self.stage("tools/a.sh", "tools/b.sh")
        code, out, ran = self.run_script("--staged")
        self.assertEqual(code, 0, out)
        self.assertEqual(sorted(ran), ["a", "other"])
        self.assertIn("tool tests: all (no tool test names tools/b.sh)", out)

    def test_staged_with_no_tool_file_staged_runs_nothing(self):
        self.stage("docs/notes.md")
        code, out, ran = self.run_script("--staged")
        self.assertEqual((code, ran), (0, []), out)
        self.assertIn("tool tests: none (no tools/ or .githooks/ file staged)", out)

    def test_a_failing_picked_test_fails_the_run(self):
        self.stage("tools/a.sh")
        code, out, ran = self.run_script("--staged", FAIL="a")
        self.assertEqual((code, ran), (1, ["a"]), out)
        self.assertIn("FAILED", out)

    def test_without_staged_it_runs_the_whole_discovery(self):
        code, out, ran = self.run_script()
        self.assertEqual(code, 0, out)
        self.assertEqual(sorted(ran), ["a", "other"])
        self.assertIn("tool tests: all", out)

    def test_an_unknown_argument_is_refused(self):
        code, out, ran = self.run_script("--stagd")
        self.assertEqual((code, ran), (2, []), out)
        self.assertIn("unknown argument: --stagd", out)


if __name__ == "__main__":
    unittest.main()
