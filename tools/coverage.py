#!/usr/bin/env python3
"""Runtime function coverage of the game from real matches and from the game tests (tools/coverage/README.md).

  python3 tools/coverage.py instrument
      build an instrumented copy of the repo in artifacts/tmp/ and print its path (the last line); the copy is kept
      (no run sweeps it), the rest of the repo is never touched
  python3 tools/coverage.py run [--matches=24] [--jobs=2] [--seed=N] [--endless-every=4] [--windowed] [--keep]
      play real headless matches in an instrumented copy: process i plays seed N+i in Watch mode (every
      endless-every-th an Endless run of three matches), both sides 1v1..5v5 by the seed, `jobs` processes at a time
      (a number, or auto: the core count, at most 6); N is random when not given (it is recorded)
  python3 tools/coverage.py run --uninstrumented [--matches=N] [--jobs=N] [--seed=N] [--endless-every=N]
      the same matches in a copy with the probe but no counter bump: their outcome and cost only (meta.json), to
      compare with a measured run over the same seeds; written to artifacts/coverage/<sha>-<time>-uninstrumented/,
      which `report` never reads
  python3 tools/coverage.py run --tests [run_tests.sh args...]
      run the copy's game tests (tools/run_tests.sh --no-lint --skip-domain=perf plus the args) with the probe on,
      the copy linted first
  python3 tools/coverage.py report [--domain=x] [--run=DIR...] [--out=DIR]
      the report of the newest matches run and the newest tests run of HEAD (or of the run folders given; several
      matches runs read as one run of all their matches, in seed order); --out also saves it into DIR (report.md,
      report.json, runs.json: the folders combined), which must not already hold a report

Each run writes artifacts/coverage/<sha>-<time>-<matches|tests>/ (hits.json, map.json, meta.json, report.md,
report.json) and fails, naming what changed, if the repo is not byte-identical afterwards. Its instrumented copy and
hit files live in artifacts/tmp/ and are removed however the run ends (--keep keeps them); interrupted, it exits
128 + the signal. This file is the CLI only; the work is in tools/coverage/.
"""
import argparse
import json
import signal
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path[0] = str(ROOT)  # import the package as tools.coverage, not this script's folder

from tools.coverage import hits, instrument, report, runner, static_refs, workspace  # noqa: E402


def cmd_instrument(_args) -> int:
    copy = workspace.create(ROOT)
    try:
        smap = instrument.instrument(copy)
    except BaseException:
        workspace.cleanup(ROOT, copy)
        raise
    workspace.keep(copy)
    print(f"Instrumented {len(smap['statements'])} statements ({len(smap['uninstrumented'])} spans left "
          f"uninstrumented); the map is {instrument.MAP_PATH} in the copy.")
    print("The probe stays idle unless FE_COVERAGE names a run config. The copy is kept (no run sweeps it): delete "
          "it when done.")
    print(copy)
    return 0


def cmd_run(source: str, **options) -> int:
    try:
        code, _folder = runner.run(ROOT, source, **options)
    except (runner.RunFailed, ValueError) as err:
        print(f"coverage run FAILED: {err}", file=sys.stderr)
        return 1
    except (runner.Interrupted, KeyboardInterrupt) as err:
        signum = err.signum if isinstance(err, runner.Interrupted) else signal.SIGINT
        kept = "its copy and hit files are kept" if options.get("keep") else "its copy and hit files are removed"
        print(f"coverage run interrupted by {signal.Signals(signum).name}: the processes it started are stopped and "
              f"{kept}", file=sys.stderr)
        return 128 + signum
    return code


def newest_runs(head: str) -> list[Path]:
    """The newest matches run and the newest tests run of commit `head` under artifacts/coverage/ (never an
    uninstrumented run: it has no hits)."""
    base = ROOT / runner.RUNS_DIR
    found = {}
    for folder in sorted(base.iterdir()) if base.is_dir() else []:
        try:
            meta = json.loads((folder / "meta.json").read_text())
        except (OSError, ValueError):
            continue
        if meta.get("commit") != head or meta.get("instrumented") is False:
            continue
        key = (meta.get("time", ""), folder.stat().st_mtime, folder.name)
        if meta.get("source") not in found or key > found[meta["source"]][0]:
            found[meta.get("source")] = (key, folder)
    return [found[s][1] for s in ("matches", "tests") if s in found]


