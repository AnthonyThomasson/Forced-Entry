"""tools/tool_tests.sh: the tool tests, the whole discovery or (--staged) only the test modules a commit can break, as
tools/tool_tests_pick.py picks them; --changed does the same for a branch's diff, the working tree and the untracked
files. The picker also explains a pick (--why) and sweeps the tree (--sweep).

PickTests pin the mapping on this checkout's own tools: a hook-only commit picks the hook's test, a shared test helper
or a tool file no test names picks everything, a file outside the tools picks only the tests that read it from the
checkout, a staged test module runs itself, and naming carries through the tools (a change to tools/lint.sh picks the
tests of what runs it) and through the helper symbols a test imports (not the rest of the helper), and every game file
at once picks only GAME_COMMIT_PICKS, the cheap tool tests the hook may run on a game commit. This module's code
names many of those files as sample paths, so it is among their picks. ScriptTests run the script, and the picker on
its own, in a throwaway repo with sentinel test modules, staged files, branch commits and git, where each rule's picks
are exact, and the picker refuses an argument holding several paths.
"""
import json
import os
import subprocess
import unittest
from collections import Counter
from pathlib import Path
from unittest import mock

from tools import tool_tests_pick
from tools.coverage.tests.support import TempDir, clean_env, git

ROOT = Path(__file__).resolve().parents[2]
SELF = "tools.tests.test_tool_tests"
# A tool file and a file outside the tools no test names: built here, so not even this module's code names them.
UNNAMED = f"tools/no_tool_{os.getpid()}.py"
OUTSIDE = f"no_tool_{os.getpid()}.md"
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

    def test_a_split_skill_file_or_a_doc_picks_the_skill_pointer_test(self):
        for path in (".claude/skills/architecture/SKILL.md", ".claude/skills/domain-testing/SKILL.md",
                     ".claude/skills/domain-testing/perf.md", ".claude/skills/architecture/tuning-holders.md",
                     ".claude/skills/architecture/interfaces/05-pushable-contract.md", "docs/hearing.md"):
            with self.subTest(path=path):
                self.assertIn("tools.tests.test_skill_pointers", self.modules(path))

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

    def why(self, *paths):
        return subprocess.run(["python3", str(ROOT / "tools" / "tool_tests_pick.py"), "--why", *paths],
                              capture_output=True, text=True, check=True).stdout.splitlines()

    def test_why_names_the_file_a_test_reads(self):
        lines = self.why("scenes/general/command_server.gd")
        self.assertIn("tools.tests.test_load_check <- reads scenes/general/command_server.gd", lines)

    def test_why_shows_each_link_of_a_chain_through_a_tool(self):
        lines = self.why("tools/lint.sh")
        self.assertIn("tools.coverage.tests.test_runner_cli <- tools/coverage/runner.py <- names tools/lint.sh", lines)

    def test_why_for_a_whole_discovery_pick_prints_all_and_its_reasons(self):
        self.assertEqual(self.why(UNNAMED), ["all", f"# no tool test names {UNNAMED}"])

    def test_why_for_a_path_reaching_nothing_says_so(self):
        self.assertEqual(self.why(OUTSIDE), [f"none <- {OUTSIDE}"])

    def test_why_ends_a_chain_through_a_helper_symbol_at_the_symbol(self):
        lines = self.why("tools/coverage.py")
        self.assertIn("tools.coverage.tests.test_report <- tools/coverage/tests/support.py::fixture_repo"
                      " <- names tools/coverage.py", lines)

    def test_why_for_a_changed_test_module_says_it_is_that_module(self):
        self.assertIn("tools.tests.test_gdstyle <- is tools/tests/test_gdstyle.py", self.why("tools/tests/test_gdstyle.py"))

    # Tracked paths of every kind: a scene file, a game test, a tool, a file two tools share the name of (runner.py), a
    # file outside the tools a test reads, a test module, a hook.
    SAMPLE = ["scenes/general/command_server.gd", "scenes/general/event_bus.gd", "scenes/testing/test_batch.gd",
              "tests/ai/entry/entry_suite.gd", "tools/lint.sh", "tools/coverage.py", "tools/coverage/runner.py",
              "tools/lint_rules/runner.py", "gdstyle.toml", "tools/tests/test_gdstyle.py", ".githooks/pre-commit",
              "docs/hearing.md", "project.godot"]

    def test_a_sweep_picks_what_pick_picks_for_each_path_on_its_own(self):
        swept = tool_tests_pick.sweep(self.SAMPLE)
        self.assertEqual(swept["files"], len(self.SAMPLE), "premise: each sample path is tracked")
        picks = {path: tool_tests_pick.pick([path]) for path in self.SAMPLE}
        self.assertEqual(swept["all"], {path: why for path, (_, why) in picks.items() if why})
        expected = Counter(m for modules, _ in picks.values() for m in modules)
        self.assertEqual(swept["modules"], dict(expected))
        self.assertEqual(list(swept["modules"].values()), sorted(swept["modules"].values(), reverse=True))

    def test_a_sweep_reads_each_source_once(self):
        read = []
        of = tool_tests_pick.Code.of
        with mock.patch.object(tool_tests_pick.Code, "of", side_effect=lambda path: read.append(path) or of(path)):
            swept = tool_tests_pick.sweep(["scenes"])
        self.assertGreater(swept["files"], 500, "premise: the scenes are swept")
        self.assertGreater(len(read), 50, "premise: the tools' sources are read")
        self.assertEqual(sorted(read), sorted(set(read)))

    def test_a_sweep_keeps_to_the_prefixes_given(self):
        swept = tool_tests_pick.sweep(["scenes/general", "gdstyle.toml"])
        listed = subprocess.run(["git", "ls-files", "scenes/general", "gdstyle.toml"], cwd=ROOT, capture_output=True,
                                text=True, check=True).stdout.splitlines()
        self.assertEqual(swept["files"], len(listed))

    def sweep_script(self, *args):
        return subprocess.run(["python3", str(ROOT / "tools" / "tool_tests_pick.py"), "--sweep", *args],
                              capture_output=True, text=True, check=True).stdout

    def test_the_sweep_script_prints_the_count_each_modules_picks_most_first(self):
        self.assertEqual(self.sweep_script("scenes/general/command_server.gd").splitlines(),
                         ["swept 1 files", "1 tools.tests.test_load_check"])
        lines = self.sweep_script("scenes/general/command_server.gd", "tools/load_check.sh").splitlines()
        self.assertEqual(lines[0], "swept 2 files")
        counts = [int(l.split(" ", 1)[0]) for l in lines[1:]]
        self.assertEqual(counts, sorted(counts, reverse=True))
        self.assertEqual(lines[1], "2 tools.tests.test_load_check", "both paths pick it")
        self.assertGreater(len(lines), 2, "tools/load_check.sh picks more tests, with a count of 1 each")

    def test_a_sweep_of_a_prefix_no_tracked_file_is_under_sweeps_nothing(self):
        self.assertEqual(self.sweep_script(UNNAMED).splitlines(), ["swept 0 files"])

    def test_the_sweep_script_lists_a_path_picking_all_with_its_reason(self):
        helper = "tools/coverage/tests/support.py"
        lines = self.sweep_script(helper).splitlines()
        self.assertEqual(lines, ["swept 1 files", f"all <- {helper} ({helper} is a shared test helper)"])

    def test_the_sweep_script_json_has_the_files_the_modules_and_the_all_paths(self):
        helper = "tools/coverage/tests/support.py"
        out = json.loads(self.sweep_script("--json", "scenes/general/command_server.gd", helper))
        self.assertEqual(out, {"files": 2, "modules": {"tools.tests.test_load_check": 1},
                               "all": {helper: [f"{helper} is a shared test helper"]}})

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
    top-level notes/ whole; tools/test_script.py, a test script, names tools/script_only.sh. tools/b.sh and
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
                "# {names}", 'KIT = ROOT / "tools" / "kit"\nPLUGINS = KIT / "plugins"\nNOTES = ROOT / "notes"'),
            "tools/kit/__init__.py": "", "tools/kit/plugins/p.py": "",
            "tools/test_script.py": 'TOOL = "tools/script_only.sh"\n', "tools/script_only.sh": "",
            "docs/notes.md": "", "docs/read.md": "", "docs/fixture.md": "", "notes/n.md": "",
        }
        for rel, text in files.items():
            (self.root / rel).parent.mkdir(parents=True, exist_ok=True)
            (self.root / rel).write_text(text)
        for name in ("tool_tests.sh", "tool_tests_pick.py"):
            (self.root / "tools" / name).write_bytes((ROOT / "tools" / name).read_bytes())
        (self.root / "tools" / "tool_tests.sh").chmod(0o755)
        git(d, "init", "-q", "-b", "main", "repo")
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

    def test_staged_a_file_in_a_top_level_folder_read_whole_runs_its_reader(self):
        self.stage("notes/n.md")
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

    def commit_on_branch(self, rel):
        """The base commit's sha; HEAD is then a commit on a new branch changing `rel`."""
        base = git(self.root, "rev-parse", "HEAD").strip()
        git(self.root, "checkout", "-q", "-b", "feature")
        with open(self.root / rel, "a") as f:
            f.write("# changed\n")
        git(self.root, "add", rel)
        git(self.root, "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "-m", "change")
        return base

    def test_changed_runs_the_modules_naming_what_a_branch_commit_changed_and_says_which(self):
        base = self.commit_on_branch("tools/a.sh")
        code, out, ran = self.run_script(f"--changed={base}")
        self.assertEqual((code, ran), (0, ["a"]), out)
        self.assertIn("tool tests: tools.tests.test_a\n", out)

    def test_changed_picks_a_tracked_change_of_the_working_tree_only(self):
        with open(self.root / "tools" / "a.sh", "a") as f:
            f.write("# edited\n")
        code, out, ran = self.run_script("--changed=HEAD")
        self.assertEqual((code, ran), (0, ["a"]), out)

    def test_changed_picks_an_untracked_file(self):
        (self.root / "tools" / "c.sh").write_text("echo c\n")
        code, out, ran = self.run_script("--changed=HEAD")
        self.assertEqual((code, ran), (0, ["other"]), out)

    def test_changed_without_a_ref_diffs_against_origin_main(self):
        base = self.commit_on_branch("tools/a.sh")
        git(self.root, "update-ref", "refs/remotes/origin/main", base)
        git(self.root, "branch", "-f", "main", "HEAD")  # main has the change: only origin/main can show it
        code, out, ran = self.run_script("--changed")
        self.assertEqual((code, ran), (0, ["a"]), out)

    def test_changed_without_a_ref_falls_back_to_main(self):
        self.commit_on_branch("tools/a.sh")
        code, out, ran = self.run_script("--changed")
        self.assertEqual((code, ran), (0, ["a"]), out)

    def test_changed_with_an_unknown_ref_is_refused_naming_it(self):
        code, out, ran = self.run_script("--changed=no-such-ref")
        self.assertEqual((code, ran), (2, []), out)
        self.assertIn("unknown ref: no-such-ref", out)

    def test_changed_with_a_ref_sharing_no_history_fails_instead_of_picking_nothing(self):
        git(self.root, "checkout", "-q", "--orphan", "island")
        git(self.root, "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "-m", "island")
        with open(self.root / "tools" / "a.sh", "a") as f:
            f.write("# edited\n")
        code, out, ran = self.run_script("--changed=main")
        self.assertEqual((code, ran), (1, []), out)
        self.assertIn("no merge base", out)
        self.assertNotIn("tool tests: none", out)

    def test_changed_with_an_empty_ref_is_refused(self):
        code, out, ran = self.run_script("--changed=")
        self.assertEqual((code, ran), (2, []), out)
        self.assertIn("unknown ref: ", out)

    def test_changed_with_staged_is_refused(self):
        code, out, ran = self.run_script("--changed", "--staged")
        self.assertEqual((code, ran), (2, []), out)
        self.assertIn("--changed and --staged cannot be combined", out)

    def test_changed_with_nothing_changed_runs_nothing(self):
        code, out, ran = self.run_script("--changed=HEAD")
        self.assertEqual((code, ran), (0, []), out)
        self.assertIn("tool tests: none (no tool test names a changed file)", out)

    def test_changed_a_file_no_test_names_runs_everything_and_says_why(self):
        base = self.commit_on_branch("tools/b.sh")
        code, out, ran = self.run_script(f"--changed={base}")
        self.assertEqual(code, 0, out)
        self.assertEqual(sorted(ran), ["a", "kit", "other"])
        self.assertIn("tool tests: all (no tool test names tools/b.sh)", out)

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
