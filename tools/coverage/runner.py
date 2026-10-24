"""Running the instrumented game and keeping its hits: the match plan, the game processes, the Von server, the game
tests, the merge of the shards and the run folder (tools/coverage/README.md).

  plan_matches(matches, seed, endless_every) -> [{index, seed, mode, matches, defenders, invaders}]
      process i plays seed base+i in Watch mode (one match), or an Endless run of three matches when
      i % endless_every == endless_every - 1; both sides the same size, 1v1..5v5 by the seed (seed % 5 + 1)
  resolve_jobs(value) -> int     "auto" = the core count, at most 6; a positive number as given; else ValueError
  launch(copy, entry, hits_dir, windowed=False) -> Popen
      one game process of an instrumented copy for one plan entry, its probe flushing coverage_hits_<pid>.json
      into `hits_dir` every 5 s
  ensure_von(copy, port) -> VonServer / stop_von(server)
      a decision server that answers is reused and left running; otherwise the copy's `application/von/server_path`
      is started, and only a server started here is stopped
  run(root, source, ...) -> (exit code, run folder)
      the whole run: copy and hit folder (workspace.py: in artifacts/tmp/), instrument, play (matches, `jobs`
      processes at a time: 2 by default, what one shared Von server answers) or run the copy's tools/run_tests.sh
      (tests, `jobs` unused), merge, write artifacts/coverage/<sha>-<time>-<source>/, then check the repo is
      byte-identical to before (a RunFailed part-way says whether it still is). With instrumented=False (matches
      only) the copy gets the probe but no counter bump: the same matches, their outcome and cost recorded, no hits,
      in artifacts/coverage/<sha>-<time>-uninstrumented/ (no report)
      However it ends (done, RunFailed, any exception, Ctrl-C, SIGTERM or SIGHUP, the last two raised as
      Interrupted), it first stops the game processes, the test runner (its whole process group) and a Von server it
      started, then removes its copy and hit folder (workspace.cleanup), unless `keep`; signals wait while it does,
      and the first stopping signal ignores the ones after it until the cleanup is done. A process is recorded for
      the cleanup as it starts, signals held in between. A folder the cleanup cannot remove is a warning (`shout`).

Modules talk only through the map and the hit files: the probe writes the shards, hits.py merges them.
"""
import datetime
import hashlib
import json
import os
import random
import re
import shutil
import subprocess
import sys
import signal
import threading
import time
import urllib.error
import urllib.request
from contextlib import contextmanager, nullcontext
from dataclasses import dataclass
from pathlib import Path

from . import hits, instrument, report, static_refs, workspace

JOBS_MOST = 6
FLUSH_SECONDS = 5.0
ENDLESS_MATCHES = 3
SIDE_SIZES = 5                   # both sides 1..5 strong, by the seed
PROCESS_WALL_BASE = 120.0        # wall seconds a game process may take, plus PROCESS_WALL_PER_MATCH per match,
PROCESS_WALL_PER_MATCH = 600.0   # before it is killed (its last flush is kept)
IMPORT_TIMEOUT = 600.0           # wall seconds the import of a copy with no class cache may take (ensure_imported)
IMPORT_LOG_TAIL = 20             # lines of a failed import's log said with its failure (ensure_imported)
RUNS_DIR = Path("artifacts") / "coverage"
VON_PORT = 8000
VON_HEALTH = "/v1/systemone"
VON_MODEL = "von-1.2.0"
VON_READY_SECONDS = 90.0
VON_TESTS_FLAGS = ("--include-von", "--require-von")
# How the copy is linted before its tests: what instrumenting breaks on purpose left out (the isolation rule, and
# gdstyle: each probe shares its statement's line, so line numbers match the real tree).
COPY_LINT = ("--skip-rule=coverage_isolation", "--no-gdstyle")
# What meta.json keeps of each match unit: its outcome, then its cost (probe.gd; null where the probe did not record it)
MATCH_FIELDS = ("seed", "mode", "match", "verdict", "duration", "shots", "deaths", "wall", "frames", "physics_peak_ms",
                "process_peak_ms", "npcs", "decisions", "decided", "failed", "decided_per_npc_minute",
                "von_failed_share")
