#!/usr/bin/env python3
"""Label the lint's findings in scripts a commit does not hold.

  tools/lint.sh --quiet PATH... | python3 tools/lint_label.py PATH...

Copies the lint's output (stdin) to stdout, and appends `  [not in this commit: <path>]` to each line that names a
script (a .gd path, with or without res://) none of the PATHs is: a finding the engine pass reached through a staged
script (one it loads or preloads), which the commit did not make. The pre-commit hook pipes its lint through it, and
tools/run_tests.sh --changed --staged its own, each given the commit's staged paths.
"""
import re
import sys

SCRIPT = re.compile(r"(?:res://)?([^\s:()\[\]'\"]+\.gd)(?![\w.])")


def label(line: str, held: set[str]) -> str:
    outside = []
    for m in SCRIPT.finditer(line):
        path = m.group(1)
        if path not in held and path not in outside:
            outside.append(path)
    return line + "".join(f"  [not in this commit: {path}]" for path in outside)


def main(argv: list[str]) -> int:
    held = {a.removeprefix("res://") for a in argv}
    for line in sys.stdin:
        print(label(line.rstrip("\n"), held))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
