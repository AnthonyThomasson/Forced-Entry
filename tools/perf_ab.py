#!/usr/bin/env python3
"""Same-fight A/B of two revisions on the match guards (#203): tools/perf_ab.sh BASE TIP [options].

A revision plays its own match, so two revisions' frame times are only comparable when they played the same fight (read
.skillshare/skills/domain-testing/perf-nondeterminism.md and perf-fingerprint.md). This tool runs the match guards on both revisions in
rounds (BASE, TIP, BASE, TIP ...), each through that revision's own tools/run_tests.sh with GAME_TEST_FINGERPRINT_DIR set
to a directory of that round, checks every round's fight fingerprint against the first one of BASE and, only when every
fight is the same, prints per test the medians of avg / p95 / max ms per frame for BASE and TIP and the delta.

  tools/perf_ab.sh BASE TIP [--different-fights] [--ids=perf/a,perf/b] [--rounds=6] [--bar=5] [--retries=3] [--quiet=30] [--clean]
  tools/perf_ab.sh --clean

Two modes. Use the default (same fight) for a change that keeps every result identical (a speed-up that must not change what the
game does): it proves the fight is the same and the delta is the code's. Use --different-fights for a change that changes the
fight on purpose (a decision that lands later, a cone published late): the two revisions cannot play one fight, so it only
checks that each revision still replays its own, and the delta is a statement about two different matches' cost.

  BASE, TIP    two revisions (anything `git rev-parse` resolves), resolved to shas first: BASE and TIP may be the same sha.
  --ids=       the tests to run, a comma list (default: the four match guards: perf/match_5v5_stress,
               perf/grenade_match_stress, perf/match_10v10_stress, perf/match_npc_vision).
  --different-fights
               BASE and TIP may play different fights (a behaviour-changing slice). Default rounds 10 (more rounds: the medians
               of two different fights are noisier than of one). The rounds still interleave and a round marked loaded is still
               dropped. The refusal changes: BASE's fingerprints and TIP's are not compared with each other, but every round of a
               side is compared with that side's first round, and a round that differs ends the run (exit 3, `<SIDE> does not
               replay its own fight: frame N`, the side, the test and the files named): frame times of a revision that plays a
               different match every round say nothing. The report is labelled DIFFERENT FIGHTS, says per test whether BASE and
               TIP happened to play the same fight (and from which frame they differ), prints the medians of avg / p95 / max and
               their deltas, and holds the avg delta to --bar as ever (p95 and max are printed, not held). Without the flag the
               strict same-fight mode is unchanged.
  --rounds=N   rounds of BASE then TIP (default 6; 10 with --different-fights).
  --bar=P      the delta of the median avg, in percent of BASE's median avg, a TIP may not exceed (default 5); the run
               exits 1 past it. p95 and max are printed as percent of BASE's avg too, and are not held.
  --retries=N  a round whose result is marked `loaded` (run_tests.sh --quiet gave up waiting for a quiet machine) is
               dropped and run again, at most N times (default 3); a round still loaded after that ends the run (exit 2).
  --quiet=MIN  the minutes each run_tests.sh waits for a quiet machine before it runs anyway and marks its results loaded (its own
               default, 30, without it): with retries, a machine that never clears costs MIN x (retries + 1) a round.
  --clean      with BASE and TIP: remove their scratch trees when the run ends (otherwise they stay, built, for the next
               run); alone: remove every scratch tree.

Each revision gets a scratch git worktree at ${TMPDIR}/forced-entry-perf-ab/<sha> (made on the first run, reused while it holds
that sha and has no tracked file changed, else reset --hard to it keeping what git ignores, `.godot/`, so Godot's import is paid once; `git worktree prune` drops the record of one deleted by hand). The test run of each round is
`tools/run_tests.sh --no-lint --quiet --verbose --id=<ids>` of that tree (no lint: a revision's lint says nothing about its speed).
A run_tests.sh that exits non-zero is no failure here: the match guards miss their budgets on some revisions, and the PERF
lines are what is read. A round that wrote no fingerprint, or printed no PERF avg / p95 / max for a test, ends the run (exit 2).

Every round's run_tests.sh output is kept in its run directory (`run_tests.out`, named by a failure that read it); the run
directories are removed when the run ends well and kept when it does not.

Exit: 0 every test within the bar; 1 a delta over the bar (a regression); 3 the fights differ (a refusal, no delta is printed:
`fights differ from frame N`, N the first frame of two fingerprints that differs, the files kept and named; with --different-fights only
a side that differs from its own first round); 2 a usage error or a run that could not be read.
"""
from __future__ import annotations

