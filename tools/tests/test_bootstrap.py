"""tools/setup/bootstrap.sh and bootstrap.ps1: the one command that installs what Forced-Entry needs, pinned in
tools/setup/versions.env, each step logged as installed, upgraded or up to date.

Every scenario runs through bash (bootstrap.sh) and, on Windows, through Windows PowerShell 5.1 (bootstrap.ps1), on a
per-user root of its own (FORCED_ENTRY_HOME in a temp folder) holding the fake Von home of fake_von.py: a real venv with
a stand-in von-sdk. No test touches the network (a dead proxy makes any attempt fail), the real per-user root or the
user's PATH. What they cannot cover is what needs the network or an installer: the real downloads, winget and brew.
Those are checked by hand (README's list, the ticket's fresh-machine run).

The Godot and skillshare steps are driven with fake `--version` programs; the hooks step with a stub
tools/install_hooks.sh in a throwaway git repo that carries a copy of tools/setup.
"""
from __future__ import annotations

import functools
import http.server
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
import uuid
import zipfile
from pathlib import Path

from tools.tests import fake_von

ROOT = Path(__file__).resolve().parents[2]
SETUP = ROOT / "tools" / "setup"
WINDOWS = sys.platform == "win32"
BASH = shutil.which("bash")
POWERSHELL = shutil.which("powershell") if WINDOWS else None

# The steps that need a machine-level installer, left out of every run here but the ones that test them.
SKIP_MACHINE = "git,python,godot,skillshare,hooks"


def manifest() -> dict:
    values = {}
    for line in (SETUP / "versions.env").read_text().splitlines():
        if line and not line.startswith("#") and "=" in line:
            key, _, value = line.partition("=")
            values[key] = value
    return values


REVISION = manifest()["VON_WEIGHTS_REVISION"]


class Runner:
    """One way to run the bootstrap: `run(args, env)` returns the CompletedProcess. `args` use the bash spelling
    (`--check`, `--skip=a,b`); the PowerShell runner translates them."""

    name = "bash"

    def __init__(self, tree: Path):
        self.tree = tree

    def run(self, args: list, env: dict) -> subprocess.CompletedProcess:
        return subprocess.run([BASH, str(self.tree / "tools" / "setup" / "bootstrap.sh"), *args], env=env,
                              capture_output=True, text=True, timeout=300)


class PowerShellRunner(Runner):
    name = "powershell"

    def run(self, args: list, env: dict) -> subprocess.CompletedProcess:
        translated = []
        for a in args:
            if a == "--check":
                translated.append("-Check")
            elif a.startswith("--skip="):
                translated += ["-Skip", a[len("--skip="):]]
            else:
                translated.append(a)
        return subprocess.run([POWERSHELL, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                               str(self.tree / "tools" / "setup" / "bootstrap.ps1"), "-NoPath", *translated], env=env,
                              capture_output=True, text=True, timeout=300)


def runners(tree: Path) -> list:
    found = [Runner(tree)] if BASH else []
    if POWERSHELL:
        found.append(PowerShellRunner(tree))
    return found


def step_lines(out: str) -> dict:
    """`bootstrap: <step>: <status text>` lines as {step: status text}."""
    lines = {}
    for line in out.splitlines():
        m = re.match(r"bootstrap: (git|python|godot|skillshare|hooks|venv|weights): (.*)", line)
        if m:
            lines[m.group(1)] = m.group(2)
    return lines


class BootstrapCase(unittest.TestCase):
    """A temp tree with tools/setup copied in (so a run's repo root is the temp tree), a per-user root of its own and a
    scrubbed environment."""

    @classmethod
    def setUpClass(cls):
        cls.fake = fake_von.von_home()

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="bootstrap."))
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.tree = self.tmp / "tree"
        shutil.copytree(SETUP, self.tree / "tools" / "setup", ignore=shutil.ignore_patterns("__pycache__"))
        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        self.fake.put_weights(REVISION)
        self.addCleanup(self.fake.clear_weights)

    def env(self, **over) -> dict:
        env = {k: v for k, v in os.environ.items()
               if not k.startswith("GIT_") and k not in ("GODOT", "PYTHON", "PYTHONPATH", "FE_VON_PYTHON")}
        env.update(FORCED_ENTRY_HOME=str(self.fake.root), FE_VON_PYTHON=sys.executable,
                   # Any step that reaches for the network fails at once instead of downloading.
                   HTTP_PROXY="http://127.0.0.1:9", HTTPS_PROXY="http://127.0.0.1:9", ALL_PROXY="http://127.0.0.1:9",
                   PIP_NO_INDEX="1", PIP_RETRIES="0")
        env.update({k: v for k, v in over.items() if v is not None})
        for k, v in over.items():
            if v is None:
                env.pop(k, None)
        return env

    def each(self, check, ps: bool = True) -> None:
        """`check(runner)` for the bash runner and, on Windows, the PowerShell one (unless `ps` is False: a Windows
        PowerShell start costs seconds, so only the scenarios that exercise its own code run through it), each its own
        subtest."""
        for runner in runners(self.tree):
            if runner.name == "powershell" and not ps:
                continue
            with self.subTest(runner=runner.name):
                check(runner)


