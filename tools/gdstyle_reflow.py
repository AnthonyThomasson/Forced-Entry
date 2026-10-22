#!/usr/bin/env python3
"""`tools/gdstyle.sh fmt` runs gdstyle through this: gdstyle wraps an over-long comment line by moving its tail onto a
new line of its own, and this fills the tail back into the comment it came from, to the width of `gdstyle.toml`'s
`max_line_length` (a tab counts 4), with the same indent and marker (`#` / `##`), never splitting a backtick span.

  python3 tools/gdstyle_reflow.py GDSTYLE fmt [OPTION...] [PATH...]

Reads every .gd under the PATHs (the working directory when none is given), runs GDSTYLE with the arguments after it,
then re-flows the files gdstyle changed and exits with gdstyle's status.

What is re-flowed is only what gdstyle split: from the line it cut (never a line above it) through the tail it cut off,
and on through the comment lines below that flowed on from it in the original. A break counts as flow when the line
before it was full (the next word would not have fitted); the first line after the tail is taken in only when it flows
on itself, or ends its paragraph and a sentence (`.` `!` `?`), so a heading, a note on a line of its own or a line of
code keeps its break. A paragraph never takes in a line of another indent or marker, a blank comment line, a list item
(`- `, `* `, `1. `), a preformatted line (more than one space after the marker; only an item's own hang lines continue
it), or code. A comment with runs of spaces inside it (aligned columns) is left as gdstyle wrote it.
"""
import difflib
import re
import subprocess
import sys
import tomllib
from pathlib import Path
from typing import NamedTuple

ROOT = Path(__file__).resolve().parent.parent
TAB = 4

COMMENT = re.compile(r"^(?P<indent>\s*)(?P<marker>#+)(?P<rest>.*)$")
LIST_ITEM = re.compile(r"^(?:[-*]|\d+[.)]) ")
# A word, with any backtick span (spaces and all) and what is glued to it on either side kept as one.
TOKEN = re.compile(r"[^\s`]*`[^`]*`(?:[^\s`]*`[^`]*`)*[^\s`]*|\S+")


def _width() -> int:
    """gdstyle's `max_line_length` from the checkout's gdstyle.toml (100 when it names none)."""
    try:
        return int(tomllib.loads((ROOT / "gdstyle.toml").read_text()).get("max_line_length", 100))
    except (OSError, ValueError):
        return 100


WIDTH = _width()


class Comment(NamedTuple):
    """A full-line comment: its `indent` and `marker`, its `kind` and `body`, and the `prefix` its body follows.
    `kind`: "text" (prose), "item" (a list item), "hang" (the body indented past the marker's one space: an item's
    continuation or a preformatted row) or "break" (empty, or no space after the marker)."""
    indent: str
    marker: str
    kind: str
    body: str
    prefix: str


def _parse(line: str) -> Comment | None:
    """The full-line comment `line` is, else None."""
    m = COMMENT.match(line)
    if not m:
        return None
    indent, marker, rest = m.group("indent"), m.group("marker"), m.group("rest")
    if not rest.startswith(" ") or not rest.strip():
        return Comment(indent, marker, "break", rest, indent + marker)
    body = rest[1:].lstrip(" ")
    prefix = line[:len(line) - len(body)]
    if rest[1:].startswith(" "):
        return Comment(indent, marker, "hang", body, prefix)
    return Comment(indent, marker, "item" if LIST_ITEM.match(body) else "text", body, prefix)


def _columns(text: str) -> int:
    """How many columns `text` takes, a tab counting TAB."""
    return len(text.expandtabs(TAB))


def _full(line: str, following: Comment) -> bool:
    """Whether `line` was full: the first word of the comment `following` it would not have fitted on it."""
    words = TOKEN.findall(following.body)
    return bool(words) and _columns(f"{line} {words[0]}") > WIDTH


def _fill(words: list[str], first: str, rest: str) -> list[str]:
    """`words` filled greedily into lines of at most WIDTH columns, the first line after `first`, the others after
    `rest`; a word longer than a line gets a line of its own."""
    out, line = [], first + words[0]
    for word in words[1:]:
        if _columns(f"{line} {word}") > WIDTH:
            out.append(line)
            line = rest + word
        else:
            line = f"{line} {word}"
    out.append(line)
    return out