import os
import re
import shutil
import statistics
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SCRATCH_NAME = "forced-entry-perf-ab"
DEFAULT_IDS = ("perf/match_5v5_stress", "perf/grenade_match_stress", "perf/match_10v10_stress", "perf/match_npc_vision")
DEFAULT_ROUNDS = 6
DEFAULT_ROUNDS_DIFFERENT_FIGHTS = 10
DEFAULT_BAR = 5.0
DEFAULT_RETRIES = 3
METRICS = ("avg", "p95", "max")
PERF_LINE = re.compile(r"^PERF (?P<label>.+) (?P<metric>avg|p95|max) ms/frame (?P<value>-?\d+(?:\.\d+)?) \(budget")
VERDICT = re.compile(r"^(?P<status>PASS|FAIL|TIMEOUT|SKIPPED|GAP)\s+(?P<id>\S+)\s+\((?P<rest>.*)$")
# godot_slot.py annotate marks a verdict line of a loaded process with this suffix (after a TIMEOUT or SKIPPED reason too).
LOADED_SUFFIX = re.compile(r"  loaded$")
EXIT_OVER_BAR = 1
EXIT_UNREADABLE = 2
EXIT_FIGHTS_DIFFER = 3
USAGE = "usage: tools/perf_ab.sh BASE TIP [--different-fights] [--ids=perf/a,perf/b] [--rounds=6] [--bar=5] [--retries=3] [--quiet=30] [--clean]   |   tools/perf_ab.sh --clean"


class Fail(Exception):
    """A run that ends with `code` and says why."""

    def __init__(self, message: str, code: int = EXIT_UNREADABLE):
        super().__init__(message)
        self.code = code


class Options:
    def __init__(self):
        self.revisions: list[str] = []
        self.ids = list(DEFAULT_IDS)
        self.rounds: int | None = None  # None: the mode's default (settled after the flags are read)
        self.different_fights = False
        self.bar = DEFAULT_BAR
        self.retries = DEFAULT_RETRIES
        self.quiet = "--quiet"
        self.clean = False


def parse_args(argv: list[str]) -> Options:
    o = Options()
    for a in argv:
        if a == "--clean":
            o.clean = True
        elif a == "--different-fights":
            o.different_fights = True
        elif a.startswith("--ids="):
            o.ids = [i for i in a[len("--ids="):].split(",") if i]
            if not o.ids or any(not re.fullmatch(r"[\w/.-]+", i) for i in o.ids):
                raise Fail("--ids wants a comma list of test ids (perf/match_5v5_stress), got: %s\n%s" % (a, USAGE))
        elif a.startswith("--rounds="):
            o.rounds = whole(a, "--rounds", 1)
        elif a.startswith("--quiet="):
            minutes = a[len("--quiet="):]
            try:
                valid = float(minutes) > 0
            except ValueError:
                valid = False
            if not valid:
                raise Fail("--quiet wants the minutes to wait for a quiet machine (30), got: %s\n%s" % (a, USAGE))
            o.quiet = a
        elif a.startswith("--retries="):
            o.retries = whole(a, "--retries", 0)
        elif a.startswith("--bar="):
            try:
                o.bar = float(a[len("--bar="):])
            except ValueError:
                raise Fail("--bar wants a percent (5), got: %s\n%s" % (a, USAGE)) from None
            if not o.bar >= 0:
                raise Fail("--bar wants a percent of zero or more, got: %s\n%s" % (a, USAGE))
        elif a.startswith("--"):
            raise Fail("unknown flag: %s\n%s" % (a, USAGE))
        else:
            o.revisions.append(a)
    if o.rounds is None:
        o.rounds = DEFAULT_ROUNDS_DIFFERENT_FIGHTS if o.different_fights else DEFAULT_ROUNDS
    if o.revisions == [] and o.clean:
        return o
    if len(o.revisions) != 2:
        raise Fail("two revisions wanted (BASE TIP), got %d\n%s" % (len(o.revisions), USAGE))
    return o