class CheckTests(BootstrapCase):
    def test_a_complete_setup_is_all_up_to_date(self):
        def check(r):
            out = r.run(["--check", f"--skip={SKIP_MACHINE}"], self.env())
            self.assertEqual(out.returncode, 0, out.stdout + out.stderr)
            steps = step_lines(out.stdout)
            self.assertTrue(steps["venv"].startswith("up to date"), out.stdout)
            self.assertTrue(steps["weights"].startswith("up to date"), out.stdout)
            self.assertIn("0 installed, 0 upgraded, 2 up to date", out.stdout)
        self.each(check)

    def test_check_reports_what_is_missing_and_exits_1(self):
        self.fake.clear_weights()
        def check(r):
            out = r.run(["--check", f"--skip={SKIP_MACHINE}"], self.env())
            self.assertEqual(out.returncode, 1, out.stdout + out.stderr)
            self.assertRegex(step_lines(out.stdout)["weights"], r"^missing")
            self.assertIn("1 missing or outdated", out.stdout)
        self.each(check)

    def test_a_home_with_no_venv_misses_the_venv_and_the_weights(self):
        empty = self.tmp / "empty"
        def check(r):
            out = r.run(["--check", f"--skip={SKIP_MACHINE}"], self.env(FORCED_ENTRY_HOME=str(empty)))
            self.assertEqual(out.returncode, 1, out.stdout)
            steps = step_lines(out.stdout)
            self.assertRegex(steps["venv"], r"^missing")
            self.assertRegex(steps["weights"], r"^missing")
            self.assertFalse(empty.exists(), "--check must not create anything")
        self.each(check)

    def test_weights_without_the_revision_marker_are_not_up_to_date(self):
        self.fake.put_weights()  # the files, no marker
        def check(r):
            out = r.run(["--check", f"--skip={SKIP_MACHINE}"], self.env())
            self.assertRegex(step_lines(out.stdout)["weights"], r"^missing or not revision")
        self.each(check)

    def test_weights_of_another_revision_or_with_a_file_gone_are_not_up_to_date(self):
        self.fake.put_weights("0" * 40)
        def check(r):
            self.assertRegex(step_lines(r.run(["--check", f"--skip={SKIP_MACHINE}"], self.env()).stdout)["weights"], r"^missing")
        self.each(check, ps=False)
        self.fake.put_weights(REVISION)
        (self.fake.weights / "model.safetensors").unlink()
        def check(r):
            self.assertRegex(step_lines(r.run(["--check", f"--skip={SKIP_MACHINE}"], self.env()).stdout)["weights"], r"^missing")
        self.each(check, ps=False)

    def test_a_venv_whose_base_python_is_gone_is_named(self):
        cfg = self.fake.venv / "pyvenv.cfg"
        original = cfg.read_text()
        self.addCleanup(cfg.write_text, original)
        cfg.write_text(re.sub(r"(?m)^home = .*$", lambda _m: "home = " + str(self.tmp / "no" / "python"), original))
        def check(r):
            out = r.run(["--check", f"--skip={SKIP_MACHINE}"], self.env())
            self.assertRegex(step_lines(out.stdout)["venv"], r"^its base Python is gone")
        self.each(check)

    def test_a_venv_with_another_von_sdk_version_is_outdated(self):
        meta = next(self.fake.site_packages().glob("von_sdk-*.dist-info")) / "METADATA"
        original = meta.read_text()
        self.addCleanup(meta.write_text, original)
        meta.write_text(original.replace("Version: 1.3.1", "Version: 1.2.0"))
        def check(r):
            out = r.run(["--check", f"--skip={SKIP_MACHINE}"], self.env())
            self.assertRegex(step_lines(out.stdout)["venv"], r"^von-sdk 1\.2\.0, want 1\.3\.1")
        self.each(check)

    def test_a_venv_built_from_another_python_than_the_pin_is_rebuilt(self):
        # Without FE_VON_PYTHON the venv must be the manifest's VON_PYTHON; the fake one is whatever runs the tests.
        want = manifest()["VON_PYTHON"]
        if "%d.%d" % sys.version_info[:2] == want:
            self.skipTest(f"the tests run on Python {want}, the pinned one")
        def check(r):
            out = r.run(["--check", f"--skip={SKIP_MACHINE}"], self.env(FE_VON_PYTHON=None))
            self.assertRegex(step_lines(out.stdout)["venv"], rf"^it is Python \d+\.\d+, Von needs {re.escape(want)}")
        self.each(check, ps=False)

    def test_bad_arguments_exit_2_with_a_message(self):
        def check(r):
            bad = ["-Bogus", "stray"] if r.name == "powershell" else ["--nope", "stray"]
            for arg in bad:
                out = r.run([arg], self.env())
                self.assertEqual(out.returncode, 2, f"{arg}: {out.stdout}{out.stderr}")
                self.assertIn("unknown argument", out.stderr)
                self.assertNotIn("bootstrap:", out.stdout, "nothing is looked at or installed before the arguments are right")
            out = r.run(["--skip=git,nonsense"], self.env())
            self.assertEqual(out.returncode, 2, out.stdout + out.stderr)
            self.assertIn("unknown step", out.stderr)
            self.assertIn("nonsense", out.stderr)
        self.each(check)

    def test_skipped_steps_are_logged_and_counted(self):
        def check(r):
            out = r.run(["--check", f"--skip={SKIP_MACHINE},venv,weights"], self.env())
            self.assertEqual(out.returncode, 0, out.stdout)
            self.assertIn("7 skipped", out.stdout)
            self.assertEqual(step_lines(out.stdout)["godot"], "skipped")
        self.each(check, ps=False)


