"""tools/gdstyle.sh, the pinned gdstyle (v0.4.0) the lint formats and checks with: it fetches this platform's release
asset into a cache outside the tree, checks the asset's sha256 against the one pinned in tools/setup/versions.env, refuses to run
on a mismatch, reuses the cached binary after that, and hands gdstyle its arguments, working directory and exit status.

Each case runs the script with GDSTYLE_CACHE (the cache) in a temp folder of its own and GDSTYLE_RELEASE_URL (where the
assets are fetched from) pointing at a temp folder (a file:// URL) holding what the case serves, so nothing touches the
real cache. CacheLocationAndFetchTests covers where the cache is by default (the per-user root) and the `--cached` and
`--fetch` modes the bootstrap uses, on every OS. The last case fetches the real release from GitHub, and skips where github.com does not resolve (the Bash
sandbox).
"""
import hashlib
import io
import platform
import re
import shutil
import socket
import subprocess
import sys
import tarfile
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock

from tools.coverage.tests.support import clean_env

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "gdstyle.sh"
VERSION = "0.4.0"
WINDOWS = sys.platform == "win32"
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


def platform_asset() -> tuple[str, str]:
    """(this platform's release asset, its binary's file name), Windows included: the cases below never run the binary."""
    system, machine = platform.system(), platform.machine().lower()
    arch = {"arm64": "aarch64", "aarch64": "aarch64", "x86_64": "x86_64", "amd64": "x86_64"}[machine]
    if system == "Darwin":
        return f"gdstyle-{arch}-apple-darwin.tar.gz", "gdstyle"
    if system == "Linux":
        return f"gdstyle-{arch}-unknown-linux-gnu.tar.gz", "gdstyle"
    if system == "Windows":
        return f"gdstyle-{arch}-pc-windows-msvc.zip", "gdstyle.exe"
    raise unittest.SkipTest(f"no gdstyle release for {system}")


def fake_archive(path: Path, exe: str) -> None:
    """An archive of the right type holding a stand-in `exe` (never run)."""
    data = b"not a real gdstyle\n"
    if path.name.endswith(".zip"):
        with zipfile.ZipFile(path, "w") as z:
            z.writestr(exe, data)
    else:
        with tarfile.open(path, "w:gz") as tar:
            info = tarfile.TarInfo(exe)
            info.size, info.mode = len(data), 0o755
            tar.addfile(info, io.BytesIO(data))


class CacheLocationAndFetchTests(unittest.TestCase):
    """Where the binary is cached (under the per-user root, tools/setup/lib.sh's fe_home), and `--cached` / `--fetch`, the
    modes the bootstrap's hooks step uses so the first lint works offline. Each case runs a copy of the script and
    tools/setup whose versions.env pins the sha256 of an archive the case serves, so the real fetch, check and unpack run."""

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.base = Path(tmp.name)
        self.asset, self.exe = platform_asset()
        self.tree = self.base / "tree"
        (self.tree / "tools").mkdir(parents=True)
        shutil.copy2(SCRIPT, self.tree / "tools" / "gdstyle.sh")
        shutil.copytree(ROOT / "tools" / "setup", self.tree / "tools" / "setup", ignore=shutil.ignore_patterns("__pycache__"))
        self.release = self.base / "release"
        self.release.mkdir()
        self.home = self.base / "home"

    def pin(self, sha: str) -> None:
        """The tree's versions.env pins `sha` for this platform's asset."""
        key = {"gdstyle-aarch64-apple-darwin.tar.gz": "GDSTYLE_AARCH64_MACOS_SHA256",
               "gdstyle-x86_64-apple-darwin.tar.gz": "GDSTYLE_X86_64_MACOS_SHA256",
               "gdstyle-x86_64-unknown-linux-gnu.tar.gz": "GDSTYLE_X86_64_LINUX_SHA256",
               "gdstyle-x86_64-pc-windows-msvc.zip": "GDSTYLE_X86_64_WINDOWS_SHA256"}[self.asset]
        env_file = self.tree / "tools" / "setup" / "versions.env"
        text = re.sub(rf"(?m)^{key}=.*$", f"{key}={sha}", env_file.read_text())
        env_file.write_text(text, newline="\n")

    def run_script(self, *args, **env):
        environ = clean_env(FORCED_ENTRY_HOME=str(self.home), GDSTYLE_RELEASE_URL=self.release.as_uri())
        environ.pop("GDSTYLE_CACHE", None)
        environ.update(env)
        return subprocess.run(["bash", str(self.tree / "tools" / "gdstyle.sh"), *args], cwd=self.base, env=environ,
                              capture_output=True, text=True, timeout=300)

    def binary(self) -> Path:
        dir_name = self.asset.removesuffix(".tar.gz").removesuffix(".zip")
        return self.home / "gdstyle" / f"v{VERSION}" / dir_name / self.exe

    def serve_a_pinned_archive(self) -> None:
        archive = self.release / self.asset
        fake_archive(archive, self.exe)
        self.pin(hashlib.sha256(archive.read_bytes()).hexdigest())

    def test_the_pins_are_the_manifests(self):
        manifest = (ROOT / "tools" / "setup" / "versions.env").read_text()
        self.assertIn(f"GDSTYLE_VERSION={VERSION}", manifest)
        text = SCRIPT.read_text()
        self.assertNotRegex(text, r"[0-9a-f]{64}", "a sha256 pinned in the script itself, not in versions.env")
        self.assertNotIn(".cache/forced-entry-gdstyle", text)

    def test_nothing_cached_is_exit_1_with_no_output_and_nothing_is_fetched(self):
        r = self.run_script("--cached")
        self.assertEqual((r.returncode, r.stdout), (1, ""), r.stderr)
        self.assertFalse(self.home.exists(), "--cached only looks")

    def test_fetch_downloads_checks_unpacks_and_caches_under_the_per_user_root(self):
        self.serve_a_pinned_archive()
        r = self.run_script("--fetch")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertTrue(self.binary().is_file(), r.stdout + r.stderr)
        self.assertTrue(r.stdout.strip().endswith(self.exe), "it prints the binary's path: " + r.stdout)
        # Now cached: --cached says so, a second --fetch fetches nothing (the release folder is emptied).
        shutil.rmtree(self.release)
        self.release.mkdir()
        r = self.run_script("--cached")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(r.stdout.strip().endswith(self.exe), r.stdout)
        self.assertEqual(self.run_script("--fetch").returncode, 0)

    def test_fetch_refuses_an_archive_that_is_not_the_pinned_one_and_caches_nothing(self):
        fake_archive(self.release / self.asset, self.exe)  # the pins are the real ones: it does not match
        r = self.run_script("--fetch")
        self.assertEqual(r.returncode, 2, r.stdout)
        self.assertIn("sha256 mismatch", r.stderr)
        self.assertFalse(self.binary().exists())
        self.assertEqual(self.run_script("--cached").returncode, 1)

    def test_fetch_with_the_release_out_of_reach_fails_with_a_message(self):
        r = self.run_script("--fetch")  # an empty release folder
        self.assertEqual(r.returncode, 2, r.stdout)
        self.assertIn("could not fetch", r.stderr)

    def test_gdstyle_cache_overrides_the_per_user_root(self):
        self.serve_a_pinned_archive()
        elsewhere = self.base / "elsewhere"
        r = self.run_script("--fetch", GDSTYLE_CACHE=str(elsewhere))
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertTrue((elsewhere / f"v{VERSION}").is_dir())
        self.assertFalse(self.home.exists())


if __name__ == "__main__":
    unittest.main()
