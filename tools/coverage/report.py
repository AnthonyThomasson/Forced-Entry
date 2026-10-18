"""The coverage report: one or more runs (a matches run and/or a tests run) rolled up per domain, file and function,
tagged, with the saturation curve, the uninstrumented spans and the limits of what zero hits means.

  build(runs, unreferenced, domain=None) -> dict
      runs          [{"meta": meta.json, "map": map.json, "hits": hits.json}]
      unreferenced  {(file, function)}: the functions nothing references (static_refs.unreferenced)
      domain        only that domain's files (the first folder under scenes/; "main" for a script directly in it)
  markdown(report) -> str     the same report as Markdown

The runs are joined by statement id when their maps are the same (one hash). Maps that differ (runs of different
builds) are joined by (file, line, kind) instead, with a warning; so are runs of different commits, with a warning
naming both. The first matches run's map is the report's (the first run's when there is none). A function's line
and hits are those of its first body statement (its `function` statement, tools/coverage/README.md).

Tags (README "Report"): dead, dead branch, test-only, untriggered system, rare, live-but-unpinned, noise.
"""
import collections
import re

TAGS = ("dead", "dead branch", "test-only", "untriggered system", "rare", "live-but-unpinned", "noise")
RARE = 0.10  # fired in fewer than this share of the matches
TEST_IDS_SHOWN = 3
# Code that is not the game itself: the test harness and its UI, the dev command server, the debug overlays and the
# settings menu. Tagged, never hidden.
NOISE = re.compile(r"^scenes/(?:ui/)?testing/|(?:^|/)command_server\.gd$|(?:^|/)debug/|debug[^/]*\.gd$"
                   r"|^scenes/ui/overlays/|settings_menu[^/]*\.gd$")
LIMITS = [
    "Zero hits means \"did not run in the sampled matches\" (or tests), not unreachable: another seed, side count or "
    "loadout, or a longer match, may reach it. The saturation curve shows whether new code was still turning up.",
    "Coverage is per statement: the conditions inside one expression (`a and b`, a ternary) are not seen.",
    "Matches with no human player skip player-only code (input, the leader's command menu, driving a vehicle by "
    "hand); scripted play through gcmd can cover it.",
    "Declarations and data (a const, a signal, a config field, an unselected data-table entry), shaders, scene "
    "wiring, gcmd `Expression` eval and runtime-built scripts are not measured; audit_scan.py remains the view for "
    "declarations.",
    "Counts from threads (the nav bake, the WorkerThreadPool) may lose increments; zero vs. non-zero stays right.",
    "A result belongs to one commit: re-measure after a refactor.",
    "The uninstrumented spans hold no counter, so they are never read as dead; they are listed in their own section.",
    "`dead` and `untriggered system` rest on audit_scan's token matching: a same-named function anywhere hides a "
    "dead one, so both are leads to confirm by hand.",
    "A match the probe capped (verdict TIME CAP, past Main's endless_time_limit) never reached its own end. An "
    "Endless run's later matches draw their seed at random (Main's own), so only a process's first match is "
    "reproducible by seed.",
]


def domain_of(file: str) -> str:
    parts = file.split("/")
    return parts[1] if len(parts) > 2 else "main"


def short(commit: str) -> str:
    return commit[:7]


def starved(meta: dict) -> list[dict]:
    """The matches of a run whose NPCs got fewer Von decisions (walks Von answered) per NPC per game minute than its
    floor."""
    floor = meta.get("von_floor")
    return [m for m in meta.get("matches", []) if floor is not None and m.get("decided_per_npc_minute") is not None
            and m["decided_per_npc_minute"] < floor]


def starved_warning(meta: dict) -> str | None:
    """The warning for a run's starved matches (runner.run prints it too), or None."""
    slow = starved(meta)
    if not slow:
        return None
    return (f"{len(slow)} of {len(meta['matches'])} matches got fewer than {meta['von_floor']:g} Von decisions per "
            f"NPC per game minute (walks Von answered; its NPCs were starved of decisions and held steady: the Von "
            f"server was busy; lower --jobs or wait for a quiet machine): "
            + ", ".join(f"{m['seed']}-{m['match']} ({m['decided_per_npc_minute']:.1f}, "
                        f"{(m.get('von_failed_share') or 0):.0%} failed)" for m in slow))


