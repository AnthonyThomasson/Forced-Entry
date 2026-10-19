"""Tests for tools/coverage/runner.py (the match and test drivers, sharding) and the tools/coverage.py CLI.

The CLI is driven the way an agent drives it, on the fixture project made a git repo with the tool copied in
(support.fixture_repo): its own tools/coverage.py works on it as the real one works on Forced-Entry.

  coverage.py instrument                    builds the instrumented copy directly in the repo's artifacts/tmp/ and
                                            prints its path as the last line; the rest of the repo is untouched
  coverage.py run [--matches=24] [--jobs=2] [--seed=N] [--endless-every=4] [--windowed] [--uninstrumented]
      Process i plays seed base+i in Watch mode with both sides the same size, cycled 1v1..5v5 by the seed; every
      `endless-every`-th process plays an Endless run of 3 matches instead. The probe starts each match by emitting
      the setup window's start_requested(config) and caps it at Main's endless_time_limit. `jobs` processes at a
      time, 2 when not given; --jobs=auto is the core count, at most 6.
  coverage.py run --tests [run_tests args...]
      Runs the copy's own tools/run_tests.sh with --skip-domain=perf added and the args passed on (its --jobs too;
      none added when not given); the probe keeps the statements each test ran (its unit is the test id).
  Every run writes artifacts/coverage/<sha>-<time>-<matches|tests>/ holding hits.json, map.json, meta.json,
  report.md and report.json, then checks that the repo is byte-identical to before (git status and the
  scenes/ + project.godot hash) and fails loudly, naming what changed, if not. Its copy and hit folder are made
  directly in artifacts/tmp/; however the run ends (done, failed, raised, Ctrl-C, SIGTERM) it stops the game
  processes it started and leaves nothing there, unless --keep (it names both). A run killed with SIGKILL leaves its
  folders; the next run sweeps them, never those of a run still alive.

  meta.json: commit (HEAD, at least 7 hex digits of it), time, source (matches | tests), scenes_hash
  (workspace.tree_hash of the repo), map_hash (map.json's hash), windowed (bool); for matches also seeds (in process
  order) and matches ([{seed, mode, match, verdict, duration}], duration in game seconds).

  runner.plan_matches(matches, seed, endless_every) -> [{index, seed, mode, matches, defenders, invaders}]
  runner.resolve_jobs(value) -> int          "auto" = min(core count, 6); a number as given; anything else ValueError
  runner.launch(copy, entry, hits_dir, windowed=False) -> subprocess.Popen
                                            starts one game process of an instrumented copy for one plan entry, its
                                            probe flushing coverage_hits_<pid>.json into `hits_dir` every 5 s

The fixture game (fixtures/project/scenes/main.gd) plays a match a few frames long; a seed of 9000 or more is a
stalemate that never ends on its own (near real time), for the time cap and the kill -9 tests.
"""
import collections
import os
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
import unittest
from unittest import mock
from pathlib import Path

from tools.coverage import hits, instrument, runner, workspace
from tools.coverage.tests.support import (
    ROOT, RUN_FILES, class_tempdir, env_with_godot, fixture_repo, git, git_status, needs_godot, newest_run, project_repo,
    read_json, run_cli, run_folders, slow, tree_digest, wait_for, TempDir,
)

FOLDER = re.compile(r"^(?P<sha>[0-9a-f]{7,40})-(?P<time>.+)-(?P<kind>matches|tests)$")


def scratch_left(repo: Path) -> list[str]:
    """What is left in the repo's artifacts/tmp/, where a run makes its copy and its hit folder ([] when it is gone)."""
    tmp = repo / "artifacts" / "tmp"
    return sorted(p.name for p in tmp.iterdir()) if tmp.is_dir() else []


def ids_of(smap: dict, file: str, line: int, kind: str) -> list[int]:
    return [s["id"] for s in smap["statements"] if (s["file"], s["line"], s["kind"]) == (file, line, kind)]


def one_id(smap: dict, file: str, line: int, kind: str) -> int:
    found = ids_of(smap, file, line, kind)
    if len(found) != 1:
        raise AssertionError(f"one statement at {file}:{line} ({kind}) in the map, found {found}")
    return found[0]


def count(unit: dict, sid: int) -> int:
    return unit["counts"].get(str(sid), 0)


def counts_by_unit(data: dict) -> dict:
    return {u["id"]: u["counts"] for u in data["units"]}


EVERY_MATCH = ("scenes/game/match_logic.gd", 7, "function")
NEVER_CALLED = ("scenes/game/match_logic.gd", 37, "function")
EVEN = ("scenes/game/match_logic.gd", 12, "branch")
ODD = ("scenes/game/match_logic.gd", 14, "branch")
SIDE_ARMS = {1: 20, 2: 22, 3: 24, 4: 26, 5: 28}  # side_count's arm for each count, scenes/game/match_logic.gd
TEARDOWN = ("scenes/game/match_logic.gd", 32, "function")
STALL_LOOP = ("scenes/worker.gd", 16, "branch")
ALPHA = ("scenes/game/test_targets.gd", 7, "function")
BETA = ("scenes/game/test_targets.gd", 11, "function")
HEAVY = ("scenes/game/test_targets.gd", 15, "function")
TEARDOWN_TARGET = ("scenes/game/test_targets.gd", 19, "function")
RUNNER_CLOSE = ("scenes/testing/test_runner.gd", 72, "function")  # the fixture runner's _close, run after each test


class PlanTests(unittest.TestCase):
    def test_process_i_plays_seed_base_plus_i(self):
        plan = runner.plan_matches(24, 1000, 4)
        self.assertEqual([e["index"] for e in plan], list(range(24)))
        self.assertEqual([e["seed"] for e in plan], list(range(1000, 1024)))

    def test_every_nth_process_plays_an_endless_run_of_three_matches(self):
        plan = runner.plan_matches(24, 1000, 4)
        endless = [e["index"] for e in plan if e["mode"] == "endless"]
        self.assertEqual(len(endless), 6)
        self.assertEqual(len({i % 4 for i in endless}), 1, f"spaced 4 apart: {endless}")
        for e in plan:
            self.assertEqual(e["matches"], 3 if e["mode"] == "endless" else 1, e)
            self.assertIn(e["mode"], ("watch", "endless"))
        self.assertEqual(sum(e["mode"] == "endless" for e in runner.plan_matches(8, 0, 2)), 4)

    def test_both_sides_are_the_same_size_cycled_1v1_to_5v5_by_the_seed(self):
        plan = runner.plan_matches(24, 1000, 4)
        by_seed = {e["seed"]: e["defenders"] for e in plan}
        for e in plan:
            self.assertEqual(e["defenders"], e["invaders"], e)
            self.assertIn(e["defenders"], range(1, 6), e)
        for start in range(1000, 1019):
            self.assertEqual(sorted(by_seed[s] for s in range(start, start + 5)), [1, 2, 3, 4, 5])
            self.assertEqual(by_seed[start], by_seed[start + 5])
        other = runner.plan_matches(5, 1005, 4)
        self.assertEqual([e["defenders"] for e in other], [by_seed[s] for s in range(1005, 1010)],
                         "the count follows the seed, not the process index")

    def test_chunks_of_a_multiple_of_endless_every_play_the_same_plan_as_one_run(self):
        def played(plan):
            return [(e["seed"], e["mode"], e["matches"], e["defenders"], e["invaders"]) for e in plan]
        whole = played(runner.plan_matches(24, 1000, 4))
        for k in (4, 8, 12):
            with self.subTest(chunk=k):
                chunks = [e for b in range(1000, 1024, k) for e in played(runner.plan_matches(k, b, 4))]
                self.assertEqual(chunks, whole)
        halves = [e for b in range(1000, 1024, 2) for e in played(runner.plan_matches(2, b, 4))]
        self.assertNotEqual(halves, whole, "a chunk of 2 never reaches its every-4th Endless process")

    def test_jobs_auto_is_the_core_count_at_most_six(self):
        self.assertEqual(runner.resolve_jobs("auto"), min(os.cpu_count() or 1, 6))
        self.assertEqual(runner.resolve_jobs("3"), 3)
        for bad in ("lots", "0", "-2"):
            with self.subTest(value=bad), self.assertRaises(ValueError):
                runner.resolve_jobs(bad)


