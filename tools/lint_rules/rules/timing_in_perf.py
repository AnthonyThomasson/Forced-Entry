"""A wall-clock time budget is a performance guard: under tests/, `Time.get_ticks_usec()` (what a budget is measured
with, `Perf.time_ms` among them) appears only in tests/perf/ and tests/_perf/. The pre-commit hook leaves the perf
domain out, since a budget fails on a loaded machine; a budget in another domain's test would run in every commit's
hook. Only code counts: a comment naming the call is left alone, and so is `Time.get_ticks_msec()`, which the
real-time pacing of a test uses (a wall-clock wait), not a budget.
"""
import re

from tools.lint_rules.walk import Finding, gdscript_lines, godot_scripts

NAME = "timing_in_perf"
DESCRIPTION = "Time.get_ticks_usec() under tests/ only in tests/perf/ and tests/_perf/: a time budget is a perf guard"

PERF = ("tests/perf/", "tests/_perf/")
CALL = re.compile(r"\bTime\.get_ticks_usec\s*\(")


def check(root, paths):
    found = []
    for path in godot_scripts(root, ["tests"], paths):
        if path.startswith(PERF):
            continue
        for line in gdscript_lines(root, path):
            if CALL.search(line.bare):
                found.append(Finding(path, line.number, "wall-clock timing (Time.get_ticks_usec) outside the perf "
                                     "domain: a time budget goes in a test under tests/perf/"))
    return found
