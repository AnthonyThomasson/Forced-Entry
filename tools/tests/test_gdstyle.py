"""tools/gdstyle.sh, the pinned gdstyle (v0.4.0) the lint formats and checks with: it fetches this platform's release
asset into a cache outside the tree, checks the asset's sha256 against the one pinned in the script, refuses to run on
a mismatch, reuses the cached binary after that, and hands gdstyle its arguments, working directory and exit status.

Each case runs the script with GDSTYLE_CACHE (the cache) in a temp folder of its own and GDSTYLE_RELEASE_URL (where the
assets are fetched from) pointing at a temp folder (a file:// URL) holding what the case serves, so nothing touches the
real cache. The last case fetches the real release from GitHub, and skips where github.com does not resolve (the Bash
sandbox).
"""
import io
import platform
import socket
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from tools.coverage.tests.support import clean_env

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "gdstyle.sh"
VERSION = "0.4.0"
NO_NETWORK = "no network (the Bash sandbox?): the pinned release cannot be fetched"

FAKE_GDSTYLE = """#!/usr/bin/env bash
touch "$GDSTYLE_TEST_MARKER"
pwd
for a in "$@"; do echo "arg[$a]"; done
exit 7
"""


def asset() -> str:
    """This platform's release asset, as v0.4.0 names it."""
    system, machine = platform.system(), platform.machine().lower()
    arch = {"arm64": "aarch64", "aarch64": "aarch64", "x86_64": "x86_64", "amd64": "x86_64"}[machine]
    if system == "Darwin":
        return f"gdstyle-{arch}-apple-darwin.tar.gz"
    if system == "Linux":
        return f"gdstyle-{arch}-unknown-linux-gnu.tar.gz"
    raise unittest.SkipTest(f"no gdstyle release for {system}")


def fake_tarball(path: Path) -> None:
    """A release asset of the right name whose `gdstyle` is the fake above (so its sha256 is not the pinned one)."""
    data = FAKE_GDSTYLE.encode()
    with tarfile.open(path, "w:gz") as tar:
        info = tarfile.TarInfo("gdstyle")
        info.size, info.mode = len(data), 0o755
        tar.addfile(info, io.BytesIO(data))


class GdStyleScriptTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        base = Path(tmp.name)
        self.cache, self.release, self.marker = base / "cache", base / "release", base / "ran"
        self.release.mkdir()

    def run_script(self, *args, cwd=ROOT):
        env = clean_env(GDSTYLE_CACHE=str(self.cache), GDSTYLE_RELEASE_URL=self.release.as_uri(),
                        GDSTYLE_TEST_MARKER=str(self.marker))
        return subprocess.run(["bash", str(SCRIPT), *args], cwd=cwd, env=env, capture_output=True, text=True,
                              timeout=300)

    def cached_binary(self) -> Path:
        return self.cache / f"v{VERSION}" / asset().removesuffix(".tar.gz") / "gdstyle"

    def plant_cached_fake(self) -> None:
        binary = self.cached_binary()
        binary.parent.mkdir(parents=True)
        binary.write_text(FAKE_GDSTYLE)
        binary.chmod(0o755)

    def test_a_wrong_checksum_refuses_to_run(self):
        fake_tarball(self.release / asset())
        r = self.run_script("check")
        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertNotEqual(r.returncode, 7, "the fake gdstyle ran\n" + r.stdout + r.stderr)
        self.assertIn("sha256", r.stderr)
        self.assertIn(asset(), r.stderr)
        self.assertFalse(self.marker.exists(), "a binary that failed its checksum was run")
        self.assertFalse(self.cached_binary().exists(), "a binary that failed its checksum was cached")
        # Asked again, it still refuses: nothing of the bad download was kept.
        r = self.run_script("check")
        self.assertNotEqual(r.returncode, 7)
        self.assertFalse(self.marker.exists())

    def test_a_cached_binary_is_reused(self):
        self.plant_cached_fake()  # the release folder is empty: a fetch would fail
        r = self.run_script("--version")
        self.assertEqual(r.returncode, 7, r.stdout + r.stderr)
        self.assertTrue(self.marker.exists(), "the cached binary did not run")
        self.assertEqual(list(self.release.iterdir()), [])

    def test_arguments_working_directory_and_exit_status_pass_through(self):
        self.plant_cached_fake()
        sub = ROOT / "tools"
        r = self.run_script("fmt", "--check", "a b", "", "res://x.gd", cwd=sub)
        self.assertEqual(r.returncode, 7, r.stdout + r.stderr)
        lines = r.stdout.splitlines()
        self.assertEqual(Path(lines[0]).resolve(), sub.resolve())
        self.assertEqual(lines[1:], ["arg[fmt]", "arg[--check]", "arg[a b]", "arg[]", "arg[res://x.gd]"])

    def test_the_pinned_release_case_skips_where_github_does_not_resolve(self):
        case = GdStyleScriptTests("test_the_pinned_release_is_fetched_verified_and_cached")
        result = unittest.TestResult()
        with mock.patch("socket.getaddrinfo", side_effect=socket.gaierror(8, "nodename nor servname provided")):
            case.run(result)
        self.assertEqual([reason for _case, reason in result.skipped], [NO_NETWORK],
                         [text for _case, text in result.failures + result.errors])

    def test_the_pinned_release_is_fetched_verified_and_cached(self):
        try:
            socket.getaddrinfo("github.com", 443)
        except OSError:
            self.skipTest(NO_NETWORK)
        env = clean_env(GDSTYLE_CACHE=str(self.cache))
        r = subprocess.run(["bash", str(SCRIPT), "--version"], cwd=ROOT, env=env, capture_output=True, text=True,
                           timeout=300)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(r.stdout.strip(), f"gdstyle {VERSION}")
        self.assertTrue(self.cached_binary().exists())
        # The second run is the cached binary: with the release out of reach it still answers.
        r = self.run_script("--version")
        self.assertEqual(r.stdout.strip(), f"gdstyle {VERSION}", r.stderr)
        self.assertEqual(list(self.release.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