@needs_godot
class WatchRunTests(unittest.TestCase):
    """`run --matches=2 --seed=100`: two Watch matches, seeds 100 and 101, in two processes, two at a time (the
    default `--jobs`)."""

    @classmethod
    def setUpClass(cls):
        cls.repo = fixture_repo(class_tempdir(cls))
        cls.head = git(cls.repo, "rev-parse", "HEAD").strip()
        cls.before = (git_status(cls.repo), tree_digest(cls.repo))
        cls.result = run_cli(cls.repo, "run", "--matches=2", "--seed=100")
        if cls.result.returncode != 0:
            raise AssertionError(f"coverage.py run failed:\n{cls.result.stdout}\n{cls.result.stderr}")
        cls.folder = newest_run(cls.repo, "matches")
        cls.map = read_json(cls.folder / "map.json")
        cls.hits = hits.load(cls.folder / "hits.json")
        cls.meta = read_json(cls.folder / "meta.json")
        cls.units = {u["seed"]: u for u in cls.hits["units"]}

    def test_given_no_jobs_it_plays_two_processes_at_a_time(self):
        self.assertIn("Playing 2 processes from seed 100 (2 matches), 2 at a time", self.result.stdout)

    def test_the_run_folder_is_named_for_the_commit_and_source(self):
        m = FOLDER.match(self.folder.name)
        self.assertIsNotNone(m, self.folder.name)
        self.assertTrue(self.head.startswith(m.group("sha")), (self.head, m.group("sha")))
        self.assertEqual(m.group("kind"), "matches")
        self.assertEqual(len(run_folders(self.repo)), 1)

    def test_the_run_folder_holds_its_files(self):
        for name in RUN_FILES:
            self.assertTrue((self.folder / name).is_file(), name)
        self.assertTrue((self.folder / "report.md").read_text().strip())
        self.assertIsInstance(read_json(self.folder / "report.json"), dict)

    def test_meta_records_the_run(self):
        meta = self.meta
        self.assertTrue(len(meta["commit"]) >= 7 and self.head.startswith(meta["commit"]), meta["commit"])
        self.assertIsInstance(meta["time"], str)
        self.assertEqual(meta["source"], "matches")
        self.assertEqual(meta["scenes_hash"], workspace.tree_hash(self.repo))
        self.assertEqual(meta["map_hash"], self.map["hash"])
        self.assertIs(meta["windowed"], False)
        self.assertEqual(meta["seeds"], [100, 101])
        self.assertEqual(sorted(m["seed"] for m in meta["matches"]), [100, 101])
        for m in meta["matches"]:
            self.assertEqual(m["verdict"], "INVADER WINS", m)
            self.assertTrue(0 < m["duration"] < 5, f"a few frames of game time: {m}")
            self.assertEqual((m["mode"], m["match"]), ("watch", 1), m)

    def test_the_hits_are_one_watch_unit_per_seed_on_this_map(self):
        self.assertEqual((self.hits["source"], self.hits["map_hash"]), ("matches", self.map["hash"]))
        self.assertEqual(sorted(self.units), [100, 101])
        for u in self.hits["units"]:
            self.assertEqual((u["mode"], u["match"], u["verdict"]), ("watch", 1, "INVADER WINS"), u["id"])

    def test_a_function_run_every_match_has_hits_in_every_match_and_one_never_called_has_none(self):
        every = one_id(self.map, *EVERY_MATCH)
        never = one_id(self.map, *NEVER_CALLED)
        for seed, u in self.units.items():
            self.assertEqual(count(u, every), 1, seed)
        self.assertEqual(hits.fired_in(self.hits).get(every), 2)
        self.assertNotIn(never, hits.totals(self.hits))

    def test_each_match_got_its_own_seed(self):
        even, odd = one_id(self.map, *EVEN), one_id(self.map, *ODD)
        self.assertEqual((count(self.units[100], even), count(self.units[100], odd)), (1, 0))
        self.assertEqual((count(self.units[101], even), count(self.units[101], odd)), (0, 1))

    def test_each_match_got_its_planned_side_count(self):
        for entry in runner.plan_matches(2, 100, 4):
            u = self.units[entry["seed"]]
            ran = {n for n, line in SIDE_ARMS.items()
                   if count(u, one_id(self.map, "scenes/game/match_logic.gd", line, "branch"))}
            self.assertEqual(ran, {entry["defenders"]}, entry)

    def test_the_repo_is_byte_identical_after_the_run(self):
        self.assertEqual((git_status(self.repo), tree_digest(self.repo)), self.before)

    def test_nothing_is_left_in_artifacts_tmp(self):
        self.assertEqual(scratch_left(self.repo), [])

    def test_the_run_names_the_run_folder_it_wrote(self):
        self.assertIn(f"Run folder: {self.folder.relative_to(self.repo)}\n", self.result.stdout)


@needs_godot
class ShardTests(unittest.TestCase):
    def test_parallel_shards_give_the_same_hits_as_one_process(self):
        with TempDir() as d:
            repo = fixture_repo(d)
            serial = run_cli(repo, "run", "--matches=3", "--jobs=1", "--seed=200")
            self.assertEqual(serial.returncode, 0, serial.stdout + serial.stderr)
            one = hits.load(newest_run(repo, "matches") / "hits.json")
            time.sleep(1.1)  # a later run folder, whatever resolution its time stamp has
            parallel = run_cli(repo, "run", "--matches=3", "--jobs=3", "--seed=200")
            self.assertEqual(parallel.returncode, 0, parallel.stdout + parallel.stderr)
            many = hits.load(newest_run(repo, "matches") / "hits.json")
            self.assertEqual(len(run_folders(repo, "matches")), 2, "each run has its own folder")
        self.assertEqual(hits.totals(many), hits.totals(one))
        self.assertEqual(counts_by_unit(many), counts_by_unit(one))


@needs_godot
class EndlessRunTests(unittest.TestCase):
    """`run --matches=4 --endless-every=4 --jobs=4 --seed=300`: one of the four processes plays an Endless run."""

    @classmethod
    def setUpClass(cls):
        cls.repo = fixture_repo(class_tempdir(cls))
        r = run_cli(cls.repo, "run", "--matches=4", "--endless-every=4", "--jobs=4", "--seed=300")
        if r.returncode != 0:
            raise AssertionError(f"coverage.py run failed:\n{r.stdout}\n{r.stderr}")
        folder = newest_run(cls.repo, "matches")
        cls.map = read_json(folder / "map.json")
        cls.hits = hits.load(folder / "hits.json")
        cls.meta = read_json(folder / "meta.json")

    def test_the_endless_process_plays_three_matches_and_the_others_one(self):
        by_seed = collections.defaultdict(list)
        for u in self.hits["units"]:
            by_seed[u["seed"]].append(u)
        self.assertEqual(sorted(by_seed), [300, 301, 302, 303])
        endless = [s for s, us in by_seed.items() if any(u["mode"] == "endless" for u in us)]
        self.assertEqual(len(endless), 1, by_seed.keys())
        self.assertEqual(sorted(u["match"] for u in by_seed[endless[0]]), [1, 2, 3])
        self.assertTrue(all(u["mode"] == "endless" for u in by_seed[endless[0]]))
        for s, us in by_seed.items():
            if s != endless[0]:
                self.assertEqual([(u["mode"], u["match"]) for u in us], [("watch", 1)], s)
        self.assertEqual(len(self.meta["matches"]), 6)

    def test_the_endless_run_covers_its_teardown(self):
        teardown = one_id(self.map, *TEARDOWN)
        endless_units = [u for u in self.hits["units"] if u["mode"] == "endless"]
        self.assertGreaterEqual(sum(count(u, teardown) for u in endless_units), 2, "between its three matches")
        self.assertEqual(sum(count(u, teardown) for u in self.hits["units"] if u["mode"] == "watch"), 0)


def set_time_limit(seconds: float):
    """An `edit` for fixture_repo: Main's endless_time_limit set to `seconds` in main.tscn."""
    def edit(repo: Path) -> None:
        scene = repo / "scenes" / "main.tscn"
        text = scene.read_text()
        anchor = 'script = ExtResource("1_main")\n'
        assert anchor in text
        scene.write_text(text.replace(anchor, anchor + f"endless_time_limit = {seconds}\n", 1))
    return edit


@needs_godot
class TimeCapTests(unittest.TestCase):
    def test_a_match_that_never_ends_is_capped_at_mains_endless_time_limit(self):
        with TempDir() as d:
            repo = fixture_repo(d, set_time_limit(1.0))
            r = run_cli(repo, "run", "--matches=1", "--jobs=1", "--seed=9000", timeout=180)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            folder = newest_run(repo, "matches")
            meta = read_json(folder / "meta.json")
            smap = read_json(folder / "map.json")
            data = hits.load(folder / "hits.json")
        self.assertEqual(len(meta["matches"]), 1)
        self.assertTrue(0.9 <= meta["matches"][0]["duration"] <= 1.5, meta["matches"][0])
        self.assertGreater(hits.totals(data).get(one_id(smap, *STALL_LOOP), 0), 0, "the stalemate was played")


def descendants(pid: int) -> list[int]:
    out = subprocess.run(["pgrep", "-P", str(pid)], capture_output=True, text=True).stdout.split()
    kids = [int(x) for x in out]
    return kids + [d for k in kids for d in descendants(k)]


def godot_processes_under(pid: int) -> list[int]:
    found = []
    for p in descendants(pid):
        comm = subprocess.run(["ps", "-o", "comm=", "-p", str(p)], capture_output=True, text=True).stdout
        if "godot" in comm.lower():
            found.append(p)
    return found


def stall_hits(data: dict, smap: dict) -> int:
    return hits.totals(data).get(one_id(smap, *STALL_LOOP), 0)


def setup_wait(frames: int):
    """An `edit` for fixture_repo: the setup window's start waits `frames` physics frames before the match is built,
    as the real Main waits for the Von server before it builds the world."""
    def edit(repo: Path) -> None:
        main = repo / "scenes" / "main.gd"
        text = main.read_text()
        anchor = "\tcall(\"_by_name\")\n\t_play()\n"
        assert anchor in text
        main.write_text(text.replace(anchor, f"\tcall(\"_by_name\")\n\tfor _i in {frames}:\n"
                                     "\t\tawait get_tree().physics_frame\n\t_play()\n", 1))
    return edit


def both(*edits):
    def edit(repo: Path) -> None:
        for e in edits:
            e(repo)
    return edit


def without_world(repo: Path) -> None:
    """An `edit` for fixture_repo: the match's world never joins the group `match_world`."""
    main = repo / "scenes" / "main.gd"
    text = main.read_text()
    anchor = 'world.add_to_group(&"match_world")'
    assert anchor in text, "the fixture's Main adds its world to the group match_world"
    main.write_text(text.replace(anchor, 'world.add_to_group(&"not_the_match_world")', 1))