def whole(arg: str, name: str, least: int) -> int:
    text = arg.split("=", 1)[1]
    if not text.isdigit() or int(text) < least:
        raise Fail("%s wants a whole number of %d or more, got: %s\n%s" % (name, least, arg, USAGE))
    return int(text)


def git(*args: str, cwd: Path = REPO, check: bool = True) -> subprocess.CompletedProcess:
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}  # a hook's index is not this repo's
    r = subprocess.run(["git", *args], cwd=cwd, env=env, capture_output=True, text=True)
    if check and r.returncode != 0:
        raise Fail("git %s failed: %s" % (" ".join(args), (r.stderr or r.stdout).strip()))
    return r


def resolve(rev: str) -> str:
    r = git("rev-parse", "--verify", "--quiet", rev + "^{commit}", check=False)
    if r.returncode != 0:
        raise Fail("unknown revision: %s" % rev)
    return r.stdout.strip()


def scratch_root() -> Path:
    return Path(tempfile.gettempdir()) / SCRATCH_NAME


def tree_holds(path: Path, sha: str) -> bool:
    if not path.is_dir():
        return False
    r = git("rev-parse", "HEAD", cwd=path, check=False)
    return r.returncode == 0 and r.stdout.strip() == sha and (path / ".git").exists()


def ensure_tree(sha: str) -> Path:
    """The scratch worktree of `sha`: reused while it holds that sha with no tracked file changed (a changed one is reset to
    it; untracked and ignored files, the `.godot/` import, stay), else made."""
    path = scratch_root() / sha
    if tree_holds(path, sha):
        if git("status", "--porcelain", "--untracked-files=no", cwd=path).stdout.strip():
            git("reset", "--hard", sha, cwd=path)
        return path
    if path.exists():
        shutil.rmtree(path, ignore_errors=True)  # a leftover of a run that died half way
    git("worktree", "prune")
    path.parent.mkdir(parents=True, exist_ok=True)
    git("worktree", "add", "--detach", "--force", str(path), sha)
    return path


def remove_tree(path: Path) -> None:
    git("worktree", "remove", "--force", str(path), check=False)
    shutil.rmtree(path, ignore_errors=True)
    git("worktree", "prune", check=False)


def clean_all() -> None:
    root = scratch_root()
    if root.is_dir():
        for child in sorted(root.iterdir()):
            if child.name != "runs":
                remove_tree(child)
        shutil.rmtree(root / "runs", ignore_errors=True)
    git("worktree", "prune", check=False)


class Round:
    """What one run_tests.sh process said: per test its metrics (the first label's avg / p95 / max), whether the result is
    marked loaded, and where the fingerprints went."""

    def __init__(self, directory: Path):
        self.dir = directory
        self.loaded = False
        self.stats: dict[str, dict[str, float]] = {}

    def fingerprint(self, test_id: str) -> Path:
        return self.dir / (test_id.replace("/", "__") + ".fp")


def read_output(text: str, ids: list[str], rnd: Round, where: str, saved: Path) -> None:
    pending: dict[str, float] = {}
    label = None
    for line in text.splitlines():
        m = PERF_LINE.match(line)
        if m:
            if label is None:
                label = m["label"]
            if m["label"] == label:
                pending.setdefault(m["metric"], float(m["value"]))
            continue
        m = VERDICT.match(line)
        if m:
            if m["id"] in ids:
                rnd.stats[m["id"]] = pending
                rnd.loaded = rnd.loaded or LOADED_SUFFIX.search(line) is not None
            pending, label = {}, None
    for test_id in ids:
        got = rnd.stats.get(test_id)
        if got is None:
            raise Fail("%s: no verdict line for %s in the run_tests.sh output (%s)" % (where, test_id, saved))
        missing = [k for k in METRICS if k not in got]
        if missing:
            raise Fail("%s: no PERF %s ms/frame line for %s (a test that stopped before its measurement? output: %s)"
                       % (where, "/".join(missing), test_id, saved))