def build(runs, unreferenced, domain=None) -> dict:
    runs = list(runs)
    warnings = []
    commits = {r["meta"]["commit"] for r in runs}
    if len(commits) > 1:
        warnings.append("The runs are of different commits: " + ", ".join(
            f"{short(r['meta']['commit'])} ({r['meta']['source']})" for r in runs) + ". The newer code's lines may "
            "not match the older run's.")
    for r in runs:
        if r["meta"]["source"] == "matches" and starved_warning(r["meta"]):
            warnings.append(starved_warning(r["meta"]))
    base = next((r for r in runs if r["meta"]["source"] == "matches"), runs[0])["map"]
    statements = base["statements"]
    match_hits = collections.Counter()
    match_fired = collections.Counter()
    test_hits = collections.Counter()
    outside_hits = collections.Counter()  # a tests run's `outside` unit: ran while no test ran
    tests_of = collections.defaultdict(set)
    first_unit = {}  # statement id -> index of the match unit that first hit it
    match_units = 0
    has = {"matches": False, "tests": False}
    played = []  # (unit, to_base) of every matches run, then taken in seed order: one run played in chunks reads as one
    for r in runs:
        source = r["meta"]["source"]
        has[source] = True
        to_base = id_map(r["map"], base, warnings, r["meta"])
        if source == "matches":
            played += [(unit, to_base) for unit in r["hits"]["units"]]
            continue
        for unit in r["hits"]["units"]:
            for key, n in unit["counts"].items():
                sid = to_base.get(int(key))
                if sid is None or n <= 0:
                    continue
                if unit.get("outside"):
                    outside_hits[sid] += n
                else:
                    test_hits[sid] += n
                    tests_of[sid].add(unit["id"])
    seen = collections.Counter(unit["id"] for unit, _ in played)
    if any(n > 1 for n in seen.values()):
        warnings.append("The matches runs repeat matches (each repeat counts again): "
                        + ", ".join(sorted(i for i, n in seen.items() if n > 1)) + ".")
    for unit, to_base in sorted(played, key=lambda p: (p[0].get("seed", 0), p[0].get("match", 0))):
        for key, n in unit["counts"].items():
            sid = to_base.get(int(key))
            if sid is None or n <= 0:
                continue
            match_hits[sid] += n
            match_fired[sid] += 1
            first_unit.setdefault(sid, match_units)
        match_units += 1

    def ran(sid):
        return match_hits[sid] > 0 or test_hits[sid] > 0 or outside_hits[sid] > 0

    groups = collections.OrderedDict()
    for s in statements:
        groups.setdefault((s["file"], s["class"], s["function"]), []).append(s)
    files = collections.defaultdict(list)
    for (file, cls, function), body in groups.items():
        if domain is not None and domain_of(file) != domain:
            continue
        head = next((s for s in body if s["kind"] == "function"), body[0])
        sid = head["id"]
        total = match_hits[sid] + test_hits[sid] + outside_hits[sid]
        dead_branches = sorted({s["line"] for s in body if s["kind"] == "branch" and not ran(s["id"])}) if total else []
        tags = set()
        if total == 0:
            tags.add("dead" if (file, function) in unreferenced else "untriggered system")
        if dead_branches:
            tags.add("dead branch")
        if has["matches"] and test_hits[sid] and not match_hits[sid]:
            tags.add("test-only")
        if match_hits[sid] and match_fired[sid] < RARE * match_units:
            tags.add("rare")
        if has["tests"] and match_hits[sid] and not test_hits[sid]:
            tags.add("live-but-unpinned")
        if NOISE.search(file):
            tags.add("noise")
        files[file].append({
            "function": function, "class": cls, "line": head["line"],
            "match_hits": match_hits[sid], "matches_fired": match_fired[sid], "test_hits": test_hits[sid],
            "outside_hits": outside_hits[sid],
            "tests": {"count": len(tests_of[sid]), "ids": sorted(tests_of[sid])[:TEST_IDS_SHOWN]},
            "tags": [t for t in TAGS if t in tags],
            "uncovered": uncovered(body, ran),
            "dead_branches": dead_branches,
        })
    domains = collections.defaultdict(list)
    for file in sorted(files):
        domains[domain_of(file)].append({"file": file, "functions": sorted(files[file], key=lambda f: f["line"])})
    spans = []
    for r in runs:
        spans += [u for u in r["map"]["uninstrumented"] if u not in spans]
    return {
        "runs": [{"source": r["meta"]["source"], "commit": r["meta"]["commit"], "time": r["meta"]["time"],
                  "map_hash": r["meta"]["map_hash"], "units": len(r["hits"]["units"])} for r in runs],
        "warnings": warnings,
        "matches_total": match_units,
        "failed_tests": [f for r in runs if r["meta"]["source"] == "tests" for f in r["meta"].get("failed", [])],
        "crashed": [c for r in runs if r["meta"]["source"] == "matches" for c in r["meta"].get("crashed", [])],
        "domains": [{"domain": d, "files": domains[d]} for d in sorted(domains)],
        "curve": curve(statements, groups, first_unit, match_units),
        "uninstrumented": [u for u in spans if domain is None or domain_of(u["file"]) == domain],
        "limits": LIMITS,
    }


