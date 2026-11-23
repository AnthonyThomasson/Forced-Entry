"""A native suite script (tests/**/*_suite.gd) declares no `static var`.

Godot 4.4.1 on Windows ends with an access violation (0xC0000005, exit 139 under Git Bash) when a run given `--out` has
loaded such a script and not run it: TestBatch.begin counts the native suites by `load()`ing every `*_suite.gd`, and the
three suites that kept a `static var _next_base` took the engine down at exit, after the report was written and gdUnit
had printed `Exit code: 0` and `Finallize .. done`. Without the static var (an instance var, the same test frames) the
engine exits 0, on a Mac as well. Bisected in a copy of the checkout: the engine's exit code followed this one line.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
# `static var` at the start of a line, indented (an inner class) or after annotations (`@warning_ignore("...")`).
STATIC_VAR = re.compile(r"^[ \t]*(?:@\w+(?:\([^)]*\))?[ \t]+)*static[ \t]+var\b", re.MULTILINE)


class SuiteStaticVarTests(unittest.TestCase):
    def test_the_pattern_finds_a_static_var_however_it_is_written(self):
        for line in ("static var x := 1", "static var x", "\tstatic var x: int", '@warning_ignore("unused") static var x',
                     "@static_unload\nstatic var x"):
            with self.subTest(line=line):
                self.assertTrue(STATIC_VAR.search("extends Node\n" + line + "\n"), line)
        for line in ("var x := 1", "static func f() -> void:", "# static var x", "const static_var := 1",
                     "var static_var := 1"):
            with self.subTest(line=line):
                self.assertFalse(STATIC_VAR.search("extends Node\n" + line + "\n"), line)

    def test_no_native_suite_declares_a_static_var(self):
        suites = sorted((ROOT / "tests").rglob("*_suite.gd"))
        self.assertTrue(suites, "no suite found under tests/")
        found = [path.relative_to(ROOT).as_posix() for path in suites
                 if STATIC_VAR.search(path.read_text(encoding="utf-8"))]
        self.assertEqual(found, [], "a `static var` in a suite script crashes the 4.4.1 Windows engine at exit "
                                    "(see this test's docstring): make it an instance var")


if __name__ == "__main__":
    unittest.main()
