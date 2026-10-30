"""Tests for tools/audit_scan.py after its small refactor (ticket #68): `dead` callable as a function, its output
unchanged, and the coverage fixtures (tools/coverage/tests/fixtures/) skipped so they neither add to nor hide from it.

  audit_scan.dead_functions(root) -> [(path, line, name)]
      the "Functions nothing references" list for the tree at `root` (path relative to `root`, posix, e.g.
      "scenes/a.gd"; line 1-based), whatever the current directory is: what tools/coverage/static_refs.py adapts

Every CLI run here copies the script under test into a folder of the tree that is not scanned (`x/`), so its ROOT is
that tree and its own text is not part of the corpus: the old and the new script then read the same files.

The "output unchanged" check compares the script as it was before the refactor (pinned below) with the current one,
on a copy of this checkout without the fixtures. It passes today, before any change: that is its job, to keep
passing after the refactor. The other checks fail until the refactor and the fixture skip are in.
"""
import importlib
import os
import re
import shutil
import subprocess
import sys
import unittest
from pathlib import Path

from tools.coverage.tests.support import TempDir, class_tempdir

ROOT = Path(__file__).resolve().parents[2]
PINNED = "304afdf7debab3f2db7fd09b9dfe3a555417a17e"  # tools/audit_scan.py before the ticket #68 refactor
SCANNED = ("scenes", "tests", "tools", "addons", ".claude", "docs")
FIXTURES = Path("tools") / "coverage" / "tests" / "fixtures"


def copy_tree(dest: Path, with_fixtures: bool) -> Path:
    """The folders audit_scan reads, copied from this checkout to `dest` (no __pycache__ or .godot)."""
    skip = shutil.ignore_patterns("__pycache__", ".godot")
    for name in SCANNED:
        src = ROOT / name
        if src.is_dir():
            shutil.copytree(src, dest / name, ignore=skip)
    if not with_fixtures:
        shutil.rmtree(dest / FIXTURES)
    return dest


# A function nothing references, planted in each copied tree, so the dead list has an entry to compare whatever the
# real tree holds (it may have none). Its name is put together here, never spelled out: this file is copied into the
# tree too (tools/tests/), and its text naming the function would be a reference to it.
PLANTED_NAME = "_".join(("audit", "scan", "planted", "dead", "function"))
PLANTED_PATH = Path("scenes") / "zz_audit_scan_planted.gd"


def plant_dead_function(tree: Path) -> tuple[str, int, str]:
    """Write a scene script whose one function nothing references into `tree`; returns its dead-list entry."""
    (tree / PLANTED_PATH).write_text(f"extends Node\n\n\nfunc {PLANTED_NAME}() -> void:\n\tpass\n")
    return (PLANTED_PATH.as_posix(), 4, PLANTED_NAME)


def place_script(tree: Path, name: str, text: str) -> Path:
    (tree / "x").mkdir(exist_ok=True)
    path = tree / "x" / name
    path.write_text(text)
    return path


def scan(script: Path, *args: str) -> subprocess.CompletedProcess:
    r = subprocess.run([sys.executable, str(script), *args], capture_output=True, text=True, timeout=300,
                       cwd=script.parent)
    if r.returncode != 0:
        raise AssertionError(f"{script} {' '.join(args)} failed:\n{r.stdout}\n{r.stderr}")
    return r


def dead_section(output: str) -> list[tuple[str, int, str]]:
    """The "Functions nothing references" lines of `audit_scan.py dead` output, as (path, line, name)."""
    found, inside = [], False
    for line in output.splitlines():
        if line.startswith("== "):
            inside = line.startswith("== Functions nothing references")
            continue
        m = re.match(r"\s+(\S+):(\d+)\s+(\w+)\s*$", line)
        if inside and m:
            found.append((m.group(1), int(m.group(2)), m.group(3)))
    return found


# The sections whose output the audit's scanner fixes changed, by the start of their `== ` title.
CHANGED_SECTIONS = ("== Snapshot facts", "== EventBus topics")