def run_round(tree: Path, ids: list[str], directory: Path, where: str, quiet: str) -> Round:
    directory.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, GAME_TEST_FINGERPRINT_DIR=str(directory))
    cmd = [str(tree / "tools" / "run_tests.sh"), "--no-lint", quiet, "--verbose", "--id=" + ",".join(ids)]
    r = subprocess.run(cmd, cwd=tree, env=env, stdout=subprocess.PIPE, text=True)  # stderr (a slot wait) passes
    saved = directory / "run_tests.out"
    saved.write_text(r.stdout)
    rnd = Round(directory)
    read_output(r.stdout, ids, rnd, where, saved)
    return rnd


def fingerprint_lines(path: Path) -> list[str]:
    """The lines of a fingerprint, split at newlines only (an act can hold a space or a character `splitlines` splits at)."""
    lines = path.read_text().split("\n")
    return lines[:-1] if lines and lines[-1] == "" else lines


def first_difference(a: Path, b: Path) -> int | None:
    """The first frame of two fingerprints that differs (the first field of the first line that differs; a file that is a
    prefix of the other differs at the frame it ends on), None when they are equal."""
    left, right = fingerprint_lines(a), fingerprint_lines(b)
    for i in range(min(len(left), len(right))):
        if left[i] != right[i]:
            return frame_of(left[i], i)
    if len(left) == len(right):
        return None
    longer = left if len(left) > len(right) else right
    return frame_of(longer[min(len(left), len(right))], min(len(left), len(right)))


def frame_of(line: str, index: int) -> int:
    first = line.split("\t", 1)[0]
    return int(first) if first.isdigit() else index


