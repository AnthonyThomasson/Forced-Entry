"""Helpers the project lint rules share: the finding a rule returns, walking the tree, matching lines and names.

A rule never opens the tree on its own terms: `files` lists what it may look at (limited to the paths lint was given),
`lines_matching` reads a text file's matching lines, `names_matching` its path's matching file or folder names. See
tools/lint_rules/README.md for how a rule is written.
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
