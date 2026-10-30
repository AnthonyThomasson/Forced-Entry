#!/usr/bin/env python3
"""The tests a changed spec paragraph names (tools/run_tests.sh --changed).

  python3 tools/spec_tests.py [--staged]

Reads the uncommitted change to docs/*.md (`git diff HEAD -U0`, plus the untracked docs; with --staged what is staged,
`git diff --cached`, the doc as the index holds it) and prints, one per line:

  ID <test id>                                       a test a changed paragraph names (resolved under tests/)
  NOTE docs/<f>.md:<line>: changed paragraph names no test
  NOTE unknown test name in docs/<f>.md:<line>: <name>

A changed paragraph is the blank-line-bounded block of the new file that holds a changed line of a hunk; a hunk that only
deletes lines changes the block around the place they were (<line> is the block's first line). A paragraph names its
tests on its `Test:` / `Tests:` line (anywhere in a line, as in `Why: ... Tests: ...`), which goes on to the next line
while it ends with a comma: each backticked name there is a test file, `tests/**/<name>_test.gd` (a name with a `/` is
a path under tests/, `ai/grenade/order_frag_entry`). A name is a lowercase identifier; text in parentheses is
commentary, and a backticked `code.name` is not a test. A name with no test file is the second NOTE (<line> is the line
of the name). Helper folders (`tests/_*`) hold no tests. Neither NOTE is a failure.
"""
import re
import subprocess
import sys
from pathlib import Path

HUNK = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@")
TEST_LINE = re.compile(r"\bTests?:(.*)$")
NAME = re.compile(r"`([a-z][a-z0-9_]*(?:/[a-z][a-z0-9_]*)*)`")


def changed_lines(diff: str) -> dict:
    """path -> the (first line, line count) of each hunk's new side, for every docs/*.md the unified diff touches."""
    out, path = {}, None
    for line in diff.splitlines():
        if line.startswith("+++ "):
            target = line[4:].strip()
            path = target[2:] if target.startswith("b/") else None  # /dev/null: a deleted file
            if path is not None and not (path.startswith("docs/") and path.endswith(".md")):
                path = None
        elif line.startswith("@@") and path is not None:
            m = HUNK.match(line)
            if m:
                out.setdefault(path, []).append((int(m.group(1)), 1 if m.group(2) is None else int(m.group(2))))
    return out


def paragraph(lines: list, n: int):
    """The (first, last) line number, 1-based, of the blank-line-bounded block holding line `n`; None if it is blank."""
    if not 1 <= n <= len(lines) or not lines[n - 1].strip():
        return None
    first = n
    while first > 1 and lines[first - 2].strip():
        first -= 1
    last = n
    while last < len(lines) and lines[last].strip():
        last += 1
    return first, last


def changed_paragraphs(lines: list, hunks: list) -> list:
    """The paragraphs (first, last) a doc's hunks change, in file order, each once."""
    found = set()
    for start, count in hunks:
        # A pure deletion (count 0) sits after line `start`: the block around the place the lines were.
        candidates = range(start, start + count) if count else (start, start + 1)
        for n in candidates:
            block = paragraph(lines, n)
            if block:
                found.add(block)
                if not count:
                    break
    return sorted(found)


def without_parentheses(text: str) -> str:
    """`text` with the balanced (...) removed, and an unclosed one cut off with all that follows it."""
    text = re.sub(r"\([^()]*\)", "", text)
    while re.search(r"\([^()]*\)", text):
        text = re.sub(r"\([^()]*\)", "", text)
    return text.split("(")[0]


def test_names(lines: list, first: int, last: int) -> list:
    """The (line, name) pairs of the `Test:` / `Tests:` lines of the paragraph spanning `first`..`last`."""
    names, n = [], first
    while n <= last:
        m = TEST_LINE.search(lines[n - 1])
        n += 1
        if not m:
            continue
        text, at = m.group(1), n - 1
        while text.rstrip().endswith(",") and n <= last:
            text += " " + lines[n - 1]
            n += 1
        names += [(at, name) for name in NAME.findall(without_parentheses(text))]
    return names


def resolve(name: str, tests_root: Path) -> list:
    """The ids of the test files `name` stands for: `<tests_root>/**/<name>_test.gd`, outside the helper folders."""
    ids = []
    if "/" in name:
        files = [tests_root / (name + "_test.gd")]
    else:
        files = sorted(tests_root.rglob(name + "_test.gd"))
    for f in files:
        rel = f.relative_to(tests_root)
        if f.is_file() and not any(part.startswith("_") for part in rel.parts):
            ids.append(rel.as_posix()[: -len("_test.gd")])
    return ids


def map_diff(diff: str, read_doc, tests_root: Path):
    """(test ids, NOTE lines) for a unified `-U0` diff; `read_doc(path)` returns a doc's new text."""
    ids, notes = [], []
    for path, hunks in changed_lines(diff).items():
        lines = read_doc(path).splitlines()
        for first, last in changed_paragraphs(lines, hunks):
            named = test_names(lines, first, last)
            if not named:
                notes.append(f"NOTE {path}:{first}: changed paragraph names no test")
            for at, name in named:
                found = resolve(name, tests_root)
                if not found:
                    notes.append(f"NOTE unknown test name in {path}:{at}: {name}")
                ids += [i for i in found if i not in ids]
    return ids, notes


def git(*args: str) -> str:
    return subprocess.run(["git", *args], check=True, capture_output=True, text=True).stdout


def main(argv: list) -> int:
    staged = "--staged" in argv
    diff = git("-c", "core.quotePath=false", "diff", "-U0", "--no-color", "--cached" if staged else "HEAD", "--", "docs")
    if staged:
        def read_doc(path):
            return git("show", ":" + path)
    else:
        def read_doc(path):
            return Path(path).read_text()
        # An untracked doc is all new: its whole text is one hunk.
        for path in git("ls-files", "--others", "--exclude-standard", "docs").split("\n"):
            if path.endswith(".md"):
                diff += f"+++ b/{path}\n@@ -0,0 +1,{len(Path(path).read_text().splitlines())} @@\n"
    ids, notes = map_diff(diff, read_doc, Path("tests"))
    for line in [f"ID {i}" for i in ids] + notes:
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