def without_sections(output: str, titles: tuple) -> str:
    """`output` with each section whose `== ` title starts with one of `titles` dropped, up to the next title."""
    kept, skipping = [], False
    for line in output.splitlines():
        if line.startswith("== "):
            skipping = line.startswith(titles)
        if not skipping:
            kept.append(line)
    return "\n".join(kept)


def audit_scan_module():
    """tools.audit_scan imported with the current directory kept (the script changes it at import today)."""
    cwd = os.getcwd()
    try:
        return importlib.import_module("tools.audit_scan")
    finally:
        os.chdir(cwd)


def current_script() -> str:
    return (ROOT / "tools" / "audit_scan.py").read_text()


class RealTreeTests(unittest.TestCase):
    """On a copy of this checkout, with and without the coverage fixtures."""

    @classmethod
    def setUpClass(cls):
        base = class_tempdir(cls, "audit_scan_test.")
        cls.full = copy_tree(base / "full", with_fixtures=True)
        cls.bare = copy_tree(base / "bare", with_fixtures=False)
        cls.planted = plant_dead_function(cls.full)
        plant_dead_function(cls.bare)
        old = subprocess.run(["git", "show", f"{PINNED}:tools/audit_scan.py"], cwd=ROOT, capture_output=True,
                             text=True, check=True).stdout
        cls.old_on_bare = place_script(cls.bare, "audit_scan_old.py", old)
        cls.new_on_bare = place_script(cls.bare, "audit_scan_new.py", current_script())
        cls.new_on_full = place_script(cls.full, "audit_scan_new.py", current_script())

    def test_output_is_unchanged_by_the_refactor(self):
        # Passes before the refactor too: it guards the refactor. The facts and events sections are left out: the
        # m-audit-everything audit changed what they count on purpose (gated facts, balanced-bracket posts).
        for command in ("dead", "all"):
            with self.subTest(command=command):
                self.assertEqual(without_sections(scan(self.new_on_bare, command).stdout, CHANGED_SECTIONS),
                                 without_sections(scan(self.old_on_bare, command).stdout, CHANGED_SECTIONS))

    def test_the_coverage_fixtures_change_no_output(self):
        for command in ("dead", "all"):
            with self.subTest(command=command):
                self.assertEqual(scan(self.new_on_full, command).stdout, scan(self.new_on_bare, command).stdout)

    def test_dead_functions_is_the_dead_list_of_the_cli(self):
        want = dead_section(scan(self.new_on_bare, "dead").stdout)
        self.assertIn(self.planted, want, "the CLI lists the function planted with no reference")
        got = audit_scan_module().dead_functions(self.bare)
        self.assertEqual(sorted(got), sorted(want))


GD_A = """extends Node


func _ready() -> void:
	used()


func used() -> void:
	pass


func lonely() -> void:
	pass


static func lonely_static() -> int:
	return 1
"""
GD_B = """extends Node


func hidden_by_fixture() -> void:
	pass


func named_by_a_tool_test() -> void:
	pass
"""
FIXTURE_CALLER = """extends Node


func _ready() -> void:
	hidden_by_fixture()
	lonely()
"""
TOOL_TEST = '''"""Calls scenes/b.gd's named_by_a_tool_test through gcmd."""
CALL = "named_by_a_tool_test"
'''


