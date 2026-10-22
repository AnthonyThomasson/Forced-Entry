#!/usr/bin/env python3
"""`tools/gdstyle.sh fmt` runs gdstyle through this: gdstyle wraps an over-long comment line by moving its tail onto a
new line of its own, and this fills each comment paragraph gdstyle changed back to 100 columns (a tab counts 4), with
the same indent and marker (`#` / `##`), never splitting a backtick span.

  python3 tools/gdstyle_reflow.py GDSTYLE fmt [OPTION...] [PATH...]

Reads every .gd under the PATHs (the working directory when none is given), runs GDSTYLE with the arguments after it,
then re-flows the files gdstyle changed and exits with gdstyle's status. A paragraph is the full-line comments of one
indent and marker, ended by a blank comment line, a line of another indent or marker, a list item (`- `, `* `, `1. `:
it starts a paragraph, continued by its hang-indented lines and by the tail gdstyle split off it), a preformatted line
(more than one space after the marker), a line with no space after the marker (`#region`), or code. A trailing comment
on a code line is never part of one, and a paragraph with no line gdstyle changed is left as it is.
"""
import difflib
import re
import subprocess
import sys
from pathlib import Path

WIDTH = 100
TAB = 4

COMMENT = re.compile(r"^(?P<indent>\s*)(?P<marker>#+)(?P<rest>.*)$")
LIST_ITEM = re.compile(r"^(?:[-*]|\d+[.)]) ")
# A word, with any backtick span (spaces and all) and what is glued to it on either side kept as one.
TOKEN = re.compile(r"[^\s`]*`[^`]*`(?:[^\s`]*`[^`]*`)*[^\s`]*|\S+")


def _columns(text: str) -> int:
    return len(text.expandtabs(TAB))


def _parse(line: str):
    """(indent, marker, kind, body) of a full-line comment, else None. `kind`: "text" (prose), "item" (a list item),
    "hang" (`body` indented past the marker's one space: a list item's continuation or a preformatted row) or "break"
    (empty, or no space after the marker)."""
    m = COMMENT.match(line)
    if not m:
        return None
    rest = m.group("rest")
    if not rest.startswith(" ") or not rest.strip():
        return m.group("indent"), m.group("marker"), "break", rest
    body = rest[1:]
    if body.startswith(" "):
        return m.group("indent"), m.group("marker"), "hang", body
    return m.group("indent"), m.group("marker"), "item" if LIST_ITEM.match(body) else "text", body


def _paragraphs(lines: list[str], changed: set[int]) -> list[tuple[int, int, str, str]]:
    """The re-flowable paragraphs of `lines`: (first, end, first-line prefix, continuation prefix), `end` exclusive."""
    out = []
    i = 0
    while i < len(lines):
        parsed = _parse(lines[i])
        if parsed is None or parsed[2] in ("break", "hang"):
            i += 1
            continue
        indent, marker, kind, body = parsed
        first = f"{indent}{marker} "
        rest = first
        if kind == "item":
            bullet = LIST_ITEM.match(body).group(0)
            first, rest = first + bullet, first + " " * len(bullet)
        j = i + 1
        while j < len(lines):
            nxt = _parse(lines[j])
            if nxt is None or nxt[:2] != (indent, marker):
                break
            if kind == "item":
                # Its hang lines continue it, and so does the tail gdstyle split off it (no hang: a changed line).
                if not ((nxt[2] == "hang" and lines[j].startswith(rest)) or (nxt[2] == "text" and j in changed)):
                    break
            elif nxt[2] != "text":
                break
            j += 1
        out.append((i, j, first, rest))
        i = j
    return out


def _fill(words: list[str], first: str, rest: str) -> list[str]:
    out, line = [], first
    for word in words:
        bare = line in (first, rest) and line == (first if not out else rest)
        if not bare and _columns(f"{line} {word}") > WIDTH:
            out.append(line)
            line = rest + word
        else:
            line = line + word if bare else f"{line} {word}"
    out.append(line)
    return out


def reflow(before: str, after: str) -> str:
    """`after` (gdstyle's output for `before`) with each comment paragraph holding a line gdstyle changed filled to
    WIDTH columns again; the rest of `after` as it is."""
    old, new = before.split("\n"), after.split("\n")
    changed = set()
    for tag, _i1, _i2, j1, j2 in difflib.SequenceMatcher(None, old, new, autojunk=False).get_opcodes():
        if tag in ("replace", "insert"):
            changed.update(range(j1, j2))
    if not changed:
        return after
    out, at = [], 0
    for first_line, end, first, rest in _paragraphs(new, changed):
        if not changed.intersection(range(first_line, end)):
            continue
        # Joined first, so a span gdstyle split across two lines is one word again.
        text = " ".join([new[first_line][len(first):]] + [_parse(new[k])[3] for k in range(first_line + 1, end)])
        words = TOKEN.findall(text)
        out += new[at:first_line] + _fill(words, first, rest)
        at = end
    return "\n".join(out + new[at:])


def _scripts(targets: list[str]) -> list[Path]:
    found = []
    for target in targets or ["."]:
        path = Path(target.removeprefix("res://"))
        if path.is_dir():
            found += [p for p in path.rglob("*.gd") if ".godot" not in p.parts]
        elif path.suffix == ".gd" and path.is_file():
            found.append(path)
    return found


def main(argv: list[str]) -> int:
    gdstyle, args = argv[0], argv[1:]
    scripts = _scripts([a for a in args[1:] if not a.startswith("-")])
    before = {p: p.read_text(encoding="utf-8") for p in scripts}
    status = subprocess.run([gdstyle, *args]).returncode
    for path, text in before.items():
        after = path.read_text(encoding="utf-8") if path.exists() else text
        if after != text:
            flowed = reflow(text, after)
            if flowed != after:
                path.write_text(flowed, encoding="utf-8")
                print(f"Re-flowed comments in {path}")
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
