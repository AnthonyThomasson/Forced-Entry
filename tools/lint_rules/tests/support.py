"""Shared helpers for the lint-rule tests: temp trees, the runner's CLI, and a temp tree with its own lint.sh.

Not a test module (unittest discovery only loads test*.py).
"""
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
LINT_RULES = ROOT / "tools" / "lint_rules"
RUNNER = LINT_RULES / "runner.py"
RULES = LINT_RULES / "rules"
README = LINT_RULES / "README.md"
FIXTURES = Path(__file__).resolve().parent / "fixtures"
LOGS = FIXTURES / "logs"


def write(root: Path, rel: str, text: str = "") -> Path:
    """Write `text` to `root/rel`, making its folders."""
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    return path


def clean_env(**extra: str) -> dict:
    """This process's environment without git's GIT_* variables, plus `extra`: what every process a test starts in a
    temp tree gets. A test run from inside git (the pre-commit hook, `git rebase --exec`) inherits GIT_INDEX_FILE,
    GIT_DIR and the rest, and a git started with them acts on the repo they name, not on the temp tree."""
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    env.update(extra)
    return env


# The temp trees live in the system temp directory, outside this checkout, on purpose: a folder inside the checkout
# sits under its .git, so a git run there would silently act on this repo.
class TempTree:
    """A fresh directory for one test, removed afterwards: `with TempTree() as root:`."""

    def __enter__(self) -> Path:
        self._dir = tempfile.mkdtemp(prefix="lint_rules_test.")
        return Path(self._dir)

    def __exit__(self, *_exc):
        shutil.rmtree(self._dir, ignore_errors=True)


def run_runner(root: Path, *args: str, rules_dir: Path | None = None, runner: Path = RUNNER):
    """Run the rule runner's CLI on `root` (with `rules_dir` instead of the real rules when given)."""
    cmd = [sys.executable, str(runner), f"--root={root}"]
    if rules_dir is not None:
        cmd.append(f"--rules-dir={rules_dir}")
    return subprocess.run(cmd + list(args), cwd=root, env=clean_env(), capture_output=True, text=True, timeout=120)


def sections(output: str) -> dict[str, str]:
    """The runner's output split into its per-rule sections: {header line: the lines under it}. A section starts at
    a line beginning with `== ` (after optional whitespace)."""
    found: dict[str, list[str]] = {}
    current = None
    for line in output.splitlines():
        if line.strip().startswith("== "):
            current = line.strip()
            found[current] = []
        elif current is not None:
            found[current].append(line)
    return {k: "\n".join(v) for k, v in found.items()}


def section_of(output: str, name: str) -> str | None:
    """The body of the section whose header names rule `name` (a whole word), or None."""
    for header, body in sections(output).items():
        if re.search(rf"(?<![\w-]){re.escape(name)}(?![\w-])", header):
            return body
    return None


FAKE_GODOT = """#!/usr/bin/env bash
# Fake Godot for the lint.sh tests: records its arguments (one call per line) and prints the canned log.
echo "$*" >> "$FAKE_GODOT_CALLS"
[[ -n "${FAKE_GODOT_OUTPUT:-}" ]] && cat "$FAKE_GODOT_OUTPUT"
exit 0
"""


