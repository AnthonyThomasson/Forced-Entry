"""Reading Markdown the skill checks share (`test_skills.py`, `test_skill_pointers.py`)."""
import re

# A code fence's opening or closing run: three or more backticks or tildes, indented at most three spaces.
FENCE = re.compile(r" {0,3}(`{3,}|~{3,})")


def outside_fences(text: str):
    """(line number, line) for every line of `text` outside a code fence, the fence lines themselves left out. A fence
    closes on a run of its own char at least as long with nothing after it; a backtick run with a backtick after it
    opens none (it is inline code)."""
    fence = ""
    for n, line in enumerate(text.splitlines(), 1):
        opener = FENCE.match(line)
        rest = line.strip()[len(opener[1]):] if opener else ""
        if fence:
            if opener and opener[1].startswith(fence) and not rest:
                fence = ""
        elif opener and not (opener[1][0] == "`" and "`" in rest):
            fence = opener[1]
        else:
            yield n, line


def names_alternation(names) -> str:
    """A regex alternation of `names`, longest first, so a name never loses to its own prefix."""
    return "|".join(re.escape(n) for n in sorted(names, key=len, reverse=True))