class RerunTests(BootstrapCase):
    def test_a_second_run_installs_nothing_and_needs_no_network(self):
        def check(r):
            out = r.run([f"--skip={SKIP_MACHINE}"], self.env())
            self.assertEqual(out.returncode, 0, out.stdout + out.stderr)
            self.assertIn("0 installed, 0 upgraded, 2 up to date", out.stdout)
            self.assertNotIn("downloading", out.stdout)
        self.each(check)

    def test_incomplete_weights_are_downloaded_again_and_marked(self):
        self.fake.put_weights()  # the files, no marker: what a download stopped before its last step leaves
        (self.fake.weights / "option_marker.pt").unlink()
        def check(r):
            self.fake.put_weights()
            (self.fake.weights / "option_marker.pt").unlink()
            out = r.run([f"--skip={SKIP_MACHINE}"], self.env())
            self.assertEqual(out.returncode, 0, out.stdout + out.stderr)
            self.assertRegex(step_lines(out.stdout)["weights"], r"^installed")
            self.assertEqual((self.fake.weights / ".fe-revision").read_text().strip(), REVISION)
            self.assertTrue((self.fake.weights / "option_marker.pt").is_file())
            again = r.run([f"--skip={SKIP_MACHINE}"], self.env())
            self.assertRegex(step_lines(again.stdout)["weights"], r"^up to date")
        self.each(check)

    def test_weights_without_a_venv_stop_the_run_naming_the_step(self):
        empty = self.tmp / "empty"
        def check(r):
            out = r.run([f"--skip={SKIP_MACHINE},venv"], self.env(FORCED_ENTRY_HOME=str(empty)))
            self.assertEqual(out.returncode, 1, out.stdout)
            self.assertRegex(out.stdout, r"weights: FAILED: .*venv step has not completed")
            self.assertIn("carries on from here", out.stdout)
        self.each(check)

    def test_a_venv_step_with_no_network_fails_with_the_cause_and_leaves_a_resumable_venv(self):
        # A pip failure (here: no index) leaves a venv without von-sdk; the next run only has to pip install.
        empty = self.tmp / "empty"
        def check(r):
            shutil.rmtree(empty, ignore_errors=True)
            out = r.run([f"--skip={SKIP_MACHINE},weights"], self.env(FORCED_ENTRY_HOME=str(empty)))
            self.assertEqual(out.returncode, 1, out.stdout[-600:] + out.stderr[-600:])
            self.assertRegex(out.stdout, r"venv: FAILED: pip install von-sdk==1\.3\.1 failed")
            again = r.run(["--check", f"--skip={SKIP_MACHINE},weights"], self.env(FORCED_ENTRY_HOME=str(empty)))
            self.assertRegex(step_lines(again.stdout)["venv"], r"^von-sdk is not installed")
        self.each(check)


