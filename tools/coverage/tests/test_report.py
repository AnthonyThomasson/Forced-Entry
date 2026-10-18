"""Tests for tools/coverage/report.py (rollup, tags, curve, Markdown and JSON), tools/coverage/static_refs.py (the
thin adapter over audit_scan) and the `coverage.py report` command.

  report.build(runs, unreferenced, domain=None) -> dict
      runs: [{"meta": meta.json, "map": map.json, "hits": hits.json}], a matches run and/or a tests run
      unreferenced: {(file, function)} the functions nothing references (static_refs.unreferenced)
      domain: only that domain's files (the first folder under scenes/)
    returns the report JSON:
      warnings        [str]: the runs' commits differ (naming both), or their map hashes differ (then the runs are
                      joined by (file, line, kind) instead of by statement id)
      matches_total   how many matches the matches run holds
      domains         [{domain, files: [{file, functions: [{function, class, line, match_hits, matches_fired,
                      test_hits, tests: {count, ids (up to 3)}, tags, uncovered, dead_branches}]}]}]
                      `line` is the function's first body statement; match_hits / test_hits its hits; matches_fired
                      the matches it ran in; `tests` the tests that ran it; `uncovered` the [first, last] line
                      ranges of its statements with no hit in any run (a range runs on until a statement with hits);
                      `dead_branches` the lines of its branch arms with no hit while the function has hits
      curve           [{matches: k, new_functions, new_lines}] per match added, in seed order then match number over
                      every matches run (several runs read as one run of all their matches)
      uninstrumented  the maps' uninstrumented spans
      limits          [str]: what zero hits does and does not mean
  report.markdown(report) -> str      the same as Markdown: the rollup with the tags, a saturation section, an
                                      uninstrumented section (each span as `file:line`) and a limits section
  static_refs.unreferenced(root) -> {(file, function)}   audit_scan's "Functions nothing references", for `root`

Tags, from the brief: dead (no hits anywhere, nothing references it), dead branch (a branch arm with no hits in a
function with hits), test-only (hits in tests, none in matches), untriggered system (no hits anywhere, but
referenced), rare (fired in fewer than 10% of matches), live-but-unpinned (hits in matches, none in tests) and noise
(scenes/testing/, the dev command server, debug overlays, settings menus: tagged, never hidden).

`coverage.py report [--domain=x] [--run=DIR...]` combines the newest matches run and the newest tests run of HEAD
under artifacts/coverage/ (or the --run folders given), prints the Markdown report naming the run folders it
combined, and warns when their commits differ.

All data here is written by hand: one map, twenty matches and five tests, and the tags and numbers they must give.
"""
import json
import os
import re
import unittest
from pathlib import Path

from tools.coverage import report, static_refs
from tools.coverage.tests.support import TempDir, fixture_repo, git, run_cli

COMMIT = "a" * 40
OTHER = "b" * 40
TAGS = ("dead", "dead branch", "test-only", "untriggered system", "rare", "live-but-unpinned", "noise")


def st(sid, file, line, kind, function, cls=""):
    return {"id": sid, "file": file, "line": line, "kind": kind, "function": function, "class": cls}


