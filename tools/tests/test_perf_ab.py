"""tools/perf_ab.sh (the same-fight A/B of two revisions, #203) in a throwaway git repo of its own: two commits that each hold a
fake tools/run_tests.sh (the revision's own, which the tool must call in that revision's scratch worktree) and a fake.json that says
what that revision "plays": the avg / p95 / max of each of its runs and the fingerprint it writes. A plan file, keyed by the number
of the run_tests.sh call, marks single runs loaded or makes them write another fight. Nothing runs Godot."""
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GUARDS = ["perf/match_5v5_stress", "perf/grenade_match_stress", "perf/match_10v10_stress", "perf/match_npc_vision"]

# The revision's tools/run_tests.sh. It reads the fake.json at the root of the tree it lives in: {"name", "avgs": [one per run of
# this revision, the last one repeats], "p95", "max", "frames", "diverge": frame, "no_fingerprint": bool}, notes each call in
# $FAKE_LOG (`<name> <pwd> fp=<dir> <args>`) and applies $FAKE_PLAN[<number of this call>] = {"loaded", "diverge", "avg"}.
FAKE_RUN_TESTS = r"""#!/usr/bin/env python3
import json, os, sys
from pathlib import Path

tree = Path(__file__).resolve().parents[1]
data = json.loads((tree / "fake.json").read_text())
log = Path(os.environ["FAKE_LOG"])
lines = log.read_text().splitlines() if log.exists() else []
number = len(lines) + 1
mine = len([l for l in lines if l.split()[0] == data["name"]])
plan_file = os.environ.get("FAKE_PLAN")
plan = json.loads(Path(plan_file).read_text()).get(str(number), {}) if plan_file and Path(plan_file).exists() else {}
fp = os.environ.get("GAME_TEST_FINGERPRINT_DIR", "<unset>")
with log.open("a") as f:
    f.write("%s %s fp=%s %s\n" % (data["name"], Path.cwd().resolve(), fp, " ".join(sys.argv[1:])))
ids = [a[len("--id="):].split(",") for a in sys.argv[1:] if a.startswith("--id=")][0]
avgs = data["avgs"]
avg = plan.get("avg", avgs[min(mine, len(avgs) - 1)])
diverge = plan.get("diverge", data.get("diverge"))
for test_id in ids:
    if fp != "<unset>" and not data.get("no_fingerprint"):
        Path(fp).mkdir(parents=True, exist_ok=True)
        rows = ["%d\tstate-%d" % (i, i) for i in range(data.get("frames", 6))]
        if diverge is not None and diverge < len(rows):
            rows[diverge] = "%d\tother-%s" % (diverge, data["name"])
        (Path(fp) / (test_id.replace("/", "__") + ".fp")).write_text("\n".join(rows) + "\n")
    print("PERF fake match contact at 8.7 s (load 1.00, 0 busy Godot)")
    if not data.get("no_perf"):
        print("PERF fake match avg ms/frame %.2f (budget 16.70) (load 1.00, 0 busy Godot)" % avg)
        print("PERF fake match p95 ms/frame %.2f (budget 20.00) (load 1.00, 0 busy Godot)" % data.get("p95", avg + 3))
        print("PERF fake match max ms/frame %.2f (budget 33.40) (load 1.00, 0 busy Godot)" % data.get("max", avg + 8))
    print("PERF fake match node growth 251 (load 1.00, 0 busy Godot)")
    status = "PASS" if avg <= 16.7 else "FAIL"
    print("%s    %s  (13.7s sim, 14341 ms)%s" % (status, test_id, "  loaded" if plan.get("loaded") else ""))
print("1 passed, 0 failed, 0 timed out, 0 skipped, 0 gap  load 1.00")
sys.exit(0 if avg <= 16.7 else 1)
"""


class PerfAbTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="perf_ab_"))
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.state = self.tmp / "state"
        self.state.mkdir()
        self.repo = self.tmp / "repo"
        (self.repo / "tools").mkdir(parents=True)
        for name in ("perf_ab.sh", "perf_ab.py"):
            shutil.copy2(ROOT / "tools" / name, self.repo / "tools" / name)
        self.log = self.tmp / "calls.log"
        self.plan = self.tmp / "plan.json"
        self.git("init", "-q")
        self.commit("base", avgs=[10.0])
        self.base = self.git("rev-parse", "HEAD").strip()
        self.commit("tip", avgs=[10.0])
        self.tip = self.git("rev-parse", "HEAD").strip()

    def git(self, *args, cwd=None):
        env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
        return subprocess.run(["git", *args], cwd=cwd or self.repo, env=env, check=True, capture_output=True, text=True).stdout

    def commit(self, name, **data):
        """A commit whose revision plays `data` (its name, a fake run_tests.sh and fake.json)."""
        script = self.repo / "tools" / "run_tests.sh"
        script.write_text(FAKE_RUN_TESTS)
        script.chmod(0o755)
        (self.repo / "fake.json").write_text(json.dumps({"name": name, **data}))
        (self.repo / ".gitignore").write_text(".godot/\n")
        self.git("add", "-A")
        self.git("-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "--allow-empty", "-m", name)
        return self.git("rev-parse", "HEAD").strip()

    def revs(self, base=None, tip=None):
        """Two new commits, the revision that plays `base` (a dict for fake.json) and the one that plays `tip`: their shas."""
        return self.commit("base", **(base or {"avgs": [10.0]})), self.commit("tip", **(tip or {"avgs": [10.0]}))

    def perf_ab(self, *args, plan=None):
        if plan is not None:
            self.plan.write_text(json.dumps(plan))
        env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
        env.update(TMPDIR=str(self.state), FAKE_LOG=str(self.log), FAKE_PLAN=str(self.plan))
        r = subprocess.run(["bash", str(self.repo / "tools" / "perf_ab.sh"), *args], cwd=self.repo, env=env,
                           capture_output=True, text=True, timeout=120)
        return r.returncode, r.stdout + r.stderr

    def calls(self):
        return [l.split(" ", 3) for l in self.log.read_text().splitlines()] if self.log.exists() else []

    def names(self):
        return [c[0] for c in self.calls()]

    def trees(self):
        root = self.state / "forced-entry-perf-ab"
        return sorted(p.name for p in root.iterdir() if p.name != "runs") if root.is_dir() else []

    def test_rounds_interleave_base_and_tip(self):
        code, out = self.perf_ab(self.base, self.tip, "--rounds=3")
        self.assertEqual(code, 0, out)
        self.assertEqual(self.names(), ["base", "tip"] * 3)

    def test_each_round_runs_that_revisions_own_run_tests_in_its_own_tree_quiet_and_verbose_on_the_default_ids(self):
        code, out = self.perf_ab(self.base, self.tip, "--rounds=1")
        self.assertEqual(code, 0, out)
        (_, base_pwd, _, base_args), (_, tip_pwd, _, tip_args) = self.calls()
        self.assertEqual(Path(base_pwd), (self.state / "forced-entry-perf-ab" / self.base).resolve())
        self.assertEqual(Path(tip_pwd), (self.state / "forced-entry-perf-ab" / self.tip).resolve())
        for args in (base_args, tip_args):
            self.assertIn("--quiet", args.split())
            self.assertIn("--verbose", args.split())
            self.assertIn("--id=" + ",".join(GUARDS), args.split())

    def test_ids_replace_the_default_four(self):
        code, out = self.perf_ab(self.base, self.tip, "--rounds=1", "--ids=perf/match_5v5_stress")
        self.assertEqual(code, 0, out)
        self.assertTrue(all("--id=perf/match_5v5_stress" in c[3].split() for c in self.calls()), self.calls())
        self.assertNotIn("perf/match_10v10_stress", out)

    def test_every_round_gets_a_fingerprint_directory_of_its_own_as_an_absolute_path(self):
        code, out = self.perf_ab(self.base, self.tip, "--rounds=2")
        self.assertEqual(code, 0, out)
        dirs = [c[2] for c in self.calls()]
        self.assertTrue(all(d.startswith("fp=/") for d in dirs), dirs)
        self.assertEqual(len(set(dirs)), 4, dirs)

    def test_it_prints_the_medians_and_the_delta_in_percent_of_the_base_average_per_test(self):
        base, tip = self.revs({"avgs": [10.0, 10.0, 100.0], "p95": 14.0, "max": 20.0},
                              {"avgs": [11.0, 12.0, 11.0], "p95": 15.0, "max": 25.0})
        code, out = self.perf_ab(base, tip, "--rounds=3", "--ids=perf/match_5v5_stress", "--bar=25")
        self.assertEqual(code, 0, out)
        # The median of BASE's 10, 10, 100 is 10 (the outlier is no mean); TIP's is 11. 1 ms is 10 % of BASE's avg.
        self.assertRegex(out, r"avg\s+BASE\s+10\.00 ms\s+TIP\s+11\.00 ms\s+delta \+1\.00 ms \(\+10\.0% of BASE avg\)")
        self.assertRegex(out, r"p95\s+BASE\s+14\.00 ms\s+TIP\s+15\.00 ms\s+delta \+1\.00 ms \(\+10\.0% of BASE avg\)")
        self.assertRegex(out, r"max\s+BASE\s+20\.00 ms\s+TIP\s+25\.00 ms\s+delta \+5\.00 ms \(\+50\.0% of BASE avg\)")
        self.assertIn("perf/match_5v5_stress", out)

    def test_a_delta_over_the_bar_fails_and_one_under_it_passes(self):
        base, tip = self.revs(tip={"avgs": [10.6]})  # +6 % of 10.0
        code, out = self.perf_ab(base, tip, "--rounds=2", "--bar=5", "--ids=perf/match_5v5_stress")
        self.assertEqual(code, 1, out)
        self.assertIn("FAIL", out)
        self.assertIn("+6.0%", out)
        code, out = self.perf_ab(base, tip, "--rounds=2", "--bar=7", "--ids=perf/match_5v5_stress")
        self.assertEqual(code, 0, out)
        self.assertIn("PASS", out)

    def test_the_default_bar_is_five_percent(self):
        base, tip = self.revs(tip={"avgs": [10.4]})
        self.assertEqual(self.perf_ab(base, tip, "--rounds=1", "--ids=perf/match_5v5_stress")[0], 0)
        base, tip = self.revs(tip={"avgs": [10.6]})
        self.assertEqual(self.perf_ab(base, tip, "--rounds=1", "--ids=perf/match_5v5_stress")[0], 1)

    def test_a_tip_that_is_faster_passes(self):
        base, tip = self.revs(tip={"avgs": [8.0]})
        code, out = self.perf_ab(base, tip, "--rounds=1", "--bar=0", "--ids=perf/match_5v5_stress")
        self.assertEqual(code, 0, out)
        self.assertIn("-20.0%", out)

    def test_a_run_tests_that_exits_non_zero_over_a_budget_is_not_a_failed_round(self):
        base, tip = self.revs({"avgs": [20.0]}, {"avgs": [20.5]})
        code, out = self.perf_ab(base, tip, "--rounds=2", "--ids=perf/match_5v5_stress")
        self.assertEqual(code, 0, out)
        self.assertEqual(self.names(), ["base", "tip"] * 2)
        self.assertIn("+2.5%", out)

    def test_a_loaded_round_is_dropped_and_run_again(self):
        # Call 3 is BASE's second round, marked loaded and 99 ms: its numbers must not enter the median.
        code, out = self.perf_ab(self.base, self.tip, "--rounds=2", "--ids=perf/match_5v5_stress",
                                 plan={"3": {"loaded": True, "avg": 99.0}})
        self.assertEqual(code, 0, out)
        self.assertEqual(self.names(), ["base", "tip", "base", "base", "tip"], "the round ran again, on the same revision")
        self.assertIn("loaded", out)
        self.assertIn("dropped", out)
        self.assertNotIn("99.00", out)
        self.assertIn("+0.0%", out)

    def test_loaded_reruns_are_capped_and_the_run_says_so(self):
        plan = {str(n): {"loaded": True} for n in range(1, 40)}
        code, out = self.perf_ab(self.base, self.tip, "--rounds=2", "--retries=2", "--ids=perf/match_5v5_stress", plan=plan)
        self.assertEqual(code, 2, out)
        self.assertEqual(len(self.calls()), 3, "one run and two reruns, then it gives up")
        self.assertRegex(out, r"still marked loaded after 2 reruns")
        self.assertNotIn("delta", out)

    def test_fingerprints_that_differ_refuse_with_the_first_frame_the_test_and_the_revisions_and_print_no_delta(self):
        base, tip = self.revs(tip={"avgs": [10.0], "diverge": 3})
        code, out = self.perf_ab(base, tip, "--rounds=2", "--ids=perf/match_5v5_stress")
        self.assertNotEqual(code, 0, out)
        self.assertIn("fights differ from frame 3", out)
        self.assertIn("perf/match_5v5_stress", out)
        self.assertIn(tip[:8], out)
        self.assertNotIn("delta", out)
        self.assertNotIn("PASS", out)
        self.assertEqual(self.names(), ["base", "tip"], "it stops at the first round that shows it")

    def test_two_plays_of_base_that_differ_refuse_too(self):
        # Call 3 is BASE's second round: a revision that does not replay its own fight cannot be compared at all.
        code, out = self.perf_ab(self.base, self.tip, "--rounds=2", "--ids=perf/match_5v5_stress", plan={"3": {"diverge": 2}})
        self.assertNotEqual(code, 0, out)
        self.assertIn("fights differ from frame 2", out)
        self.assertRegex(out, r"BASE %s round 1 against BASE %s round 2" % (self.base[:8], self.base[:8]))
        self.assertNotIn("delta", out)

    def test_the_first_differing_frame_is_the_first_of_every_test(self):
        base, tip = self.revs(tip={"avgs": [10.0], "diverge": 4})
        code, out = self.perf_ab(base, tip, "--rounds=1", "--ids=perf/match_5v5_stress,perf/match_npc_vision")
        self.assertNotEqual(code, 0, out)
        self.assertIn("fights differ from frame 4: perf/match_5v5_stress", out)

    def test_a_fingerprint_that_is_a_prefix_of_the_other_differs_at_the_frame_it_ends_on(self):
        base, tip = self.revs(tip={"avgs": [10.0], "frames": 4})  # base wrote frames 0..5, tip 0..3
        code, out = self.perf_ab(base, tip, "--rounds=1", "--ids=perf/match_5v5_stress")
        self.assertNotEqual(code, 0, out)
        self.assertIn("fights differ from frame 4", out)

    def test_a_revision_that_writes_no_fingerprint_ends_the_run_naming_it(self):
        base = self.commit("base", avgs=[10.0], no_fingerprint=True)
        code, out = self.perf_ab(base, base, "--rounds=1", "--ids=perf/match_5v5_stress")
        self.assertEqual(code, 2, out)
        self.assertIn("wrote no fight fingerprint", out)
        self.assertNotIn("delta", out)

    def test_a_test_with_no_perf_lines_ends_the_run_naming_it(self):
        base = self.commit("base", avgs=[10.0], no_perf=True)
        code, out = self.perf_ab(base, base, "--rounds=1", "--ids=perf/match_5v5_stress")
        self.assertEqual(code, 2, out)
        self.assertIn("perf/match_5v5_stress", out)
        self.assertIn("avg/p95/max ms/frame", out)

    def test_the_scratch_trees_are_kept_and_reused_by_the_next_run(self):
        code, out = self.perf_ab(self.base, self.tip, "--rounds=1")
        self.assertEqual(code, 0, out)
        self.assertEqual(self.trees(), sorted([self.base, self.tip]))
        (self.state / "forced-entry-perf-ab" / self.base / "built.marker").write_text("godot import")
        code, out = self.perf_ab(self.base, self.tip, "--rounds=1")
        self.assertEqual(code, 0, out)
        self.assertTrue((self.state / "forced-entry-perf-ab" / self.base / "built.marker").exists(), "the tree was not rebuilt")
        listed = self.git("worktree", "list", "--porcelain")
        self.assertEqual(listed.count("forced-entry-perf-ab"), 2, listed)

    def test_the_same_revision_twice_shares_one_tree(self):
        code, out = self.perf_ab("HEAD", self.tip, "--rounds=1")  # HEAD is the tip commit of setUp
        self.assertEqual(code, 0, out)
        self.assertEqual(self.trees(), [self.tip])
        self.assertEqual(self.names(), ["tip", "tip"])
        self.assertIn("+0.0%", out)

    def test_revisions_are_resolved_to_shas_first(self):
        code, out = self.perf_ab("HEAD~1", "HEAD", "--rounds=1")
        self.assertEqual(code, 0, out)
        self.assertEqual(self.trees(), sorted([self.base, self.tip]))
        self.assertIn(self.base[:8], out)
        self.assertIn(self.tip[:8], out)

    def test_a_tree_deleted_by_hand_is_made_again(self):
        self.assertEqual(self.perf_ab(self.base, self.tip, "--rounds=1")[0], 0)
        shutil.rmtree(self.state / "forced-entry-perf-ab" / self.base)
        code, out = self.perf_ab(self.base, self.tip, "--rounds=1")
        self.assertEqual(code, 0, out)
        self.assertEqual(self.trees(), sorted([self.base, self.tip]))

    def test_clean_removes_the_trees_this_run_made_and_leaves_no_worktree_record(self):
        code, out = self.perf_ab(self.base, self.tip, "--rounds=1", "--clean")
        self.assertEqual(code, 0, out)
        self.assertEqual(self.trees(), [])
        self.assertNotIn("forced-entry-perf-ab", self.git("worktree", "list", "--porcelain"))

    def test_clean_alone_removes_every_scratch_tree(self):
        self.assertEqual(self.perf_ab(self.base, self.tip, "--rounds=1")[0], 0)
        self.assertEqual(len(self.trees()), 2)
        code, out = self.perf_ab("--clean")
        self.assertEqual(code, 0, out)
        self.assertEqual(self.trees(), [])
        self.assertNotIn("forced-entry-perf-ab", self.git("worktree", "list", "--porcelain"))

    def test_the_fingerprints_are_removed_when_the_run_ends_clean_and_kept_when_the_fights_differ(self):
        self.assertEqual(self.perf_ab(self.base, self.tip, "--rounds=1")[0], 0)
        self.assertFalse((self.state / "forced-entry-perf-ab" / "runs").exists())
        base, tip = self.revs(tip={"avgs": [10.0], "diverge": 1})
        code, out = self.perf_ab(base, tip, "--rounds=1", "--ids=perf/match_5v5_stress")
        self.assertNotEqual(code, 0, out)
        kept = [l.strip() for l in out.splitlines() if l.strip().endswith(".fp")]
        self.assertEqual(len(kept), 2, out)
        self.assertTrue(all(Path(k).is_file() for k in kept), kept)

    def test_argument_errors_exit_2_before_any_tree_or_run(self):
        for args in ([], [self.base], [self.base, self.tip, "HEAD"], [self.base, self.tip, "--rounds=0"],
                     [self.base, self.tip, "--rounds=x"], [self.base, self.tip, "--rounds=-2"], [self.base, self.tip, "--bar=-1"],
                     [self.base, self.tip, "--bar=x"], [self.base, self.tip, "--ids="], [self.base, self.tip, "--ids=perf/a b"],
                     [self.base, self.tip, "--retries=x"], [self.base, self.tip, "--nope"], ["nosuchrev", self.tip],
                     [self.base, "nosuchrev"]):
            with self.subTest(args=args):
                code, out = self.perf_ab(*args)
                self.assertEqual(code, 2, out)
                self.assertRegex(out, r"usage:|unknown revision")
                self.assertEqual(self.calls(), [])
                self.assertEqual(self.trees(), [])

    def test_the_unknown_revision_is_named(self):
        code, out = self.perf_ab("nosuchrev", self.tip)
        self.assertEqual(code, 2, out)
        self.assertIn("unknown revision: nosuchrev", out)


if __name__ == "__main__":
    unittest.main()