class VenvRepairTests(BootstrapCase):
    def test_a_venv_without_pip_is_rebuilt_and_then_only_needs_the_install(self):
        # `python -m venv --without-pip` leaves a venv that cannot install anything; it used to fail the same way on every
        # re-run. Now its missing pip is a rebuild.
        home = self.tmp / "home"
        venv = home / "von" / "venv"

        def check(r):
            shutil.rmtree(home, ignore_errors=True)
            subprocess.run([sys.executable, "-m", "venv", "--without-pip", str(venv)], check=True, capture_output=True)
            env = self.env(FORCED_ENTRY_HOME=str(home))
            skip = f"--skip={SKIP_MACHINE},weights"
            checked = r.run(["--check", skip], env)
            self.assertRegex(step_lines(checked.stdout)["venv"], r"^its pip does not run", checked.stdout)
            run = r.run([skip], env)  # no network: the pip install fails, but only after the venv was rebuilt with pip
            self.assertEqual(run.returncode, 1, run.stdout[-500:])
            self.assertRegex(run.stdout, r"venv: rebuilding \(its pip does not run\)")
            self.assertRegex(run.stdout, r"venv: FAILED: pip install von-sdk==")
            pip = subprocess.run([str(venv / ("Scripts" if WINDOWS else "bin") / ("python.exe" if WINDOWS else "python")),
                                  "-m", "pip", "--version"], capture_output=True)
            self.assertEqual(pip.returncode, 0, "the rebuilt venv has pip")
            again = r.run(["--check", skip], env)
            self.assertRegex(step_lines(again.stdout)["venv"], r"^von-sdk is not installed")
        self.each(check)


class WeightsOfflineTests(BootstrapCase):
    def test_present_weights_with_no_marker_survive_a_failed_download(self):
        self.fake.put_weights()  # every file, no revision marker (copied in by hand, or an older run)

        def check(r):
            out = r.run([f"--skip={SKIP_MACHINE}"], self.env(FAKE_HF_FAIL="1"))
            self.assertEqual(out.returncode, 0, out.stdout + out.stderr)
            self.assertRegex(step_lines(out.stdout)["weights"], r"^present, revision not verified")
            self.assertIn("1 unverified", out.stdout)
            self.assertFalse((self.fake.weights / ".fe-revision").exists(), "an unverified revision is not marked")
        self.each(check)

    def test_missing_weights_still_fail_a_failed_download(self):
        self.fake.put_weights()
        (self.fake.weights / "model.safetensors").unlink()

        def check(r):
            out = r.run([f"--skip={SKIP_MACHINE}"], self.env(FAKE_HF_FAIL="1"))
            self.assertEqual(out.returncode, 1, out.stdout)
            self.assertRegex(out.stdout, r"weights: FAILED: hf download failed")
        self.each(check, ps=False)

    def test_the_weight_files_are_one_list_in_the_manifest(self):
        self.assertEqual(tuple(manifest()["VON_WEIGHT_FILES"].split(",")), fake_von.WEIGHT_FILES)
        for name in ("bootstrap.sh", "bootstrap.ps1", "../von/boot.sh", "../von/boot.ps1"):
            text = (SETUP / name).read_text()
            self.assertNotIn("model.safetensors", text, f"{name} must read the list from versions.env")