BRAIN, GUN = "scenes/ai/brain.gd", "scenes/items/gun.gd"
STATEMENTS = [
    st(0, BRAIN, 3, "function", "think"),
    st(1, BRAIN, 4, "statement", "think"),        # if
    st(2, BRAIN, 5, "branch", "think"),           # if body: tests only
    st(3, BRAIN, 7, "branch", "think"),           # elif body: never
    st(4, BRAIN, 9, "branch", "think"),           # else body: matches
    st(5, BRAIN, 10, "statement", "think"),
    st(6, BRAIN, 13, "function", "plan"),         # first match only
    st(7, BRAIN, 14, "statement", "plan"),
    st(8, BRAIN, 15, "branch", "plan"),           # for body: never
    st(9, BRAIN, 17, "statement", "plan"),        # never
    st(10, BRAIN, 20, "function", "lonely"),      # never, unreferenced
    st(11, GUN, 3, "function", "fire"),           # tests only
    st(12, GUN, 4, "statement", "fire"),
    st(13, GUN, 7, "function", "reload_quirk"),   # never, referenced
    st(14, GUN, 10, "function", "steady"),        # matches 4 and 5 of 20, test t/a
    st(15, GUN, 11, "statement", "steady"),
    st(16, "scenes/testing/helper.gd", 3, "function", "assist"),            # tests only
    st(17, "scenes/general/command_server.gd", 3, "function", "serve"),     # never, referenced
    st(18, "scenes/ui/menus/settings_menu.gd", 3, "function", "open"),      # never, unreferenced
    st(19, "scenes/ai/debug/overlay.gd", 3, "function", "draw_it"),         # never, referenced
]
SPAN = {"file": BRAIN, "line": 22, "end_line": 24, "reason": "a statement starts on the closing line of a string"}
MAP = {"format": "fe-coverage-map", "version": 1, "hash": "map-one", "statements": STATEMENTS, "uninstrumented": [SPAN]}
UNREFERENCED = {(BRAIN, "lonely"), ("scenes/ui/menus/settings_menu.gd", "open")}


def match_unit(i: int) -> dict:
    counts = {0: 1, 1: 1, 4: 1, 5: 1}
    if i == 0:
        counts |= {6: 1, 7: 1}
    if i in (3, 4):
        counts |= {14: 1, 15: 1}
    return {"id": f"{1000 + i}-1", "seed": 1000 + i, "mode": "watch", "match": 1, "verdict": "DEFENDER WINS",
            "duration": 60.0, "counts": {str(k): v for k, v in counts.items()}}


def test_unit(test_id: str) -> dict:
    counts = {0: 1, 1: 1, 2: 1, 5: 1}
    if test_id == "t/a":
        counts |= {11: 1, 12: 1, 14: 1, 15: 1, 16: 1}
    if test_id == "t/b":
        counts |= {11: 1, 12: 1}
    return {"id": test_id, "counts": {str(k): v for k, v in counts.items()}}


TEST_IDS = ["t/a", "t/b", "t/c", "t/d", "t/e"]


def hits_file(source, units, map_hash="map-one"):
    return {"format": "fe-coverage-hits", "version": 1, "map_hash": map_hash, "source": source, "units": units}


def meta(source, commit=COMMIT, map_hash="map-one", time="2026-10-17T10:00:00Z", **extra):
    return {"commit": commit, "time": time, "source": source, "scenes_hash": "s" * 64, "map_hash": map_hash,
            "windowed": False, **extra}


def matches_run(commit=COMMIT):
    units = [match_unit(i) for i in range(20)]
    return {"meta": meta("matches", commit, seeds=[u["seed"] for u in units],
                         matches=[{k: u[k] for k in ("seed", "mode", "match", "verdict", "duration")} for u in units]),
            "map": MAP, "hits": hits_file("matches", units)}


def tests_run(commit=COMMIT):
    return {"meta": meta("tests", commit), "map": MAP, "hits": hits_file("tests", [test_unit(t) for t in TEST_IDS])}


def reshuffled_tests_run():
    """The tests run with a map of the same statements numbered the other way round (another hash), its hits
    renumbered to match: what a run of a slightly different build looks like."""
    n = len(STATEMENTS)
    flipped = [dict(s, id=n - 1 - s["id"]) for s in STATEMENTS]
    smap = dict(MAP, hash="map-two", statements=sorted(flipped, key=lambda s: s["id"]))
    units = []
    for t in TEST_IDS:
        u = test_unit(t)
        units.append({**u, "counts": {str(n - 1 - int(k)): v for k, v in u["counts"].items()}})
    return {"meta": meta("tests", map_hash="map-two"), "map": smap, "hits": hits_file("tests", units, "map-two")}


def functions(rep: dict) -> dict[tuple[str, str], dict]:
    return {(f["file"], fn["function"]): fn for d in rep["domains"] for f in d["files"] for fn in f["functions"]}


class TagTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rep = report.build([matches_run(), tests_run()], UNREFERENCED)
        cls.fns = functions(cls.rep)

    def tags(self, file, name):
        return set(self.fns[(file, name)]["tags"])

    def test_an_unreferenced_never_run_function_is_dead(self):
        self.assertIn("dead", self.tags(BRAIN, "lonely"))
        self.assertNotIn("untriggered system", self.tags(BRAIN, "lonely"))

    def test_a_never_taken_elif_in_a_live_function_is_a_dead_branch(self):
        think = self.fns[(BRAIN, "think")]
        self.assertIn("dead branch", think["tags"])
        self.assertEqual(think["dead_branches"], [7])
        self.assertTrue(set(think["tags"]).isdisjoint({"dead", "untriggered system", "test-only"}), think["tags"])

    def test_a_function_run_only_by_tests_is_test_only(self):
        self.assertIn("test-only", self.tags(GUN, "fire"))
        self.assertNotIn("dead", self.tags(GUN, "fire"))

    def test_a_referenced_never_run_function_is_an_untriggered_system(self):
        self.assertIn("untriggered system", self.tags(GUN, "reload_quirk"))
        self.assertNotIn("dead", self.tags(GUN, "reload_quirk"))

    def test_rare_is_fewer_than_ten_percent_of_matches(self):
        self.assertIn("rare", self.tags(BRAIN, "plan"), "1 match of 20")
        self.assertNotIn("rare", self.tags(GUN, "steady"), "2 matches of 20 is not fewer than 10%")
        self.assertNotIn("rare", self.tags(BRAIN, "think"))

    def test_hits_in_matches_and_none_in_tests_is_live_but_unpinned(self):
        self.assertIn("live-but-unpinned", self.tags(BRAIN, "plan"))
        self.assertNotIn("live-but-unpinned", self.tags(BRAIN, "think"))
        self.assertNotIn("live-but-unpinned", self.tags(GUN, "steady"))

    def test_noise_is_tagged_and_still_listed_with_its_other_tags(self):
        self.assertEqual(self.tags("scenes/testing/helper.gd", "assist") & {"noise", "test-only"}, {"noise", "test-only"})
        self.assertEqual(self.tags("scenes/general/command_server.gd", "serve") & {"noise", "untriggered system"},
                         {"noise", "untriggered system"})
        self.assertEqual(self.tags("scenes/ui/menus/settings_menu.gd", "open") & {"noise", "dead"}, {"noise", "dead"})
        self.assertIn("noise", self.tags("scenes/ai/debug/overlay.gd", "draw_it"))
        for file, name in ((BRAIN, "think"), (GUN, "fire"), (BRAIN, "lonely")):
            self.assertNotIn("noise", self.tags(file, name))

    def test_a_plain_live_and_pinned_function_has_no_tag(self):
        self.assertEqual(self.tags(GUN, "steady"), set())

    def test_every_tag_is_one_of_the_documented_ones(self):
        for key, fn in self.fns.items():
            self.assertTrue(set(fn["tags"]) <= set(TAGS), (key, fn["tags"]))


class RollupTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rep = report.build([matches_run(), tests_run()], UNREFERENCED)
        cls.fns = functions(cls.rep)

    def test_rollup_is_domain_then_file_then_function(self):
        domains = {d["domain"]: {f["file"] for f in d["files"]} for d in self.rep["domains"]}
        self.assertEqual(domains, {
            "ai": {BRAIN, "scenes/ai/debug/overlay.gd"},
            "items": {GUN},
            "testing": {"scenes/testing/helper.gd"},
            "general": {"scenes/general/command_server.gd"},
            "ui": {"scenes/ui/menus/settings_menu.gd"},
        })

    def test_columns_of_a_function(self):
        think = self.fns[(BRAIN, "think")]
        self.assertEqual((think["line"], think["class"]), (3, ""))
        self.assertEqual((think["match_hits"], think["matches_fired"], think["test_hits"]), (20, 20, 5))
        self.assertEqual(think["tests"]["count"], 5)
        self.assertEqual(len(think["tests"]["ids"]), 3, "up to three test ids")
        self.assertTrue(set(think["tests"]["ids"]) <= set(TEST_IDS))
        fire = self.fns[(GUN, "fire")]
        self.assertEqual((fire["match_hits"], fire["matches_fired"], fire["test_hits"]), (0, 0, 2))
        self.assertEqual((fire["tests"]["count"], sorted(fire["tests"]["ids"])), (2, ["t/a", "t/b"]))
        steady = self.fns[(GUN, "steady")]
        self.assertEqual((steady["match_hits"], steady["matches_fired"], steady["test_hits"]), (2, 2, 1))
        self.assertEqual(self.rep["matches_total"], 20)

    def test_uncovered_line_ranges(self):
        self.assertEqual(self.fns[(BRAIN, "think")]["uncovered"], [[7, 7]])
        self.assertEqual(self.fns[(BRAIN, "plan")]["uncovered"], [[15, 17]], "line 16 holds no statement")
        self.assertEqual(self.fns[(BRAIN, "plan")]["dead_branches"], [15])
        self.assertEqual(self.fns[(BRAIN, "lonely")]["uncovered"], [[20, 20]])
        self.assertEqual(self.fns[(GUN, "steady")]["uncovered"], [])

    def test_saturation_curve_counts_what_each_added_match_covers_first(self):
        curve = self.rep["curve"]
        self.assertEqual([c["matches"] for c in curve], list(range(1, 21)))
        self.assertEqual([c["new_functions"] for c in curve], [2, 0, 0, 1] + [0] * 16)
        self.assertEqual([c["new_lines"] for c in curve], [6, 0, 0, 2] + [0] * 16)

    def test_uninstrumented_spans_and_limits_are_carried(self):
        self.assertIn(SPAN, self.rep["uninstrumented"])
        self.assertTrue(any("did not run in the sampled matches" in limit for limit in self.rep["limits"]),
                        self.rep["limits"])

    def test_domain_filter(self):
        rep = report.build([matches_run(), tests_run()], UNREFERENCED, domain="items")
        self.assertEqual([d["domain"] for d in rep["domains"]], ["items"])
        self.assertEqual(set(functions(rep)), {(GUN, "fire"), (GUN, "reload_quirk"), (GUN, "steady")})

    def test_the_report_is_plain_json(self):
        self.assertEqual(json.loads(json.dumps(self.rep)), self.rep)


OUTSIDE_UNIT = {"id": "", "outside": True, "counts": {"17": 1, "19": 3}}  # serve and draw_it, run between tests


class OutsideTestsTests(unittest.TestCase):
    """A tests run's `outside` unit holds the hits made while no test was running (the runner's start-up, each
    test's teardown after its verdict): that code ran, so it is never dead or an untriggered system, but no test pins it."""

    def setUp(self):
        run = tests_run()
        run["hits"]["units"].append(OUTSIDE_UNIT)
        self.rep = report.build([matches_run(), run], UNREFERENCED)
        self.fns = functions(self.rep)

    def test_code_run_outside_any_test_is_neither_dead_nor_untriggered(self):
        for name in (("scenes/general/command_server.gd", "serve"), ("scenes/ai/debug/overlay.gd", "draw_it")):
            fn = self.fns[name]
            self.assertNotIn("untriggered system", fn["tags"], name)
            self.assertNotIn("dead", fn["tags"], name)
            self.assertIn("noise", fn["tags"], name)

    def test_outside_hits_are_their_own_column_and_pin_nothing(self):
        serve, draw = self.fns[("scenes/general/command_server.gd", "serve")], self.fns[("scenes/ai/debug/overlay.gd", "draw_it")]
        self.assertEqual((serve["outside_hits"], draw["outside_hits"]), (1, 3))
        self.assertEqual((serve["test_hits"], serve["tests"]["count"]), (0, 0))
        self.assertEqual(self.fns[(BRAIN, "think")]["tests"]["count"], len(TEST_IDS), "the outside unit is no test")
        self.assertEqual(self.fns[(BRAIN, "think")]["outside_hits"], 0)

    def test_the_rest_is_unchanged(self):
        plain = functions(report.build([matches_run(), tests_run()], UNREFERENCED))
        for key, fn in plain.items():
            if key[1] in ("serve", "draw_it"):
                continue
            self.assertEqual(self.fns[key]["tags"], fn["tags"], key)
        self.assertIn("dead", self.fns[(BRAIN, "lonely")]["tags"])

    def test_markdown_shows_the_outside_hits(self):
        md = report.markdown(self.rep)
        row = next(l for l in md.splitlines() if l.startswith("| draw_it |"))
        self.assertIn("+3 outside tests", row)