class LintTree:
    """A temp copy of the lint machinery (tools/lint.sh, lint_report.py, the lint_rules package, the gdstyle pass and
    gdstyle.toml) with `rules_from`'s rules as its registered rules, two scenes (scenes/clean.gd, and scenes/bad.gd
    holding the word BAD), a class cache so lint.sh does not import, and a fake Godot that prints a canned engine log."""

    def __init__(self, rules_from: Path):
        self.rules_from = rules_from

    def __enter__(self):
        self.dir = Path(tempfile.mkdtemp(prefix="lint_sh_test."))
        self.root = self.dir / "tree"
        tools = self.root / "tools"
        tools.mkdir(parents=True)
        for name in ("lint.sh", "lint_report.py", "lint_gdstyle.py", "gdstyle.sh"):
            shutil.copy2(ROOT / "tools" / name, tools / name)
        shutil.copy2(ROOT / "gdstyle.toml", self.root / "gdstyle.toml")
        (tools / "__init__.py").write_text("")
        shutil.copytree(LINT_RULES, tools / "lint_rules",
                        ignore=shutil.ignore_patterns("tests", "rules", "__pycache__"))
        shutil.copytree(self.rules_from, tools / "lint_rules" / "rules", ignore=shutil.ignore_patterns("__pycache__"))
        write(self.root, "scenes/clean.gd", "extends Node\n")
        write(self.root, "scenes/bad.gd", "extends Node\n# BAD on purpose\n")
        write(self.root, ".godot/global_script_class_cache.cfg", "list=Array[Dictionary]([])\n")
        self.godot = self.dir / "godot"
        self.godot.write_text(FAKE_GODOT)
        self.godot.chmod(self.godot.stat().st_mode | stat.S_IEXEC)
        self.calls = self.dir / "godot_calls.txt"
        return self

    def __exit__(self, *_exc):
        shutil.rmtree(self.dir, ignore_errors=True)

    def lint(self, *args: str, log: str = "clean.log"):
        """Run the tree's own tools/lint.sh with the fake Godot printing fixtures/logs/`log`."""
        env = clean_env(GODOT=str(self.godot), FAKE_GODOT_CALLS=str(self.calls), FAKE_GODOT_OUTPUT=str(LOGS / log))
        return subprocess.run([str(self.root / "tools" / "lint.sh"), *args], cwd=self.root, env=env,
                              capture_output=True, text=True, timeout=120)

    def engine_calls(self) -> list[str]:
        """The argument lines of every call lint.sh made to the (fake) engine."""
        return self.calls.read_text().splitlines() if self.calls.exists() else []


def godot_binary() -> str | None:
    """The Godot binary, looked up in tools/lint.sh's order (GODOT, then godot / godot4 on PATH, then
    /Applications/Godot*.app); None when there is none."""
    if os.environ.get("GODOT"):
        return os.environ["GODOT"]
    for name in ("godot", "godot4"):
        found = shutil.which(name)
        if found:
            return found
    apps = sorted(Path("/Applications").glob("Godot*.app/Contents/MacOS/Godot"))
    return str(apps[0]) if apps else None


ENGINE_PROJECT = """config_version=5

[application]

config/name="lint engine tree"
"""


class EngineLintTree:
    """A temp Godot project with the lint machinery (tools/lint.sh, lint_report.py, lint_scripts.gd / .tscn, the
    lint_rules package with its real rules, the gdstyle pass and gdstyle.toml) and one clean script, scenes/clean.gd,
    linted by the real engine (godot_binary())."""

    def __enter__(self):
        self.dir = Path(tempfile.mkdtemp(prefix="lint_engine_test."))
        self.root = self.dir / "tree"
        tools = self.root / "tools"
        tools.mkdir(parents=True)
        for name in ("lint.sh", "lint_report.py", "lint_gdstyle.py", "gdstyle.sh", "lint_scripts.gd",
                     "lint_scripts.tscn"):
            shutil.copy2(ROOT / "tools" / name, tools / name)
        shutil.copy2(ROOT / "gdstyle.toml", self.root / "gdstyle.toml")
        (tools / "__init__.py").write_text("")
        shutil.copytree(LINT_RULES, tools / "lint_rules", ignore=shutil.ignore_patterns("tests", "__pycache__"))
        write(self.root, "project.godot", ENGINE_PROJECT)
        write(self.root, "scenes/clean.gd", "extends Node\n")
        return self

    def __exit__(self, *_exc):
        shutil.rmtree(self.dir, ignore_errors=True)

    def lint(self, *args: str):
        """Run the tree's own tools/lint.sh with the real engine."""
        return subprocess.run([str(self.root / "tools" / "lint.sh"), *args], cwd=self.root,
                              env=clean_env(GODOT=godot_binary()), capture_output=True, text=True, timeout=300)
