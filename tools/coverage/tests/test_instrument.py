"""Tests for tools/coverage/instrument.py and the probe it copies in (probe.gd, registered as CoverageProbe), on the
fixture project (fixtures/project/), against fixtures/expected_hits.json, which is written by hand.

  instrument.instrument(copy) -> dict
      In a copy made by workspace.create: puts a counter bump on the same line, before every statement of
      scenes/**/*.gd (every source line stays where it was), leaves every other file alone, copies the probe in as a
      `coverage_probe*.gd` file and registers it as the autoload `CoverageProbe`, FIRST in the copy's project.godot,
      and returns the statement map (format in tools/coverage/README.md; run folders keep it as map.json).
  Without FE_COVERAGE the probe stays idle, so the copy still loads and runs like the game (the load check, the
  lint and the game tests run on it); `coverage.py run` sets FE_COVERAGE.

What the fixture holds, and why each form is expected to be instrumented exactly:
  - The forms issue #68's brief verified on Godot 4.4 headless (scenes/constructs/forms.gd): a marker before a simple
    and before a compound statement, as the first statement of if / elif / else and match-arm bodies, in one-line
    bodies, inside a multi-line lambda assigned to a variable, after a statement wrapped over several lines, and in
    for / while bodies.
  - The forms of scenes/constructs/edge.gd and tool_script.gd, verified on Godot 4.4.stable (mono, macOS) headless
    with a throwaway project whose autoload `Cov` holds `var h := PackedInt32Array()` and whose markers read
    `Cov.h[n] += 1; <statement>`: every counter reads back the expected count for an inline lambda in call arguments
    (`arr.map(func(x): Cov.h[2] += 1; return x * 2)`: 3 for three elements; `sort_custom` likewise), a multi-line
    lambda in call arguments (each body line 3), a lambda in a dictionary literal, a `static func`, an inner class's
    method and a static func of a class nested in it, a `@tool` script instanced at run time, a multi-line signature,
    a string holding `#` followed by `; statement`, and one-line if / elif / else, match-arm, for and while bodies,
    with no parse error or warning logged. `func(): a; b` keeps `b` inside the lambda, and a script error names the
    source line (`at: _ready (res://main.gd:6)`). All of them are instrumented.
  - One construct the scanner is meant to be unsure of (scenes/constructs/unsure.gd): a statement that starts on the
    closing line of a multi-line string (`last\"\"\"; s += "!"`). It is left untouched and listed as uninstrumented;
    the string's opening statement is still instrumented.
  - A callback reached only through a .tscn signal connection (main.gd `_on_worker_pinged`, wired in main.tscn) and
    one reached only through `call("_by_name")`: both must count.
  - The hook surfaces the probe uses on the real game, in the same places: Main's `endless_time_limit`, the
    SetupMenu's `start_requested(config)`, the MatchHUD's `match_ended(verdict)`, and scenes/testing/test_runner.gd's
    `open_entry` and `open_ctx` (`is_finished`, the signal `finished`).

The Godot tests (needs_godot) play one Watch match of seed 100 through the fixture repo's own tools/coverage.py and
compare the run folder's map.json and hits.json with the expected hits.
"""
import collections
import re
import subprocess
import sys
import unittest
from pathlib import Path

from tools.coverage import instrument, workspace
from tools.coverage.tests.support import (
    PROJECT, TempDir, class_tempdir, expected, fixture_repo, git_status, godot_binary, needs_godot, newest_run, project_repo,
    read_json, run_cli, statement_key, tree_digest, ROOT,
)

KINDS = {"function", "branch", "statement"}


def autoloads(project_godot: str) -> list[tuple[str, str]]:
    """The [autoload] entries of a project.godot, in order: (name, value)."""
    section = re.search(r"^\[autoload\]\s*$(.*?)(?=^\[|\Z)", project_godot, re.M | re.S)
    if not section:
        return []
    return [(m.group(1), m.group(2)) for m in re.finditer(r'^(\w+)\s*=\s*"?([^"\n]*)"?\s*$', section.group(1), re.M)]


def is_subsequence(needles: list[str], haystack: list[str]) -> bool:
    it = iter(haystack)
    return all(any(n == h for h in it) for n in needles)


class InstrumentedFixture(unittest.TestCase):
    """One instrumented copy of the fixture repo, shared by the tests of this class."""

    @classmethod
    def setUpClass(cls):
        cls.src = project_repo(class_tempdir(cls))
        cls.before = (git_status(cls.src), tree_digest(cls.src))
        cls.copy = workspace.create(cls.src)
        cls.addClassCleanup(workspace.cleanup, cls.src, cls.copy)
        cls.map = instrument.instrument(cls.copy)
        cls.expected = expected()