class GodotAndSkillshareTests(BootstrapCase):
    """Fake programs that answer `--version`: a Godot of the pin, a mono build of it, another version; skillshare."""

    def fake_program(self, name: str, version_line: str) -> Path:
        """A program in self.bin that answers with `version_line`: a .cmd on Windows (PowerShell finds that) and, so bash
        finds it by name too, an extensionless sh script."""
        path = self.bin / name
        path.write_text(f"#!/bin/sh\necho '{version_line}'\n", newline="\n")
        path.chmod(0o755)
        if WINDOWS:
            path = self.bin / f"{name}.cmd"
            path.write_text(f"@echo off\r\necho {version_line}\r\n", newline="")
        return path

    def check_godot(self, runner, version_line: str):
        godot = self.fake_program("godot_fake", version_line)
        return runner.run(["--check", "--skip=git,python,skillshare,hooks,venv,weights"], self.env(GODOT=str(godot)))

    def test_the_pinned_godot_is_up_to_date_standard_or_mono(self):
        def check(r):
            lines = ("4.4.1.stable.official.49a5bc7b6", "4.4.1.stable.mono.official.49a5bc7b6")
            for line in lines[:1] if r.name == "powershell" else lines:
                out = self.check_godot(r, line)
                self.assertEqual(out.returncode, 0, out.stdout)
                self.assertRegex(step_lines(out.stdout)["godot"], r"^up to date \(4\.4\.1-stable at ")
        self.each(check)

    def test_another_godot_version_is_not_the_pin(self):
        def check(r):
            lines = ("4.3.stable.official.77dcf97d8", "4.4.1.rc.official.abc", "4.4.10.stable.official.abc")
            for line in lines[:1] if r.name == "powershell" else lines:
                out = self.check_godot(r, line)
                self.assertEqual(out.returncode, 1, line + out.stdout)
                self.assertRegex(step_lines(out.stdout)["godot"], r"^missing \(4\.4\.1-stable; .* is another version\)")
        self.each(check)

    def test_no_godot_at_all_is_missing(self):
        def check(r):
            out = r.run(["--check", "--skip=git,python,skillshare,hooks,venv,weights"],
                        self.env(LOCALAPPDATA=str(self.tmp / "nolocal"), PROGRAMFILES=str(self.tmp / "nopf"),
                                 HOME=str(self.tmp / "nohome"), USERPROFILE=str(self.tmp / "nohome")))
            if step_lines(out.stdout)["godot"].startswith("up to date"):
                self.skipTest("a Godot of the pinned version is on this machine's PATH")
            self.assertRegex(step_lines(out.stdout)["godot"], r"^missing")
        self.each(check)

    def skillshare_env(self, **over) -> dict:
        """PATH with the real skillshare folders out and self.bin first; an empty per-user root and no go/bin."""
        kept = [d for d in os.environ["PATH"].split(os.pathsep) if d and not shutil.which("skillshare", path=d)]
        base = dict(PATH=os.pathsep.join([str(self.bin)] + kept), FORCED_ENTRY_HOME=str(self.tmp / "home"),
                    USERPROFILE=str(self.tmp / "h"), HOME=str(self.tmp / "h"))
        base.update(over)
        return self.env(**base)

    def skillshare_status(self, r, version_line=None) -> tuple:
        if version_line is not None:
            self.fake_program("skillshare", version_line)
        out = r.run(["--check", "--skip=git,python,godot,hooks,venv,weights"], self.skillshare_env())
        return out.returncode, step_lines(out.stdout)["skillshare"]

    def test_skillshare_at_or_above_the_pin_is_up_to_date(self):
        want = manifest()["SKILLSHARE_VERSION"]
        major, minor, patch = (int(n) for n in want.split("."))
        newer = [f"skillshare v{want}", f"skillshare v{major}.{minor}.{patch + 1}", f"skillshare v{major}.{minor + 1}.0",
                 f"skillshare v{major + 1}.0.0"]

        def check(r):
            for line in newer[:1] if r.name == "powershell" else newer:
                code, status = self.skillshare_status(r, line)
                self.assertEqual(code, 0, line)
                self.assertRegex(status, r"^up to date \(v\d+\.\d+\.\d+ at .*skillshare", line)
        self.each(check)

    def test_an_older_or_unreadable_skillshare_is_outdated(self):
        want = manifest()["SKILLSHARE_VERSION"]
        major, minor, patch = (int(n) for n in want.split("."))
        older = [("skillshare v0.1.0", "0.1.0"), (f"skillshare v{major}.{minor}.{patch - 1}", f"{major}.{minor}.{patch - 1}"),
                 ("something else entirely", "?")]

        def check(r):
            for line, shown in older[:1] if r.name == "powershell" else older:
                code, status = self.skillshare_status(r, line)
                self.assertEqual(code, 1, line)
                self.assertEqual(status, f"outdated (v{shown}), needs v{want}", line)
        self.each(check)

    def test_no_skillshare_is_missing(self):
        def check(r):
            out = r.run(["--check", "--skip=git,python,godot,hooks,venv,weights"], self.skillshare_env())
            self.assertEqual(step_lines(out.stdout)["skillshare"], f"missing (needs v{manifest()['SKILLSHARE_VERSION']})")
        self.each(check)

    @unittest.skipIf(WINDOWS, "needs a fake skillshare.exe in the per-user folder")
    def test_the_per_user_folders_skillshare_comes_before_the_one_on_path(self):
        want = manifest()["SKILLSHARE_VERSION"]
        self.fake_program("skillshare", "skillshare v0.1.0")  # old, on PATH
        own = self.tmp / "home" / "bin"
        own.mkdir(parents=True)
        (own / "skillshare").write_text(f"#!/bin/sh\necho 'skillshare v{want}'\n", newline="\n")
        (own / "skillshare").chmod(0o755)
        code, status = self.skillshare_status(Runner(self.tree))
        self.assertEqual(code, 0, status)
        self.assertIn(str(own), status)

    @unittest.skipUnless(WINDOWS, "the Windows bootstrap downloads skillshare; the Mac one is not run here")
    def test_an_older_skillshare_is_never_overwritten_by_the_install(self):
        # The release is made unreachable (a dead local port; PowerShell does not use the proxy variables), so the install
        # fails at the download. The old one stays exactly as it was and nothing is written into its folder; the pin would
        # go into <per-user folder>\bin.
        env_file = self.tree / "tools" / "setup" / "versions.env"
        env_file.write_text(re.sub(r"(?m)^SKILLSHARE_BASE_URL=.*$", "SKILLSHARE_BASE_URL=http://127.0.0.1:9",
                                   env_file.read_text()), newline="\n")
        old = self.fake_program("skillshare", "skillshare v0.1.0")
        before = old.read_bytes()
        r = PowerShellRunner(self.tree)
        out = r.run(["--skip=git,python,godot,hooks,venv,weights"], self.skillshare_env())
        self.assertEqual(out.returncode, 1, out.stdout)
        self.assertRegex(out.stdout, r"skillshare: FAILED: download of .* failed")
        self.assertEqual(old.read_bytes(), before)
        self.assertEqual(sorted(p.name for p in self.bin.iterdir()), ["skillshare", "skillshare.cmd"])


