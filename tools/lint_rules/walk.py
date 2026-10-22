"""Helpers the project lint rules share: the finding a rule returns, walking the tree, matching lines and names.

A rule never opens the tree on its own terms: `files` lists what it may look at (limited to the paths lint was given),
`godot_scripts` the scripts among them Godot loads, `lines_matching` reads a text file's matching lines,
`names_matching` its path's matching file or folder names, and `gdscript_lines` a script's lines split into code and
comment, each marked where a statement starts. See tools/lint_rules/README.md for how a rule is written.
"""
import fnmatch
import re
from pathlib import Path, PurePosixPath
from typing import NamedTuple


class Finding(NamedTuple):
    """One thing a rule found: the repo-relative POSIX `path`, its 1-based `line` (0 = the file or folder itself, not a
    line of it) and a `message` saying what is wrong."""
    path: str
    line: int
    message: str


def _inside(path: str, limit: str) -> bool:
    """Whether the repo-relative `path` is `limit` or lies under it."""
    limit = limit.strip("/")
    return limit in ("", ".") or path == limit or path.startswith(limit + "/")


def files(root, dirs, paths=None) -> list[str]:
    """Sorted repo-relative POSIX paths of every file under `dirs` of `root` (a name in `dirs` may be a file, such as
    "project.godot"; a missing one is skipped), limited to those inside `paths` (files or folders) when given."""
    root = Path(root)
    found = []
    for name in dirs:
        base = root / name
        if base.is_file():
            found.append(name)
        elif base.is_dir():
            found += [p.relative_to(root).as_posix() for p in base.rglob("*") if p.is_file()]
    if paths is not None:
        limits = [str(PurePosixPath(p.removeprefix("res://"))) for p in paths]
        found = [f for f in found if any(_inside(f, limit) for limit in limits)]
    return sorted(set(found))


def godot_scripts(root, dirs, paths=None) -> list[str]:
    """The `.gd` files of `files(root, dirs, paths)` that Godot loads: none under a folder holding a `.gdignore` (the
    engine and tools/lint.sh skip those, e.g. artifacts/, where a coverage run keeps its copy)."""
    root = Path(root)
    ignored = {p.parent.relative_to(root).as_posix() for name in dirs if (root / name).is_dir()
               for p in (root / name).rglob(".gdignore")}
    return [f for f in files(root, dirs, paths)
            if f.endswith(".gd") and not any(_inside(f, folder) for folder in ignored)]


def lines_matching(root, path: str, pattern: str) -> list[tuple[int, str]]:
    """The 1-based (line, text) of every line of the file `path` (relative to `root`) that matches the regex `pattern`;
    the file is read as text, undecodable bytes dropped, so a binary file simply matches nothing."""
    text = (Path(root) / path).read_text(encoding="utf-8", errors="ignore")
    regex = re.compile(pattern)
    return [(n, line) for n, line in enumerate(text.split("\n"), start=1) if regex.search(line)]


def names_matching(path: str, globs) -> list[str]:
    """The leading parts of the repo-relative `path` whose last name matches one of the shell `globs`
    (`scenes/a/coverage_hits/x.json` and `coverage_hits*` -> ["scenes/a/coverage_hits"]): the files and folders named so."""
    parts = PurePosixPath(path).parts
    return ["/".join(parts[:i + 1]) for i, name in enumerate(parts) if any(fnmatch.fnmatchcase(name, g) for g in globs)]


class GDLine(NamedTuple):
    """One line of a GDScript file: its 1-based `number`, its `text`, the `code` before its comment, its `comment`
    (from the first `#` outside a string, "" for none), whether it `starts` a statement (it is not inside
    brackets, a triple-quoted string or a backslash continuation that an earlier line opened), and its `bare` code:
    `code` with what is inside each string blanked to spaces (the quotes kept), for matching the code's shape."""
    number: int
    text: str
    code: str
    comment: str
    starts: bool
    bare: str


def gdscript_lines(root, path: str) -> list[GDLine]:
    """The lines of the GDScript file `path` (relative to `root`), each split into code and comment and marked where a
    statement starts. Strings ("", '', triple-quoted, with their `&` / `^` prefixes) hide a `#` and brackets."""
    text = (Path(root) / path).read_text(encoding="utf-8", errors="ignore")
    out = []
    depth, quote, continued = 0, None, False
    for number, line in enumerate(text.split("\n"), start=1):
        starts = depth == 0 and quote is None and not continued
        comment_at = len(line)
        bare = []
        i = 0
        while i < len(line):
            c = line[i]
            if quote:
                if c == "\\":
                    bare.append(" " * len(line[i:i + 2]))
                    i += 2
                    continue
                if line.startswith(quote, i):
                    bare.append(quote)
                    i += len(quote)
                    quote = None
                    continue
                bare.append(" ")
            elif c in "\"'":
                quote = line[i:i + 3] if line[i:i + 3] in ('"""', "'''") else c
                bare.append(quote)
                i += len(quote)
                continue
            elif c == "#":
                comment_at = i
                break
            else:
                bare.append(c)
                if c in "([{":
                    depth += 1
                elif c in ")]}":
                    depth = max(0, depth - 1)
            i += 1
        if quote in ("\"", "'"):
            quote = None  # a one-line string never runs on past its line
        code = line[:comment_at]
        continued = quote is None and code.rstrip().endswith("\\")
        out.append(GDLine(number, line, code, line[comment_at:], starts, "".join(bare)))
    return out
