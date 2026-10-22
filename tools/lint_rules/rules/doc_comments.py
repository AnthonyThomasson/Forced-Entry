"""Every function and member of a script under scenes/ has a `##` doc comment (the comment rules, `audit` step 4).

- A function (`func` / `static func`, at any indent: an inner class's too, an annotation before it on its line or
  not) has a `##` line directly above it; only annotation lines (`@warning_ignore(...)`, `@rpc`, one whose arguments
  run over several lines too) may stand between. The lifecycle overrides in LIFECYCLE are exempt.
- A top-level member (`var`, `static var`, `@export… var`, `@onready var`, `signal`) has a trailing `## …`, or a `##`
  line above the run of declarations it belongs to: one doc comment covers consecutive declarations, a multi-line value
  and an annotation-only line (`@export_group(...)`) included. A blank line, a plain `#` comment or any other statement
  ends the run.
Declarations are matched on the code with what is inside its strings blanked, so a `)` or `#` in a string is no stop.
`const`, a function's locals, a folder Godot ignores (`.gdignore`) and everything outside scenes/ are not checked.
"""
import re

from tools.lint_rules.walk import Finding, gdscript_lines, godot_scripts

NAME = "doc_comments"
DESCRIPTION = "every function and member var / export / signal under scenes/ has a `##` doc comment"

LIFECYCLE = {"_ready", "_process", "_physics_process", "_draw", "_init", "_input", "_unhandled_input", "_enter_tree",
             "_exit_tree", "_notification", "_integrate_forces"}
FUNC = re.compile(r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:static\s+)?func\s+(\w+)")
MEMBER = re.compile(r"^(?:@\w+(?:\([^)]*\))?\s+)*(?:static\s+)?(var|signal)\s+(\w+)")
# An annotation alone on its line, its arguments closed there or opened to run on over the lines below.
ANNOTATION = re.compile(r"^\s*@\w+(?:\([^)]*\)?)?\s*$")


def _is_doc(line) -> bool:
    return line.code.strip() == "" and line.comment.startswith("##")


def _function_documented(lines, i) -> bool:
    """Whether the `##` line directly above statement `i` documents it, over annotation lines only."""
    j = i - 1
    while j >= 0:
        start = j
        while start > 0 and not lines[start].starts:
            start -= 1  # a line inside a multi-line annotation's arguments
        if not ANNOTATION.match(lines[start].bare):
            break
        j = start - 1
    return j >= 0 and _is_doc(lines[j])


def _member_documented(lines, i) -> bool:
    """Whether member `i` has a trailing `##`, or a `##` line above the run of declarations it belongs to."""
    if lines[i].comment.startswith("##"):
        return True
    j = i - 1
    while j >= 0:
        while j > 0 and not lines[j].starts:
            j -= 1  # a line inside an earlier declaration's multi-line value
        line = lines[j]
        if _is_doc(line):
            return True
        if not (MEMBER.match(line.bare) or ANNOTATION.match(line.bare)) or not line.code.strip():
            return False
        j -= 1
    return False


def check(root, paths):
    found = []
    for path in godot_scripts(root, ["scenes"], paths):
        lines = gdscript_lines(root, path)
        for i, line in enumerate(lines):
            if not line.starts:
                continue
            func = FUNC.match(line.bare)
            if func:
                if func.group(1) not in LIFECYCLE and not _function_documented(lines, i):
                    found.append(Finding(path, line.number, f"func {func.group(1)} has no `##` doc comment above it"))
                continue
            member = MEMBER.match(line.bare)
            if member and not _member_documented(lines, i):
                found.append(Finding(path, line.number, f"{member.group(1)} {member.group(2)} has no `##` doc comment "
                                     "(above its run of declarations, or trailing)"))
    return found