@needs_godot
class WorldClockTests(unittest.TestCase):
    """A match is timed from its world: the node Main adds to the group `match_world` when it builds the match, in
    the frame the MatchHUD's own clock starts. So the wait before it (the Von server, on the real Main) is in no
    match's duration, and the cap at Main's endless_time_limit counts the match itself."""

    def test_a_match_is_timed_from_its_world_not_from_the_start(self):
        with TempDir() as d:
            repo = fixture_repo(d, setup_wait(60))
            r = run_cli(repo, "run", "--matches=1", "--jobs=1", "--seed=100", "--endless-every=0", timeout=180)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            meta = read_json(newest_run(repo, "matches") / "meta.json")
        m = meta["matches"][0]
        self.assertEqual(m["verdict"], "INVADER WINS", m)
        self.assertLess(m["duration"], 0.5, f"a few frames, not the 1 s wait before the world: {m}")

    def test_the_cap_counts_from_the_world(self):
        with TempDir() as d:
            repo = fixture_repo(d, both(set_time_limit(1.0), setup_wait(120)))
            r = run_cli(repo, "run", "--matches=1", "--jobs=1", "--seed=9000", "--endless-every=0", timeout=180)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            folder = newest_run(repo, "matches")
            meta = read_json(folder / "meta.json")
            smap = read_json(folder / "map.json")
            data = hits.load(folder / "hits.json")
        self.assertEqual(meta["matches"][0]["verdict"], "TIME CAP", meta["matches"][0])
        self.assertTrue(0.9 <= meta["matches"][0]["duration"] <= 1.5, meta["matches"][0])
        self.assertGreater(stall_hits(data, smap), 0, "the cap came after the 2 s wait: the stalemate was played")

    def test_a_match_whose_world_never_appears_fails_loudly(self):
        with TempDir() as d:
            repo = fixture_repo(d, without_world)
            r = run_cli(repo, "run", "--matches=1", "--jobs=1", "--seed=100", "--endless-every=0", timeout=180)
        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("match_world", r.stdout + r.stderr)


