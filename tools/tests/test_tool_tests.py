"""tools/tool_tests.sh: the tool tests, the whole discovery or (--staged) only the test modules a commit can break, as
tools/tool_tests_pick.py picks them.

PickTests pin the mapping on this checkout's own tools: a hook-only commit picks the hook's test, a shared test helper
or a tool file no test names picks everything, a file outside the tools picks only the tests that read it from the
checkout, a staged test module runs itself, and naming carries through the tools (a change to tools/lint.sh picks the
tests of what runs it) and through the helper symbols a test imports (not the rest of the helper), and every game file
at once picks only GAME_COMMIT_PICKS, the cheap tool tests the hook may run on a game commit. This module's code
names many of those files as sample paths, so it is among their picks. ScriptTests run the script, and the picker on
its own, in a throwaway repo with sentinel test modules, staged files and git, where each rule's picks are exact, and
the picker refuses an argument holding several paths.
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
# The tool test modules a game-only commit (scenes/, tests/, project.godot) can make the pre-commit hook run. Adding a
# module here means the hook runs it on game commits: time it first.
GAME_COMMIT_PICKS = {"tools.tests.test_dump_sounds", "tools.tests.test_load_check", "tools.tests.test_run_tests_flags"}


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

    def test_a_path_a_test_writes_into_a_repo_of_its_own_is_no_read_of_the_checkouts_file(self):
        coverage = {"tools.coverage.tests.test_runner_cli", "tools.coverage.tests.test_instrument",
                    "tools.coverage.tests.test_user_dir", "tools.coverage.tests.test_workspace"}
        for path in ("scenes/main.gd", "scenes/main.tscn", "scenes/general/event_bus.gd", "project.godot"):
            with self.subTest(path=path):
                self.assertEqual(coverage & set(self.modules(path)), set())
        picked = self.modules("scenes/ai/brain.gd")
        self.assertNotIn("tools.lint_rules.tests.test_coverage_isolation", picked, "it lints a temp tree's scenes/ai")
        self.assertNotIn("tools.lint_rules.tests.test_comment_ticket_refs", picked)

    def test_a_game_commit_picks_only_the_cheap_tool_tests(self):
        game = subprocess.run(["git", "ls-files", "scenes", "tests", "project.godot"], cwd=ROOT, capture_output=True,
                              text=True, check=True).stdout.splitlines()
        self.assertGreater(len(game), 100, "premise: the game files are listed")
        modules, why = tool_tests_pick.pick(game)
        self.assertEqual(why, [])
        outside = sorted(set(modules) - GAME_COMMIT_PICKS)
        if outside:
            # Only on failure: one path that picks each module outside the set, by halving the paths (the picks of a
            # set of paths are the union of each path's).
            by = {}
            for m in outside:
                paths = game
                while len(paths) > 1:
                    half = paths[:len(paths) // 2]
                    paths = half if m in tool_tests_pick.pick(half)[0] else paths[len(paths) // 2:]
                by[m] = paths[0]
            self.fail("a game commit picks tool tests outside GAME_COMMIT_PICKS (the hook would run them): "
                      + "; ".join(f"{m} (picked by {p})" for m, p in by.items()))

    def test_a_game_file_a_test_runs_a_tool_on_picks_it(self):
        self.assertIn("tools.tests.test_load_check", self.modules("scenes/general/command_server.gd"),
                      "CommandPortTests runs the load check on the checkout, the server kept off")
        self.assertNotIn("tools.tests.test_load_check", self.modules("scenes/general/event_bus.gd"),
                         "scenes/general/ is only the way to the server's path, not a folder it reads")

    def test_a_package_init_is_named_by_every_import_of_the_package(self):
        picked = self.modules("tools/__init__.py")
        for module in ("tools.tests.test_pre_commit", "tools.lint_rules.tests.test_lint_sh",
                       "tools.coverage.tests.test_runner_cli"):
            self.assertIn(module, picked)

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


# The throwaway repo's tools/__init__.py: its discovery keeps to tools/tests/, as this checkout's keeps to its tests
# packages, so tools/test_script.py there is a test script.
INIT = '''from pathlib import Path

HERE = Path(__file__).resolve().parent
TEST_PACKAGES = ("tests",)


def load_tests(loader, tests, pattern):
    for package in TEST_PACKAGES:
        tests.addTests(loader.discover(start_dir=str(HERE / package), pattern=pattern or "test*.py",
                                       top_level_dir=str(HERE.parent)))
    return tests
'''
SENTINEL = '''import os
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# {names}


class SentinelTests(unittest.TestCase):
    def test_sentinel(self):
        with open(os.environ["TOOL_TESTS_LOG"], "a") as log:
            log.write("{name}\\n")
        self.assertNotEqual(os.environ.get("FAIL"), "{name}", "told to fail")
'''


class ScriptTests(unittest.TestCase):
    """A throwaway repo with tools/tool_tests.sh, the picker and sentinel test modules that log their name, committed.
    Its tools/__init__.py keeps the discovery to tools/tests/, as this checkout's does. test_a names tools/a.sh and
    reads docs/read.md from its checkout; test_other names tools/c.sh (a.sh's name after a rename) and writes
    docs/fixture.md into a repo of its own; test_kit reads tools/kit/plugins/ (no package) through a variable and the
    top-level docs/ whole; tools/test_script.py, a test script, names tools/script_only.sh. tools/b.sh and
    docs/notes.md are named by no test."""

    def setUp(self):
        self.tmp = TempDir()
        d = Path(self.tmp.__enter__())
        self.addCleanup(self.tmp.__exit__, None, None, None)
        self.root = d / "repo"
        self.log = d / "ran.log"
        files = {
            "tools/__init__.py": INIT, "tools/tests/__init__.py": "", "tools/a.sh": "echo a\n", "tools/b.sh": "",
            "tools/tests/test_a.py": SENTINEL.replace("{name}", "a").replace(
                "# {names}", 'TOOL = "tools/a.sh"\nDOC = ROOT / "docs" / "read.md"'),
            "tools/tests/test_other.py": SENTINEL.replace("{name}", "other").replace(
                "# {names}", 'TOOL = "tools/c.sh"\nFIXTURE = Path("/tmp/repo") / "docs" / "fixture.md"'),
            "tools/tests/test_kit.py": SENTINEL.replace("{name}", "kit").replace(
                "# {names}", 'KIT = ROOT / "tools" / "kit"\nPLUGINS = KIT / "plugins"\nDOCS = ROOT / "docs"'),
            "tools/kit/__init__.py": "", "tools/kit/plugins/p.py": "",
            "tools/test_script.py": 'TOOL = "tools/script_only.sh"\n', "tools/script_only.sh": "",
            "docs/notes.md": "", "docs/read.md": "", "docs/fixture.md": "",
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
        self.assertEqual(sorted(ran), ["a", "kit", "other"])
        self.assertIn("tool tests: all (no tool test names tools/b.sh)", out)

    def test_staged_runs_the_modules_naming_a_file_outside_the_tools(self):
        self.stage("docs/read.md")
        code, out, ran = self.run_script("--staged")
        self.assertEqual((code, ran), (0, ["a"]), out)

    def test_staged_a_path_a_test_writes_into_a_repo_of_its_own_runs_nothing(self):
        self.stage("docs/fixture.md")
        code, out, ran = self.run_script("--staged")
        self.assertEqual((code, ran), (0, []), out)

    def test_staged_a_file_in_a_folder_read_through_a_variable_runs_its_reader(self):
        self.stage("tools/kit/plugins/p.py")
        code, out, ran = self.run_script("--staged")
        self.assertEqual((code, ran), (0, ["kit"]), out)

    def test_staged_a_tool_file_only_a_test_script_names_runs_nothing(self):
        self.stage("tools/script_only.sh")
        code, out, ran = self.run_script("--staged")
        self.assertEqual((code, ran), (0, []), out)

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
        self.assertEqual(sorted(ran), ["a", "kit", "other"])
        self.assertIn("tool tests: all", out)

    def test_an_unknown_argument_is_refused(self):
        code, out, ran = self.run_script("--stagd")
        self.assertEqual((code, ran), (2, []), out)
        self.assertIn("unknown argument: --stagd", out)

    def run_picker(self, *args):
        return subprocess.run(["python3", str(self.root / "tools" / "tool_tests_pick.py"), *args], cwd=self.root,
                              capture_output=True, text=True, timeout=120, env=clean_env())

    def test_the_picker_refuses_two_paths_joined_in_one_argument(self):
        # zsh does not word-split `$var`: a list of paths in one variable reaches the picker as one argument.
        r = self.run_picker("tools/a.sh tools/kit/plugins/p.py")
        self.assertEqual((r.returncode, r.stdout), (2, ""), r.stderr)
        self.assertIn("one path per argument: tools/a.sh tools/kit/plugins/p.py", r.stderr)
        self.assertIn("xargs, or ${=var} in zsh", r.stderr)
        self.assertIn("a path with whitespace is not supported", r.stderr)

    def test_the_picker_picks_the_same_paths_given_one_per_argument(self):
        r = self.run_picker("tools/a.sh", "tools/kit/plugins/p.py")
        self.assertEqual((r.returncode, r.stdout), (0, "tools.tests.test_a\ntools.tests.test_kit\n"), r.stderr)


if __name__ == "__main__":
    unittest.main()
