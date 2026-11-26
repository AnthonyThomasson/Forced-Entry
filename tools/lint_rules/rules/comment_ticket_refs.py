"""Game comments say what the code is, never which ticket asked for it: a comment under scenes/ or sandboxes/ holds no
`#NN` (two to five digits) and no `ticket #N` or `issue #N` (any case, plural too). The ticket and its history live in git
and on GitHub; tests may name the ticket whose spec they check, so only the scripts Godot loads under those two folders
are scanned. Only comments count: the words inside a string are left alone. A one-digit `#N` is a numbered slot, and
`name#N` is another repository's issue (an engine bug a workaround waits for): neither is this project's ticket.
"""
import re

from tools.lint_rules.walk import Finding, gdscript_lines, godot_scripts

NAME = "comment_ticket_refs"
DESCRIPTION = "no `#NNN` ticket reference in a comment under scenes/ or sandboxes/: say what the code is, not who asked"

REFERENCE = re.compile(r"\b(?:ticket|issue)s?\s*#\d+|(?<!\w)#\d{2,5}(?!\w)", re.IGNORECASE)


def check(root, paths):
    found = []
    for path in godot_scripts(root, ["scenes", "sandboxes"], paths):
        for line in gdscript_lines(root, path):
            ref = REFERENCE.search(line.comment)
            if ref:
                found.append(Finding(path, line.number, f"a ticket reference in a comment ({ref.group(0)}): "
                                     "say what the code is, not which ticket asked for it"))
    return found