def rated_matches_run(rates, floor=30.0):
    """The matches run with each match's decided Von walks per NPC per game minute set (None = not measured) and the
    floor the run warned against."""
    run = matches_run()
    run["meta"]["von_floor"] = floor
    for m, rate in zip(run["meta"]["matches"], rates):
        m["decided_per_npc_minute"] = rate
    return run


class VonRateTests(unittest.TestCase):
    """The report header warns when a match of a matches run made fewer Von decisions per NPC per game minute than
    the floor its run recorded (meta `von_floor`): its NPCs were starved, so its coverage is not a normal match's."""

    def test_a_match_below_the_floor_is_warned_about_by_id(self):
        rep = report.build([rated_matches_run([10.0] + [60.0] * 19), tests_run()], UNREFERENCED)
        slow = [w for w in rep["warnings"] if "decisions per NPC per game minute" in w]
        self.assertEqual(len(slow), 1, rep["warnings"])
        self.assertIn("1000-1", slow[0])
        self.assertNotIn("1001-1", slow[0])
        self.assertIn("30", slow[0])
        self.assertIn(slow[0], report.markdown(rep))

    def test_matches_at_or_above_the_floor_or_unmeasured_are_not(self):
        rep = report.build([rated_matches_run([30.0, None] + [60.0] * 18), tests_run()], UNREFERENCED)
        self.assertFalse([w for w in rep["warnings"] if "decisions per NPC" in w], rep["warnings"])


FAILED = [{"id": "t/b", "verdict": "FAIL", "first": "the library renders within budget (10568 ms of 3000)"},
          {"id": "t/c", "verdict": "TIMEOUT", "first": ""}]


class FailedUnderInstrumentationTests(unittest.TestCase):
    """A tests run's meta `failed` (the tests that failed or timed out in the instrumented copy) is listed in its own
    section, with the note that wall-clock budgets fail from the counters' cost; their hits still count."""

    def setUp(self):
        run = tests_run()
        run["meta"]["failed"] = FAILED
        self.rep = report.build([matches_run(), run], UNREFERENCED)

    def test_the_report_lists_them(self):
        self.assertEqual(self.rep["failed_tests"], FAILED)

    def test_the_markdown_has_the_section_and_the_note(self):
        md = report.markdown(self.rep)
        section = md.split("## Failed under instrumentation", 1)
        self.assertEqual(len(section), 2, "the section exists")
        body = section[1].split("\n## ", 1)[0]
        self.assertIn("t/b", body)
        self.assertIn("10568 ms of 3000", body)
        self.assertIn("t/c", body)
        self.assertIn("TIMEOUT", body)
        self.assertIn("counters", body)

    def test_none_failed_says_so(self):
        md = report.markdown(report.build([matches_run(), tests_run()], UNREFERENCED))
        self.assertIn("## Failed under instrumentation", md)
        self.assertIn("(none)", md.split("## Failed under instrumentation", 1)[1].split("\n## ", 1)[0])

    def test_their_hits_still_count(self):
        plain = functions(report.build([matches_run(), tests_run()], UNREFERENCED))
        self.assertEqual(functions(self.rep), plain)