class HandTreeTests(unittest.TestCase):
    """A tree written by hand: scenes/a.gd and scenes/b.gd, a coverage fixture that calls two of their functions, and
    a coverage test (outside fixtures/) that names one."""

    def tree(self, root: Path) -> Path:
        files = {
            "scenes/a.gd": GD_A,
            "scenes/b.gd": GD_B,
            f"{FIXTURES}/project/scenes/caller.gd": FIXTURE_CALLER,
            "tools/coverage/tests/test_calls.py": TOOL_TEST,
        }
        for rel, text in files.items():
            (root / rel).parent.mkdir(parents=True, exist_ok=True)
            (root / rel).write_text(text)
        return root

    # Unreferenced: lonely (a.gd:12), lonely_static (a.gd:16), hidden_by_fixture (b.gd:4), whatever the fixture calls.
    # named_by_a_tool_test is referenced by tools/coverage/tests/test_calls.py, which is not a fixture.
    WANT = [("scenes/a.gd", 12, "lonely"), ("scenes/a.gd", 16, "lonely_static"), ("scenes/b.gd", 4, "hidden_by_fixture")]

    def test_a_fixture_caller_does_not_hide_a_dead_function_from_the_cli(self):
        with TempDir("audit_scan_test.") as d:
            root = self.tree(d)
            out = scan(place_script(root, "audit_scan.py", current_script()), "dead").stdout
        self.assertEqual(sorted(dead_section(out)), self.WANT)

    def test_dead_functions_of_a_tree_from_any_directory(self):
        module = audit_scan_module()
        with TempDir("audit_scan_test.") as d, TempDir("audit_scan_cwd.") as elsewhere:
            root = self.tree(d)
            cwd = os.getcwd()
            os.chdir(elsewhere)
            try:
                got = module.dead_functions(root)
            finally:
                os.chdir(cwd)
        self.assertEqual(sorted(got), self.WANT)


POSTS = """extends Node


func _a() -> void:
	EventBus.post(
		&"footfall",
		{ "position": p, "foot": 0, },
	)
	EventBus.post(&"explosion", { "kind": k })
	var data := { "x": 1 }
	EventBus.post(&"hit", { "victim": v, "damage": d })
	EventBus.post(&"order", data)
	EventBus.post(topic, { "y": 2 })
"""
LISTENER = """extends Node


func _on_posted(topic: StringName, data: Dictionary) -> void:
	if topic != &"stun":
		return
	match topic:
		&"shot", &"hit":
			pass
	var leader_named := data.get("leader", &"leader")
"""


class EventsAndFactsTests(unittest.TestCase):
    """The `events` post parser and listener test, and the `facts` gates, on text written by hand."""

    def test_posts_are_read_with_balanced_brackets(self):
        got = [(t, k) for t, k, _ in audit_scan_module().event_posts(POSTS)]
        self.assertEqual(got, [
            ("footfall", ["position", "foot"]),  # spread over lines, trailing commas
            ("explosion", ["kind"]),  # not given the next post's keys
            ("hit", ["victim", "damage"]),
            ("order", None),  # a variable payload: not scanned
            (None, ["y"]),  # a topic held in a variable
        ])
        self.assertEqual([line for _, _, line in audit_scan_module().event_posts(POSTS)], [5, 9, 11, 12, 13])

    def test_a_listener_handles_a_topic_it_compares_or_matches(self):
        module = audit_scan_module()
        for topic, want in (("stun", True), ("shot", True), ("hit", True), ("leader", False), ("order", False)):
            with self.subTest(topic=topic):
                self.assertEqual(module.handles(LISTENER, topic), want)

    def test_only_requires_entry_rules_and_fact_reads_gate(self):
        files = {
            "scenes/ai/decision/decision_tree.gd": 'var t := { "requires": [&"ordered", &"!follows"] }\n',
            "scenes/ai/tuning/npc_decision_tuning.gd": "@export var entry_rules: Dictionary = { &\"under_fire\": &\"combat\" }\n",
            "tests/a_test.gd": 's.actor(&"hurt", &"puppet")\nvar f = brain.debug_state()["facts"]["exposed"]\n',
        }
        module = audit_scan_module()
        with TempDir("audit_scan_test.") as d:
            for rel, text in files.items():
                (d / rel).parent.mkdir(parents=True, exist_ok=True)
                (d / rel).write_text(text)
            cwd = os.getcwd()
            os.chdir(d)
            try:
                gated = module.gated_facts()
            finally:
                os.chdir(cwd)
        for name in ("ordered", "follows", "under_fire", "exposed"):
            self.assertIn(name, gated)
        self.assertNotIn("hurt", gated, "an actor's name in a test is not a gate")


if __name__ == "__main__":
    unittest.main()