class MapTests(InstrumentedFixture):
    def test_the_map_lists_exactly_the_expected_statements(self):
        got = collections.Counter(statement_key(s) for s in self.map["statements"])
        want = collections.Counter(statement_key(s) for s in self.expected["statements"])
        self.assertEqual(sorted((got - want).elements()), [], "statements found that the fixture does not hold")
        self.assertEqual(sorted((want - got).elements()), [], "statements of the fixture that were missed")

    def test_the_map_has_the_documented_shape(self):
        m = self.map
        self.assertEqual((m["format"], m["version"]), ("fe-coverage-map", 1))
        self.assertIsInstance(m["hash"], str)
        self.assertTrue(m["hash"])
        self.assertEqual([s["id"] for s in m["statements"]], list(range(len(m["statements"]))), "ids dense, id == index")
        for s in m["statements"]:
            self.assertTrue(s["file"].startswith("scenes/") and s["file"].endswith(".gd"), s)
            self.assertIn(s["kind"], KINDS, s)
            self.assertIsInstance(s["line"], int)

    def test_unsure_constructs_are_listed_as_uninstrumented_and_nothing_else_is(self):
        spans = self.map["uninstrumented"]
        want = [(u["file"], u["line"]) for u in self.expected["uninstrumented"]]
        for file, line in want:
            self.assertTrue(any(s["file"] == file and s["line"] <= line <= s["end_line"] for s in spans),
                            f"{file}:{line} listed as uninstrumented: {spans}")
        for s in spans:
            self.assertTrue(any(f == s["file"] and s["line"] <= l <= s["end_line"] for f, l in want),
                            f"nothing else is uninstrumented: {s}")
            self.assertTrue(s["reason"].strip(), "every span says why")

    def test_the_same_sources_give_the_same_map_and_a_moved_statement_changes_its_hash(self):
        again = workspace.create(self.src)
        try:
            self.assertEqual(instrument.instrument(again), self.map)
        finally:
            workspace.cleanup(self.src, again)
        with TempDir() as d:
            moved = project_repo(d, lambda r: (r / "scenes" / "bus.gd").write_text(
                "\n" + (r / "scenes" / "bus.gd").read_text()))
            copy = workspace.create(moved)
            try:
                self.assertNotEqual(instrument.instrument(copy)["hash"], self.map["hash"])
            finally:
                workspace.cleanup(moved, copy)


class CopyTests(InstrumentedFixture):
    def test_every_line_stays_where_it_was(self):
        marked = collections.defaultdict(set)
        for s in self.expected["statements"]:
            marked[s["file"]].add(s["line"])
        untouched_lines = {(u["file"], u["line"]) for u in self.expected["uninstrumented"]}
        for src in sorted(PROJECT.glob("scenes/**/*.gd")):
            rel = str(src.relative_to(PROJECT))
            with self.subTest(file=rel):
                before = src.read_text().split("\n")
                after = (self.copy / rel).read_text().split("\n")
                self.assertEqual(len(after), len(before), "same number of lines")
                for n, (a, b) in enumerate(zip(before, after), start=1):
                    if n in marked[rel]:
                        self.assertTrue(is_subsequence(a.split(), b.split()), f"line {n} keeps its code: {b!r}")
                        self.assertTrue(b.startswith(a[:len(a) - len(a.lstrip())]), f"line {n} keeps its indentation")
                    else:
                        self.assertEqual(b, a, f"line {n} holds no statement (or is uninstrumented) and is unchanged"
                                         if (rel, n) not in untouched_lines else f"uninstrumented line {n} is untouched")

    def test_files_that_are_not_scene_scripts_are_unchanged(self):
        for rel in ("tests/helper.gd", "tools/run_tests.sh", "scenes/main.tscn", "scenes/testing/test_runner.tscn",
                    ".gitignore"):
            with self.subTest(file=rel):
                self.assertEqual((self.copy / rel).read_bytes(), (PROJECT / rel).read_bytes())

    def test_the_probe_is_registered_first_and_the_other_autoloads_stay(self):
        entries = autoloads((self.copy / "project.godot").read_text())
        self.assertTrue(entries, "the copy's project.godot has autoloads")
        name, value = entries[0]
        self.assertEqual(name, "CoverageProbe")
        path = value.lstrip("*").replace("res://", "")
        self.assertTrue((self.copy / path).is_file(), f"the probe script exists in the copy: {path}")
        self.assertTrue(Path(path).name.startswith("coverage_probe"), path)
        self.assertIn(("Bus", "*res://scenes/bus.gd"), entries)

    def test_the_source_repo_is_untouched(self):
        self.assertEqual((git_status(self.src), tree_digest(self.src)), self.before)