CRASHED = [{"seed": 1007, "mode": "watch", "process": 7, "pid": 4242, "exit": -6, "phase": "after the last flush",
            "log": "artifacts/coverage/x-matches/crashed/godot_7.out",
            "message": "libc++abi: terminating due to uncaught exception of type std::__1::system_error"}]


class CrashedAfterLastFlushTests(unittest.TestCase):
    """A matches run's meta `crashed` (game processes that exited non-zero at quit after their last flush, every
    match of theirs decided and recorded) is listed in its own section with the exit, the phase, the message and the
    log; their hits still count."""

    def setUp(self):
        run = matches_run()
        run["meta"]["crashed"] = CRASHED
        self.rep = report.build([run, tests_run()], UNREFERENCED)

    def test_the_report_lists_them(self):
        self.assertEqual(self.rep["crashed"], CRASHED)

    def test_the_markdown_has_the_section(self):
        md = report.markdown(self.rep)
        section = md.split("## Crashed after the last flush", 1)
        self.assertEqual(len(section), 2, "the section exists")
        body = section[1].split("\n## ", 1)[0]
        for part in ("1007", "-6", "after the last flush", "libc++abi", "crashed/godot_7.out"):
            self.assertIn(part, body)

    def test_none_crashed_says_so(self):
        md = report.markdown(report.build([matches_run(), tests_run()], UNREFERENCED))
        self.assertIn("(none)", md.split("## Crashed after the last flush", 1)[1].split("\n## ", 1)[0])

    def test_their_hits_still_count(self):
        plain = functions(report.build([matches_run(), tests_run()], UNREFERENCED))
        self.assertEqual(functions(self.rep), plain)


def chunk_runs(size: int) -> list[dict]:
    """matches_run's twenty matches as matches runs of `size` matches each (seeds 1000.., in order), as
    `coverage.py run --matches=size --seed=1000+k*size` would give them, each with its own time."""
    whole = matches_run()
    units = whole["hits"]["units"]
    out = []
    for k in range(0, len(units), size):
        part = units[k:k + size]
        seeds = [u["seed"] for u in part]
        out.append({"meta": meta("matches", time=f"2026-10-17T1{k // size}:00:00Z", seeds=seeds,
                                 matches=[m for m in whole["meta"]["matches"] if m["seed"] in seeds]),
                    "map": MAP, "hits": hits_file("matches", part)})
    return out


class ChunkedMatchesRunsTests(unittest.TestCase):
    """A report over several matches runs (one run played in chunks) is the report of one run of all their matches:
    hits summed, matches counted over all of them, and the saturation curve over every match in seed order (then
    match number), whatever order the runs are given in. Runs that repeat a match are warned about."""

    @classmethod
    def setUpClass(cls):
        cls.whole = report.build([matches_run(), tests_run()], UNREFERENCED)

    def test_chunks_in_order_give_the_whole_runs_report(self):
        rep = report.build([*chunk_runs(4), tests_run()], UNREFERENCED)
        self.assertEqual(rep["matches_total"], 20)
        self.assertEqual(functions(rep), functions(self.whole))
        self.assertEqual(rep["curve"], self.whole["curve"])

    def test_chunks_in_any_order_give_the_curve_in_seed_order(self):
        chunks = chunk_runs(4)
        for order in (chunks[::-1], [chunks[2], chunks[0], chunks[4], chunks[1], chunks[3]]):
            rep = report.build([tests_run(), *order], UNREFERENCED)
            self.assertEqual(rep["curve"], self.whole["curve"], [r["meta"]["seeds"][0] for r in order])
            self.assertEqual(functions(rep), functions(self.whole))

    def test_an_endless_process_keeps_its_matches_in_order(self):
        runs = chunk_runs(4)
        later = runs[0]["hits"]["units"]
        first = later[0]
        # seed 1000 becomes an Endless process of two matches, its second one the first to run steady (14, 15)
        runs[0]["hits"]["units"] = [dict(first, mode="endless", match=2, id="1000-2",
                                         counts={**first["counts"], "14": 1, "15": 1}),
                                    dict(first, mode="endless")] + later[1:]
        rep = report.build(runs[::-1] + [tests_run()], UNREFERENCED)
        self.assertEqual([c["new_functions"] for c in rep["curve"][:5]], [2, 1, 0, 0, 0])

    def test_runs_that_repeat_a_match_are_warned_about(self):
        chunks = chunk_runs(4)
        rep = report.build([*chunks, chunks[1], tests_run()], UNREFERENCED)
        repeated = [w for w in rep["warnings"] if "repeat" in w]
        self.assertEqual(len(repeated), 1, rep["warnings"])
        self.assertIn("1004-1", repeated[0])
        self.assertNotIn("1000-1", repeated[0])
        self.assertFalse([w for w in self.whole["warnings"] if "repeat" in w])