# Von decisions per NPC per game minute below which a match's NPCs were starved of decisions (a Von server busy for
# other worktrees, or too many game processes for it): half the rate of quiet --jobs=1 matches, counted in walks Von
# answered (`decided_per_npc_minute`). Measured at c8821b0 on 2026-10-17: 8 instrumented Watch matches, seeds 500-507
# (1v1..5v5), one at a time, each started at >= 75% raw CPU idle with no other game or test running and kept only while
# the CPU stayed >= 70% idle apart from the game and Von; median 15.47 decided per NPC per game minute (12.3..39.2),
# none failed. A starved run (24 processes at --jobs=6) read 0.7, 95% of its walks failed. A run warns about every
# match below the floor, and so does its report; it does not lower --jobs itself.
VON_DECISIONS_FLOOR = 7.73
# run_tests.sh's verdict line of a test that failed or timed out, the first failed check under it, and the summary
# line it ends with (a run that printed it finished)
TEST_VERDICT = re.compile(r"^(PASS|FAIL|TIMEOUT|SKIPPED|GAP|FLAKY|FAILING)\s+(\S+)\s+\(")
TEST_CHECK = "        \u2717 "
TEST_SUMMARY = re.compile(r"^\d+ passed, \d+ failed, \d+ timed out")
# The phase of a game process that exited non-zero with no hit lost: its hit file is the probe's final flush (written
# as the tree is freed) and holds every match it was planned, each decided. Godot can still abort after that, in its
# own shutdown (the engine's servers and the script language are torn down after the tree).
AFTER_LAST_FLUSH = "after the last flush"
CRASHED_DIR = "crashed"         # in the run folder: the logs of the processes that exited non-zero after the last flush


class RunFailed(Exception):
    """A run that cannot go on, or whose result must not be trusted; the message says why."""


class Interrupted(BaseException):
    """SIGTERM or SIGHUP during a run (Ctrl-C is KeyboardInterrupt), raised so the run stops its processes and cleans
    up on the way out; `signum` is the signal."""

    def __init__(self, signum: int):
        super().__init__(f"interrupted by {signal.Signals(signum).name}")
        self.signum = signum


STOPPING = (signal.SIGINT, signal.SIGTERM, signal.SIGHUP)


@contextmanager
def interrupts_raise():
    """Inside the block, Ctrl-C raises KeyboardInterrupt and SIGTERM and SIGHUP raise Interrupted; the first of them
    also ignores every stopping signal after it until the block ends, so the cleanup it starts is never cut short
    (in the main thread; elsewhere signals cannot be handled and the block runs as it is)."""
    if threading.current_thread() is not threading.main_thread():
        yield
        return

    def handler(signum, _frame):
        for s in handled:
            signal.signal(s, signal.SIG_IGN)
        if signum == signal.SIGINT:
            raise KeyboardInterrupt
        raise Interrupted(signum)

    # Ctrl-C only where Python's own handler has it: a process started with it ignored keeps it ignored, as Python does
    handled = [s for s in STOPPING if s != signal.SIGINT or signal.getsignal(s) is signal.default_int_handler]
    previous = {s: signal.signal(s, handler) for s in handled}
    try:
        yield
    finally:
        for s, h in previous.items():
            signal.signal(s, signal.SIG_DFL if h is None else h)


@contextmanager
def signals_held():
    """Ctrl-C, SIGTERM and SIGHUP wait until the block is done (delivered after it), so a cleanup, or a process
    started and recorded, is never cut short. Nests."""
    if threading.current_thread() is not threading.main_thread():
        yield
        return
    before = signal.pthread_sigmask(signal.SIG_BLOCK, STOPPING)
    try:
        yield
    finally:
        signal.pthread_sigmask(signal.SIG_SETMASK, before)


def unheld() -> None:
    """A child's preexec_fn: unblocks there the stopping signals signals_held blocks in its parent."""
    signal.pthread_sigmask(signal.SIG_UNBLOCK, STOPPING)


def start(*args, **kwargs) -> subprocess.Popen:
    """subprocess.Popen, for a call made under signals_held: the child does not inherit the held signals."""
    return subprocess.Popen(*args, preexec_fn=unheld, **kwargs)


def stop_group(proc: subprocess.Popen, grace: float = 10.0) -> None:
    """Stop a process started with start_new_session=True and every process of its group (a shell script's
    children): SIGTERM, then SIGKILL for what is left after `grace` seconds."""
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(proc.pid, sig)
        except ProcessLookupError:
            break
        try:
            proc.wait(timeout=grace)
        except subprocess.TimeoutExpired:
            continue
        end = time.monotonic() + grace
        while time.monotonic() < end and group_alive(proc.pid):
            time.sleep(0.1)
        if not group_alive(proc.pid):
            break
    if proc.poll() is None:
        proc.wait()