def cmd_report(args) -> int:
    folders = [Path(r) for r in args.run] or newest_runs(runner.git_head(ROOT))
    if not folders:
        print("coverage report: no run of HEAD under artifacts/coverage/ (run `python3 tools/coverage.py run` "
              "first, or pass --run=DIR)", file=sys.stderr)
        return 1
    runs = []
    for folder in folders:
        try:
            runs.append({name: json.loads((folder / f"{name}.json").read_text()) for name in ("meta", "map", "hits")})
        except (OSError, ValueError) as err:
            print(f"coverage report: cannot read the run folder {folder}: {err}", file=sys.stderr)
            return 1
    out = Path(args.out).resolve() if args.out else None
    if out is not None and (out / "report.md").exists():
        print(f"coverage report: {out} already holds a report; pick another --out", file=sys.stderr)
        return 1
    rep = report.build(runs, static_refs.unreferenced(ROOT), domain=args.domain)
    md = report.markdown(rep)
    print("Runs: " + ", ".join(f.name for f in folders))
    print()
    print(md, end="")
    if out is not None:
        out.mkdir(parents=True, exist_ok=True)
        combined = [{"folder": f.name, "source": r["meta"]["source"], "commit": r["meta"]["commit"],
                     "time": r["meta"]["time"], "units": len(r["hits"]["units"])} for f, r in zip(folders, runs)]
        hits.write_json(out / "runs.json", combined)
        hits.write_json(out / "report.json", rep)
        (out / "report.md").write_text(md, encoding="utf-8")
        print(f"\nReport folder: {out}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("instrument", help="build an instrumented copy and print its path")
    run = sub.add_parser("run", help="play matches (or run the game tests) in an instrumented copy")
    run.add_argument("--tests", action="store_true", help="run the copy's game tests instead of matches; the "
                     "arguments that follow are passed to its tools/run_tests.sh")
    run.add_argument("--matches", type=int, default=24, help="game processes to play (default 24)")
    run.add_argument("--jobs", default="2", help="processes at a time: a number or auto (cores, at most 6); default 2, "
                     "what one shared Von server answers (tools/coverage/README.md)")
    run.add_argument("--seed", type=int, default=None, help="process i plays seed N+i (default random)")
    run.add_argument("--endless-every", type=int, default=4, help="every Nth process plays an Endless run of 3 "
                     "matches (default 4; 0 = none)")
    run.add_argument("--windowed", action="store_true", help="play with a window (draws), not headless")
    run.add_argument("--keep", action="store_true", help="keep the instrumented copy and the raw hit files")
    run.add_argument("--uninstrumented", action="store_true", help="the same matches with no counter bump: their "
                     "outcome and cost only, to compare with a measured run")
    rep = sub.add_parser("report", help="the report of the newest runs of HEAD, or of the run folders given")
    rep.add_argument("--domain", default=None, help="only this domain (the folder under scenes/)")
    rep.add_argument("--run", action="append", default=[], help="a run folder (repeatable)")
    rep.add_argument("--out", default=None, help="also save the report into this folder (report.md, report.json, "
                     "runs.json); refused if it already holds one")
    argv = sys.argv[1:]
    if argv[:1] == ["run"] and "--tests" in argv:
        # Every argument but --keep belongs to the copy's tools/run_tests.sh (its --jobs too).
        return cmd_run("tests", test_args=[a for a in argv[1:] if a not in ("--tests", "--keep")],
                       keep="--keep" in argv)
    args = parser.parse_args(argv)
    if args.command == "run":
        return cmd_run("matches", matches=args.matches, jobs=args.jobs, seed=args.seed,
                       endless_every=args.endless_every, windowed=args.windowed, keep=args.keep,
                       instrumented=not args.uninstrumented)
    return cmd_instrument(args) if args.command == "instrument" else cmd_report(args)


if __name__ == "__main__":
    sys.exit(main())