class CombineTests(unittest.TestCase):
    def test_runs_of_one_commit_and_one_map_carry_no_such_warning(self):
        rep = report.build([matches_run(), tests_run()], UNREFERENCED)
        self.assertFalse([w for w in rep["warnings"] if re.search(r"(?i)commit|map", w)], rep["warnings"])

    def test_mixed_commits_are_warned_about_naming_both(self):
        rep = report.build([matches_run(COMMIT), tests_run(OTHER)], UNREFERENCED)
        self.assertTrue(any(COMMIT[:7] in w and OTHER[:7] in w for w in rep["warnings"]), rep["warnings"])

    def test_different_maps_are_joined_by_file_line_and_kind_with_a_warning(self):
        rep = report.build([matches_run(), reshuffled_tests_run()], UNREFERENCED)
        self.assertTrue(any(re.search(r"(?i)map", w) for w in rep["warnings"]), rep["warnings"])
        fns = functions(rep)
        self.assertIn("test-only", fns[(GUN, "fire")]["tags"])
        self.assertEqual(fns[(GUN, "fire")]["test_hits"], 2)
        self.assertEqual(fns[(BRAIN, "think")]["dead_branches"], [7])
        self.assertEqual(fns[(BRAIN, "think")]["test_hits"], 5)

    def test_a_matches_run_alone_still_reports(self):
        rep = report.build([matches_run()], UNREFERENCED)
        self.assertEqual(functions(rep)[(GUN, "fire")]["test_hits"], 0)


class MarkdownTests(unittest.TestCase):
    def test_markdown_holds_the_rollup_tags_and_sections(self):
        md = report.markdown(report.build([matches_run(), tests_run()], UNREFERENCED))
        for tag in TAGS:
            self.assertIn(tag, md)
        for name in ("think", "plan", "lonely", "fire", "reload_quirk", "steady"):
            self.assertIn(name, md)
        for section in ("saturation", "uninstrumented", "limits"):
            self.assertRegex(md, rf"(?im)^#+ .*{section}", f"a {section} section")
        self.assertIn("scenes/ai/brain.gd:22", md)
        self.assertIn("did not run in the sampled matches", md)


class StaticRefsTests(unittest.TestCase):
    def test_unreferenced_lists_the_functions_nothing_references(self):
        with TempDir() as root:
            (root / "scenes").mkdir()
            (root / "scenes" / "a.gd").write_text(
                "extends Node\n\n\nfunc _ready() -> void:\n\tpass\n\n\nfunc used() -> void:\n\tpass\n\n\n"
                "func lonely() -> void:\n\tpass\n")
            (root / "scenes" / "b.gd").write_text("extends Node\n\n\nfunc _ready() -> void:\n\t$A.used()\n")
            self.assertEqual(static_refs.unreferenced(root), {("scenes/a.gd", "lonely")})


def write_run(repo: Path, name: str, run: dict, mtime: float) -> Path:
    folder = repo / "artifacts" / "coverage" / name
    folder.mkdir(parents=True)
    for key, file in (("meta", "meta.json"), ("map", "map.json"), ("hits", "hits.json")):
        (folder / file).write_text(json.dumps(run[key]))
    os.utime(folder, (mtime, mtime))
    return folder