@needs_godot
class KillTests(unittest.TestCase):
    def test_a_process_killed_with_kill_9_leaves_its_last_flush(self):
        with TempDir() as d:
            src = project_repo(d)
            copy = workspace.create(src)
            try:
                smap = instrument.instrument(copy)
                hits_dir = d / "hits"
                hits_dir.mkdir()
                entry = runner.plan_matches(1, 9000, 100)[0]
                proc = runner.launch(copy, entry, hits_dir)
                try:
                    def flushed():
                        for f in hits_dir.glob("coverage_hits*.json"):
                            try:
                                data = hits.load(f)
                            except (ValueError, OSError):
                                continue
                            if stall_hits(data, smap) > 0:
                                return f
                        return None
                    shard = wait_for(flushed, timeout=40)
                    self.assertIsNotNone(shard, "a flush with the running match's hits within 40 s (one every 5 s)")
                    self.assertIsNone(proc.poll(), "the stalemate is still running when it is killed")
                finally:
                    proc.send_signal(signal.SIGKILL)
                    proc.wait(timeout=30)
                data = hits.load(shard)
                self.assertEqual(data["map_hash"], smap["hash"])
                self.assertGreater(stall_hits(data, smap), 0)
                merged = hits.merge([data])
                self.assertEqual(hits.totals(merged), hits.totals(data), "the killed shard merges like any other")
            finally:
                workspace.cleanup(src, copy)

    def test_a_run_whose_game_process_is_killed_still_keeps_its_last_flush(self):
        with TempDir() as d:
            repo = fixture_repo(d)
            cli = subprocess.Popen([sys.executable, str(repo / "tools" / "coverage.py"), "run", "--matches=1",
                                    "--jobs=1", "--seed=9000"], cwd=repo, env=env_with_godot(),
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            try:
                game = wait_for(lambda: godot_processes_under(cli.pid), timeout=120)
                self.assertTrue(game, "the run started a game process")
                time.sleep(8)  # past the first 5 s flush
                for pid in godot_processes_under(cli.pid):
                    os.kill(pid, signal.SIGKILL)
                out, _ = cli.communicate(timeout=180)
            finally:
                if cli.poll() is None:
                    cli.kill()
            folder = newest_run(repo, "matches")
            data = hits.load(folder / "hits.json")
            smap = read_json(folder / "map.json")
        self.assertGreater(stall_hits(data, smap), 0, out)


@needs_godot
class TestsRunTests(unittest.TestCase):
    """`run --tests --jobs=2`: the fixture's own tools/run_tests.sh, split over two processes; then `run --tests`
    with no `--jobs`, which passes none on (the matches run's default is not the tests run's)."""

    @classmethod
    def setUpClass(cls):
        tmp = class_tempdir(cls)
        cls.repo = fixture_repo(tmp)
        cls.args_file = tmp / "run_tests_args.txt"
        cls.before = (git_status(cls.repo), tree_digest(cls.repo))
        r = run_cli(cls.repo, "run", "--tests", "--jobs=2", FIXTURE_ARGS_FILE=str(cls.args_file))
        if r.returncode != 0:
            raise AssertionError(f"coverage.py run --tests failed:\n{r.stdout}\n{r.stderr}")
        cls.out = r.stdout + r.stderr
        cls.folder = newest_run(cls.repo, "tests")
        cls.map = read_json(cls.folder / "map.json")
        cls.hits = hits.load(cls.folder / "hits.json")
        cls.meta = read_json(cls.folder / "meta.json")
        cls.units = {u["id"]: u for u in cls.hits["units"]}
        r = run_cli(cls.repo, "run", "--tests", FIXTURE_ARGS_FILE=str(cls.args_file))
        if r.returncode != 0:
            raise AssertionError(f"coverage.py run --tests (no --jobs) failed:\n{r.stdout}\n{r.stderr}")

    def test_the_run_folder_and_meta_are_for_tests(self):
        self.assertTrue(self.folder.name.endswith("-tests"), self.folder.name)
        for name in RUN_FILES:
            self.assertTrue((self.folder / name).is_file(), name)
        self.assertEqual((self.hits["source"], self.meta["source"]), ("tests", "tests"))
        self.assertEqual(self.meta["map_hash"], self.map["hash"])

    def test_run_tests_got_the_args_with_perf_skipped(self):
        args = self.args_file.read_text().split("--end--")[0].split()
        self.assertIn("--skip-domain=perf", args)
        self.assertIn("--jobs=2", args)

    def test_run_tests_gets_no_jobs_when_none_is_given(self):
        args = self.args_file.read_text().split("--end--")[1].split()
        self.assertIn("--skip-domain=perf", args)
        self.assertFalse([a for a in args if a.startswith("--jobs")], args)

    def test_each_statement_is_kept_with_the_tests_that_ran_it(self):
        alpha, beta = one_id(self.map, *ALPHA), one_id(self.map, *BETA)
        for test_id in ("t/alpha", "t/beta", "t/both"):
            self.assertIn(test_id, self.units)
        self.assertEqual((count(self.units["t/alpha"], alpha), count(self.units["t/alpha"], beta)), (1, 0))
        self.assertEqual((count(self.units["t/beta"], alpha), count(self.units["t/beta"], beta)), (0, 1))
        self.assertEqual((count(self.units["t/both"], alpha), count(self.units["t/both"], beta)), (1, 1))

    def test_the_perf_test_never_ran(self):
        self.assertNotIn("perf/heavy", self.units)
        self.assertNotIn(one_id(self.map, *HEAVY), hits.totals(self.hits))

    def test_the_teardown_after_each_test_is_kept_outside_any_test(self):
        outside = next(u for u in self.hits["units"] if u.get("outside"))
        for statement in (TEARDOWN_TARGET, RUNNER_CLOSE):
            sid = one_id(self.map, *statement)
            self.assertEqual(count(outside, sid), 3, f"{statement}: once after each of the three tests")
            for test_id in ("t/alpha", "t/beta", "t/both"):
                self.assertEqual(count(self.units[test_id], sid), 0, f"{statement} charged to {test_id}")

    def test_nothing_is_left_in_artifacts_tmp(self):
        self.assertEqual(scratch_left(self.repo), [])

    def test_the_run_names_the_run_folder_it_wrote(self):
        self.assertIn(f"Run folder: {self.folder.relative_to(self.repo)}\n", self.out)

    def test_the_summary_counts_the_tests_not_the_outside_unit(self):
        self.assertIn("  3 tests;", self.out)

    def test_the_repo_is_byte_identical_after_the_run(self):
        self.assertEqual((git_status(self.repo), tree_digest(self.repo)), self.before)


EVENT_BUS = """extends Node
## Test stand-in for the game's EventBus autoload (scenes/general/event_bus.gd): post(topic, data) emits posted.

signal posted(topic: StringName, data: Dictionary)


func post(topic: StringName, data: Dictionary) -> void:
	posted.emit(topic, data)
"""

FAKE_CHARACTER = """extends Node
## Test stand-in for a character: in the group `characters`, with `is_dead`.

var is_dead := false


func _ready() -> void:
	add_to_group("characters")
"""

DEATHS_PER_MATCH = 2


def shots_of(seed: int) -> int:
    return seed % 3 + 1


def with_shots_and_deaths(repo: Path) -> None:
    """An `edit` for fixture_repo: an EventBus autoload, and each match posts shots_of(seed) `shot` events (and one
    `hit`, which is not a shot) and adds three characters, DEATHS_PER_MATCH of them dead."""
    (repo / "scenes" / "event_bus.gd").write_text(EVENT_BUS)
    (repo / "scenes" / "fake_character.gd").write_text(FAKE_CHARACTER)
    project = repo / "project.godot"
    text = project.read_text()
    assert 'Bus="*res://scenes/bus.gd"\n' in text
    project.write_text(text.replace('Bus="*res://scenes/bus.gd"\n',
                                    'Bus="*res://scenes/bus.gd"\nEventBus="*res://scenes/event_bus.gd"\n', 1))
    main = repo / "scenes" / "main.gd"
    text = main.read_text()
    anchor = "\tlogic.every_match()\n"
    assert anchor in text
    main.write_text(text.replace(anchor, anchor
                                 + "\tfor _i in _seed % 3 + 1:\n\t\tEventBus.post(&\"shot\", {})\n"
                                 + "\tEventBus.post(&\"hit\", {})\n"
                                 + "\tfor dead in [true, true, false]:\n"
                                 + "\t\tvar c = load(\"res://scenes/fake_character.gd\").new()\n"
                                 + "\t\tc.is_dead = dead\n\t\tadd_child(c)\n", 1))


OUTCOME_KEYS = ("seed", "mode", "match", "verdict", "duration", "shots", "deaths", "wall", "frames", "physics_peak_ms",
                "process_peak_ms", "npcs", "decisions", "decided", "failed", "decided_per_npc_minute",
                "von_failed_share")


@needs_godot
class OutcomeTests(unittest.TestCase):
    """The same two Watch matches (seeds 100, 101) played instrumented, then `--uninstrumented`: each match records
    its outcome (verdict, game-time duration, shots, deaths) and its cost (wall seconds, process frames, the mean ms
    of a physics step and of a process step), so the two can be compared seed by seed."""

    @classmethod
    def setUpClass(cls):
        cls.repo = fixture_repo(class_tempdir(cls), with_shots_and_deaths)
        cls.before = (git_status(cls.repo), tree_digest(cls.repo))
        args = ("run", "--matches=2", "--seed=100", "--endless-every=0")  # no --jobs: the default, 2
        r = cls.measured_result = run_cli(cls.repo, *args)
        if r.returncode != 0:
            raise AssertionError(f"coverage.py run failed:\n{r.stdout}\n{r.stderr}")
        time.sleep(1.1)  # a later run folder
        cls.plain_result = run_cli(cls.repo, *args, "--uninstrumented")
        if cls.plain_result.returncode != 0:
            raise AssertionError(f"coverage.py run --uninstrumented failed:\n{cls.plain_result.stdout}\n"
                                 f"{cls.plain_result.stderr}")
        cls.measured = newest_run(cls.repo, "matches")
        cls.plain = newest_run(cls.repo, "uninstrumented")
        cls.measured_meta = read_json(cls.measured / "meta.json")
        cls.plain_meta = read_json(cls.plain / "meta.json")

    def by_seed(self, meta: dict) -> dict:
        return {m["seed"]: m for m in meta["matches"]}

    def test_given_no_jobs_both_runs_play_two_processes_at_a_time(self):
        for r in (self.measured_result, self.plain_result):
            self.assertIn("Playing 2 processes from seed 100 (2 matches), 2 at a time", r.stdout)

    def test_each_match_records_its_shots_and_deaths(self):
        for meta in (self.measured_meta, self.plain_meta):
            matches = self.by_seed(meta)
            self.assertEqual(sorted(matches), [100, 101])
            for seed, m in matches.items():
                self.assertEqual((m["shots"], m["deaths"]), (shots_of(seed), DEATHS_PER_MATCH), m)

    def test_each_match_records_its_wall_time_frames_and_step_costs(self):
        for meta in (self.measured_meta, self.plain_meta):
            for m in meta["matches"]:
                self.assertEqual(sorted(m), sorted(OUTCOME_KEYS), m)
                self.assertGreater(m["wall"], 0, m)
                self.assertGreater(m["frames"], 0, m)
                self.assertGreaterEqual(m["physics_peak_ms"], 0, m)
                self.assertGreaterEqual(m["process_peak_ms"], 0, m)

    def test_a_game_with_no_npc_controllers_measures_no_decision_rate_and_warns_of_none(self):
        for meta in (self.measured_meta, self.plain_meta):
            for m in meta["matches"]:
                self.assertEqual((m["npcs"], m["decisions"], m["decided"], m["failed"], m["decided_per_npc_minute"],
                                  m["von_failed_share"]), (0, None, None, None, None, None), m)
        out = self.measured_result.stdout + self.measured_result.stderr
        self.assertNotIn("decisions per NPC per game minute", out)

    def test_the_hit_units_carry_the_same_outcome(self):
        data = hits.load(self.measured / "hits.json")
        for u in data["units"]:
            m = self.by_seed(self.measured_meta)[u["seed"]]
            self.assertEqual({k: u[k] for k in OUTCOME_KEYS}, m)

    def test_the_uninstrumented_run_plays_the_same_matches_and_counts_nothing(self):
        self.assertIs(self.measured_meta["instrumented"], True)
        self.assertIs(self.plain_meta["instrumented"], False)
        self.assertEqual(self.plain_meta["seeds"], self.measured_meta["seeds"])
        for seed, m in self.by_seed(self.plain_meta).items():
            other = self.by_seed(self.measured_meta)[seed]
            self.assertEqual((m["verdict"], m["shots"], m["deaths"]),
                             (other["verdict"], other["shots"], other["deaths"]), seed)
        self.assertEqual(read_json(self.plain / "map.json")["statements"], [])
        for u in hits.load(self.plain / "hits.json")["units"]:
            self.assertEqual(u["counts"], {}, u["id"])

    def test_the_uninstrumented_run_folder_is_named_apart_and_holds_no_report(self):
        self.assertTrue(self.plain.name.endswith("-uninstrumented"), self.plain.name)
        self.assertEqual(len(run_folders(self.repo, "matches")), 1, "an uninstrumented run is not a matches run")
        for name in ("hits.json", "meta.json", "map.json"):
            self.assertTrue((self.plain / name).is_file(), name)
        for name in ("report.md", "report.json"):
            self.assertFalse((self.plain / name).exists(), f"{name}: there is nothing to report")

    def test_report_never_reads_an_uninstrumented_run(self):
        r = run_cli(self.repo, "report")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        runs_line = next(l for l in r.stdout.splitlines() if l.startswith("Runs: "))
        self.assertIn(self.measured.name, runs_line)
        self.assertNotIn(self.plain.name, runs_line)

    def test_the_repo_is_byte_identical_after_both_runs(self):
        self.assertEqual((git_status(self.repo), tree_digest(self.repo)), self.before)


def runner_waits_first(repo: Path) -> None:
    """An `edit` for fixture_repo: the fixture's test runner waits a few frames before its first test, as the real
    one does (it discovers the tests and builds its UI first)."""
    runner_gd = repo / "scenes" / "testing" / "test_runner.gd"
    text = runner_gd.read_text()
    anchor = "func _ready() -> void:\n"
    assert anchor in text
    runner_gd.write_text(text.replace(anchor, anchor + "\tawait _frames(3)\n", 1))


def runner_awaits_before_the_world(repo: Path) -> None:
    """An `edit` for fixture_repo: the fixture's test runner adds no world as a test starts, so the first the probe
    hears of the test is a frame later, when the runner already waits for the test's `finished`."""
    runner_gd = repo / "scenes" / "testing" / "test_runner.gd"
    text = runner_gd.read_text()
    anchor = "\t_world = Node.new()\n\tadd_child(_world)\n"
    assert anchor in text
    runner_gd.write_text(text.replace(anchor, "\t_world = Node.new()\n", 1))


def runner_without_context(repo: Path) -> None:
    """An `edit` for fixture_repo: the fixture's test runner keeps its test's context under another name than `open_ctx`."""
    runner_gd = repo / "scenes" / "testing" / "test_runner.gd"
    runner_gd.write_text(runner_gd.read_text().replace("open_ctx", "open_context"))


def context_without_is_finished(repo: Path) -> None:
    """An `edit` for fixture_repo: the fixture runner's test context keeps its `is_finished` under another name; the
    runner still runs its tests."""
    runner_gd = repo / "scenes" / "testing" / "test_runner.gd"
    text = runner_gd.read_text()
    assert "is_finished" in text
    runner_gd.write_text(text.replace("is_finished", "done"))


def context_without_finished_signal(repo: Path) -> None:
    """An `edit` for fixture_repo: the fixture runner's test context emits its end as the signal `done`, not
    `finished`; the runner still runs its tests."""
    runner_gd = repo / "scenes" / "testing" / "test_runner.gd"
    text = runner_gd.read_text()
    for old, new in (("\tsignal finished\n", "\tsignal done\n"), ("await open_ctx.finished\n", "await open_ctx.done\n"),
                     ("finished.emit()\n", "done.emit()\n")):
        assert old in text
        text = text.replace(old, new)
    runner_gd.write_text(text)


@needs_godot
class TestEndTests(unittest.TestCase):
    """`run --tests`: the probe ends a test's unit when the runner's test context (`open_ctx`) emits `finished`, before the
    runner hears it, so the teardown after it is not the test's; a runner it cannot read that way fails the run."""

    def test_a_runner_with_no_test_context_fails_loudly(self):
        with TempDir() as d:
            repo = fixture_repo(d, runner_without_context)
            r = run_cli(repo, "run", "--tests")
        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("open_ctx", r.stdout + r.stderr)

    def test_a_test_context_with_no_is_finished_fails_loudly(self):
        with TempDir() as d:
            repo = fixture_repo(d, context_without_is_finished)
            r = run_cli(repo, "run", "--tests")
        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("is_finished", r.stdout + r.stderr)

    def test_a_test_context_with_no_finished_signal_fails_loudly(self):
        with TempDir() as d:
            repo = fixture_repo(d, context_without_finished_signal)
            r = run_cli(repo, "run", "--tests")
        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("finished signal", r.stdout + r.stderr)

    def test_a_runner_that_hears_the_end_of_a_test_before_the_probe_fails_loudly(self):
        with TempDir() as d:
            repo = fixture_repo(d, runner_awaits_before_the_world)
            r = run_cli(repo, "run", "--tests")
        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("finished", r.stdout + r.stderr)


@needs_godot
class OutsideTestsRunTests(unittest.TestCase):
    """`run --tests`: the hits made while no test runs (the runner's start-up, between tests) are kept in one unit of
    their own, `{"id": "", "outside": true}`, never in a test's and never dropped."""

    @classmethod
    def setUpClass(cls):
        cls.repo = fixture_repo(class_tempdir(cls), runner_waits_first)
        r = run_cli(cls.repo, "run", "--tests", "--jobs=2")
        if r.returncode != 0:
            raise AssertionError(f"coverage.py run --tests failed:\n{r.stdout}\n{r.stderr}")
        folder = newest_run(cls.repo, "tests")
        cls.map = read_json(folder / "map.json")
        cls.hits = hits.load(folder / "hits.json")
        cls.report = read_json(folder / "report.json")
        cls.ready = next(s["id"] for s in cls.map["statements"] if (s["file"], s["function"], s["kind"])
                         == ("scenes/testing/test_runner.gd", "_ready", "function"))

    def test_one_outside_unit_holds_the_runners_start_up(self):
        outside = [u for u in self.hits["units"] if u.get("outside")]
        self.assertEqual([u["id"] for u in outside], [""], "one, merged over the shards")
        self.assertEqual(count(outside[0], self.ready), 2, "the runner's _ready, once per shard")

    def test_no_test_unit_holds_it(self):
        for u in self.hits["units"]:
            if not u.get("outside"):
                self.assertEqual(count(u, self.ready), 0, u["id"])

    def test_the_report_counts_it_as_run_and_pinned_by_no_test(self):
        fn = next(fn for d in self.report["domains"] for f in d["files"] for fn in f["functions"]
                  if f["file"] == "scenes/testing/test_runner.gd" and fn["function"] == "_ready")
        self.assertEqual((fn["outside_hits"], fn["test_hits"], fn["tests"]["count"]), (2, 0, 0), fn)
        self.assertNotIn("untriggered system", fn["tags"])
        self.assertNotIn("dead", fn["tags"])


FAKE_NPC = """extends Node
## Test stand-in for an NPC's AI controller: in the group `npc_controllers`, with the debug_state() the probe reads,
## and a decision planner child that finishes its walks with the planner's `decided` or `failed` signal.

var decisions := 0
var answered := true


func _ready() -> void:
	add_to_group("npc_controllers")
	var planner = load("res://scenes/fake_planner.gd").new()
	planner.walks = decisions
	planner.answered = answered
	add_child(planner)


func debug_state() -> Dictionary:
	return { "decisions": decisions, "decision": { "last_failed": not answered } }
"""

FAKE_PLANNER = """extends Node
## Test stand-in for the AI's decision planner: its `decided` / `failed` signals, one per finished walk.

signal decided(leaf: Dictionary)
signal failed()

var walks := 0
var answered := true


func _ready() -> void:
	for i in walks:
		if answered:
			decided.emit({})
		else:
			failed.emit()
"""


def with_npcs(repo: Path) -> None:
    """An `edit` for fixture_repo: each match adds two NPC controllers that start 5 decision walks each; on an even
    seed Von answers none of them (every walk fails: a starved server, below any floor), on an odd one all."""
    (repo / "scenes" / "fake_npc.gd").write_text(FAKE_NPC)
    (repo / "scenes" / "fake_planner.gd").write_text(FAKE_PLANNER)
    main = repo / "scenes" / "main.gd"
    text = main.read_text()
    anchor = "\tlogic.every_match()\n"
    assert anchor in text
    main.write_text(text.replace(anchor, anchor
                                 + "\tfor i in 2:\n"
                                 + "\t\tvar npc = load(\"res://scenes/fake_npc.gd\").new()\n"
                                 + "\t\tnpc.decisions = 5\n"
                                 + "\t\tnpc.answered = _seed % 2 == 1\n"
                                 + "\t\tadd_child(npc)\n", 1))


JANK = """extends Node
## Test stand-in for an uneven game: busy-waits 1 ms and 25 ms on alternate process and physics frames.

var _process_n := 0
var _physics_n := 0


func _process(_delta: float) -> void:
	_process_n += 1
	_busy(1000 if _process_n % 2 == 0 else 25000)


func _physics_process(_delta: float) -> void:
	_physics_n += 1
	_busy(1000 if _physics_n % 2 == 0 else 25000)


func _busy(usec: int) -> void:
	var t := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t < usec:
		pass
"""


def with_jank(repo: Path) -> None:
    """An `edit` for fixture_repo: Main holds a node whose process and physics frames take 1 ms and 25 ms in turn."""
    (repo / "scenes" / "jank.gd").write_text(JANK)
    main = repo / "scenes" / "main.gd"
    text = main.read_text()
    anchor = "func _ready() -> void:\n"
    assert anchor in text
    main.write_text(text.replace(anchor, anchor + "\tadd_child(load(\"res://scenes/jank.gd\").new())\n", 1))


@needs_godot
class StepPeakTests(unittest.TestCase):
    """`physics_peak_ms` and `process_peak_ms` are the engine's TIME_PHYSICS_PROCESS and TIME_PROCESS monitors averaged
    over a match's frames, and those monitors hold the slowest frame of each second (not each frame's own time): in a
    game whose frames take 1 ms and 25 ms in turn they read above 20 ms, where a per-frame mean would be about 13."""

    def test_the_step_figures_are_the_per_second_peak(self):
        with TempDir() as d:
            repo = fixture_repo(d, both(with_jank, set_time_limit(2.0)))
            r = run_cli(repo, "run", "--matches=1", "--jobs=1", "--seed=9000", "--endless-every=0", timeout=180)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            m = read_json(newest_run(repo, "matches") / "meta.json")["matches"][0]
        self.assertGreater(m["duration"], 1.5, m)
        self.assertGreater(m["physics_peak_ms"], 20.0, m)
        self.assertGreater(m["process_peak_ms"], 20.0, m)


@needs_godot
class VonRateTests(unittest.TestCase):
    """Each match records how often its NPCs got a Von decision: `npcs` (the group `npc_controllers` as it ends),
    `decisions` (their debug_state() `decisions`, the walks started, summed), `decided` and `failed` (the decision
    planners' `decided` / `failed` signals during it: walks Von answered, walks that ended without an answer),
    `decided_per_npc_minute` (decided per NPC per game minute) and `von_failed_share` (failed / (decided + failed)).
    A starved Von server times its walks out, so walks keep starting while few are decided: the guarded rate is the
    decided one. A run warns about every match below runner.VON_DECISIONS_FLOOR, records the floor in meta
    (`von_floor`), and its report's header warns too."""

    @classmethod
    def setUpClass(cls):
        cls.repo = fixture_repo(class_tempdir(cls), with_npcs)
        cls.result = run_cli(cls.repo, "run", "--matches=2", "--jobs=2", "--seed=100", "--endless-every=0")
        if cls.result.returncode != 0:
            raise AssertionError(f"coverage.py run failed:\n{cls.result.stdout}\n{cls.result.stderr}")
        cls.folder = newest_run(cls.repo, "matches")
        cls.meta = read_json(cls.folder / "meta.json")
        cls.by_seed = {m["seed"]: m for m in cls.meta["matches"]}

    def test_each_match_records_its_decision_rate(self):
        slow, fast = self.by_seed[100], self.by_seed[101]
        self.assertEqual((slow["npcs"], slow["decisions"], slow["decided"], slow["failed"],
                          slow["decided_per_npc_minute"], slow["von_failed_share"]), (2, 10, 0, 10, 0.0, 1.0), slow)
        self.assertEqual((fast["npcs"], fast["decisions"], fast["decided"], fast["failed"], fast["von_failed_share"]),
                         (2, 10, 10, 0, 0.0), fast)
        self.assertAlmostEqual(fast["decided_per_npc_minute"], 10 / 2 / (fast["duration"] / 60), places=3)

    def test_the_floor_is_recorded(self):
        self.assertEqual(self.meta["von_floor"], runner.VON_DECISIONS_FLOOR)
        self.assertGreater(runner.VON_DECISIONS_FLOOR, 0)

    def test_the_run_warns_about_the_match_below_the_floor_only(self):
        out = self.result.stdout + self.result.stderr
        warning = [l for l in out.splitlines() if "decisions per NPC per game minute" in l]
        self.assertTrue(warning, out)
        self.assertIn("100-1", " ".join(warning))
        self.assertNotIn("101-1", " ".join(warning))

    def test_the_report_header_warns_too(self):
        header = (self.folder / "report.md").read_text().split("\n## ", 1)[0]
        self.assertIn("decisions per NPC per game minute", header)
        self.assertIn("100-1", header)
        self.assertNotIn("101-1", header)


def with_failing_tests(repo: Path) -> None:
    """An `edit` for fixture_repo: the fixture's run_tests.sh reports t/beta failed and t/both timed out, in the
    real runner's verdict lines, after its runner has run every test, and exits 1."""
    script = repo / "tools" / "run_tests.sh"
    text = script.read_text()
    anchor = "exit $status\n"
    assert text.endswith(anchor)
    script.write_text(text[: -len(anchor)] + (
        'echo "PASS    t/alpha  (0.1s sim, 2 ms)"\n'
        'echo "FAIL    t/beta  (0.1s sim, 3 ms)"\n'
        'echo "        \u2717 the fixture fails it on purpose (10568 ms of 3000)"\n'
        'echo "        \u00b7 actor at (0, 0)  health 100"\n'
        'echo "TIMEOUT t/both  (10.0s sim, 9 ms)"\n'
        'echo "2 passed, 1 failed, 1 timed out, 0 skipped, 0 gap"\n'
        "exit 1\n"))


@needs_godot
class FailedTestsRunTests(unittest.TestCase):
    """`run --tests` measures coverage and does not judge the tests: a test that fails or times out in the
    instrumented copy is recorded in meta.json (`failed`: id, verdict, its first failed check) and listed in the
    report, its hits are kept, and the run exits 0. It fails only when the run itself broke."""

    @classmethod
    def setUpClass(cls):
        cls.repo = fixture_repo(class_tempdir(cls), with_failing_tests)
        cls.result = run_cli(cls.repo, "run", "--tests", "--jobs=2")
        cls.folder = newest_run(cls.repo, "tests")
        cls.meta = read_json(cls.folder / "meta.json")

    def test_the_run_exits_0(self):
        self.assertEqual(self.result.returncode, 0, self.result.stdout + self.result.stderr)

    def test_meta_records_the_failed_tests(self):
        self.assertEqual(self.meta["failed"], [
            {"id": "t/beta", "verdict": "FAIL", "first": "the fixture fails it on purpose (10568 ms of 3000)"},
            {"id": "t/both", "verdict": "TIMEOUT", "first": ""}])
        self.assertEqual(self.meta["run_tests_exit"], 1)

    def test_their_hits_are_kept(self):
        units = {u["id"] for u in hits.load(self.folder / "hits.json")["units"]}
        self.assertTrue({"t/beta", "t/both"} <= units, units)

    def test_the_report_lists_them(self):
        md = (self.folder / "report.md").read_text()
        section = md.split("## Failed under instrumentation", 1)[1].split("\n## ", 1)[0]
        self.assertIn("t/beta", section)
        self.assertIn("t/both", section)
        self.assertNotIn("t/alpha", section)

    def test_the_run_names_them(self):
        out = self.result.stdout + self.result.stderr
        self.assertIn("t/beta", out)


@needs_godot
class BrokenTestsRunTests(unittest.TestCase):
    def test_a_runner_that_crashes_with_no_hits_fails_the_run(self):
        def crash(repo: Path) -> None:
            script = repo / "tools" / "run_tests.sh"
            text = script.read_text()
            anchor = 'cd "$(dirname "$0")/.."\n'
            assert anchor in text
            script.write_text(text.replace(anchor, anchor + "echo 'crashed before any test' >&2\nexit 3\n", 1))
        with TempDir() as d:
            repo = fixture_repo(d, crash)
            r = run_cli(repo, "run", "--tests")
        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)


