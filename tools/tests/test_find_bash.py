"""tools/setup/fe_env.py find_bash(): the bash that runs the repo's scripts. On Windows it is Git Bash, never WSL's launcher
in System32 (which cannot run a script by its Windows path)."""
import shutil
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.setup import fe_env  # noqa: E402


class FindBashTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("bash"), "no bash")
    def test_it_finds_a_bash_that_exists(self):
        found = fe_env.find_bash()
        self.assertIsNotNone(found)
        self.assertTrue(Path(found).is_file(), found)

    @unittest.skipUnless(sys.platform == "win32" and shutil.which("bash"), "Windows with a bash")
    def test_on_windows_it_is_never_the_wsl_launcher(self):
        lowered = fe_env.find_bash().lower()
        self.assertNotIn("\system32\\", lowered)
        self.assertNotIn("\windowsapps\\", lowered)


if __name__ == "__main__":
    unittest.main()