class ReportCommandTests(unittest.TestCase):
    def test_report_combines_the_newest_matches_and_tests_runs_of_head(self):
        with TempDir() as d:
            repo = fixture_repo(d)
            head = git(repo, "rev-parse", "HEAD").strip()
            runs = {
                f"{head}-20261017T100000Z-matches": (matches_run(head), 1_000_000),
                f"{head}-20261017T103000Z-tests": (tests_run(head), 1_001_800),
                f"{head}-20261017T110000Z-matches": (matches_run(head), 1_003_600),
                f"{OTHER}-20261017T120000Z-matches": (matches_run(OTHER), 1_007_200),
            }
            for name, (run, mtime) in runs.items():
                run["meta"]["time"] = f"2026-10-17T{name.split('T')[1][:2]}:{name.split('T')[1][2:4]}:00Z"
                write_run(repo, name, run, mtime)
            r = run_cli(repo, "report")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn(f"{head}-20261017T110000Z-matches", r.stdout)
        self.assertIn(f"{head}-20261017T103000Z-tests", r.stdout)
        self.assertNotIn(f"{head}-20261017T100000Z-matches", r.stdout)
        self.assertNotIn(f"{OTHER}-20261017T120000Z-matches", r.stdout)
        self.assertIn("dead branch", r.stdout)

    def test_report_of_given_runs_warns_when_their_commits_differ(self):
        with TempDir() as d:
            repo = fixture_repo(d)
            a = write_run(repo, f"{COMMIT}-20261017T100000Z-matches", matches_run(COMMIT), 1_000_000)
            b = write_run(repo, f"{OTHER}-20261017T103000Z-tests", tests_run(OTHER), 1_001_800)
            r = run_cli(repo, "report", f"--run={a}", f"--run={b}")
        out = r.stdout + r.stderr
        self.assertTrue(any(COMMIT[:7] in line and OTHER[:7] in line for line in out.splitlines()), out)

    def test_report_out_saves_the_combined_report_and_its_runs(self):
        with TempDir() as d:
            repo = fixture_repo(d)
            chunks = [write_run(repo, f"{COMMIT}-20261017T1{k}0000Z-matches", run, 1_000_000 + k)
                      for k, run in enumerate(chunk_runs(10))]
            tests = write_run(repo, f"{COMMIT}-20261017T150000Z-tests", tests_run(), 1_002_000)
            out = repo / "artifacts" / "coverage" / "first-report"
            args = ["report", *(f"--run={c}" for c in chunks), f"--run={tests}", f"--out={out}"]
            r = run_cli(repo, *args)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            saved = json.loads((out / "report.json").read_text())
            md = (out / "report.md").read_text()
            runs = json.loads((out / "runs.json").read_text())
            again = run_cli(repo, *args)
            md_after = (out / "report.md").read_text()
        self.assertEqual(saved["matches_total"], 20)
        self.assertEqual(saved["curve"], report.build([matches_run(), tests_run()], UNREFERENCED)["curve"])
        self.assertIn(md, r.stdout, "the saved Markdown is the printed report")
        self.assertEqual([x["folder"] for x in runs], [c.name for c in chunks] + [tests.name])
        self.assertEqual([x["source"] for x in runs], ["matches", "matches", "tests"])
        self.assertIn(str(out), r.stdout)
        self.assertNotEqual(again.returncode, 0, "a folder that already holds a report is never overwritten")
        self.assertIn("already", again.stderr)
        self.assertEqual(md_after, md)

    def test_report_domain_filter(self):
        with TempDir() as d:
            repo = fixture_repo(d)
            a = write_run(repo, f"{COMMIT}-20261017T100000Z-matches", matches_run(), 1_000_000)
            b = write_run(repo, f"{COMMIT}-20261017T103000Z-tests", tests_run(), 1_001_800)
            r = run_cli(repo, "report", "--domain=items", f"--run={a}", f"--run={b}")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("reload_quirk", r.stdout)
        self.assertNotIn("scenes/ai/brain.gd", r.stdout)


if __name__ == "__main__":
    unittest.main()
