"""Game comments say what the code is, never which ticket asked for it: a comment under scenes/ holds no `ticket #N` or
`issue #N` (any case, plural too). The ticket and its history live in git and on GitHub; tests may name the ticket whose
spec they check, so only the scripts Godot loads under scenes/ are scanned. Only comments count: the words inside a
string are left alone.
"""
import re

from tools.lint_rules.walk import Finding, gdscript_lines, godot_scripts

NAME = "comment_ticket_refs"
DESCRIPTION = "no `ticket #N` / `issue #N` in a comment under scenes/: say what the code is, not which ticket asked"

REFERENCE = re.compile(r"\b(?:ticket|issue)s?\s*#\d+", re.IGNORECASE)


def check(root, paths):
    found = []
    for path in godot_scripts(root, ["scenes"], paths):
        for line in gdscript_lines(root, path):
            ref = REFERENCE.search(line.comment)
            if ref:
                found.append(Finding(path, line.number, f"a ticket reference in a comment ({ref.group(0)}): "
                                     "say what the code is, not which ticket asked for it"))
    return found