TEARDOWN_NODE = """extends Node
## Test stand-in for a game that ends badly at quit, on an even seed only: its _exit_tree runs after the probe's
## flush at the last match's end and before the probe's final flush (when the tree is freed).


func _exit_tree() -> void:
	if get_parent()._seed % 2 == 0:
		STATEMENT
"""


def ends_badly(statement: str):
    """An `edit` for fixture_repo: a node under Main whose _exit_tree runs `statement` on an even seed."""
    def edit(repo: Path) -> None:
        (repo / "scenes" / "teardown.gd").write_text(TEARDOWN_NODE.replace("STATEMENT", statement))
        main = repo / "scenes" / "main.gd"
        text = main.read_text()
        anchor = "\t$SetupMenu.start_requested.connect(_on_setup_chosen)\n"
        assert anchor in text
        main.write_text(text.replace(anchor, anchor + '\tadd_child(load("res://scenes/teardown.gd").new())\n', 1))
    return edit


@needs_godot
class CrashedAfterLastFlushRunTests(unittest.TestCase):
    """A game process that exits non-zero at quit after its final flush (every match decided, the hit file marked
    final) lost no hits: it is recorded in meta.json (`crashed`: seed, mode, process, pid, exit, phase, log, message)
    and the report, its log is kept in the run folder, its hits are kept, and the run exits 0."""

    @classmethod
    def setUpClass(cls):
        cls.repo = fixture_repo(class_tempdir(cls), ends_badly('print("ending badly")\n\t\tget_tree().quit(134)'))
        cls.result = run_cli(cls.repo, "run", "--matches=2", "--jobs=2", "--seed=100")
        cls.folder = newest_run(cls.repo, "matches")
        cls.meta = read_json(cls.folder / "meta.json")

    def test_the_run_exits_0(self):
        self.assertEqual(self.result.returncode, 0, self.result.stdout + self.result.stderr)

    def test_meta_records_the_crashed_process_only(self):
        self.assertEqual([(c["seed"], c["mode"], c["process"], c["exit"], c["phase"]) for c in self.meta["crashed"]],
                         [(100, "watch", 0, 134, "after the last flush")], self.meta["crashed"])
        self.assertIsInstance(self.meta["crashed"][0]["pid"], int)

    def test_its_log_is_kept_in_the_run_folder_and_its_last_line_recorded(self):
        crashed = self.meta["crashed"][0]
        log = self.repo / crashed["log"]
        self.assertTrue(log.is_relative_to(self.folder), crashed["log"])
        self.assertIn("ending badly", log.read_text())
        self.assertEqual(crashed["message"], "ending badly")

    def test_its_hits_are_kept(self):
        units = {u["seed"]: u for u in hits.load(self.folder / "hits.json")["units"]}
        self.assertEqual(sorted(units), [100, 101])
        self.assertTrue(units[100]["verdict"])

    def test_the_report_lists_it(self):
        md = (self.folder / "report.md").read_text()
        section = md.split("## Crashed after the last flush", 1)[1].split("\n## ", 1)[0]
        self.assertIn("seed 100 ", section)
        self.assertNotIn("seed 101 ", section)

    def test_the_run_names_it(self):
        out = self.result.stdout + self.result.stderr
        self.assertIn("after the last flush", out)