class ChecksumGateTests(BootstrapCase):
    """A download is accepted only when a non-empty pinned checksum equals the computed one. The pins in the tree's copy
    of versions.env are edited and the 'release' is a local web server."""

    def setUp(self):
        super().setUp()
        self.served = self.tmp / "served"
        self.served.mkdir()
        class Quiet(http.server.SimpleHTTPRequestHandler):
            def log_message(self, *args, **kwargs):
                pass

        handler = functools.partial(Quiet, directory=str(self.served))
        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.addCleanup(self.server.shutdown)
        self.addCleanup(self.server.server_close)

    def point_godot_at_the_server(self, zip_name: str, sha_key: str, sha: str) -> None:
        with zipfile.ZipFile(self.served / zip_name, "w") as z:
            z.writestr("Godot_v4.4.1-stable_win64_console.exe", "not an engine")
        env_file = self.tree / "tools" / "setup" / "versions.env"
        lines = []
        for line in env_file.read_text().splitlines():
            key = line.partition("=")[0]
            if key == "GODOT_BASE_URL":
                line = f"GODOT_BASE_URL=http://127.0.0.1:{self.server.server_address[1]}"
            elif key in ("GODOT_WIN64_ZIP", "GODOT_MACOS_ZIP"):
                line = f"{key}={zip_name}"
            elif key == sha_key:
                line = f"{key}={sha}"
            lines.append(line)
        env_file.write_text("\n".join(lines) + "\n", newline="\n")

    def run_install(self):
        """The one runner whose OS installs Godot here (Windows PowerShell, or bash on a Mac), against the local server."""
        if WINDOWS:
            runner, key = PowerShellRunner(self.tree), "GODOT_WIN64_SHA512"
        elif sys.platform == "darwin":
            runner, key = Runner(self.tree), "GODOT_MACOS_SHA512"
        else:
            self.skipTest("no Godot install on this OS")
        return runner, key

    def install(self, runner, **over):
        # Local only: the dead proxy of the other tests would also catch 127.0.0.1 for curl.
        env = self.env(HTTP_PROXY=None, HTTPS_PROXY=None, ALL_PROXY=None, NO_PROXY="127.0.0.1",
                       FORCED_ENTRY_HOME=str(self.tmp / "home"), LOCALAPPDATA=str(self.tmp / "nolocal"),
                       PROGRAMFILES=str(self.tmp / "nopf"), HOME=str(self.tmp / "nohome"), USERPROFILE=str(self.tmp / "nohome"),
                       **over)
        out = runner.run(["--skip=git,python,skillshare,hooks,venv,weights"], env)
        if "godot: up to date" in out.stdout:
            self.skipTest("a Godot of the pinned version is on this machine's PATH")
        return out

    def test_an_empty_pinned_checksum_is_refused(self):
        runner, key = self.run_install()
        self.point_godot_at_the_server("godot.zip", key, "")
        out = self.install(runner)
        self.assertEqual(out.returncode, 1, out.stdout)
        self.assertRegex(out.stdout, r"godot: FAILED: .* does not match the SHA-512 pinned")

    def test_a_wrong_checksum_is_refused(self):
        runner, key = self.run_install()
        self.point_godot_at_the_server("godot.zip", key, "0" * 128)
        out = self.install(runner)
        self.assertEqual(out.returncode, 1, out.stdout)
        self.assertRegex(out.stdout, r"godot: FAILED: .* does not match the SHA-512 pinned")
        self.assertFalse((self.tmp / "home" / "godot").exists(), "nothing is unpacked from a download that failed its check")

    def test_the_right_checksum_gets_as_far_as_the_unpack_and_the_version_check(self):
        import hashlib
        runner, key = self.run_install()
        self.point_godot_at_the_server("godot.zip", key, "")
        sha = hashlib.sha512((self.served / "godot.zip").read_bytes()).hexdigest()
        self.point_godot_at_the_server("godot.zip", key, sha)
        out = self.install(runner)
        self.assertEqual(out.returncode, 1, out.stdout)
        self.assertRegex(out.stdout, r"godot: FAILED: the unpacked Godot in .* does not report")


