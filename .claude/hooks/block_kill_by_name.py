#!/usr/bin/env python3
"""Claude Code PreToolUse hook (Bash and PowerShell): refuse a command that kills processes BY NAME. Every worktree
runs its own Von decision server, and a name matches every worktree's (and another agent's) process, so
`pkill -f "von serve"` takes the others' servers down with it. Reads the hook's JSON on stdin; exit 2 with the reason on stderr refuses the
command, exit 0 lets it through. Wired in .claude/settings.json through block_kill_by_name.sh.

Refused (as the command of any statement of the line, also inside `bash -c "..."`, `eval`, `powershell -Command "..."`,
`cmd /c ...`, behind `sudo`, `env`, `xargs` ...):
  pkill (with or without -f), killall,
  taskkill with /IM (or -IM) or an /FI filter on IMAGENAME,
  Stop-Process with -Name / -ProcessName (any abbreviation PowerShell takes), or fed by `Get-Process <name>`.
Allowed: `kill <pid>`, `taskkill /PID <pid>`, `Stop-Process -Id <pid>`, and the word `pkill` anywhere that is not a
command (a `grep pkill`, a commit message).
The refusal names the way out: `kill <pid>`, or `tools/von_stop.sh <game pid>` for a Von server.
"""
import json
import re
import shlex
import sys
from typing import List, Optional

MESSAGE = (
    "Refused: {what} kills processes by name, and a name matches every worktree's (and every agent's) processes, "
    "including other games' Von servers. Stop one process by its pid instead: `kill <pid>` (Windows: `taskkill /PID "
    "<pid>` or `Stop-Process -Id <pid>`), and a game's Von server with `tools/von_stop.sh <game pid>`."
)
# Words that run the next word as a command.
WRAPPERS = {"sudo", "env", "nohup", "exec", "time", "command", "builtin", "xargs", "nice", "stdbuf", "timeout", "doas",
            "then", "do", "else", "if", "while", "until", "!", "call", "start"}
SHELLS = {"bash", "sh", "zsh", "dash", "ksh"}
POWERSHELLS = {"powershell", "pwsh"}
# What ends one command and starts the next: every operator but a single `|`, which only pipes (a pipeline is read
# whole).
STATEMENT_END = r"&&|\|\||[;&\n(){}`]"
PIPE = r"\|"
STOP_NAME = re.compile(r"^-(n|na|nam|name|pr|pro|proc|proce|proces|process|processn|processna|processnam|processname)"
                       r"(:.*)?$", re.I)
GET_PROCESS = {"get-process", "gps"}
STOP_PROCESS = {"stop-process", "spps"}
HEREDOC = re.compile(r"(?<!<)<<(?!<)-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")
WINDOWS_PATH_BACKSLASH = re.compile(r"\\(?=[A-Za-z0-9_.])")


def base(word: str) -> str:
    """A command word reduced to its program name: no folder, no .exe/.sh/.cmd/.bat/.ps1, lower case."""
    name = re.split(r"[\\/]", word.strip("\"'"))[-1].lower()
    return re.sub(r"\.(exe|sh|cmd|bat|ps1)$", "", name)


def words(segment: str) -> List[str]:
    # A backslash before a letter is a Windows path's (`C:\Windows\taskkill.exe`), not an escape: shlex would eat it.
    segment = WINDOWS_PATH_BACKSLASH.sub("/", segment)
    try:
        return shlex.split(segment, posix=True)
    except ValueError:
        return segment.split()


def split(command: str, pattern: str) -> List[str]:
    """`command` cut at each match of `pattern` outside quotes (a quoted string stays whole, an escaped quote in a
    double-quoted one does not end it)."""
    ender = re.compile(pattern)
    out, current, quote, i = [], "", "", 0
    while i < len(command):
        ch = command[i]
        if quote:
            current += ch
            if ch == "\\" and quote == '"' and i + 1 < len(command):
                i += 1
                current += command[i]
            elif ch == quote:
                quote = ""
        elif ch in "\"'":
            quote = ch
            current += ch
        elif ender.match(command, i):
            out.append(current)
            current = ""
            i += len(ender.match(command, i)[0]) - 1
        else:
            current += ch
        i += 1
    out.append(current)
    return [c for c in out if c.strip()]


def without_heredocs(command: str) -> str:
    """`command` minus the bodies of its here-documents (`python - <<'EOF' ... EOF`): text handed to a program, not
    commands, unless the program is a shell, which runs it."""
    lines, out, i = command.split("\n"), [], 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        i += 1
        found = HEREDOC.search(line)
        if found:
            start = i
            while i < len(lines) and lines[i].strip() != found[2]:
                i += 1
            if any(base(w) in SHELLS | POWERSHELLS | {"cmd"} for w in words(line[:found.start()])):
                out.extend(lines[start:i])
            i += 1  # the delimiter line
    return "\n".join(out)


