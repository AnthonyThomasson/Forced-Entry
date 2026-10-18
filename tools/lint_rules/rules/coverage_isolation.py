"""Nothing in the game touches the coverage tool (tools/coverage/, issue #68): the tool knows the project, the project
never knows the tool, so deleting tools/coverage/ and tools/coverage.py breaks nothing.

Scanned: scenes/, tests/, addons/ and project.godot. A breach is the text `tools/coverage`, `CoverageProbe` or
`FE_COVERAGE` on any line (a comment counts), or a file or folder named `coverage_probe*` or `coverage_hits*`, or a path
`tools/coverage*`. The plain word "coverage" is a game term (cover height, docs/cover-and-stance.md) and is not flagged.
The instrumented copy the tool builds names CoverageProbe in its project.godot on purpose; the tool lints that copy
with `--skip-rule=coverage_isolation`.
"""
import re

from tools.lint_rules.walk import Finding, files, lines_matching, names_matching

NAME = "coverage_isolation"
DESCRIPTION = "nothing in scenes/, tests/, addons/ or project.godot names the coverage tool (tools/coverage/)"

PLACES = ["scenes", "tests", "addons", "project.godot"]
TEXTS = ("tools/coverage", "CoverageProbe", "FE_COVERAGE")
NAMES = ("coverage_probe*", "coverage_hits*")
TOOL_PATH = re.compile(r"(?:^|/)tools/coverage[^/]*")


def check(root, paths):
    found = []
    reserved_paths = set()
    pattern = "|".join(re.escape(t) for t in TEXTS)
    for path in files(root, PLACES, paths):
        for line, text in lines_matching(root, path, pattern):
            named = ", ".join(t for t in TEXTS if t in text)
            found.append(Finding(path, line, f"names the coverage tool ({named}); the game must not know it"))
        reserved_paths.update(names_matching(path, NAMES))
        tool = TOOL_PATH.search(path)
        if tool:
            reserved_paths.add(path[:tool.end()])
    for path in sorted(reserved_paths):
        found.append(Finding(path, 0, "a reserved coverage-tool name (coverage_probe*, coverage_hits*, tools/coverage*)"))
    return found
