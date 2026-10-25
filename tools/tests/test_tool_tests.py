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
# A tool file and a file outside the tools no test names: built here, so not even this module's code names them.
UNNAMED = f"tools/no_tool_{os.getpid()}.py"
OUTSIDE = f"docs/no_tool_{os.getpid()}.md"


class PickTests(unittest.TestCase):
    def modules(self, *paths):
        modules, why = tool_tests_pick.pick(list(paths))
        return "all" if why else modules

    def test_the_test_modules_are_the_ones_the_discovery_loads(self):
        suite = unittest.defaultTestLoader.discover(str(ROOT / "tools"), top_level_dir=str(ROOT))
        loaded = set()
        stack = [suite]
        while stack:
            for t in stack.pop():
                if isinstance(t, unittest.TestSuite):
                    stack.append(t)
                else:
                    loaded.add(type(t).__module__)
        self.assertIn(SELF, loaded, "premise: the discovery is read")
        self.assertEqual(sorted(tool_tests_pick.dotted(m) for m in tool_tests_pick.test_modules()), sorted(loaded))

    def test_a_staged_test_script_runs_no_tool_test(self):
        # tools/test_coverage.py and tools/test_log_gate.py match the discovery's pattern, but it never loads them.
        picked = self.modules("tools/test_coverage.py")
        self.assertNotEqual(picked, "all")
        self.assertNotIn("tools.test_coverage", picked)
        self.assertNotIn("tools.test_log_gate", self.modules("tools/test_log_gate.py", ".githooks/pre-commit"))

    def test_a_hook_only_commit_picks_the_hooks_test(self):
        self.assertIn("tools.tests.test_pre_commit", self.modules(".githooks/pre-commit"))
        picked = self.modules(".githooks/commit-msg")
        self.assertIn("tools.tests.test_commit_msg", picked)
        self.assertNotIn("tools.tests.test_pre_commit", picked, "the pre-commit hook's test names no commit-msg")

    def test_a_shared_test_helper_picks_everything(self):
        for helper in ("tools/coverage/tests/support.py", "tools/lint_rules/tests/support.py",
                       "tools/tests/__init__.py"):
            with self.subTest(helper=helper):
                modules, why = tool_tests_pick.pick([helper])
                self.assertEqual((modules, why), ([], [f"{helper} is a shared test helper"]))

    def test_a_tool_file_no_test_names_picks_everything(self):
        modules, why = tool_tests_pick.pick([UNNAMED, ".githooks/pre-commit"])
        self.assertEqual((modules, why), ([], [f"no tool test names {UNNAMED}"]))

    def test_a_file_outside_the_tools_no_test_names_picks_nothing(self):
        self.assertEqual(tool_tests_pick.pick([OUTSIDE]), ([], []))

    def test_a_file_outside_the_tools_picks_the_tests_that_read_it(self):
        self.assertIn("tools.tests.test_run_tests_flags", self.modules("scenes/testing/test_batch.gd"),
                      "it reads the flags of every script in scenes/testing/")
        self.assertIn("tools.tests.test_gdstyle_reflow", self.modules("gdstyle.toml"))

    def test_a_staged_test_module_runs_itself_and_its_importers(self):
        picked = self.modules("tools/tests/test_gdstyle.py")
        self.assertIn("tools.tests.test_gdstyle", picked)
        self.assertIn("tools.tests.test_gdstyle_reflow", picked, "it imports test_gdstyle")
        self.assertNotIn("tools.tests.test_commit_msg", picked)
        self.assertIn("tools.tests.test_load_check", self.modules("tools/tests/test_load_check.py"))

    def test_naming_carries_through_the_tools_that_run_a_file(self):
        picked = self.modules("tools/lint.sh")
        self.assertIn("tools.lint_rules.tests.test_lint_sh", picked, "it runs tools/lint.sh itself")
        self.assertIn("tools.tests.test_lint_staged", picked, "tools/lint_staged.sh runs tools/lint.sh")
        self.assertNotIn("tools.tests.test_commit_msg", picked, "nothing the commit-msg hook runs uses tools/lint.sh")

    def test_a_helper_counts_by_the_symbols_a_test_imports(self):
        picked = self.modules("tools/coverage.py")
        self.assertIn("tools.coverage.tests.test_runner_cli", picked, "it runs the tool through support.run_cli")
        self.assertNotIn("tools.tests.test_pre_commit", picked,
                         "it imports only TempDir, clean_env and git from the coverage support: none runs the tool")

    def test_a_lint_rule_picks_every_test_that_runs_the_rules_folder(self):
        # tools/lint_rules/runner.py loads every module of the folder it names (`HERE / "rules"`).
        picked = self.modules("tools/lint_rules/rules/timing_in_perf.py")
        for module in ("tools.lint_rules.tests.test_timing_in_perf", "tools.lint_rules.tests.test_lint_sh",
                       "tools.lint_rules.tests.test_runner", "tools.lint_rules.tests.test_coverage_isolation"):
            self.assertIn(module, picked)

    def test_the_script_prints_the_picks_all_and_why_or_nothing(self):
        def script(*paths):
            return subprocess.run(["python3", str(ROOT / "tools" / "tool_tests_pick.py"), *paths],
                                  capture_output=True, text=True, check=True).stdout

        self.assertIn("tools.tests.test_commit_msg\n", script(".githooks/commit-msg"))
        self.assertEqual(script(UNNAMED), f"all\n# no tool test names {UNNAMED}\n")
        self.assertEqual(script(OUTSIDE), "")


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
    """A throwaway repo with tools/tool_tests.sh, the picker, tools/a.sh and docs/read.md (named by test_a's code),
    tools/b.sh and docs/notes.md (named by no test), and two sentinel modules that log their name (test_other names
    tools/c.sh, a.sh's name after a rename), committed."""

    def setUp(self):
        self.tmp = TempDir()
        d = Path(self.tmp.__enter__())
        self.addCleanup(self.tmp.__exit__, None, None, None)
        self.root = d / "repo"
        self.log = d / "ran.log"
        files = {
            "tools/__init__.py": "", "tools/tests/__init__.py": "", "tools/a.sh": "echo a\n", "tools/b.sh": "",
            "tools/tests/test_a.py": SENTINEL.replace("{name}", "a").replace(
                "# {names}", 'TOOL = "tools/a.sh"\nDOC = "docs/read.md"'),
            "tools/tests/test_other.py": SENTINEL.replace("{name}", "other").replace(
                "# {names}", 'TOOL = "tools/c.sh"'),
            "docs/notes.md": "", "docs/read.md": "",
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

    def test_staged_runs_the_modules_naming_a_file_outside_the_tools(self):
        self.stage("docs/read.md")
        code, out, ran = self.run_script("--staged")
        self.assertEqual((code, ran), (0, ["a"]), out)

    def test_staged_with_only_files_no_test_names_outside_the_tools_runs_nothing(self):
        self.stage("docs/notes.md")
        code, out, ran = self.run_script("--staged")
        self.assertEqual((code, ran), (0, []), out)
        self.assertIn("tool tests: none (no tool test names a staged file)", out)

    def test_staged_with_nothing_staged_runs_nothing(self):
        code, out, ran = self.run_script("--staged")
        self.assertEqual((code, ran), (0, []), out)
        self.assertIn("tool tests: none (no tool test names a staged file)", out)

    def test_a_staged_rename_runs_the_modules_naming_either_path(self):
        git(self.root, "mv", "tools/a.sh", "tools/c.sh")
        code, out, ran = self.run_script("--staged")
        self.assertEqual(code, 0, out)
        self.assertEqual(sorted(ran), ["a", "other"], "test_a names the old path, test_other the new one")

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