def id_map(smap: dict, base: dict, warnings: list, meta: dict) -> dict[int, int]:
    """A run's statement ids -> the report map's: the same ids for the same map, else joined by (file, line, kind)
    (the n-th statement of a key to the n-th)."""
    if smap["hash"] == base["hash"]:
        return {s["id"]: s["id"] for s in base["statements"]}
    by_key = collections.defaultdict(list)
    for s in base["statements"]:
        by_key[(s["file"], s["line"], s["kind"])].append(s["id"])
    seen = collections.Counter()
    out = {}
    for s in smap["statements"]:
        key = (s["file"], s["line"], s["kind"])
        if seen[key] < len(by_key[key]):
            out[s["id"]] = by_key[key][seen[key]]
        seen[key] += 1
    lost = len(smap["statements"]) - len(out)
    warnings.append(f"The {meta['source']} run ({short(meta['commit'])}) was instrumented with another map "
                    f"({smap['hash'][:12]}, not {base['hash'][:12]}): joined by file, line and kind"
                    + (f"; {lost} of its statements have no counterpart and are left out." if lost else "."))
    return out


def uncovered(body: list, ran) -> list[list[int]]:
    """The [first, last] line ranges of the function's statements no run hit; a range runs on until a statement
    with hits."""
    ranges, start, last = [], None, None
    for s in body:
        if ran(s["id"]):
            if start is not None:
                ranges.append([start, last])
                start = None
        else:
            start = s["line"] if start is None else start
            last = s["line"]
    if start is not None:
        ranges.append([start, last])
    return ranges


def curve(statements, groups, first_unit, match_units) -> list[dict]:
    """Per match added (in seed order, then match number, over every matches run): the functions and the source lines
    it was the first to run."""
    heads = {next((s for s in body if s["kind"] == "function"), body[0])["id"] for body in groups.values()}
    new_functions = collections.Counter()
    line_first = {}
    for s in statements:
        if s["id"] in first_unit:
            if s["id"] in heads:
                new_functions[first_unit[s["id"]]] += 1
            key = (s["file"], s["line"])
            line_first[key] = min(line_first.get(key, match_units), first_unit[s["id"]])
    new_lines = collections.Counter(line_first.values())
    return [{"matches": k + 1, "new_functions": new_functions[k], "new_lines": new_lines[k]} for k in range(match_units)]


def cell(text) -> str:
    return str(text).replace("|", "\\|")


def ranges_text(ranges) -> str:
    return ", ".join(str(a) if a == b else f"{a}-{b}" for a, b in ranges)


