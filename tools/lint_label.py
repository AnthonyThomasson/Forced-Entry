#!/usr/bin/env python3
"""Label the lint's findings in scripts a commit does not hold.

  tools/lint.sh PATH... | python3 tools/lint_label.py STAGED_PATH...

Copies the lint's output (stdin) to stdout, and appends `  [not in this commit: <path>]` to each line that starts with
a script none of the STAGED_PATHs is (a .gd path, with or without res://, after the line's indent): the script a finding is
in, as an engine pass header (`res://x.gd  (2)`) or a rule's or gdstyle's `x.gd:3: …` gives it. That is a finding the
engine pass reached through a staged script (one it loads or preloads), which the commit did not make. A script a
message only names (`Could not preload … 'res://y.gd'`) is not where the finding is, so it is left unlabelled.
tools/lint_staged.sh (the lint of what a commit holds: the pre-commit hook's and tools/run_tests.sh --changed
--staged's) pipes a failed lint through it, given the commit's staged paths.
"""
import re
import sys

SCRIPT = re.compile(r"\s*(?:res://)?([^\s:()\[\]'\"]+\.gd)(?![\w.])")


def label(line: str, held: set[str]) -> str:
    m = SCRIPT.match(line)
    return line if m is None or m.group(1) in held else f"{line}  [not in this commit: {m.group(1)}]"


def main(argv: list[str]) -> int:
    held = {a.removeprefix("res://") for a in argv}
    for line in sys.stdin:
        print(label(line.rstrip("\n"), held))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