@needs_godot
class UninstrumentedCopyTests(unittest.TestCase):
    """instrument.instrument(copy, markers=False): the probe copied in and registered first, as for a measured run,
    but no counter bump anywhere (the copy's scenes/ stay byte-identical to the repo's), and a map of no statements.
    It is what `coverage.py run --uninstrumented` plays: the same matches without the counters' cost."""

    @classmethod
    def setUpClass(cls):
        cls.src = project_repo(class_tempdir(cls))
        cls.copy = workspace.create(cls.src)
        cls.addClassCleanup(workspace.cleanup, cls.src, cls.copy)
        cls.map = instrument.instrument(cls.copy, markers=False)

    def test_no_script_is_touched(self):
        self.assertEqual(tree_digest(self.copy, ("scenes",)), tree_digest(self.src, ("scenes",)))
        for f in (self.copy / "scenes").rglob("*.gd"):
            self.assertNotIn("CoverageProbe.h[", f.read_text(), f)

    def test_the_probe_is_still_the_first_autoload(self):
        first = autoloads((self.copy / "project.godot").read_text())[0]
        self.assertEqual(first[0], "CoverageProbe")
        self.assertTrue((self.copy / instrument.PROBE_PATH).is_file())

    def test_the_map_has_no_statements_and_its_own_hash(self):
        self.assertEqual((self.map["statements"], self.map["uninstrumented"]), ([], []))
        self.assertEqual(self.map["hash"], instrument.map_hash([], []))
        self.assertIn("const COUNT := 0\n", (self.copy / instrument.PROBE_PATH).read_text())


class EngineTests(InstrumentedFixture):
    def godot(self, *args: str) -> str:
        r = subprocess.run([godot_binary(), "--headless", "--path", str(self.copy), *args], capture_output=True,
                           text=True, timeout=120, stdin=subprocess.DEVNULL)
        return r.stdout + r.stderr

    def test_the_line_an_engine_error_names_is_the_source_line(self):
        out = self.godot("res://scenes/errors/error_scene.tscn")
        self.assertIn("Nonexistent function 'missing_method'", out)
        self.assertIn("res://scenes/errors/error_scene.gd:9", out, out)

    def test_the_copy_loads_and_runs_without_an_error_or_warning(self):
        log = self.copy / "load_check.log"
        self.godot("--quit-after", "60", "--log-file", str(log))
        scan = subprocess.run([sys.executable, str(ROOT / "tools" / "scan_godot_log.py"), str(log)], capture_output=True,
                              text=True)
        self.assertEqual(scan.returncode, 0, scan.stdout)


@needs_godot
class WatchMatchHitsTests(unittest.TestCase):
    """One Watch match of seed 100 through the fixture repo's own `coverage.py run`, against the expected hits."""

    @classmethod
    def setUpClass(cls):
        cls.repo = fixture_repo(class_tempdir(cls))
        cls.result = run_cli(cls.repo, "run", "--matches=1", "--seed=100", "--jobs=1")
        if cls.result.returncode != 0:
            raise AssertionError(f"coverage.py run failed:\n{cls.result.stdout}\n{cls.result.stderr}")
        folder = newest_run(cls.repo, "matches")
        cls.map = read_json(folder / "map.json")
        cls.hits = read_json(folder / "hits.json")

    def hits_by_key(self) -> dict[tuple, list[int]]:
        totals = collections.Counter()
        for u in self.hits["units"]:
            for sid, n in u["counts"].items():
                totals[int(sid)] += n
        found = collections.defaultdict(list)
        for s in self.map["statements"]:
            found[statement_key(s)].append(totals[s["id"]])
        return {k: sorted(v) for k, v in found.items()}

    def test_every_statement_has_its_expected_hits(self):
        got = self.hits_by_key()
        want = collections.defaultdict(list)
        for s in expected()["statements"]:
            if s["hits"] is not None:
                want[statement_key(s)].append(s["hits"])
        wrong = {k: (got.get(k), sorted(v)) for k, v in want.items() if got.get(k) != sorted(v)}
        self.assertEqual(wrong, {}, "statement: (hits, expected)")

    def test_exactly_one_side_count_arm_ran(self):
        got = self.hits_by_key()
        arms = [k for k in got if k[0] == "scenes/game/match_logic.gd" and k[3] == "side_count" and k[2] == "branch"]
        self.assertEqual(len(arms), 5)
        self.assertEqual(sorted(got[k][0] for k in arms), [0, 0, 0, 0, 1])

    def test_callbacks_reached_through_the_scene_and_by_name_count(self):
        got = self.hits_by_key()
        self.assertEqual(got[("scenes/main.gd", 60, "function", "_on_worker_pinged", "")], [1], "the .tscn connection")
        self.assertEqual(got[("scenes/main.gd", 70, "function", "_by_name", "")], [1], 'call("_by_name")')

    def test_a_function_never_called_reports_zero(self):
        got = self.hits_by_key()
        self.assertEqual(got[("scenes/game/match_logic.gd", 37, "function", "never_called", "")], [0])

    def test_the_hits_belong_to_the_map(self):
        self.assertEqual(self.hits["map_hash"], self.map["hash"])


if __name__ == "__main__":
    unittest.main()
