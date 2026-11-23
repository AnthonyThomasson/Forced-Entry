"""No script of ours needs `shasum` on PATH: tools/setup/lib.sh's fe_hash picks a digest tool that is in /usr/bin on a Mac
and in Git Bash's /usr/bin on Windows (sha<N>sum, then shasum, then cksum).

In Git for Windows `shasum` is in /usr/bin/core_perl, which only /etc/profile (a login Git Bash) puts on PATH, so a
script started from PowerShell, cmd, VS Code or by git.exe (a git hook) died with "shasum: command not found". The cases
below run the scripts that hash (tools/run_tests.sh, tools/stop_hook_checks.sh) with a PATH that has no folder holding
`shasum`, which is how those callers start them; they apply on Windows only (everywhere else `shasum` is in /usr/bin).
"""
import hashlib
import os
import re
import shutil
import subprocess
import sys
import unittest
from pathlib import Path

from tools.coverage.tests.support import TempDir, clean_env
from tools.tests.fake_tree import FakeTree, path_without_shasum
from tools.tests.test_stop_hook_checks import STOP_INPUT, StopHookRepo

ROOT = Path(__file__).resolve().parents[2]
SETUP = ROOT / "tools" / "setup"
BASH = shutil.which("bash")
WINDOWS = sys.platform == "win32"
ONLY_WINDOWS = unittest.skipUnless(WINDOWS, "shasum is on PATH outside Windows (it is in /usr/bin on a Mac)")


def fe_hash(algo: str, data: bytes, env: dict | None = None) -> str:
    r = subprocess.run([BASH, "-c", f'source "{SETUP.as_posix()}/lib.sh"; fe_hash {algo}'], input=data, env=env or clean_env(),
                       capture_output=True, timeout=60)
    assert r.returncode == 0, r.stderr
    return r.stdout.decode().strip()


@unittest.skipUnless(BASH, "no bash")
class HashHelperTests(unittest.TestCase):
    def test_it_prints_the_hex_digest_of_stdin_for_each_algorithm(self):
        data = b"forced entry\nsecond line\n"
        for algo, name in (("1", "sha1"), ("256", "sha256"), ("512", "sha512")):
            with self.subTest(algo=algo):
                self.assertEqual(fe_hash(algo, data), hashlib.new(name, data).hexdigest())

    def test_the_default_is_sha1(self):
        self.assertEqual(fe_hash("", b"x").__len__(), 40)

    def test_it_works_with_no_shasum_on_path(self):
        if not WINDOWS:
            self.skipTest("shasum is on PATH outside Windows")
        env = clean_env(PATH=path_without_shasum())
        self.assertEqual(fe_hash("256", b"abc", env), hashlib.sha256(b"abc").hexdigest())

    def test_hash_file_reads_a_file(self):
        with TempDir("fe_hash.") as d:
            f = d / "f.txt"
            f.write_bytes(b"abc")
            r = subprocess.run([BASH, "-c", f'source "{SETUP.as_posix()}/lib.sh"; fe_hash_file 512 "{f.as_posix()}"'],
                               env=clean_env(), capture_output=True, text=True, timeout=60)
            self.assertEqual(r.stdout.strip(), hashlib.sha512(b"abc").hexdigest(), r.stderr)


@unittest.skipUnless(BASH, "no bash")
class NoShasumTests(FakeTree):
    """tools/run_tests.sh derives its per-checkout state key from a digest on every invocation (set -euo pipefail)."""

    def base_path(self) -> str:
        return path_without_shasum() if WINDOWS else os.environ["PATH"]

    @ONLY_WINDOWS
    def test_run_tests_lists_without_shasum_on_path(self):
        code, out = self.run_tests("--list")
        self.assertNotIn("shasum", out)
        self.assertEqual(code, 0, out)

    @ONLY_WINDOWS
    def test_the_stop_hook_runs_the_checks_without_shasum_on_path(self):
        with TempDir("no_shasum_stop.") as d:
            repo = StopHookRepo(d / "repo")
            repo.change("scenes/thing.gd")
            r = subprocess.run([BASH, str(repo.root / "tools" / "stop_hook_checks.sh")], cwd=repo.root, input=STOP_INPUT,
                               env=clean_env(HOOK_TEST_LOG=str(repo.log), TMPDIR=str(repo.tmp), PATH=path_without_shasum()),
                               capture_output=True, text=True, timeout=60)
            self.assertNotIn("shasum", r.stderr)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertEqual(repo.ran(), ["lint --quiet", "load_check"])


class NoBareShasumTests(unittest.TestCase):
    """Nothing in tools/ or the Claude hooks runs `shasum` itself: they call fe_hash (the one place that knows it)."""

    def test_no_script_runs_shasum_directly(self):
        pattern = re.compile(r"(^|[\s|;&(`$])shasum\s")
        for glob in ("tools/*.sh", "tools/**/*.sh", ".claude/hooks/*", ".githooks/*"):
            for path in sorted(ROOT.glob(glob)):
                if not path.is_file() or "fixtures" in path.parts[:-1] or path == SETUP / "lib.sh":
                    continue
                for n, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
                    if line.lstrip().startswith("#"):
                        continue
                    self.assertIsNone(pattern.search(line), f"{path.relative_to(ROOT)}:{n} runs shasum: {line.strip()}")


if __name__ == "__main__":
    unittest.main()
