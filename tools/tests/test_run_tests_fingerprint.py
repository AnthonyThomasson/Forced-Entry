"""GAME_TEST_FINGERPRINT_DIR (the fight fingerprint, tests/_perf/fight_fingerprint.gd) reaches every engine process
tools/run_tests.sh starts, as an absolute path and created, and an unset one stays unset. A fake Godot notes the
variable it was started with, in a throwaway tree."""
import os
import unittest
from pathlib import Path
from unittest import mock

from tools.tests.fake_tree import FAKE_GODOT, FakeTree

# The fake of fake_tree.py that also notes the variable (or "<unset>") of each engine start.
NOTING = FAKE_GODOT.replace('echo "start$rest" >> "$FAKE_STARTS"',
                            'echo "start$rest" >> "$FAKE_STARTS"\necho "fp=${GAME_TEST_FINGERPRINT_DIR-<unset>}" >> "$FAKE_STARTS.fp"')


class FingerprintDirTests(FakeTree):
    def setUp(self):
        super().setUp()
        self.fake.write_text(NOTING)

    def seen(self):
        f = Path(str(self.starts) + ".fp")
        return f.read_text().splitlines() if f.exists() else []

    def test_the_engine_is_started_with_the_directory_as_an_absolute_path_that_exists(self):
        code, out = self.run_tests("--id=general/m_suite", suite="general/m_suite", GAME_TEST_FINGERPRINT_DIR="fp_out")
        self.assertEqual(code, 0, out)
        want = (self.repo / "fp_out").resolve()
        self.assertEqual(self.seen(), [f"fp={want}"])
        self.assertTrue(want.is_dir(), "the wrapper creates it, the engine only writes into it")

    def test_an_absolute_directory_is_kept_as_it_is(self):
        target = self.tmp / "elsewhere" / "fps"
        code, out = self.run_tests("--id=general/m_suite", suite="general/m_suite", GAME_TEST_FINGERPRINT_DIR=str(target))
        self.assertEqual(code, 0, out)
        self.assertEqual(self.seen(), [f"fp={target}"])

    def test_unset_it_stays_unset(self):
        with mock.patch.dict(os.environ):
            os.environ.pop("GAME_TEST_FINGERPRINT_DIR", None)
            code, out = self.run_tests("--id=general/m_suite", suite="general/m_suite")
        self.assertEqual(code, 0, out)
        self.assertEqual(self.seen(), ["fp=<unset>"])


if __name__ == "__main__":
    unittest.main()