class Session:
    def __init__(self, options: Options, shas: list[str]):
        self.o = options
        self.base_sha, self.tip_sha = shas
        self.trees = {sha: ensure_tree(sha) for sha in dict.fromkeys(shas)}
        self.runs = scratch_root() / "runs" / str(os.getpid())
        self.reference: dict[str, tuple[Path, str]] = {}
        self.results = {"BASE": {i: {k: [] for k in METRICS} for i in options.ids},
                        "TIP": {i: {k: [] for k in METRICS} for i in options.ids}}
        self.keep_runs = False

    def sha_of(self, side: str) -> str:
        return self.base_sha if side == "BASE" else self.tip_sha

    def play(self, number: int, side: str) -> None:
        """One round of `side`: run, rerun while loaded (at most `retries` times), check the fight, keep the numbers."""
        sha = self.sha_of(side)
        for attempt in range(self.o.retries + 1):
            where = "round %d/%d %s %s" % (number, self.o.rounds, side, sha[:8])
            print("%s%s ..." % (where, "" if attempt == 0 else " (run %d)" % (attempt + 1)), flush=True)
            rnd = run_round(self.trees[sha], self.o.ids, self.runs / ("r%02d-%s-%d" % (number, side.lower(), attempt)), where, self.o.quiet)
            if rnd.loaded:
                print("  dropped: the result is marked loaded (the machine was never quiet); running the round again", flush=True)
                continue
            self.check_fight(rnd, where, side, number)
            for test_id in self.o.ids:
                for k in METRICS:
                    self.results[side][test_id][k].append(rnd.stats[test_id][k])
            return
        raise Fail("%s: still marked loaded after %d reruns (--retries=%d): the machine never went quiet; no result (output: %s)"
                   % (where, self.o.retries, self.o.retries, rnd.dir / "run_tests.out"))

    def check_fight(self, rnd: Round, where: str, side: str, number: int) -> None:
        for test_id in self.o.ids:
            path = rnd.fingerprint(test_id)
            if not path.is_file():
                raise Fail("%s: %s wrote no fight fingerprint (%s): does that revision's test call Perf.record_fight?"
                           % (where, test_id, path))
            key = (side, test_id) if self.o.different_fights else test_id  # strict: one reference, BASE's first round
            if key not in self.reference:
                self.reference[key] = (path, "%s %s round %d" % (side, self.sha_of(side)[:8], number))
                continue
            ref_path, ref_where = self.reference[key]
            frame = first_difference(ref_path, path)
            if frame is None:
                continue
            self.keep_runs = True
            if self.o.different_fights:
                raise Fail("%s does not replay its own fight, from frame %d: %s, %s against %s %s round %d\n  %s\n  %s\nthe frame times are not "
                           "compared: a revision that plays another match every round says nothing, different fights or not "
                           "(perf-nondeterminism.md)"
                           % (side, frame, test_id, ref_where, side, self.sha_of(side)[:8], number, ref_path, path), EXIT_FIGHTS_DIFFER)
            raise Fail("fights differ from frame %d: %s, %s against %s %s round %d\n  %s\n  %s\nthe frame times are not compared: the "
                       "revisions (or two plays of one) did not play the same match (perf-nondeterminism.md)"
                       % (frame, test_id, ref_where, side, self.sha_of(side)[:8], number, ref_path, path), EXIT_FIGHTS_DIFFER)

    def fights_line(self, test_id: str) -> str:
        """Different-fights mode: whether BASE's first fight and TIP's first fight of a test are the same one."""
        frame = first_difference(self.reference[("BASE", test_id)][0], self.reference[("TIP", test_id)][0])
        return "BASE and TIP played the same fight" if frame is None else "BASE and TIP differ from frame %d" % frame

    def report(self) -> int:
        o = self.o
        print("\nperf_ab: BASE %s  TIP %s  %d rounds each, medians, bar %g%% of BASE avg" % (self.base_sha[:8], self.tip_sha[:8], o.rounds, o.bar))
        if o.different_fights:
            print("perf_ab: DIFFERENT FIGHTS mode: each side replayed its own fight every round, BASE and TIP are not required to have played the same one;\n"
                  "         the deltas compare two matches' cost, not one fight's: read them as a measure of the matches, not of the code alone")
        failed = []
        for test_id in o.ids:
            base = {k: statistics.median(self.results["BASE"][test_id][k]) for k in METRICS}
            tip = {k: statistics.median(self.results["TIP"][test_id][k]) for k in METRICS}
            print("\n%s%s" % (test_id, "  (different fights)" if o.different_fights else ""))
            if o.different_fights:
                print("  fights: %s" % self.fights_line(test_id))
            for k in METRICS:
                delta = tip[k] - base[k]
                pct = delta / base["avg"] * 100 if base["avg"] else 0.0
                print("  %-3s  BASE %7.2f ms  TIP %7.2f ms  delta %+.2f ms (%+.1f%% of BASE avg)" % (k, base[k], tip[k], delta, pct))
            pct = (tip["avg"] - base["avg"]) / base["avg"] * 100 if base["avg"] else 0.0
            ok = pct <= o.bar
            print("  %s: avg delta %+.1f%% of BASE avg, bar %g%%" % ("PASS" if ok else "FAIL", pct, o.bar))
            if not ok:
                failed.append(test_id)
        print("\nperf_ab: %s%s" % ("FAIL: over the bar: " + ", ".join(failed) if failed else "PASS", " (different fights)" if o.different_fights else ""))
        return EXIT_OVER_BAR if failed else 0

    def finish(self) -> None:
        if not self.keep_runs:
            shutil.rmtree(self.runs, ignore_errors=True)
            try:
                (scratch_root() / "runs").rmdir()
            except OSError:
                pass


def main(argv: list[str]) -> int:
    session, options, shas, code = None, None, [], 0
    try:
        options = parse_args(argv)
        if not options.revisions:
            clean_all()
            print("perf_ab: scratch trees removed")
            return 0
        shas = [resolve(r) for r in options.revisions]
        session = Session(options, shas)
        for number in range(1, options.rounds + 1):
            session.play(number, "BASE")
            session.play(number, "TIP")
        code = session.report()
    except Fail as e:
        print("perf_ab: %s" % e, file=sys.stderr)
        code = e.code
        if session is not None:
            session.keep_runs = True  # the output of the rounds says why
    finally:
        if session is not None:
            session.finish()
        if options is not None and options.clean:
            for sha in dict.fromkeys(shas):  # also the trees a setup that failed half way had built
                remove_tree(scratch_root() / sha)
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
