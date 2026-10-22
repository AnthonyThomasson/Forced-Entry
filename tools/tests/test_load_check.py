"""tools/load_check.sh, the headless start-up check, and its --import: with --import it first imports the project
(`--headless --path . --import`, which writes each new script's .uid and the class cache) with the same Godot it runs
the check with, then runs the check; an import that fails stops it before the check. With no Godot to be had (GODOT
naming nothing that runs) it fails with a message and runs nothing.

Each case is a temp tree holding a copy of this checkout's load_check.sh and scan_godot_log.py, run with GODOT set to
a fake Godot that logs each call's arguments, writes an empty log where `--log-file` asks, and fails an import when
FAKE_IMPORT_FAIL=1.
"""
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from tools.coverage.tests.support import clean_env

ROOT = Path(__file__).resolve().parents[2]

FAKE_GODOT = """#!/usr/bin/env bash
echo "$*" >> "$FAKE_GODOT_CALLS"
prev=""
for a in "$@"; do
  [[ "$prev" == --log-file ]] && : > "$a"
  prev="$a"
done
if [[ " $* " == *" --import "* && "${FAKE_IMPORT_FAIL:-}" == 1 ]]; then
  echo "ERROR: import broke"
  exit 1
fi
exit 0
"""


class LoadCheckTree:
    """A temp tree with the script copies and the fake Godot."""

    def __enter__(self):
        self.dir = Path(tempfile.mkdtemp(prefix="load_check_test."))
        self.root = self.dir / "tree"
        (self.root / "tools").mkdir(parents=True)
        for name in ("load_check.sh", "scan_godot_log.py"):
            shutil.copy2(ROOT / "tools" / name, self.root / "tools" / name)
        self.godot = self.dir / "godot"
        self.godot.write_text(FAKE_GODOT)
        self.godot.chmod(0o755)
        self.calls = self.dir / "calls.txt"
        return self

    def __exit__(self, *_exc):
        shutil.rmtree(self.dir, ignore_errors=True)

    def run(self, *args: str, godot: str | None = None, **env: str) -> subprocess.CompletedProcess:
        environ = clean_env(GODOT=godot or str(self.godot), FAKE_GODOT_CALLS=str(self.calls), TMPDIR=str(self.dir),
                            **env)
        return subprocess.run(["bash", str(self.root / "tools" / "load_check.sh"), *args], cwd=self.dir,
                              env=environ, capture_output=True, text=True, timeout=60)

    def godot_calls(self) -> list[str]:
        return self.calls.read_text().splitlines() if self.calls.exists() else []


class LoadCheckTests(unittest.TestCase):
    def test_without_import_it_runs_only_the_check(self):
        with LoadCheckTree() as tree:
            r = tree.run()
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            calls = tree.godot_calls()
            self.assertEqual(len(calls), 1, calls)
            self.assertIn("--quit-after", calls[0])
            self.assertNotIn("--import", calls[0])

    def test_import_imports_with_the_same_godot_then_runs_the_check(self):
        with LoadCheckTree() as tree:
            r = tree.run("--import")
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            calls = tree.godot_calls()
            self.assertEqual(len(calls), 2, calls)
            self.assertEqual(calls[0].split(), ["--headless", "--path", ".", "--import"], "the import first")
            self.assertIn("--quit-after", calls[1], "then the check")
            self.assertIn("PASS", r.stdout)

    def test_a_failing_import_fails_with_a_message_before_the_check(self):
        with LoadCheckTree() as tree:
            r = tree.run("--import", FAKE_IMPORT_FAIL="1")
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("import failed", r.stdout + r.stderr)
            self.assertIn("import broke", r.stdout + r.stderr, "with what the engine said")
            self.assertEqual(len(tree.godot_calls()), 1, "no check after it")

    def test_no_godot_fails_with_a_message_and_runs_nothing(self):
        for args in ((), ("--import",)):
            with self.subTest(args=args), LoadCheckTree() as tree:
                r = tree.run(*args, godot=str(tree.dir / "no_such_godot"))
                self.assertEqual(r.returncode, 2, r.stdout + r.stderr)
                self.assertIn("Godot binary not found", r.stderr)
                self.assertEqual(tree.godot_calls(), [])


if __name__ == "__main__":
    unittest.main()