@unittest.skipUnless(WINDOWS, "Windows PowerShell only")
class WindowsPathTests(unittest.TestCase):
    """Add-UserPathEntry and Update-SessionPath, run from the script's own text against a scratch registry key and a
    made-up session PATH: the real user PATH is never touched."""

    def functions(self, *names: str) -> str:
        text = (SETUP / "bootstrap.ps1").read_text()
        out = []
        for name in names:
            m = re.search(rf"(?s)function {name}\b.*?\n}}\n", text)
            self.assertTrue(m, name)
            out.append(m.group(0))
        return "\n".join(out)

    def powershell(self, script: str) -> str:
        r = subprocess.run([POWERSHELL, "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script],
                           capture_output=True, text=True, timeout=120)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        return r.stdout.strip()

    def test_the_user_path_keeps_its_unexpanded_entries_and_its_type(self):
        key = f"Software\\ForcedEntryTest\\{uuid.uuid4().hex}"
        script = self.functions("Add-UserPathEntry") + f"""
$k = '{key}'
$reg = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($k)
$reg.SetValue('Path', '%USERPROFILE%\\tools;C:\\tools', [Microsoft.Win32.RegistryValueKind]::ExpandString)
$reg.Close()
Add-UserPathEntry 'C:\\x\\skillshare\\' $k
Add-UserPathEntry 'C:\\x\\skillshare' $k
$reg = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($k)
$reg.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
$reg.GetValueKind('Path')
$reg.Close()
[Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree('Software\\ForcedEntryTest')
"""
        value, kind = self.powershell(script).splitlines()
        self.assertEqual(value, r"%USERPROFILE%\tools;C:\tools;C:\x\skillshare" + "\\")
        self.assertEqual(kind, "ExpandString")

    def test_the_session_path_keeps_what_it_has_and_gains_the_registrys_entries(self):
        script = self.functions("Update-SessionPath") + r"""
$env:Path = 'C:\only-in-this-session;C:\Windows\System32'
Update-SessionPath
$env:Path
"""
        path = self.powershell(script).split(";")
        self.assertEqual(path[0], r"C:\only-in-this-session")
        self.assertEqual(path[1], r"C:\Windows\System32")
        lower = [p.rstrip("\\").lower() for p in path]
        self.assertEqual(len(lower), len(set(lower)), "no entry twice")
        machine = subprocess.run([POWERSHELL, "-NoProfile", "-Command",
                                  "[Environment]::GetEnvironmentVariable('Path','Machine')"], capture_output=True, text=True).stdout
        for entry in (e for e in machine.strip().split(";") if e):
            self.assertIn(entry.rstrip("\\").lower(), lower, entry)


class HooksTests(BootstrapCase):
    """The hooks step in a throwaway git repo whose tools/install_hooks.sh is a stub that does what the real one does
    to the repo (sets core.hooksPath, links a skill)."""

    STUB = ('#!/usr/bin/env bash\nset -e\ncd "$(dirname "$0")/.."\n'
            'git config core.hooksPath .githooks\nfor d in .skillshare/skills/*/; do mkdir -p ".claude/skills/$(basename "$d")"; done\n')
    SKIP = "--skip=git,python,godot,skillshare,venv,weights"

    def setUp(self):
        super().setUp()
        subprocess.run(["git", "init", "-q", str(self.tree)], check=True, capture_output=True)
        for skill in ("demo", "other"):
            (self.tree / ".skillshare" / "skills" / skill).mkdir(parents=True)
        stub = self.tree / "tools" / "install_hooks.sh"
        stub.write_text(self.STUB, newline="\n")
        stub.chmod(0o755)

    def test_hooks_are_installed_once_and_then_up_to_date(self):
        def check(r):
            subprocess.run(["git", "-C", str(self.tree), "config", "--unset", "core.hooksPath"], capture_output=True)
            shutil.rmtree(self.tree / ".claude", ignore_errors=True)
            check = r.run(["--check", "--skip=git,python,godot,skillshare,venv,weights"], self.env())
            self.assertEqual(check.returncode, 1, check.stdout)
            self.assertRegex(step_lines(check.stdout)["hooks"], r"^missing")
            run = r.run(["--skip=git,python,godot,skillshare,venv,weights"], self.env())
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertRegex(step_lines(run.stdout)["hooks"], r"^installed")
            again = r.run(["--skip=git,python,godot,skillshare,venv,weights"], self.env())
            self.assertRegex(step_lines(again.stdout)["hooks"], r"^up to date")
            self.assertIn("0 installed", again.stdout)
        self.each(check)

    def test_one_skill_not_linked_is_not_up_to_date(self):
        # An entry in .claude/skills is not enough: every skill under .skillshare/skills has to be linked.
        def check(r):
            self.assertEqual(r.run([self.SKIP], self.env()).returncode, 0)
            shutil.rmtree(self.tree / ".claude" / "skills" / "other")
            (self.tree / ".claude" / "skills" / "stale").mkdir()
            out = r.run(["--check", self.SKIP], self.env())
            self.assertEqual(out.returncode, 1, out.stdout)
            self.assertRegex(step_lines(out.stdout)["hooks"], r"^missing .*a skill is not linked")
        self.each(check, ps=False)

    def test_an_install_that_leaves_a_skill_unlinked_fails_the_step(self):
        stub = self.tree / "tools" / "install_hooks.sh"
        stub.write_text('#!/usr/bin/env bash\ncd "$(dirname "$0")/.."\ngit config core.hooksPath .githooks\n'
                        'mkdir -p .claude/skills/demo\n', newline="\n")

        def check(r):
            shutil.rmtree(self.tree / ".claude", ignore_errors=True)
            out = r.run([self.SKIP], self.env())
            self.assertEqual(out.returncode, 1, out.stdout)
            self.assertRegex(out.stdout, r"hooks: FAILED: .*not every skill")
        self.each(check, ps=False)


class ManifestUseTests(unittest.TestCase):
    def test_every_step_reads_its_pins_from_the_manifest(self):
        text = {p: (SETUP / p).read_text() for p in ("bootstrap.sh", "bootstrap.ps1")}
        for key in ("GODOT_VERSION", "GODOT_BASE_URL", "GODOT_WIN64_SHA512", "GODOT_MACOS_SHA512", "VON_PYTHON",
                    "VON_SDK_VERSION", "VON_WEIGHTS_REPO", "VON_WEIGHTS_REVISION", "SKILLSHARE_VERSION"):
            self.assertIn(key, manifest())
            self.assertTrue(any(key in t for t in text.values()), key)
        pins = [manifest()["GODOT_VERSION"], manifest()["VON_SDK_VERSION"], manifest()["VON_WEIGHTS_REVISION"],
                manifest()["SKILLSHARE_VERSION"]]
        for name, t in text.items():
            for pin in pins:
                self.assertNotIn(pin, t, f"{name} must read {pin} from versions.env, not repeat it")

    def test_the_scripts_are_ascii_and_the_shell_one_has_lf_endings(self):
        for p in ("bootstrap.sh", "bootstrap.ps1"):
            data = (SETUP / p).read_bytes()
            data.decode("ascii")  # Windows PowerShell 5.1 reads a BOM-less script as ANSI
        self.assertNotIn(b"\r", (SETUP / "bootstrap.sh").read_bytes())


if __name__ == "__main__":
    unittest.main()
