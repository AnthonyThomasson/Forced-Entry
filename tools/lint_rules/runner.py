#!/usr/bin/env python3
"""Run the project lint rules: one module per rule in tools/lint_rules/rules/, each a check over the tree.

  python3 tools/lint_rules/runner.py [--root=DIR] [--rules-dir=DIR] [--list-rules] [--rule=a,b] [--skip-rule=a,b]
                                     [--quiet] [PATH...]

  --list-rules     print each rule's name and description, and exit
  --rule=a,b       run only those rules; --skip-rule=a,b runs every rule but those (an unknown name is a usage error)
  PATH...          check only those repo-relative files or folders (res:// prefixes are dropped)
  --quiet          print nothing when every rule passes; print only the failing rules' sections otherwise
  --root, --rules-dir   the tree to check (default: this checkout) and where the rules live (default: rules/ here)

Each rule prints a section, `== <name>: <description> ==`, listing `<path>:<line>: <message>` per finding (a whole file
or folder as `<path>: <message>`), then PASS or FAIL. A finding under an ALLOW entry is listed with its reason and does
not fail. Exit 1 when any rule fails: a finding not allowed, an ALLOW entry without a reason, or a rule that raised.
tools/lint.sh runs this after the engine pass; tools/lint_rules/README.md says how to write a rule.
"""
import importlib.util
import sys
import traceback
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))  # rules import tools.lint_rules.walk, whatever directory this runs from

from tools.lint_rules.walk import Finding  # noqa: E402

RULES = HERE / "rules"


def load_rules(rules_dir) -> list:
    """Every rule module of `rules_dir` (each `*.py` but `_`-prefixed ones), sorted by name. A module without NAME,
    DESCRIPTION and check() raises ValueError, naming the file."""
    rules = []
    for path in sorted(Path(rules_dir).glob("*.py")):
        if path.name.startswith("_"):
            continue
        spec = importlib.util.spec_from_file_location(f"lint_rule_{path.stem}", path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        missing = [k for k in ("NAME", "DESCRIPTION", "check") if not hasattr(module, k)]
        if missing:
            raise ValueError(f"{path}: a rule needs {', '.join(missing)}")
        rules.append(module)
    return sorted(rules, key=lambda r: r.NAME)


def allow_errors(rule) -> list[str]:
    """What is wrong with the rule's ALLOW list: every entry needs a path and a reason that is not blank."""
    errors = []
    for entry in getattr(rule, "ALLOW", []):
        path = str(entry.get("path", "")).strip()
        if not path:
            errors.append(f"ALLOW entry without a path: {entry}")
        elif not str(entry.get("reason", "")).strip():
            errors.append(f"ALLOW entry for {path} gives no reason: say why the exception is justified")
    return errors


def allowed_reason(rule, finding: Finding) -> str | None:
    """The reason of the ALLOW entry covering the finding's path (that path or a folder above it), else None."""
    for entry in getattr(rule, "ALLOW", []):
        path = str(entry.get("path", "")).strip().strip("/")
        reason = str(entry.get("reason", "")).strip()
        if path and reason and (finding.path == path or finding.path.startswith(path + "/")):
            return reason
    return None


def where(finding: Finding) -> str:
    return f"{finding.path}:{finding.line}" if finding.line > 0 else finding.path


def run_rule(rule, root: Path, paths) -> tuple[bool, list[str]]:
    """Run one rule: (passed, the lines of its section body)."""
    lines = [f"  {e}" for e in allow_errors(rule)]
    failed = bool(lines)
    try:
        findings = [Finding(*f) for f in rule.check(root, paths)]
    except Exception as err:  # a broken rule fails the lint, never passes it
        detail = traceback.format_exception_only(type(err), err)[-1].strip()
        return False, lines + [f"  the rule raised: {detail}"]
    for f in sorted(findings, key=lambda f: (f.path, f.line)):
        reason = allowed_reason(rule, f)
        if reason is None:
            failed = True
            lines.append(f"  {where(f)}: {f.message}")
        else:
            lines.append(f"  {where(f)}: {f.message}  (allowed: {reason})")
    lines.append("  FAIL" if failed else "  PASS")
    return not failed, lines


def names(value: str) -> list[str]:
    return [n.strip() for n in value.split(",") if n.strip()]


def main(argv: list[str]) -> int:
    root, rules_dir, only, skip, quiet, listing, paths = ROOT, RULES, None, [], False, False, []
    for arg in argv:
        if arg.startswith("--root="):
            root = Path(arg.split("=", 1)[1])
        elif arg.startswith("--rules-dir="):
            rules_dir = Path(arg.split("=", 1)[1])
        elif arg.startswith("--rule="):
            only = names(arg.split("=", 1)[1])
        elif arg.startswith("--skip-rule="):
            skip += names(arg.split("=", 1)[1])
        elif arg == "--quiet":
            quiet = True
        elif arg == "--list-rules":
            listing = True
        elif arg.startswith("--"):
            print(f"unknown flag {arg}\n\n{__doc__}", file=sys.stderr)
            return 2
        else:
            paths.append(arg.removeprefix("res://"))
    rules = load_rules(rules_dir)
    known = {r.NAME for r in rules}
    unknown = [n for n in (only or []) + skip if n not in known]
    if unknown:
        print(f"unknown rule {', '.join(unknown)} (rules: {', '.join(sorted(known)) or 'none'})", file=sys.stderr)
        return 2
    if listing:
        for rule in rules:
            print(f"{rule.NAME}  {rule.DESCRIPTION}")
        return 0
    chosen = [r for r in rules if (only is None or r.NAME in only) and r.NAME not in skip]
    status = 0
    for rule in chosen:
        passed, body = run_rule(rule, root, paths or None)
        if not passed:
            status = 1
        if not (quiet and passed):
            print(f"== {rule.NAME}: {rule.DESCRIPTION} ==")
            print("\n".join(body))
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