def _tails(old: list[str], new: list[str], changed: set[int]) -> set[int]:
    """The lines of `new` that are a tail gdstyle cut off the line above: a changed comment line that, joined to the
    line above it (itself rebuilt when it is a tail too), gives the start of a line of `old`."""
    olds = [line for line in old if _parse(line) is not None]
    tails, rebuilt = set(), {}
    for j in sorted(changed):
        here = _parse(new[j])
        if j == 0 or here is None or here.kind == "break":
            continue
        joined = f"{rebuilt.get(j - 1, new[j - 1])} {here.body}"
        if any(line.startswith(joined) for line in olds):
            tails.add(j)
            rebuilt[j] = joined
    return tails


def _continues(lead: Comment, line: Comment | None) -> bool:
    """Whether comment `line` may continue a paragraph led by `lead`: same indent and marker, and prose, or an item's
    hang line under an item (or under a hang line)."""
    if line is None or (line.indent, line.marker) != (lead.indent, lead.marker):
        return False
    if lead.kind in ("item", "hang"):
        return line.kind == "hang" and line.prefix == _hang(lead)
    return line.kind == "text"


def _hang(lead: Comment) -> str:
    """The prefix of the lines that continue `lead`: an item's hang under its body, else `lead`'s own."""
    if lead.kind == "item":
        return f"{lead.indent}{lead.marker} " + " " * len(LIST_ITEM.match(lead.body).group(0))
    return lead.prefix


def reflow(before: str, after: str) -> str:
    """`after` (gdstyle's output for `before`) with each tail gdstyle split off a comment line filled back into the
    comment it came from (see the module's doc); the rest of `after` as it is. Line ends (LF or CRLF) are kept."""
    eol = "\r\n" if "\r\n" in after else "\n"
    old, new = before.replace("\r\n", "\n").split("\n"), after.replace("\r\n", "\n").split("\n")
    changed, old_of = set(), {}
    for tag, i1, _i2, j1, j2 in difflib.SequenceMatcher(None, old, new, autojunk=False).get_opcodes():
        if tag in ("replace", "insert"):
            changed.update(range(j1, j2))
        elif tag == "equal":
            old_of.update({j1 + k: i1 + k for k in range(j2 - j1)})
    tails = _tails(old, new, changed)
    out, at, j = [], 0, 0
    while j < len(new):
        if j + 1 not in tails or j < at:
            j += 1
            continue
        start, lead = j, _parse(new[j])
        end = j + 1
        while end in tails:
            end += 1
        # On through the lines below that flowed on from it in the original.
        first = True
        while end < len(new) and _continues(lead, _parse(new[end])):
            if end + 1 in tails:  # another line gdstyle cut: it was over-long, so it flowed on
                end += 1
                while end in tails:
                    end += 1
                first = False
                continue
            if end not in old_of:
                break
            k = old_of[end]
            nxt = _parse(new[end + 1]) if end + 1 < len(new) else None
            flows_on = _continues(lead, nxt) and _full(new[end], nxt)
            if first:
                ends = not _continues(lead, nxt) and re.search(r"[.!?]$", _parse(new[end]).body) is not None
                if not (flows_on or ends):
                    break
            elif not (k > 0 and _full(old[k - 1], _parse(new[end]))):
                break
            end += 1
            first = False
        bodies = [lead.body] + [_parse(new[k]).body for k in range(start + 1, end)]
        if any("  " in body.strip() for body in bodies):
            j = end
            continue  # aligned columns: gdstyle's own wrap is left
        out += new[at:start] + _fill(TOKEN.findall(" ".join(bodies)), lead.prefix, _hang(lead))
        at = j = end
    return eol.join(out + new[at:])


def _scripts(targets: list[str]) -> list[Path]:
    """The .gd files under `targets` (files or folders; the working directory when there are none), as gdstyle
    would format them, the engine's .godot folder left out."""
    found = []
    for target in targets or ["."]:
        path = Path(target.removeprefix("res://"))
        if path.is_dir():
            found += [p for p in path.rglob("*.gd") if ".godot" not in p.parts]
        elif path.suffix == ".gd" and path.is_file():
            found.append(path)
    return found


def main(argv: list[str]) -> int:
    """Run gdstyle (`argv[0]`) with the rest of `argv`, then re-flow what it changed; gdstyle's exit status."""
    gdstyle, args = argv[0], argv[1:]
    scripts = _scripts([a for a in args[1:] if not a.startswith("-")])
    before = {p: p.read_text(encoding="utf-8", newline="") for p in scripts}
    status = subprocess.run([gdstyle, *args]).returncode
    for path, text in before.items():
        after = path.read_text(encoding="utf-8", newline="") if path.exists() else text
        if after != text:
            flowed = reflow(text, after)
            if flowed != after:
                path.write_text(flowed, encoding="utf-8", newline="")
                print(f"Re-flowed comments in {path}")
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