@needs_godot
class CrashedBeforeLastFlushRunTests(unittest.TestCase):
    def test_a_process_that_dies_before_its_final_flush_fails_the_run(self):
        # OS.kill is SIGKILL on Unix: the process ends at once in its teardown, after the flush at its match's end and
        # before the final one. (OS.crash is no stand-in: Godot's crash handler hangs in the mono build.)
        with TempDir() as d:
            repo = fixture_repo(d, ends_badly('OS.kill(OS.get_process_id())'))
            r = run_cli(repo, "run", "--matches=2", "--jobs=2", "--seed=100")
            meta = read_json(newest_run(repo, "matches") / "meta.json")
        out = r.stdout + r.stderr
        self.assertNotEqual(r.returncode, 0, out)
        self.assertIn("before its final flush", out)
        self.assertEqual(meta["crashed"], [])


KEPT = re.compile(r"^Kept the copy (?P<copy>\S+) and the hits (?P<hits>\S+)$", re.M)


@needs_godot
class KeepTests(unittest.TestCase):
    """`run --matches=1 --seed=100 --keep`, then `instrument`: the copy and the hit folder are made directly in the
    repo's artifacts/tmp/ and kept, and the next copy holds nothing of them."""

    @classmethod
    def setUpClass(cls):
        cls.repo = fixture_repo(class_tempdir(cls))
        cls.before = (git_status(cls.repo), tree_digest(cls.repo))
        cls.result = run_cli(cls.repo, "run", "--matches=1", "--jobs=1", "--seed=100", "--keep")
        cls.after = (git_status(cls.repo), tree_digest(cls.repo))
        cls.out = cls.result.stdout + cls.result.stderr
        cls.kept = KEPT.search(cls.result.stdout)
        cls.instrument = run_cli(cls.repo, "instrument")

    def kept_paths(self) -> tuple[Path, Path]:
        self.assertIsNotNone(self.kept, "the run names the kept copy and hits:\n" + self.out)
        return Path(self.kept.group("copy")), Path(self.kept.group("hits"))

    def test_the_run_passes_its_tree_check_with_the_copy_inside_the_repo(self):
        self.assertEqual(self.result.returncode, 0, self.out)
        self.assertEqual(self.after, self.before, "git status and the scenes/ + project.godot bytes")

    def test_the_copy_is_made_directly_in_artifacts_tmp_and_kept(self):
        copy, _hits = self.kept_paths()
        self.assertEqual(copy.resolve().parent, (self.repo / "artifacts" / "tmp").resolve())
        self.assertTrue(copy.name.startswith("fe-coverage-copy."), copy)
        autoload = (copy / "project.godot").read_text().split("[autoload]", 1)[1].strip().splitlines()[0]
        self.assertTrue(autoload.startswith("CoverageProbe="), autoload)

    def test_the_hit_shards_are_made_directly_in_artifacts_tmp_and_kept(self):
        _copy, hits_dir = self.kept_paths()
        self.assertEqual(hits_dir.resolve().parent, (self.repo / "artifacts" / "tmp").resolve())
        self.assertTrue(hits_dir.name.startswith("fe-coverage-hits."), hits_dir)
        self.assertEqual(len(list(hits_dir.glob("coverage_hits_*.json"))), 1, sorted(hits_dir.iterdir()))

    def test_a_new_copy_holds_nothing_of_artifacts_and_leaves_the_kept_one(self):
        copy, hits_dir = self.kept_paths()
        self.assertEqual(self.instrument.returncode, 0, self.instrument.stdout + self.instrument.stderr)
        new = Path(self.instrument.stdout.strip().splitlines()[-1])
        self.assertNotEqual(new, copy)
        self.assertEqual(new.resolve().parent, (self.repo / "artifacts" / "tmp").resolve())
        self.assertFalse((new / "artifacts").exists(), sorted(p.name for p in new.iterdir()))
        self.assertTrue(copy.is_dir() and hits_dir.is_dir(), "the kept folders are not swept")


