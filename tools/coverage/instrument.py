"""Instrument a copy of the repo (made by workspace.create): a counter bump before every statement of scenes/**/*.gd,
the probe copied in and registered, and the statement map (tools/coverage/README.md, "Statement map").

  instrument(copy, markers=True) -> dict
      rewrites the copy in place and returns the map (also written to the copy's tools/coverage/map.json); with
      markers=False no script is touched and the map has no statements, but the probe is installed all the same: an
      uninstrumented copy, which plays the same matches without the counters' cost (`coverage.py run
      --uninstrumented`)

The bump goes on the statement's own line, before it (`CoverageProbe.h[7] += 1; <statement>`), so every source line
stays where it was: a line in the map, in the copy and in an engine error are the same line. Ids follow the files in
path order and each file's statements in (line, column) order, so the same sources always give the same map. Spans
the scanner is unsure of are left untouched and listed in the map's `uninstrumented`.

The probe template (probe.gd, next to this file) is copied to the copy's tools/coverage/coverage_probe.gd with the
statement count and the map hash filled in, and registered FIRST in the copy's [autoload], so its counters exist
before any other script runs. The copy also gets its own user:// folder (workspace.user_dir_name), so a run never
writes the developer's settings or logs.
"""
import hashlib
import json
import re
from pathlib import Path

from . import scanner, workspace
from .hits import write_json

FORMAT = "fe-coverage-map"
VERSION = 1
PROBE_NAME = "CoverageProbe"
PROBE_TEMPLATE = Path(__file__).resolve().parent / "probe.gd"
PROBE_PATH = "tools/coverage/coverage_probe.gd"  # in the copy
MAP_PATH = "tools/coverage/map.json"  # in the copy


def marker(sid: int) -> str:
    return f"{PROBE_NAME}.h[{sid}] += 1; "


def instrument(copy, markers: bool = True) -> dict:
    copy = Path(copy)
    scripts = sorted(p.relative_to(copy).as_posix() for p in (copy / "scenes").rglob("*.gd")
                     if p.is_file()) if markers else []
    statements, uninstrumented, texts = [], [], {}
    for rel in scripts:
        text = (copy / rel).read_text(encoding="utf-8")
        found = scanner.scan(text)
        texts[rel] = (text, [])
        for s in found["statements"]:
            sid = len(statements)
            statements.append({"id": sid, "file": rel, "line": s["line"], "kind": s["kind"],
                               "function": s["function"], "class": s["class"]})
            texts[rel][1].append((s["line"], s["col"], sid))
        uninstrumented += [{"file": rel, "line": u["line"], "end_line": u["end_line"], "reason": u["reason"]}
                           for u in found["uninstrumented"]]
    smap = {"format": FORMAT, "version": VERSION, "hash": map_hash(statements, uninstrumented),
            "statements": statements, "uninstrumented": uninstrumented}
    for rel, (text, marks) in texts.items():
        if marks:
            (copy / rel).write_text(mark(text, marks), encoding="utf-8")
    install_probe(copy, len(statements), smap["hash"])
    write_json(copy / MAP_PATH, smap)
    return smap


def map_hash(statements: list, uninstrumented: list) -> str:
    body = json.dumps({"statements": statements, "uninstrumented": uninstrumented}, sort_keys=True,
                      separators=(",", ":"))
    return hashlib.sha256(body.encode()).hexdigest()


def mark(text: str, marks: list[tuple[int, int, int]]) -> str:
    """`text` with a bump inserted at each (line, col) of `marks`, right to left so earlier columns stay valid."""
    lines = text.split("\n")
    for line, col, sid in sorted(marks, key=lambda m: (m[0], m[1]), reverse=True):
        row = lines[line - 1]
        lines[line - 1] = row[:col] + marker(sid) + row[col:]
    return "\n".join(lines)


def install_probe(copy: Path, count: int, smap_hash: str) -> None:
    """Copy the probe in with the count and hash filled in, register it first, and give the copy its own user://."""
    probe = PROBE_TEMPLATE.read_text(encoding="utf-8")
    probe, n_count = re.subn(r"^const COUNT := 0$", f"const COUNT := {count}", probe, flags=re.M)
    probe, n_hash = re.subn(r'^const MAP_HASH := ""$', f'const MAP_HASH := "{smap_hash}"', probe, flags=re.M)
    if (n_count, n_hash) != (1, 1):
        raise ValueError(f"{PROBE_TEMPLATE} lost its `const COUNT := 0` or `const MAP_HASH := \"\"` line")
    (copy / PROBE_PATH).parent.mkdir(parents=True, exist_ok=True)
    (copy / PROBE_PATH).write_text(probe, encoding="utf-8")
    project = copy / "project.godot"
    text = project.read_text(encoding="utf-8")
    text = set_entry(text, "autoload", f'{PROBE_NAME}="*res://{PROBE_PATH}"', first=True)
    text = set_entry(text, "application", "config/use_custom_user_dir=true")
    text = set_entry(text, "application", f'config/custom_user_dir_name="{workspace.user_dir_name(copy)}"')
    project.write_text(text, encoding="utf-8")


def set_entry(text: str, section: str, entry: str, first: bool = False) -> str:
    """project.godot `text` with `entry` (key=value) in [section]: replacing the key's line if there is one, else
    added first or last in the section (the section is added at the end when missing)."""
    key = entry.split("=", 1)[0]
    lines = text.split("\n")
    head = next((i for i, l in enumerate(lines) if l.strip() == f"[{section}]"), None)
    if head is None:
        return text.rstrip("\n") + f"\n\n[{section}]\n\n{entry}\n"
    end = next((i for i in range(head + 1, len(lines)) if lines[i].startswith("[")), len(lines))
    for i in range(head + 1, end):
        if lines[i].split("=", 1)[0].strip() == key:
            lines[i] = entry
            return "\n".join(lines)
    if first:
        at = head + 1
        while at < end and lines[at].strip() == "":
            at += 1
    else:
        at = end
        while at > head + 1 and lines[at - 1].strip() == "":
            at -= 1
    lines.insert(at, entry)
    return "\n".join(lines)