def markdown(rep: dict) -> str:
    out = ["# Coverage report", ""]
    for r in rep.get("runs", []):
        out.append(f"- {r['source']} run of {short(r['commit'])} at {r['time']}: {r['units']} "
                   f"{'matches' if r['source'] == 'matches' else 'tests'} (map {r['map_hash'][:12]})")
    out.append("")
    for w in rep["warnings"]:
        out.append(f"> **Warning:** {w}")
    if rep["warnings"]:
        out.append("")
    counts = collections.Counter(t for d in rep["domains"] for f in d["files"] for fn in f["functions"]
                                 for t in fn["tags"])
    total = sum(len(f["functions"]) for d in rep["domains"] for f in d["files"])
    out += [f"{total} functions over {rep['matches_total']} matches. Tags: "
            + ", ".join(f"{t} {counts[t]}" for t in TAGS) + ".", "",
            "Columns: the function's first body line; its hits in the matches, the matches it ran in, its hits in "
            "the tests (with, as `+N outside tests`, those made while no test ran: the runner's start-up and "
            "each test's teardown after its verdict, which pin nothing) and the tests that ran it (up to three "
            "named); its tags; the line ranges no run reached (`uncovered`) and the branch arms of a live function "
            "that never ran (`dead branches`).", ""]
    for d in rep["domains"]:
        out += [f"## Domain {d['domain']}", ""]
        for f in d["files"]:
            out += [f"### {f['file']}", "",
                    "| function | line | match hits | matches | test hits | tests | tags | uncovered | dead branches |",
                    "|---|---|---|---|---|---|---|---|---|"]
            for fn in f["functions"]:
                name = f"{fn['class']}.{fn['function']}" if fn["class"] else fn["function"]
                tests = str(fn["tests"]["count"])
                if fn["tests"]["ids"]:
                    more = fn["tests"]["count"] - len(fn["tests"]["ids"])
                    tests += " (" + ", ".join(fn["tests"]["ids"]) + (f", +{more}" if more else "") + ")"
                test_hits = str(fn["test_hits"])
                if fn.get("outside_hits"):
                    test_hits += f" (+{fn['outside_hits']} outside tests)"
                out.append("| " + " | ".join(cell(c) for c in (
                    name, fn["line"], fn["match_hits"], fn["matches_fired"], test_hits, tests,
                    ", ".join(fn["tags"]), ranges_text(fn["uncovered"]),
                    ", ".join(str(b) for b in fn["dead_branches"]))) + " |")
            out.append("")
    out += ["## Saturation", "",
            "What each match added, in seed order: the functions and source lines no earlier match ran. A "
            "tail of zeros means more matches of the same kind are unlikely to find new code.", ""]
    if rep["curve"]:
        out += ["| matches | new functions | new lines |", "|---|---|---|"]
        out += [f"| {c['matches']} | {c['new_functions']} | {c['new_lines']} |" for c in rep["curve"]]
    else:
        out.append("(no matches run)")
    out += ["", "## Failed under instrumentation", "",
            "The game tests that failed or timed out in the instrumented copy, with their first failed check. Their "
            "hits count like any test's. A wall-clock budget (a perf or a render-time check) fails from the "
            "counters' cost, not from the game; any other failure is worth a look in the real tree.", ""]
    out += [f"- `{f['id']}` {f['verdict']}" + (f": {f['first']}" if f["first"] else "")
            for f in rep.get("failed_tests", [])] or ["(none)"]
    out += ["", "## Crashed after the last flush", "",
            "The game processes that exited non-zero at quit after their final flush: every match of theirs was "
            "decided and recorded, so no hit was lost and their hits count like any match's. The message is the last "
            "line the process printed; the log is kept in the run folder.", ""]
    out += [f"- seed {c['seed']} ({c['mode']}, process {c['process']}, pid {c['pid']}) exited with {c['exit']} "
            f"{c['phase']}: {c['message'] or '(no message)'}; log `{c['log']}`"
            for c in rep.get("crashed", [])] or ["(none)"]
    out += ["", "## Uninstrumented", "",
            "Spans the scanner was not sure of and left without counters (never read as dead):", ""]
    out += [f"- {u['file']}:{u['line']}" + (f"-{u['end_line']}" if u["end_line"] != u["line"] else "")
            + f": {u['reason']}" for u in rep["uninstrumented"]] or ["(none)"]
    out += ["", "## Limits", ""]
    out += [f"- {limit}" for limit in rep["limits"]]
    return "\n".join(out) + "\n"