def dead(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return True
    return False


def stalls_in_tests(repo: Path) -> None:
    """An `edit` for fixture_repo: the fixture's tools/run_tests.sh also starts a game that never ends (Main with the
    probe idle waits for a start that never comes), as a long test would, so a tests run is still running."""
    script = repo / "tools" / "run_tests.sh"
    text = script.read_text()
    anchor = "status=0\n"
    assert anchor in text
    script.write_text(text.replace(anchor, 'env -u FE_COVERAGE "$GODOT" --headless --path . &\npids+=($!)\n' + anchor, 1))


@needs_godot
class CleanupOnExitTests(unittest.TestCase):
    """Whatever ends a run, it stops the game processes it started and leaves nothing in artifacts/tmp/."""

    def test_a_run_that_fails_part_way_leaves_nothing(self):
        with TempDir() as d:
            repo = fixture_repo(d, without_world)
            r = run_cli(repo, "run", "--matches=1", "--jobs=1", "--seed=100", "--endless-every=0")
            self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertIn("match_world", r.stdout + r.stderr, "it failed part-way, in the probe")
            self.assertEqual(scratch_left(repo), [])

    def test_a_run_that_raises_part_way_stops_its_games_and_leaves_nothing(self):
        # Seed 8999 ends in a few frames; 9000 is a stalemate, still playing when 8999's progress line comes in.
        class Boom(Exception):
            pass

        games = []

        def say(text: str) -> None:
            if text.lstrip().startswith("[1/2]"):
                games.extend(godot_processes_under(os.getpid()))
                raise Boom(text)

        with TempDir() as d:
            repo = fixture_repo(d)
            with self.assertRaises(Boom):
                runner.run(repo, "matches", matches=2, jobs=2, seed=8999, endless_every=0, say=say,
                           shout=lambda _text: None)
            self.assertEqual(scratch_left(repo), [])
        self.assertTrue(games, "the stalemate's game was running when the run raised")
        self.assertTrue(all(dead(pid) for pid in games), f"every game the run started is stopped: {games}")

    def test_a_run_in_a_repo_whose_artifacts_is_a_symlink_cleans_both_folders_and_keeps_its_exit_code(self):
        with TempDir() as d:
            repo = fixture_repo(d)
            elsewhere = d / "artifacts_elsewhere"
            elsewhere.mkdir()
            (repo / "artifacts").symlink_to(elsewhere, target_is_directory=True)
            r = run_cli(repo, "run", "--matches=1", "--jobs=1", "--seed=100", "--endless-every=0")
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertEqual(scratch_left(repo), [], r.stdout + r.stderr)
            self.assertEqual(len(run_folders(repo, "matches")), 1, "the run folder is in the folder artifacts/ is")

    def test_a_refused_cleanup_is_reported_and_neither_hides_the_result_nor_skips_the_other_folder(self):
        refused, shouted = [], []
        real_cleanup = workspace.cleanup

        def cleanup(root, folder):
            if Path(folder).name.startswith(workspace.PREFIX):
                refused.append(Path(folder))
                raise ValueError(f"{folder} refused by the test")
            real_cleanup(root, folder)

        with TempDir() as d:
            repo = fixture_repo(d)
            with mock.patch.object(workspace, "cleanup", cleanup):
                code, folder = runner.run(repo, "matches", matches=1, jobs=1, seed=100, endless_every=0,
                                          say=lambda _text: None, shout=shouted.append)
            self.assertEqual(code, 0, shouted)
            self.assertTrue((folder / "hits.json").is_file(), "the run's result is written")
            self.assertEqual(len(refused), 1, "the copy's cleanup was refused")
            self.assertEqual(scratch_left(repo), [refused[0].name], "the hit folder is cleaned up all the same")
            self.assertTrue(any(refused[0].name in s and "refused by the test" in s for s in shouted), shouted)

    def interrupted(self, sig: signal.Signals, args: tuple, edit=None) -> None:
        with TempDir() as d:
            repo = fixture_repo(d, edit)
            cli = subprocess.Popen([sys.executable, str(repo / "tools" / "coverage.py"), "run", *args], cwd=repo,
                                   env=env_with_godot(), stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, text=True)
            try:
                games = wait_for(lambda: godot_processes_under(cli.pid), timeout=120)
                self.assertTrue(games, "the run started a game")
                time.sleep(3)  # the game is playing
                games = godot_processes_under(cli.pid)
                self.assertTrue(scratch_left(repo), "the run's copy and hit folder are in artifacts/tmp/")
                cli.send_signal(sig)
                out, _ = cli.communicate(timeout=120)
            finally:
                if cli.poll() is None:
                    cli.kill()
                    cli.communicate()
            stopped = wait_for(lambda: all(dead(pid) for pid in games), timeout=10)
            for pid in games:
                kill_left(self, pid, group=False)
            self.assertEqual(cli.returncode, 128 + sig, out)
            self.assertIn("interrupted", out)
            self.assertEqual(scratch_left(repo), [], out)
        self.assertTrue(stopped, f"every game the run started is stopped: {[p for p in games if not dead(p)]}")

    def test_sigterm_mid_match_stops_its_games_and_leaves_nothing(self):
        self.interrupted(signal.SIGTERM, ("--matches=1", "--jobs=1", "--seed=9000"))

    def test_ctrl_c_mid_match_stops_its_games_and_leaves_nothing(self):
        self.interrupted(signal.SIGINT, ("--matches=1", "--jobs=1", "--seed=9000"))

    def test_sigterm_mid_tests_stops_the_runners_games_and_leaves_nothing(self):
        self.interrupted(signal.SIGTERM, ("--tests",), stalls_in_tests)

    def test_sighup_mid_match_stops_its_games_and_leaves_nothing(self):
        self.interrupted(signal.SIGHUP, ("--matches=1", "--jobs=1", "--seed=9000"))


def made_by(repo: Path, alive: bool) -> tuple[Path, Path, subprocess.Popen]:
    """A copy and a hit folder of `repo` made by a separate process with the repo's own tool, which is then killed
    with SIGKILL (a run that could not clean up) or, with `alive`, left running (a run still going)."""
    code = ("import sys, time\n"
            "from tools.coverage import workspace\n"
            "print(workspace.create('.'), flush=True)\n"
            "print(workspace.hits_dir('.'), flush=True)\n"
            "time.sleep(600)\n")
    proc = subprocess.Popen([sys.executable, "-c", code], cwd=repo, env=env_with_godot(), stdout=subprocess.PIPE,
                            text=True)
    copy, hits_dir = Path(proc.stdout.readline().strip()), Path(proc.stdout.readline().strip())
    if not alive:
        end(proc)
    return copy, hits_dir, proc


def end(proc: subprocess.Popen) -> None:
    if proc.poll() is None:
        proc.send_signal(signal.SIGKILL)
        proc.wait(timeout=30)
    proc.stdout.close()


@needs_godot
class LeftoverTests(unittest.TestCase):
    def test_a_run_sweeps_a_killed_runs_folders_and_never_a_live_ones(self):
        with TempDir() as d:
            repo = fixture_repo(d)
            live_copy, live_hits, live = made_by(repo, alive=True)
            self.addCleanup(end, live)
            dead_copy, dead_hits, _ = made_by(repo, alive=False)
            for folder in (live_copy, live_hits, dead_copy, dead_hits):
                self.assertTrue(folder.is_dir(), folder)
            r = run_cli(repo, "run", "--matches=1", "--jobs=1", "--seed=100")
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertFalse(dead_copy.exists() or dead_hits.exists(), "the killed run's folders are swept")
            self.assertEqual(scratch_left(repo), sorted([live_copy.name, live_hits.name]),
                             "the live run's are kept, and the run left nothing of its own")


def slow_to_stop_in_tests(log: Path):
    """An `edit` for fixture_repo: the fixture's tools/run_tests.sh writes its pid to `log`.pid, starts a game that
    never ends and then never ends itself, logging each SIGTERM it gets to `log` instead of stopping, so the run's
    cleanup waits out stop_group's grace for it before its SIGKILL."""
    def edit(repo: Path) -> None:
        script = repo / "tools" / "run_tests.sh"
        text = script.read_text()
        anchor = "status=0\n"
        assert anchor in text
        script.write_text(text.replace(anchor, (
            f'echo $$ > "{log}.pid"\n'
            f"trap 'echo term >> \"{log}\"' TERM\n"
            'env -u FE_COVERAGE "$GODOT" --headless --path . &\n'
            "while true; do sleep 0.1; done\n") + anchor, 1))
    return edit


def von_server_path(path: Path):
    """An `edit` for fixture_repo: the project's `application/von/server_path` is `path`."""
    def edit(repo: Path) -> None:
        project = repo / "project.godot"
        text = project.read_text()
        anchor = "[application]\n\n"
        assert anchor in text
        project.write_text(text.replace(anchor, f'{anchor}von/server_path="{path}"\n', 1))
    return edit


# A stand-in Von server that never answers: it writes its pid to argv[0].pid, logs each SIGTERM to argv[0].log and,
# when STUBBORN is True, keeps running through it (stop_von waits out its grace, then SIGKILLs it).
FAKE_VON = '''import os, signal, sys, time
me = sys.argv[0]
def on_term(_signum, _frame):
    with open(me + ".log", "a") as log:
        log.write("term\\n")
    if not STUBBORN:
        sys.exit(0)
signal.signal(signal.SIGTERM, on_term)
with open(me + ".pid.part", "w") as f:
    f.write(str(os.getpid()))
os.replace(me + ".pid.part", me + ".pid")
while True:
    time.sleep(0.1)
'''


def fake_von(d: Path, stubborn: bool) -> Path:
    path = d / "fake_von"
    path.write_text(f"#!{sys.executable}\nSTUBBORN = {stubborn}\n{FAKE_VON}")
    path.chmod(0o755)
    return path


def read_pid(path: Path) -> int | None:
    try:
        return int(path.read_text())
    except (OSError, ValueError):
        return None


def logged_term(log: Path) -> bool:
    try:
        return "term" in log.read_text()
    except OSError:
        return False


def signal_main_when(steps, timeout: float = 120) -> threading.Thread:
    """A thread that sends this process's main thread each signal of `steps` ((condition, signal) pairs, in order) as
    soon as its condition holds, and sends nothing more once a condition does not hold within `timeout` seconds."""
    def go():
        for condition, sig in steps:
            if not wait_for(condition, timeout=timeout, step=0.05):
                return
            signal.pthread_kill(threading.main_thread().ident, sig)
    thread = threading.Thread(target=go, daemon=True)
    thread.start()
    return thread


def kill_left(test: unittest.TestCase, pid: int | None, group: bool = True) -> None:
    """When the process `pid` a test's run started is still alive (a run that left it running), SIGKILL it once the
    test ends, with its process group when `group` (a test runner, a Von server: each leads its own), so a failing
    test leaves nothing behind. Looked at now, never at the end: by then the pid of a process that is gone may be
    another's."""
    if pid is not None and not dead(pid):
        test.addCleanup(os.killpg if group else os.kill, pid, signal.SIGKILL)


@needs_godot
class SecondSignalTests(unittest.TestCase):
    """A second stopping signal, sent while the first one's cleanup runs, cuts none of it short."""

    def test_a_second_sigterm_while_the_test_runner_is_stopped_leaves_no_runner_game_or_folder(self):
        with TempDir() as d:
            log = d / "runner_term.log"
            repo = fixture_repo(d, slow_to_stop_in_tests(log))
            pid_file = Path(f"{log}.pid")
            output = d / "cli.out"
            # Its output goes to a file: a test runner left running would hold a pipe open.
            with open(output, "w") as out_file:
                cli = subprocess.Popen([sys.executable, str(repo / "tools" / "coverage.py"), "run", "--tests"],
                                       cwd=repo, env=env_with_godot(), stdin=subprocess.DEVNULL, stdout=out_file,
                                       stderr=subprocess.STDOUT)
            try:
                self.assertTrue(wait_for(lambda: read_pid(pid_file) and godot_processes_under(cli.pid), timeout=120),
                                "the test runner and its game are running")
                runner_pid = read_pid(pid_file)
                games = godot_processes_under(cli.pid)
                cli.send_signal(signal.SIGTERM)
                self.assertTrue(wait_for(lambda: logged_term(log), timeout=30), "the run's cleanup is stopping it")
                cli.send_signal(signal.SIGTERM)
                cli.wait(timeout=120)
            finally:
                if cli.poll() is None:
                    cli.kill()
                    cli.wait()
            out = output.read_text()
            stopped = wait_for(lambda: dead(runner_pid) and all(dead(p) for p in games), timeout=10)
            kill_left(self, runner_pid)
            self.assertEqual(cli.returncode, 128 + signal.SIGTERM, out)
            self.assertTrue(stopped,
                            f"the test runner and its games are stopped: runner {runner_pid} "
                            f"{'dead' if dead(runner_pid) else 'alive'}, games {[p for p in games if not dead(p)]}")
            self.assertEqual(scratch_left(repo), [], out)


class SignalPhaseTests(unittest.TestCase):
    """A stopping signal in each phase before play stops what the run started there and leaves nothing (in this
    process: no Godot is reached)."""

    def run_to_interrupt(self, repo: Path) -> None:
        handlers = {s: signal.getsignal(s) for s in runner.STOPPING}
        with self.assertRaises(runner.Interrupted) as raised:
            runner.run(repo, "matches", matches=1, jobs=1, seed=100, endless_every=0, say=lambda _text: None,
                       shout=lambda _text: None)
        self.assertEqual(raised.exception.signum, signal.SIGTERM)
        self.assertEqual({s: signal.getsignal(s) for s in runner.STOPPING}, handlers,
                         "the stopping signals are handled as before the run once it is done")

    def test_a_second_sigterm_while_a_started_von_server_is_stopped_leaves_it_stopped_and_nothing_left(self):
        with TempDir() as d:
            von = fake_von(d, stubborn=True)
            pid_file = Path(f"{von}.pid")
            repo = fixture_repo(d, von_server_path(von))
            with mock.patch.object(runner, "von_live", return_value=False):
                sender = signal_main_when([(lambda: read_pid(pid_file), signal.SIGTERM),
                                           (lambda: logged_term(Path(f"{von}.log")), signal.SIGTERM)])
                try:
                    self.run_to_interrupt(repo)
                finally:
                    sender.join(timeout=5)
                    kill_left(self, read_pid(pid_file))
            self.assertTrue(logged_term(Path(f"{von}.log")), "the run's cleanup was stopping the server")
            self.assertTrue(dead(read_pid(pid_file)), "the Von server the run started is stopped")
            self.assertEqual(scratch_left(repo), [])

    def test_sigterm_while_waiting_for_a_started_von_server_stops_it_and_leaves_nothing(self):
        with TempDir() as d:
            von = fake_von(d, stubborn=False)
            pid_file = Path(f"{von}.pid")
            repo = fixture_repo(d, von_server_path(von))
            with mock.patch.object(runner, "von_live", return_value=False):
                sender = signal_main_when([(lambda: read_pid(pid_file), signal.SIGTERM)])
                try:
                    self.run_to_interrupt(repo)
                finally:
                    sender.join(timeout=5)
                    kill_left(self, read_pid(pid_file))
            self.assertTrue(dead(read_pid(pid_file)), "the Von server the run started is stopped")
            self.assertEqual(scratch_left(repo), [])

    def test_sigterm_while_copying_the_repo_leaves_nothing(self):
        copied = []
        real_copy2 = shutil.copy2

        def copy2(*args, **kwargs):
            copied.append(args[0])
            real_copy2(*args, **kwargs)
            if len(copied) == 3:
                signal.raise_signal(signal.SIGTERM)

        with TempDir() as d:
            repo = fixture_repo(d)
            with mock.patch.object(workspace.shutil, "copy2", copy2):
                self.run_to_interrupt(repo)
            self.assertEqual(len(copied), 3, "the signal came in part-way through the copy")
            self.assertEqual(scratch_left(repo), [])

    def test_sigterm_while_instrumenting_the_copy_leaves_nothing(self):
        instrumented = []
        real_instrument = instrument.instrument

        def instrument_then_signal(copy, **kwargs):
            instrumented.append(real_instrument(copy, **kwargs))
            signal.raise_signal(signal.SIGTERM)

        with TempDir() as d:
            repo = fixture_repo(d)
            with mock.patch.object(instrument, "instrument", instrument_then_signal):
                self.run_to_interrupt(repo)
            self.assertTrue(instrumented, "the signal came in as the copy was instrumented")
            self.assertEqual(scratch_left(repo), [])


@needs_godot
class TreeGuardTests(unittest.TestCase):
    def test_a_run_that_changes_the_repo_fails_loudly(self):
        with TempDir() as d:
            repo = fixture_repo(d)
            touched = repo / "scenes" / "touched.gd"
            r = run_cli(repo, "run", "--matches=1", "--jobs=1", "--seed=100", FIXTURE_TOUCH=str(touched))
            self.assertTrue(touched.exists(), "the fixture game wrote into the repo, as a broken run could")
        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("scenes/touched.gd", r.stdout + r.stderr)

    def test_the_first_run_in_a_fresh_clone_passes_its_tree_check(self):
        # The fixture repo ignores what the real repo ignores (its own .gitignore, read here) and has no artifacts/
        # yet: the run folder and the artifacts/.gdignore the run writes must not show in git status.
        def with_the_real_gitignore(repo: Path) -> None:
            (repo / ".gitignore").write_text((ROOT / ".gitignore").read_text())

        with TempDir() as d:
            repo = fixture_repo(d, with_the_real_gitignore)
            self.assertFalse((repo / "artifacts").exists())
            r = run_cli(repo, "run", "--matches=1", "--jobs=1", "--seed=100")
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertTrue((repo / "artifacts" / ".gdignore").is_file())
            self.assertEqual(git_status(repo), "")

    def test_a_run_that_fails_part_way_names_what_it_changed(self):
        with TempDir() as d:
            repo = fixture_repo(d, without_world)
            touched = repo / "scenes" / "touched.gd"
            r = run_cli(repo, "run", "--matches=1", "--jobs=1", "--seed=100", FIXTURE_TOUCH=str(touched))
            self.assertTrue(touched.exists(), "the fixture game wrote into the repo, as a broken run could")
        out = r.stdout + r.stderr
        self.assertNotEqual(r.returncode, 0, out)
        self.assertIn("match_world", out, "why it failed")
        self.assertIn("the run changed the repo", out)
        self.assertIn("scenes/touched.gd", out)

    def test_a_run_that_fails_part_way_says_it_changed_nothing(self):
        with TempDir() as d:
            repo = fixture_repo(d, without_world)
            r = run_cli(repo, "run", "--matches=1", "--jobs=1", "--seed=100")
        out = r.stdout + r.stderr
        self.assertNotEqual(r.returncode, 0, out)
        self.assertIn("match_world", out, "why it failed")
        self.assertIn("the repo is unchanged", out)


@needs_godot
class InstrumentCommandTests(unittest.TestCase):
    def test_instrument_builds_a_copy_in_artifacts_tmp_and_leaves_the_repo_untouched(self):
        with TempDir() as d:
            repo = fixture_repo(d)
            before = (git_status(repo), tree_digest(repo))
            r = run_cli(repo, "instrument")
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            copy = Path(r.stdout.strip().splitlines()[-1])
            try:
                self.assertTrue((copy / "project.godot").is_file(), copy)
                self.assertEqual(copy.resolve().parent, (repo / "artifacts" / "tmp").resolve())
                autoload = (copy / "project.godot").read_text().split("[autoload]", 1)[1].strip().splitlines()[0]
                self.assertTrue(autoload.startswith("CoverageProbe="), autoload)
                self.assertEqual((git_status(repo), tree_digest(repo)), before)
            finally:
                workspace.cleanup(repo, copy)


@slow
@needs_godot
class WindowedRunTests(unittest.TestCase):
    def test_windowed_is_recorded(self):
        with TempDir() as d:
            repo = fixture_repo(d)
            r = run_cli(repo, "run", "--matches=1", "--jobs=1", "--seed=100", "--windowed")
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            meta = read_json(newest_run(repo, "matches") / "meta.json")
        self.assertIs(meta["windowed"], True)


if __name__ == "__main__":
    unittest.main()
