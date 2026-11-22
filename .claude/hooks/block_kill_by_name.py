#!/usr/bin/env python3
"""Claude Code PreToolUse hook (Bash and PowerShell): refuse a command that kills processes BY NAME. Every worktree
runs its own Von decision server, and a name matches every worktree's (and another agent's) process, so
`pkill -f "von serve"` takes the others' servers down with it. Reads the hook's JSON on stdin; exit 2 with the
reason on stderr refuses the command, exit 0 lets it through. Wired in .claude/settings.json through
block_kill_by_name.sh.

Refused (as the command of any statement of the line, also inside `bash -c "..."`, `eval`, `powershell -Command "..."`,
`cmd /c ...`, `powershell "..."` (the command as the first argument), behind `sudo`, `env`, `xargs` ...):
  pkill (with or without -f), killall,
  taskkill with /IM (or -IM) or an /FI filter on IMAGENAME,
  Stop-Process with -Name / -ProcessName (any abbreviation PowerShell takes), or fed by `Get-Process <name>` (piped,
  or from a `% { Stop-Process -Id $_.Id }` block),
  a kill fed by a lookup by name: `kill $(pgrep x)`, kill `pgrep x`, `pgrep x | xargs kill`.
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
STOP_PROCESS = {"stop-process", "spps"}
# Statements, but a `{ }` block or `( )` group stays in its statement (`Get-Process x | % { Stop-Process -Id $_.Id }`).
WHOLE_STATEMENT_END = r"&&|\|\||[;&\n`]"
GET_BY_NAME = re.compile(r"\b(?:get-process|gps)\s+(?:-n\w*[:\s]+)?[A-Za-z*]", re.I)
STOPS_PROCESSES = re.compile(r"\b(?:stop-process|spps)\b|\.kill\(|\{[^}]*\bkill\b", re.I)
QUOTED = re.compile(r"\"(?:\\.|[^\"\\])*\"|'[^']*'")
SINGLE_QUOTED = re.compile(r"'[^']*'")
# A kill fed by a lookup by name (the shell expands what a double quote holds, not a single quote).
PGREP_KILL = re.compile(
    r"\bkill\b[^;&|\n]*(?:\$\(|`)\s*(?:pgrep|pidof)\b"  # kill $(pgrep x), kill `pgrep x`
    r"|\b(?:pgrep|pidof)\b[^;&\n]*\|\s*xargs\b[^;&|\n]*\bkill\b")  # pgrep x | xargs kill
SIGNAL = re.compile(r"^(?:\d+|(?:SIG)?(?:HUP|INT|QUIT|ILL|TRAP|ABRT|BUS|FPE|KILL|USR1|SEGV|USR2|PIPE|ALRM|TERM|CHLD"
                    r"|CONT"
                    r"|STOP|TSTP|TTIN|TTOU|URG|XCPU|XFSZ|VTALRM|PROF|WINCH|IO|PWR|SYS))$", re.I)
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
    return lookup_refusal(command)


def lookup_refusal(command: str) -> Optional[str]:
    """The kills fed by a lookup by name: `Get-Process <name>` into a Stop-Process, `pgrep` into a kill."""
    body = without_heredocs(command)
    for statement in split(body, WHOLE_STATEMENT_END):
        text = QUOTED.sub('""', statement)
        if GET_BY_NAME.search(text) and STOPS_PROCESSES.search(text):
            return "`Get-Process <name>` into a Stop-Process"
    if PGREP_KILL.search(SINGLE_QUOTED.sub("''", body)):
        return "`kill` fed by `pgrep` / `pidof`"
    return None


ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
OPERAND = re.compile(r"^\d+[smhd]?$")


def kill_by_name(rest: List[str]) -> bool:
    """PowerShell's `kill` is Stop-Process: -Name / -ProcessName (and abbreviations), not a POSIX `kill -n 9 <pid>`."""
    for i, arg in enumerate(rest):
        if STOP_NAME.match(arg) and not (arg.lower() == "-n" and i + 1 < len(rest) and SIGNAL.match(rest[i + 1])):
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
        inner = powershell_command(rest)
    elif program == "cmd":
        i = next((i for i, a in enumerate(rest) if a.lower() in ("/c", "/k")), None)
        inner = " ".join(rest[i + 1:]) if i is not None else None
    return refusal(inner, depth + 1) if inner else None


def powershell_command(rest: List[str]) -> Optional[str]:
    """The command line a `powershell` / `pwsh` call runs: what follows -Command, else the first argument that is no
    switch (`powershell -NoProfile "Stop-Process -Name x"`); None for -File and -EncodedCommand."""
    i = 0
    while i < len(rest):
        arg = rest[i]
        if re.match(r"^-c(o(m(m(a(n(d)?)?)?)?)?)?$", arg, re.I):
            return " ".join(rest[i + 1:])
        if re.match(r"^-(f|fi|fil|file|e|ec|en|enc|encodedcommand)$", arg, re.I):
            return None
        if arg.startswith("-"):
            i += 2 if re.match(r"^-(ep|executionpolicy|w|windowstyle|if|inputformat|of|outputformat|version|v"
                               r"|workingdirectory|wd|configurationname|config)$", arg, re.I) else 1
        else:
            return " ".join(rest[i:])
    return None


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