def group_alive(pgid: int) -> bool:
    try:
        os.killpg(pgid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def plan_matches(matches: int, seed: int, endless_every: int) -> list[dict]:
    plan = []
    for i in range(matches):
        endless = endless_every > 0 and i % endless_every == endless_every - 1
        size = (seed + i) % SIDE_SIZES + 1
        plan.append({"index": i, "seed": seed + i, "mode": "endless" if endless else "watch",
                     "matches": ENDLESS_MATCHES if endless else 1, "defenders": size, "invaders": size})
    return plan


def resolve_jobs(value) -> int:
    if str(value) == "auto":
        return min(os.cpu_count() or 1, JOBS_MOST)
    try:
        jobs = int(value)
    except (TypeError, ValueError):
        raise ValueError(f"--jobs must be a positive number or auto, not {value!r}") from None
    if jobs < 1:
        raise ValueError(f"--jobs must be a positive number or auto, not {value!r}")
    return jobs


def godot_binary() -> str:
    """The Godot binary, found as tools/run_tests.sh finds it."""
    if os.environ.get("GODOT"):
        return os.environ["GODOT"]
    for name in ("godot", "godot4"):
        found = shutil.which(name)
        if found:
            return found
    apps = sorted(Path("/Applications").glob("Godot*.app/Contents/MacOS/Godot"))
    if apps:
        return str(apps[0])
    raise RunFailed("Godot binary not found (set GODOT=/path/to/Godot)")


def game_env(copy, **extra: str) -> dict:
    """The environment of a process run in the copy: this one's as workspace.copy_env gives it (git there finds no
    repo), with GODOT set, FE_COVERAGE only when given, and the dev command server off (GODOT_CMD_PORT=off, over any
    port of the caller's): a coverage run never drives it, and a port another worktree's game or check holds would
    fail the run on its "failed to listen" warning."""
    env = {k: v for k, v in workspace.copy_env(copy).items() if k != "FE_COVERAGE"}
    env.update(GODOT=godot_binary(), GODOT_CMD_PORT="off", **extra)
    return env


def write_config(hits_dir: Path, name: str, config: dict) -> Path:
    path = Path(hits_dir) / name
    hits.write_json(path, {"hits_dir": str(Path(hits_dir).resolve()), "flush": FLUSH_SECONDS, **config})
    return path


def ensure_imported(copy, log_path: Path) -> str:
    """Import the copy when it has no class cache: a checkout never opened in Godot (a fresh worktree) has no .godot/
    for workspace.create to carry over, and without the cache every script naming a global class fails to parse, so
    Main never loads. tools/run_tests.sh imports a fresh checkout the same way (the tests run goes through it).
    Returns "" when the copy is imported, else why not (a non-zero exit, or no end within IMPORT_TIMEOUT) with the last
    IMPORT_LOG_TAIL lines of its log, which lives in the hit folder the run removes."""
    if (Path(copy) / ".godot" / "global_script_class_cache.cfg").is_file():
        return ""
    with open(log_path, "w") as out:
        try:
            done = subprocess.run([godot_binary(), "--headless", "--path", str(copy), "--import"], cwd=copy,
                                  env=game_env(copy), stdin=subprocess.DEVNULL, stdout=out, stderr=subprocess.STDOUT,
                                  timeout=IMPORT_TIMEOUT, check=False)
            why = f"exited with {done.returncode}" if done.returncode != 0 else ""
        except subprocess.TimeoutExpired:
            why = f"did not finish within {IMPORT_TIMEOUT:g} s"
    if not why:
        return ""
    tail = Path(log_path).read_text(encoding="utf-8", errors="replace").splitlines()[-IMPORT_LOG_TAIL:]
    return (f"the import of the never-imported copy {why}, so its scripts may not parse; the end of its log:\n"
            + "\n".join(f"  {line}" for line in tail))


def launch(copy, entry: dict, hits_dir, windowed: bool = False) -> subprocess.Popen:
    hits_dir = Path(hits_dir)
    i = entry["index"]
    config = write_config(hits_dir, f"run_{i}.json", {
        "source": "matches", "seed": entry["seed"], "mode": entry["mode"], "matches": entry["matches"],
        "defenders": entry["defenders"], "invaders": entry["invaders"]})
    cmd = [godot_binary(), *([] if windowed else ["--headless"]), "--path", str(copy),
           "--log-file", str(hits_dir / f"godot_{i}.log")]
    with open(hits_dir / f"godot_{i}.out", "w") as out:
        return start(cmd, cwd=copy, env=game_env(copy, FE_COVERAGE=str(config)), stdin=subprocess.DEVNULL, stdout=out,
                     stderr=subprocess.STDOUT)


# --- Von -------------------------------------------------------------------------------------------

@dataclass
class VonServer:
    live: bool
    started: bool = False
    process: subprocess.Popen | None = None
    note: str = ""


def von_live(port: int, timeout: float = 5.0) -> bool:
    """Whether a decision server on `port` makes a decision (the game launcher's own health check)."""
    payload = {"model": VON_MODEL, "state": "Readiness check.", "questions": {"act": {
        "type": "choice", "instructions": "What should you do right now?",
        "criteria": {"ok": "report that you are ready"}}}}
    request = urllib.request.Request(f"http://127.0.0.1:{port}{VON_HEALTH}", data=json.dumps(payload).encode(),
                                     headers={"Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status == 200
    except (urllib.error.URLError, OSError):
        return False


def von_path(copy) -> str:
    """The copy's `application/von/server_path` project setting ("" when it has none)."""
    text = (Path(copy) / "project.godot").read_text(encoding="utf-8")
    section = re.search(r"^\[application\]\s*$(.*?)(?=^\[|\Z)", text, re.M | re.S)
    found = re.search(r'^von/server_path\s*=\s*"([^"]*)"', section.group(1), re.M) if section else None
    return found.group(1) if found else ""


def ensure_von(copy, port: int = VON_PORT, log_path=None) -> VonServer:
    if von_live(port):
        return VonServer(live=True, note=f"Reusing the Von server already live on port {port}; it is left running.")
    path = von_path(copy)
    if not path:
        return VonServer(live=False, note=f"No Von server on port {port} and no application/von/server_path: the "
                                          "NPCs hold steady, so matches run to the time cap.")
    server = VonServer(live=False, started=True)
    try:
        # Started and recorded under signals_held: a server this run started is always one it stops.
        with signals_held(), (open(log_path, "a") if log_path else nullcontext(subprocess.DEVNULL)) as log:
            try:
                server.process = start([path, "serve", "--host", "127.0.0.1", "--port", str(port), "--device", "cpu"],
                                       stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
                                       start_new_session=True)
            except OSError as err:
                raise RunFailed(f"cannot start the Von server {path}: {err}") from err
        deadline = time.monotonic() + VON_READY_SECONDS
        while time.monotonic() < deadline and server.process.poll() is None:
            if von_live(port):
                server.live = True
                server.note = (f"Started the Von server on port {port} (pid {server.process.pid}); it is stopped "
                               "after the run.")
                return server
            time.sleep(0.5)
        raise RunFailed(f"the Von server {path} did not answer on port {port} within {VON_READY_SECONDS:.0f} s"
                        + (f" (see {log_path})" if log_path else ""))
    except BaseException:
        with signals_held():
            stop_von(server)
        raise


def stop_von(server: VonServer) -> None:
    """Stop the server only if this run started it."""
    if not server.started or server.process is None or server.process.poll() is not None:
        return
    server.process.terminate()
    try:
        server.process.wait(timeout=15)
    except subprocess.TimeoutExpired:
        server.process.kill()
        server.process.wait()


# --- Playing ---------------------------------------------------------------------------------------

def run_matches(copy, plan: list[dict], jobs: int, hits_dir: Path, windowed: bool, say=print) -> list[dict]:
    """Play the plan, `jobs` processes at a time; returns one {entry, pid, code, timed_out} per process."""
    pending, running, done = list(plan), {}, []
    try:
        while pending or running:
            while pending and len(running) < jobs:
                entry = pending.pop(0)
                wall = PROCESS_WALL_BASE + PROCESS_WALL_PER_MATCH * entry["matches"]
                with signals_held():  # a game started is a game recorded, for the finally to stop
                    proc = launch(copy, entry, hits_dir, windowed)
                    running[proc] = (entry, time.monotonic() + wall)
            for proc, (entry, deadline) in list(running.items()):
                code = proc.poll()
                timed_out = code is None and time.monotonic() > deadline
                if timed_out:
                    proc.kill()
                    code = proc.wait()
                if code is None:
                    continue
                del running[proc]
                result = {"entry": entry, "pid": proc.pid, "code": code, "timed_out": timed_out}
                done.append(result)
                say(progress(result, hits_dir, len(done), len(plan)))
            time.sleep(0.2)
    finally:
        with signals_held():
            for proc in running:
                proc.kill()
                proc.wait()
    return done


def shard_of(result: dict, hits_dir: Path) -> dict | None:
    """The hit file a game process left (its last flush), or None."""
    try:
        return hits.load(Path(hits_dir) / f"coverage_hits_{result['pid']}.json")
    except (OSError, ValueError):
        return None


def after_last_flush(result: dict, hits_dir: Path) -> bool:
    """Whether a game process that exited non-zero lost no hit: not killed, its hit file final and holding every match
    it was planned, each decided (AFTER_LAST_FLUSH)."""
    shard = shard_of(result, hits_dir)
    return (result["code"] != 0 and not result["timed_out"] and shard is not None and shard.get("final") is True
            and len(shard["units"]) == result["entry"]["matches"] and all(u.get("verdict") for u in shard["units"]))


def progress(result: dict, hits_dir: Path, n: int, total: int) -> str:
    e = result["entry"]
    head = f"  [{n}/{total}] seed {e['seed']} {e['mode']} {e['defenders']}v{e['invaders']}: "
    shard = shard_of(result, hits_dir)
    units = shard["units"] if shard else []
    verdicts = ", ".join(f"{u['verdict'] or 'unfinished'} ({u['duration']:.1f} s)" for u in units) or "no hits"
    if result["timed_out"]:
        return head + verdicts + " - KILLED: over its wall-time limit (its last flush is kept)"
    if after_last_flush(result, hits_dir):
        return head + verdicts + f" - the game exited with {result['code']} {AFTER_LAST_FLUSH} (every match " \
            "decided and recorded: no hit lost, recorded in meta.json)"
    if result["code"] != 0:
        return head + verdicts + f" - the game exited with {result['code']} before its final flush: the hits " \
            "after its last flush are lost (the flush before is kept)"
    return head + verdicts


def crash_record(result: dict, hits_dir: Path, folder: Path, root: Path) -> dict:
    """A process that exited non-zero after the last flush, as meta.json's `crashed` keeps it; its logs (godot_<i>.out,
    the game's stdout and stderr where an abort's message lands, and godot_<i>.log) are copied into the run folder."""
    e = result["entry"]
    kept = folder / CRASHED_DIR
    kept.mkdir(exist_ok=True)
    for ext in ("out", "log"):
        log = Path(hits_dir) / f"godot_{e['index']}.{ext}"
        if log.exists():
            shutil.copy2(log, kept / log.name)
    out = kept / f"godot_{e['index']}.out"
    lines = [l.strip() for l in out.read_text(errors="replace").splitlines() if l.strip()] if out.exists() else []
    return {"seed": e["seed"], "mode": e["mode"], "process": e["index"], "pid": result["pid"], "exit": result["code"],
            "phase": AFTER_LAST_FLUSH, "log": str(out.relative_to(root)), "message": lines[-1] if lines else ""}


def run_tests(copy, args: list[str], hits_dir: Path, say=print) -> dict:
    """Lint the copy (its own tools/lint.sh, without what instrumenting breaks on purpose: the isolation rule, and the
    gdstyle pass, since each probe shares its statement's line), then run its tools/run_tests.sh with the
    probe on, its output passed on to `say` line by line; returns {code, failed, finished}: run_tests.sh's exit code,
    the tests that failed or timed out (failed_tests) and whether it printed its summary line."""
    copy = Path(copy)
    lint = copy / "tools" / "lint.sh"
    if lint.is_file():
        say("Linting the instrumented copy (tools/lint.sh " + " ".join(COPY_LINT) + ")...")
        proc = None
        try:
            with signals_held():
                proc = start([str(lint), *COPY_LINT, "--quiet"], cwd=copy, env=game_env(copy),
                             stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                             start_new_session=True)
            out, err = proc.communicate()
        except BaseException:
            if proc is not None:
                with signals_held():
                    stop_group(proc)
            raise
        if proc.returncode != 0:
            raise RunFailed("the instrumented copy fails lint (tools/lint.sh " + " ".join(COPY_LINT) + "):\n"
                            + out + err)
    config = write_config(hits_dir, "run_tests.json", {"source": "tests"})
    cmd = [str(copy / "tools" / "run_tests.sh"), "--no-lint", *with_perf_skipped(args)]
    say("Running the game tests in the copy: tools/run_tests.sh " + " ".join(cmd[1:]))
    lines = []
    # Its own process group: the Godot processes it starts are stopped with it however the run ends.
    proc = None
    try:
        with signals_held():
            proc = start(cmd, cwd=copy, env=game_env(copy, FE_COVERAGE=str(config)), stdin=subprocess.DEVNULL,
                         stdout=subprocess.PIPE, text=True, errors="replace", bufsize=1, start_new_session=True)
        for line in proc.stdout:
            line = line.rstrip("\n")
            lines.append(line)
            say(line)
        proc.wait()
    except BaseException:
        if proc is not None:
            with signals_held():
                stop_group(proc)
        raise
    finally:
        if proc is not None:
            proc.stdout.close()
    return {"code": proc.returncode, "failed": failed_tests(lines),
            "finished": any(TEST_SUMMARY.match(l) for l in lines)}


def failed_tests(lines: list[str]) -> list[dict]:
    """The tests run_tests.sh's output names FAIL or TIMEOUT, in order, once each: {id, verdict, first}, `first` the
    first failed check printed under it ("" when none was)."""
    found, current = {}, None
    for line in lines:
        m = TEST_VERDICT.match(line)
        if m:
            current = None
            if m.group(1) in ("FAIL", "TIMEOUT") and m.group(2) not in found:
                current = found[m.group(2)] = {"id": m.group(2), "verdict": m.group(1), "first": ""}
        elif current is not None and line.startswith(TEST_CHECK) and not current["first"]:
            current["first"] = line[len(TEST_CHECK):].strip()
    return list(found.values())



def with_perf_skipped(args: list[str]) -> list[str]:
    """`args` with the perf domain added to --skip-domain (the frame-time budgets measure the counters, not the game)."""
    out, skipped = [], False
    for a in args:
        if a.startswith("--skip-domain="):
            domains = [d for d in a.split("=", 1)[1].split(",") if d]
            a = "--skip-domain=" + ",".join(domains + ([] if "perf" in domains else ["perf"]))
            skipped = True
        out.append(a)
    return out if skipped else [*out, "--skip-domain=perf"]


def collect(hits_dir: Path, source: str, smap: dict, order: list[int] = ()) -> dict:
    """The run's shards merged (in `order` of their pids first, then by name). A probe that failed fails the run."""
    hits_dir = Path(hits_dir)
    failed = sorted(hits_dir.glob("coverage_failed_*.txt"))
    if failed:
        raise RunFailed("the probe could not do its job:\n" + "".join(f.read_text() for f in failed))
    rank = {pid: i for i, pid in enumerate(order)}
    shards = sorted(hits_dir.glob("coverage_hits_*.json"),
                    key=lambda p: (rank.get(int(p.stem.rsplit("_", 1)[1]), len(rank)), p.name))
    files = [hits.load(p) for p in shards]
    if not files:
        return {"format": hits.FORMAT, "version": hits.VERSION, "map_hash": smap["hash"], "source": source, "units": []}
    for f in files:
        if f["map_hash"] != smap["hash"]:
            raise RunFailed(f"a hit file of another map ({f['map_hash']}, not {smap['hash']}) in {hits_dir}")
    return hits.merge(files)


# --- One run ---------------------------------------------------------------------------------------

def file_digests(root: Path) -> dict[str, str]:
    """sha256 of every file workspace.tree_hash covers, so a change can be named."""
    return {rel: hashlib.sha256((root / rel).read_bytes()).hexdigest() for rel in workspace.hashed_files(root)}


def tree_state(root: Path) -> tuple[str, str, dict]:
    return workspace.git_status(root), workspace.tree_hash(root), file_digests(root)


def changes(before: tuple, after: tuple) -> list[str]:
    """What differs between two tree_states, one line per path."""
    status_before, status_after = set(before[0].splitlines()), set(after[0].splitlines())
    lines = [f"  git status, now: {l}" for l in sorted(status_after - status_before)]
    lines += [f"  git status, gone: {l}" for l in sorted(status_before - status_after)]
    digests_before, digests_after = before[2], after[2]
    for rel in sorted(set(digests_before) | set(digests_after)):
        if digests_before.get(rel) != digests_after.get(rel):
            lines.append(f"  bytes changed: {rel}")
    if before[1] != after[1] and not lines:
        lines.append("  the scenes/ + project.godot hash changed")
    return lines


def tree_verdict(before: tuple, root: Path) -> str:
    """Whether the repo at `root` still matches `before` (a tree_state), for a run that failed part-way."""
    changed = changes(before, tree_state(root))
    if changed:
        return "the run changed the repo, which it must never do:\n" + "\n".join(changed)
    return "the repo is unchanged (git status and the scenes/ + project.godot bytes as before the run)"


def git_head(root: Path) -> str:
    return subprocess.run(["git", "rev-parse", "HEAD"], cwd=root, check=True, capture_output=True,
                          text=True).stdout.strip()


def run_folder(root: Path, head: str, source: str) -> Path:
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    base = root / RUNS_DIR
    base.mkdir(parents=True, exist_ok=True)
    gdignore = root / "artifacts" / ".gdignore"
    if not gdignore.exists():
        gdignore.write_text("")
    folder = base / f"{head}-{stamp}-{source}"
    n = 2
    while folder.exists():
        folder = base / f"{head}-{stamp}.{n}-{source}"
        n += 1
    folder.mkdir()
    return folder


def write_run(folder: Path, root: Path, smap: dict, merged: dict, meta: dict) -> dict | None:
    """The run folder's files; returns the report, or None for an uninstrumented run (nothing to report)."""
    hits.write_json(folder / "map.json", smap)
    hits.write_json(folder / "hits.json", merged)
    hits.write_json(folder / "meta.json", meta)
    if not meta.get("instrumented", True):
        return None
    rep = report.build([{"meta": meta, "map": smap, "hits": merged}], static_refs.unreferenced(root))
    hits.write_json(folder / "report.json", rep)
    (folder / "report.md").write_text(report.markdown(rep), encoding="utf-8")
    return rep


def run(root, source: str, matches: int = 24, jobs=2, seed: int | None = None, endless_every: int = 4,
        windowed: bool = False, test_args=(), keep: bool = False, instrumented: bool = True,
        say=lambda text: print(text, flush=True),
        shout=lambda text: print(text, file=sys.stderr, flush=True)) -> tuple[int, Path | None]:
    """One coverage run of the repo at `root`; returns (exit code, run folder). Raises RunFailed when it cannot run,
    its message ending with whether the repo is unchanged, and Interrupted on SIGTERM or SIGHUP (KeyboardInterrupt on
    Ctrl-C), after cleaning up. `say` takes the progress, `shout` each reason the run failed."""
    with interrupts_raise():
        return run_once(root, source, matches, jobs, seed, endless_every, windowed, test_args, keep, instrumented,
                        say, shout)


def run_once(root, source, matches, jobs, seed, endless_every, windowed, test_args, keep, instrumented, say, shout):
    root = Path(root).resolve()
    jobs = resolve_jobs(jobs)
    if not instrumented and source != "matches":
        raise ValueError("--uninstrumented plays matches only (the game tests measure nothing without counters)")
    head = git_head(root)
    before = tree_state(root)
    copy = hits_dir = None
    von = VonServer(live=False)
    problems = []
    failed = None
    try:
        copy = workspace.create(root)
        hits_dir = workspace.hits_dir(root)
        smap = instrument.instrument(copy, markers=instrumented)
        if instrumented:
            say(f"Instrumented {len(smap['statements'])} statements ({len(smap['uninstrumented'])} spans left "
                f"uninstrumented) in {copy}")
        else:
            say(f"Uninstrumented copy (the probe drives the matches, no counter bump) in {copy}")
        meta = {"commit": head, "time": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
                "source": source, "instrumented": instrumented, "scenes_hash": before[1], "map_hash": smap["hash"],
                "windowed": windowed,
                "dirty": any(l[3:].startswith(("scenes/", "project.godot")) for l in before[0].splitlines())}
        if source == "matches":
            seed = random.randrange(1, 1_000_000) if seed is None else seed
            plan = plan_matches(matches, seed, endless_every)
            imported = ensure_imported(copy, hits_dir / "import.log")
            if imported:
                problems.append(imported)
            von = ensure_von(copy, log_path=hits_dir / "von.log")
            say(von.note)
            say(f"Playing {len(plan)} processes from seed {seed} ({sum(e['matches'] for e in plan)} matches), "
                f"{jobs} at a time...")
            results = run_matches(copy, plan, jobs, hits_dir, windowed, say)
            crashed = [r for r in results if after_last_flush(r, hits_dir)]
            problems += [progress(r, hits_dir, i + 1, len(plan)).strip() for i, r in enumerate(results)
                         if (r["code"] != 0 or r["timed_out"]) and r not in crashed]
            by_index = sorted(results, key=lambda r: r["entry"]["index"])
            merged = collect(hits_dir, source, smap, [r["pid"] for r in by_index])
            meta["seeds"] = [e["seed"] for e in plan]
            meta["matches"] = [{k: u.get(k) for k in MATCH_FIELDS} for u in merged["units"]]
            meta["von_floor"] = VON_DECISIONS_FLOOR
            missing = sorted({e["seed"] for e in plan} - {u["seed"] for u in merged["units"]})
            if missing:
                problems.append(f"no hits from the process(es) of seed(s) {', '.join(map(str, missing))}")
        else:
            if any(a in VON_TESTS_FLAGS for a in test_args):
                von = ensure_von(copy, log_path=hits_dir / "von.log")
                say(von.note)
            ran = run_tests(copy, list(test_args), hits_dir, say)
            merged = collect(hits_dir, source, smap)
            meta["args"] = list(test_args)
            meta["run_tests_exit"] = ran["code"]
            meta["failed"] = ran["failed"]
            if ran["code"] != 0 and not (ran["finished"] and merged["units"]):
                problems.append(f"tools/run_tests.sh exited with {ran['code']} "
                                + ("before its summary line" if merged["units"] else "with no hits")
                                + ": the test runner broke, the run measured nothing to trust")
        folder = run_folder(root, head, source if instrumented else "uninstrumented")
        if source == "matches":
            meta["crashed"] = [crash_record(r, hits_dir, folder, root) for r in crashed]
        rep = write_run(folder, root, smap, merged, meta)
    except RunFailed as err:
        failed = err
    finally:
        with signals_held():
            stop_von(von)
            for scratch in (f for f in (copy, hits_dir) if f is not None):
                try:
                    if keep:
                        workspace.keep(scratch)
                    else:
                        workspace.cleanup(root, scratch)
                except (OSError, ValueError) as err:
                    shout(f"WARNING: {scratch} is left in place, delete it by hand: {err}")
        if keep and copy is not None:
            say(f"Kept the copy {copy} and the hits {hits_dir}")
    if failed is not None:
        # A problem met before it (a failed import) is often its cause: it is said with it.
        raise RunFailed("\n".join([*problems, str(failed), tree_verdict(before, root)])) from failed
    say(f"Run folder: {folder.relative_to(root)}")
    if rep is None:
        say(f"  {len(merged['units'])} matches, uninstrumented: " + "; ".join(
            f"{u['id']} {u['verdict'] or 'unfinished'} ({u['duration']:.1f} s, shots {u.get('shots')}, "
            f"deaths {u.get('deaths')})" for u in merged["units"]))
    else:
        counted = f"{len(merged['units'])} matches" if source == "matches" else \
            f"{sum(not u.get('outside') for u in merged['units'])} tests"  # the outside unit is no test
        say(f"  {counted}; "
            + ", ".join(f"{t} {sum(t in fn['tags'] for d in rep['domains'] for f in d['files'] for fn in f['functions'])}"
                        for t in report.TAGS))
    if source == "matches" and report.starved_warning(meta):
        shout("WARNING: " + report.starved_warning(meta))
    if meta.get("crashed"):
        say(f"  {len(meta['crashed'])} game processes exited non-zero {AFTER_LAST_FLUSH} (recorded, no hit lost): "
            + "; ".join(f"seed {c['seed']} exited with {c['exit']} ({c['message'] or 'no message'}), log {c['log']}"
                        for c in meta["crashed"]))
    if meta.get("failed"):
        say(f"  {len(meta['failed'])} tests failed under instrumentation (recorded, their hits kept; a wall-clock "
            "budget fails from the counters' cost): " + ", ".join(f"{f['id']} {f['verdict']}" for f in meta["failed"]))
    changed = changes(before, tree_state(root))
    if changed:
        problems.append("the run changed the repo, which it must never do:\n" + "\n".join(changed))
    for p in problems:
        shout(f"FAILED: {p}")
    return (1 if problems else 0), folder