def refusal(command: str, depth: int = 0) -> Optional[str]:
    """What `command` is refused for (a short phrase), None when it is allowed."""
    if depth > 4:
        return None
    for statement in split(without_heredocs(command), STATEMENT_END):
        pipeline = [words(part) for part in split(statement, PIPE)]
        for args in pipeline:
            found = command_refusal(args, depth)
            if found:
                return found
        names = [i for i, args in enumerate(pipeline) if args and base(args[0]) in GET_PROCESS and by_name(args)]
        stops = [i for i, args in enumerate(pipeline) if args and base(args[0]) in STOP_PROCESS]
        if names and stops and names[0] < stops[-1]:
            return "`Get-Process <name> | Stop-Process`"
    return None


def by_name(args: List[str]) -> bool:
    """Whether a `Get-Process` call picks processes by name: a positional name or -Name, not -Id / -InputObject."""
    rest = args[1:]
    if any(re.match(r"^-(i|id|inputobject)(:.*)?$", a, re.I) for a in rest):
        return False
    return bool(rest)


ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
OPERAND = re.compile(r"^\d+[smhd]?$")


def kill_by_name(rest: List[str]) -> bool:
    """PowerShell's `kill` is Stop-Process: -Name / -ProcessName (and abbreviations), not a POSIX `kill -n 9 <pid>`."""
    for i, arg in enumerate(rest):
        if STOP_NAME.match(arg) and not (arg.lower() == "-n" and i + 1 < len(rest) and OPERAND.match(rest[i + 1])):
            return True
    return False


def commands(args: List[str]) -> List[List[str]]:
    """The command lines `args` may run: itself, and, behind wrapper words, what follows their flags and operands
    (`timeout 5 pkill x`, `sudo -u root pkill x`, `nice -n 10 pkill x`, `sudo -n pkill x`). A flag's value may be
    the program or not, so each start is a candidate. `command -v pkill` only looks a command up."""
    if len(args) > 1 and base(args[0]) == "command" and args[1] in ("-v", "-V"):
        return []
    found, i, wrapped, after_flag = [], 0, False, False
    while i < len(args):
        found.append(args[i:])
        word = args[i]
        if ASSIGNMENT.match(word) or base(word) in WRAPPERS:
            wrapped = wrapped or base(word) in WRAPPERS
            after_flag = False
        elif wrapped and (word.startswith("-") or OPERAND.match(word) or after_flag):
            after_flag = word.startswith("-")
        else:
            break
        i += 1
    return found


def command_refusal(args: List[str], depth: int) -> Optional[str]:
    for candidate in commands(args):
        found = program_refusal(candidate, depth)
        if found:
            return found
    return None


def program_refusal(args: List[str], depth: int) -> Optional[str]:
    if not args:
        return None
    program, rest = base(args[0]), args[1:]
    if program in ("pkill", "killall"):
        return f"`{program}`"
    if program == "taskkill":
        for i, arg in enumerate(rest):
            if re.match(r"^[/-]{1,2}im$", arg, re.I):
                return "`taskkill /IM`"
            if re.match(r"^[/-]{1,2}fi$", arg, re.I) and i + 1 < len(rest) and "imagename" in rest[i + 1].lower():
                return "`taskkill /FI` on IMAGENAME"
    if program in STOP_PROCESS and any(STOP_NAME.match(a) for a in rest):
        return "`Stop-Process -Name`"
    if program == "kill" and kill_by_name(rest):
        return "`kill -Name`"
    # A command line handed to another shell: look inside it.
    inner = None
    if program in SHELLS:
        inner = next((rest[i + 1] for i, a in enumerate(rest[:-1]) if re.match(r"^-[a-z]*c$", a)), None)
    elif program == "eval":
        inner = " ".join(rest)
    elif program in POWERSHELLS:
        i = next((i for i, a in enumerate(rest) if re.match(r"^-c(o(m(m(a(n(d)?)?)?)?)?)?$", a, re.I)), None)
        inner = " ".join(rest[i + 1:]) if i is not None else None
    elif program == "cmd":
        i = next((i for i, a in enumerate(rest) if a.lower() in ("/c", "/k")), None)
        inner = " ".join(rest[i + 1:]) if i is not None else None
    return refusal(inner, depth + 1) if inner else None


def main() -> int:
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return 0
    command = (event.get("tool_input") or {}).get("command") if isinstance(event, dict) else None
    if not isinstance(command, str):
        return 0
    what = refusal(command)
    if what:
        print(MESSAGE.format(what=what), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
