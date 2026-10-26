#!/usr/bin/env python3
"""The gdstyle pass of tools/lint.sh: `gdstyle fmt --check` and `gdstyle check` (through tools/gdstyle.sh, the pinned
gdstyle; gdstyle.toml at the root is its config: every rule an error but some quality/* ones, 18 on and five off by
decision), one section each in lint.sh's style, failing on any finding.

  python3 tools/lint_gdstyle.py [--quiet] [PATH...]

  PATH...   files or folders to check (res:// prefixes dropped); default: the whole tree, gdstyle.toml's excludes left out
  --quiet   print only a failing section

Like the engine pass, it leaves out every folder holding a .gdignore (Godot never loads those). Exit 0 when clean, 1 on a
finding, 2 when gdstyle itself could not run.
"""
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GDSTYLE = ROOT / "tools" / "gdstyle.sh"


def gdstyle(*args):
    return subprocess.run(["bash", str(GDSTYLE), *args], cwd=ROOT, capture_output=True, text=True)


def ignored_folders() -> list[str]:
    """Folders (repo-relative, with a trailing /) holding a .gdignore, hidden folders (.godot/) left out."""
    out = []
    for folder, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        if ".gdignore" in files:
            rel = Path(folder).relative_to(ROOT).as_posix()
            out.append("" if rel == "." else rel + "/")
            dirs[:] = []
    return out


def relative(path: str) -> str:
    return path[2:] if path.startswith("./") else path


def kept(path: str, ignored: list[str]) -> bool:
    return not any(path.startswith(folder) for folder in ignored)


def section(title: str, findings: list[str], quiet: bool) -> None:
    if quiet and not findings:
        return
    print(f"== {title} ==")
    for line in findings:
        print(f"  {line}")
    print("  FAIL" if findings else "  PASS")


def main(argv: list[str]) -> int:
    quiet = "--quiet" in argv
    paths = [a.removeprefix("res://") for a in argv if not a.startswith("--")] or ["."]
    ignored = ignored_folders()

    fmt = gdstyle("fmt", "--check", "--no-color", *paths)
    would = [relative(line.split(": ", 1)[1].strip()) for line in fmt.stdout.splitlines()
             if line.startswith("Would reformat: ")]
    if fmt.returncode not in (0, 1) or (fmt.returncode == 1 and not would):
        print(f"gdstyle fmt --check could not run (exit {fmt.returncode}):\n{fmt.stdout}{fmt.stderr}", file=sys.stderr)
        return 2
    unformatted = [f"{p}: would be reformatted (tools/gdstyle.sh fmt {p})" for p in would if kept(p, ignored)]

    check = gdstyle("check", "--format", "json", "--no-color", *paths)
    try:
        found = json.loads(check.stdout or "[]")
    except json.JSONDecodeError:
        print(f"gdstyle check could not run (exit {check.returncode}):\n{check.stdout}{check.stderr}", file=sys.stderr)
        return 2
    findings = []
    for f in sorted(found, key=lambda f: (relative(f["file"]), f["span"]["line"], f["span"]["column"])):
        path = relative(f["file"])
        if kept(path, ignored):
            findings.append(f"{path}:{f['span']['line']}:{f['span']['column']}: {f['message']} [{f['rule']}]")

    section("gdstyle fmt --check: scripts the formatter would change", unformatted, quiet)
    section("gdstyle check: style rules (gdstyle.toml)", findings, quiet)
    return 1 if unformatted or findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
