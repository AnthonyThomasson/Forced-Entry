"""tools/setup/: the manifest (versions.env), the per-user root and the Godot and Python lookups the scripts share
(lib.sh for bash, fe_env.py for Python, lib.ps1 for Windows PowerShell), and the Herdr buttons' wrapper
(godot_open.*).

Each lookup runs in a child process with an environment the test builds: a temp folder as the per-user root
(FORCED_ENTRY_HOME), as %LOCALAPPDATA% or as HOME, fake `godot` / `python3` / `py` / `uname` scripts first on PATH, and
the real PATH with every folder that holds a Godot or a Python taken out. So the real machine's Godot never answers
for a lookup under test. bash and Python must answer alike (the scenarios run through both); PowerShell's lib.ps1 is
checked on Windows only.

NoCopiesTests keeps the lookups single: no script or test helper carries its own `command -v godot || ... /Applications`
line or a bare `python3` command any more.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SETUP = ROOT / "tools" / "setup"
WINDOWS = sys.platform == "win32"
MACOS = sys.platform == "darwin"
BASH = shutil.which("bash")

# A fake program: a script the child finds on PATH. On Windows a file with no extension and a shebang is what Git Bash runs.
FAKE_ECHO = "#!/usr/bin/env bash\necho fake \"$@\"\n"


def write_exe(path: Path, text: str = FAKE_ECHO) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, newline="\n")
    path.chmod(0o755)
    return path


def path_without(*names: str, front: tuple[Path, ...] = ()) -> str:
    """The real PATH without the folders that hold any of `names`, `front` folders first."""
    kept = [d for d in os.environ.get("PATH", "").split(os.pathsep)
            if d and not any(shutil.which(n, path=d) for n in names)]
    return os.pathsep.join([str(f) for f in front] + kept)


def child_env(**over) -> dict:
    env = {k: v for k, v in os.environ.items()
           if not k.startswith("GIT_") and k not in ("GODOT", "PYTHON", "FORCED_ENTRY_HOME")}
    for k, v in over.items():
        if v is None:
            env.pop(k, None)
        else:
            env[k] = v
    return env


def bash(snippet: str, env: dict) -> subprocess.CompletedProcess:
    """`source tools/setup/lib.sh; <snippet>` in bash."""
    return subprocess.run([BASH, "-c", f'source "{SETUP.as_posix()}/lib.sh"; {snippet}'], env=env, capture_output=True,
                          text=True, timeout=60)


def native(path: str, env: dict) -> str:
    """A path bash printed, as this OS writes it (Windows: /c/x becomes C:\\x), for comparing with Python's."""
    if not path or not WINDOWS:
        return path
    return subprocess.run([BASH, "-c", 'cygpath -w "$1"', "_", path], env=env, capture_output=True, text=True).stdout.strip()


def py_call(expr: str, env: dict) -> str:
    code = f"import sys; sys.path.insert(0, {str(ROOT)!r}); from tools.setup import fe_env; print({expr})"
    r = subprocess.run([sys.executable, "-I", "-c", code], env=env, capture_output=True, text=True, timeout=60)
    assert r.returncode == 0, r.stderr
    return r.stdout.strip()


def same(a: str, b: str) -> bool:
    return os.path.normcase(os.path.normpath(a)) == os.path.normcase(os.path.normpath(b))


class Scratch(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="setup_resolvers."))
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.home = self.tmp / "home"          # FORCED_ENTRY_HOME
        self.bin = self.tmp / "bin"            # fakes, first on PATH
        self.bin.mkdir()
        self.version = py_call("fe_env.manifest()['GODOT_VERSION']", child_env())

    def godot_env(self, **over) -> dict:
        """No real Godot findable: PATH without one, per-user root and the OS places under the temp folder."""
        base = dict(FORCED_ENTRY_HOME=str(self.home), PATH=path_without("godot", "godot4", front=(self.bin,)),
                    LOCALAPPDATA=str(self.tmp / "local"), PROGRAMFILES=str(self.tmp / "pf"), HOME=str(self.tmp / "h"),
                    USERPROFILE=str(self.tmp / "h"), XDG_DATA_HOME=str(self.tmp / "xdg"))
        base.update(over)
        return child_env(**base)

    def find_godot(self, **over) -> dict:
        """What bash and Python each find for this environment ('' for none)."""
        env = self.godot_env(**over)
        r = bash("fe_find_godot", env)
        found_bash = native(r.stdout.strip(), env) if r.returncode == 0 else ""
        return {"bash": found_bash, "python": py_call("fe_env.find_godot() or ''", env)}

    def assert_found(self, expected: Path, **over) -> None:
        found = self.find_godot(**over)
        for impl, got in found.items():
            self.assertTrue(same(got, str(expected)), f"{impl} found {got!r}, expected {expected}")


class ManifestTests(Scratch):
    def values(self) -> dict:
        return dict(line.split("=", 1) for line in (SETUP / "versions.env").read_text().splitlines()
                    if line and not line.startswith("#"))

    def test_it_pins_what_the_setup_installs(self):
        v = self.values()
        self.assertRegex(v["GODOT_VERSION"], r"^4\.4\.\d+-stable$")
        for key in ("GODOT_WIN64_ZIP", "GODOT_MACOS_ZIP"):
            self.assertIn(v["GODOT_VERSION"].replace("-stable", ""), v[key])
        for key in ("GODOT_WIN64_SHA512", "GODOT_MACOS_SHA512"):
            self.assertRegex(v[key], r"^[0-9a-f]{128}$")
        self.assertTrue(v["GODOT_BASE_URL"].startswith("https://github.com/godotengine/godot/releases/download/"))
        self.assertNotIn("mono", v["GODOT_WIN64_ZIP"] + v["GODOT_MACOS_ZIP"])  # the standard build: the project has no C#
        self.assertEqual(v["PYTHON_MIN"], "3.12")
        self.assertEqual(v["VON_SDK_VERSION"], "1.3.1")
        self.assertEqual(v["VON_WEIGHTS_REPO"], "wfzyx/von")
        self.assertRegex(v["VON_WEIGHTS_REVISION"], r"^[0-9a-f]{40}$")
        self.assertRegex(v["SKILLSHARE_VERSION"], r"^\d+\.\d+\.\d+$")

    def test_it_is_plain_key_value_lines(self):
        for line in (SETUP / "versions.env").read_text().splitlines():
            if line and not line.startswith("#"):
                self.assertRegex(line, r"^[A-Z0-9_]+=[^\s'\"$`]+$", line)

    def test_bash_and_python_read_every_key_alike(self):
        env = child_env()
        for key, value in self.values().items():
            with self.subTest(key=key):
                self.assertEqual(bash(f"fe_manifest_get {key}", env).stdout.strip(), value)
                self.assertEqual(py_call(f"fe_env.manifest()[{key!r}]", env), value)

    def test_bash_says_so_for_a_key_it_lacks(self):
        r = bash("fe_manifest_get NO_SUCH_KEY", child_env())
        self.assertEqual((r.returncode, r.stdout), (1, ""))

    @unittest.skipUnless(WINDOWS, "Windows PowerShell 5.1 only exists on Windows")
    def test_powershell_reads_it_too(self):
        r = subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command",
                            f". '{SETUP / 'lib.ps1'}'; $m = Get-FeManifest; $m['GODOT_VERSION']; $m['VON_WEIGHTS_REVISION']"],
                           env=child_env(), capture_output=True, text=True, timeout=120)
        v = self.values()
        self.assertEqual(r.stdout.split(), [v["GODOT_VERSION"], v["VON_WEIGHTS_REVISION"]], r.stderr)


class HomeTests(Scratch):
    def test_forced_entry_home_overrides_everything(self):
        env = child_env(FORCED_ENTRY_HOME=str(self.home))
        got = {"bash": native(bash("fe_home", env).stdout.strip(), env), "python": py_call("fe_env.home()", env)}
        for impl, path in got.items():
            self.assertTrue(same(path, str(self.home)), f"{impl}: {path}")
        self.assertTrue(same(py_call("fe_env.von_home()", env), str(self.home / "von")))
        self.assertTrue(same(py_call("fe_env.godot_dir()", env), str(self.home / "godot" / self.version)))
        self.assertTrue(same(py_call("fe_env.godot_dir('9.9-stable')", env), str(self.home / "godot" / "9.9-stable")))
        self.assertTrue(same(native(bash("fe_von_home", env).stdout.strip(), env), str(self.home / "von")))
        self.assertTrue(same(native(bash("fe_godot_dir", env).stdout.strip(), env), str(self.home / "godot" / self.version)))
        self.assertTrue(same(native(bash("fe_godot_dir 9.9-stable", env).stdout.strip(), env),
                             str(self.home / "godot" / "9.9-stable")))

    @unittest.skipUnless(WINDOWS, "the %LOCALAPPDATA% root is Windows'")
    def test_windows_default_is_local_app_data(self):
        env = child_env(FORCED_ENTRY_HOME=None, LOCALAPPDATA=str(self.tmp / "local"))
        self.assertTrue(same(py_call("fe_env.home()", env), str(self.tmp / "local" / "Forced-Entry")))
        self.assertTrue(same(native(bash("fe_home", env).stdout.strip(), env), str(self.tmp / "local" / "Forced-Entry")))

    def test_macos_default_is_application_support(self):
        write_exe(self.bin / "uname", "#!/usr/bin/env bash\necho Darwin\n")
        env = child_env(FORCED_ENTRY_HOME=None, HOME=str(self.tmp / "h"), PATH=path_without("uname", front=(self.bin,)) + os.pathsep
                        + os.environ["PATH"])
        want = self.tmp / "h" / "Library" / "Application Support" / "Forced-Entry"
        out = bash("fe_os; fe_home", env).stdout.split("\n")
        self.assertEqual(out[0], "macos")
        self.assertEqual(out[1], want.as_posix() if not WINDOWS else out[1])
        if not WINDOWS:
            self.assertEqual(out[1], str(want))


class GodotTests(Scratch):
    def test_the_godot_variable_wins_over_everything(self):
        write_exe(self.bin / "godot")
        found = self.find_godot(GODOT=str(self.tmp / "mine" / "Godot"))
        self.assertEqual(found["python"], str(self.tmp / "mine" / "Godot"))
        self.assertEqual(found["bash"], str(self.tmp / "mine" / "Godot").replace("\\", "/") if not WINDOWS else found["bash"])

    def test_path_comes_before_the_install_folder(self):
        if WINDOWS:  # only a .exe is on PATH to both bash and Python: any executable will do for a lookup
            on_path = self.bin / "godot4.exe"
            shutil.copy2(sys.executable, on_path)
        else:
            on_path = write_exe(self.bin / "godot4")
        write_exe(self.home / "godot" / self.version / "Godot_v4_win64_console.exe")
        found = self.find_godot()
        for impl, got in found.items():
            self.assertTrue(same(str(Path(got).parent), str(on_path.parent)), f"{impl}: {got}")
            self.assertEqual(Path(got).stem, "godot4", f"{impl}: {got}")

    def test_the_install_folder_a_windows_zip_unpacks_to_prefers_the_console_exe(self):
        folder = self.home / "godot" / self.version
        write_exe(folder / "Godot_v4.4.1-stable_win64.exe")
        console = write_exe(folder / "Godot_v4.4.1-stable_win64_console.exe")
        self.assert_found(console)

    def test_the_install_folder_a_mac_zip_unpacks_to(self):
        binary = write_exe(self.home / "godot" / self.version / "Godot.app" / "Contents" / "MacOS" / "Godot")
        self.assert_found(binary)

    def test_another_version_in_the_install_folder_is_not_used(self):
        # /Applications is the one place the lookups search that the test's environment cannot move.
        apps = list(Path("/Applications").glob("Godot*.app/Contents/MacOS/Godot")) if MACOS else []
        if apps:
            self.skipTest(f"this Mac has a Godot of its own, which the lookups rightly answer with: {apps[0]}")
        write_exe(self.home / "godot" / "3.0-stable" / "Godot_v3_win64_console.exe")
        for impl, got in self.find_godot().items():
            if not got:
                continue
            # Only a machine-wide Godot (none is let through to this environment) could answer.
            self.fail(f"{impl} found {got!r}")

    @unittest.skipUnless(WINDOWS, "Windows install folders")
    def test_windows_programs_folder_of_the_user(self):
        # (Program Files is not tested: Windows hands every process its own %PROGRAMFILES%, whatever the test sets.)
        local = write_exe(self.tmp / "local" / "Programs" / "Godot" / "Godot_v4.4.1-stable_win64_console.exe")
        self.assert_found(local)

    def test_macos_user_applications_folder_holds_mono_or_not(self):
        if MACOS and list(Path("/Applications").glob("Godot*.app")):
            self.skipTest("this Mac's /Applications Godot answers first (as it should)")
        write_exe(self.bin / "uname", "#!/usr/bin/env bash\necho Darwin\n")
        mono = write_exe(self.tmp / "h" / "Applications" / "Godot_mono.app" / "Contents" / "MacOS" / "Godot")
        env = self.godot_env(PATH=path_without("godot", "godot4", "uname", front=(self.bin,)) + os.pathsep + os.environ["PATH"])
        got = bash("fe_find_godot", env).stdout.strip()
        self.assertTrue(got.endswith("Godot_mono.app/Contents/MacOS/Godot"), got)
        self.assertTrue(same(native(got, env), str(mono)))

    def test_none_found_returns_1_and_fe_use_godot_says_so(self):
        if MACOS and list(Path("/Applications").glob("Godot*.app")):
            self.skipTest("this Mac has a Godot in /Applications")
        found = self.find_godot()
        self.assertEqual(found, {"bash": "", "python": ""})
        r = bash("fe_use_godot", self.godot_env())
        self.assertEqual(r.returncode, 2)
        self.assertIn("Godot binary not found", r.stderr)

    def test_fe_use_godot_exports_the_binary(self):
        binary = write_exe(self.home / "godot" / self.version / "Godot_v4_win64_console.exe")
        env = self.godot_env()
        r = bash('fe_use_godot && bash -c \'echo "$GODOT"\'', env)
        self.assertTrue(same(native(r.stdout.strip(), env), str(binary)), r.stdout + r.stderr)

    @unittest.skipUnless(WINDOWS, "Windows PowerShell 5.1 only exists on Windows")
    def test_powershell_finds_the_same_godot(self):
        console = write_exe(self.home / "godot" / self.version / "Godot_v4.4.1-stable_win64_console.exe")
        env = self.godot_env()
        r = subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command",
                            f". '{SETUP / 'lib.ps1'}'; Find-FeGodot; Get-FeHome; Get-FeVonHome"],
                           env=env, capture_output=True, text=True, timeout=120)
        found, home, von = r.stdout.split("\n")[:3]
        self.assertTrue(same(found.strip(), str(console)), r.stdout + r.stderr)
        self.assertTrue(same(home.strip(), str(self.home)))
        self.assertTrue(same(von.strip(), str(self.home / "von")))


class PythonTests(Scratch):
    """fe_find_python's order: $PYTHON, python3.14/3.13/3.12 (PATH, then Homebrew's folders), python3, py -3, python,
    each only if it runs and is PYTHON_MIN (3.12) or newer. PATH is the fakes plus the folders of `tr`, `uname`, `cygpath`
    (all it runs) and `bash` (a fake's `env bash` looks for it; macOS keeps it in /bin), so only a fake answers; FE_PYTHON_EXTRA_DIRS (Homebrew's folders) is a folder of the test's own."""

    def env(self, **over) -> dict:
        tools = {Path(shutil.which(n)).parent for n in ("tr", "uname", "bash") if shutil.which(n)}
        # A folder that holds a real Python (macOS's /usr/bin) comes after the fakes, which shadow it.
        path = os.pathsep.join([str(self.bin)] + [str(d) for d in sorted(tools)])
        return child_env(**{"PATH": path, "FE_PYTHON_EXTRA_DIRS": "", **over})

    def fake_python(self, name: str, works: bool, version: str = "3.12", folder: Path | None = None) -> Path:
        """A python that prints `version` for the version probe (as `python -c ...` does) and exits 0, or fails (the Store stub)."""
        body = f"echo {version}\nexit 0\n" if works else "exit 9\n"
        return write_exe((folder or self.bin) / name, "#!/usr/bin/env bash\n" + body)

    def test_the_python_variable_wins(self):
        self.fake_python("python3", True)
        mine = self.fake_python("mypython", True, "3.13", folder=self.tmp / "mine")
        r = bash("fe_find_python", self.env(PYTHON=str(mine)))
        self.assertEqual(r.stdout.strip(), str(mine))

    def test_python3_is_used_when_it_runs(self):
        self.fake_python("python3", True)
        self.fake_python("python", True)
        self.assertEqual(bash("fe_find_python", self.env()).stdout.strip(), "python3")

    def test_a_python3_that_does_not_run_is_skipped_for_py_3(self):
        self.fake_python("python3", False)  # the Microsoft Store stub exits non-zero
        write_exe(self.bin / "py", '#!/usr/bin/env bash\n[[ "$1" == -3 ]] || exit 1\necho "' + Path(sys.executable).as_posix() + '"\n')
        self.fake_python("python", True)
        env = self.env()
        got = bash("fe_find_python", env).stdout.strip()
        self.assertTrue(same(native(got, env), sys.executable), got)

    def test_python_is_the_last_resort(self):
        self.fake_python("python3", False)
        self.fake_python("python", True)
        self.assertEqual(bash("fe_find_python", self.env()).stdout.strip(), "python")

    def test_none_found_returns_1_and_fe_use_python_says_so_with_the_bootstrap_command(self):
        self.fake_python("python3", False)
        env = self.env()
        self.assertEqual(bash("fe_find_python", env).returncode, 1)
        r = bash("fe_use_python", env)
        self.assertEqual(r.returncode, 2)
        self.assertIn("Python >= 3.12 not found; run ", r.stderr)
        self.assertIn("bootstrap.ps1" if WINDOWS else "tools/setup/bootstrap.sh", r.stderr)

    def test_fe_use_python_exports_what_it_found(self):
        self.fake_python("python3", True)
        r = bash('fe_use_python && bash -c \'echo "$PYTHON"\'', self.env())
        self.assertEqual(r.stdout.strip(), "python3")

    # R1: a fresh Mac has only the Command Line Tools' /usr/bin/python3 (3.9), and `brew install python@3.12` adds only
    # python3.12 to the folder Homebrew is in. Every tool of ours needs 3.12 (`str | None`, tomllib ...).
    def test_a_python3_below_the_minimum_is_skipped(self):
        self.fake_python("python3", True, "3.9")
        env = self.env()
        self.assertEqual(bash("fe_find_python", env).returncode, 1)
        r = bash("fe_use_python", env)
        self.assertEqual(r.returncode, 2)
        self.assertIn("Python >= 3.12 not found", r.stderr)

    def test_python3_12_on_path_beats_an_old_python3(self):
        self.fake_python("python3", True, "3.9")
        self.fake_python("python3.12", True, "3.12")
        self.assertEqual(bash("fe_find_python", self.env()).stdout.strip(), "python3.12")

    def test_python3_13_comes_before_python3_12(self):
        self.fake_python("python3.12", True, "3.12")
        self.fake_python("python3.13", True, "3.13")
        self.assertEqual(bash("fe_find_python", self.env()).stdout.strip(), "python3.13")

    def test_homebrews_folder_is_searched_when_it_is_not_on_path(self):
        self.fake_python("python3", True, "3.9")
        brew = self.fake_python("python3.12", True, "3.12", folder=self.tmp / "opt" / "homebrew" / "bin")
        env = self.env(FE_PYTHON_EXTRA_DIRS=f"{(self.tmp / 'nowhere').as_posix()} {brew.parent.as_posix()}")
        self.assertEqual(bash("fe_find_python", env).stdout.strip(), brew.as_posix())

    def test_a_python3_in_homebrews_folder_that_is_new_enough_is_used(self):
        self.fake_python("python3", True, "3.9")
        brew = self.fake_python("python3", True, "3.14", folder=self.tmp / "brew")
        env = self.env(FE_PYTHON_EXTRA_DIRS=brew.parent.as_posix())
        self.assertEqual(bash("fe_find_python", env).stdout.strip(), brew.as_posix())

    def test_a_py_3_that_is_below_the_minimum_is_skipped(self):
        self.fake_python("python3", False)
        old = self.fake_python("oldpython", True, "3.8", folder=self.tmp / "old")
        write_exe(self.bin / "py", '#!/usr/bin/env bash\n[[ "$1" == -3 ]] || exit 1\necho "' + old.as_posix() + '"\n')
        self.assertEqual(bash("fe_find_python", self.env()).returncode, 1)

    def test_the_python_variable_below_the_minimum_warns_and_is_refused(self):
        old = self.fake_python("oldpython", True, "3.9", folder=self.tmp / "old")
        self.fake_python("python3", True, "3.12")  # a good one on PATH is not a fallback for a bad $PYTHON
        env = self.env(PYTHON=str(old))
        r = bash("fe_find_python", env)
        self.assertEqual((r.returncode, r.stdout), (1, ""))
        self.assertIn("is Python 3.9, below the 3.12", r.stderr)
        r = bash("fe_use_python", env)
        self.assertEqual(r.returncode, 2)
        self.assertIn("Python >= 3.12 not found; run ", r.stderr)
        self.assertIn("below the 3.12", r.stderr)

    def test_the_python_variable_that_does_not_run_is_refused(self):
        env = self.env(PYTHON=str(self.tmp / "no" / "python"))
        r = bash("fe_use_python", env)
        self.assertEqual(r.returncode, 2)
        self.assertIn("not a Python that runs", r.stderr)

    def test_a_child_script_does_not_probe_the_python_a_parent_already_checked(self):
        counter = self.tmp / "probes"
        write_exe(self.bin / "python3", f'#!/usr/bin/env bash\necho probe >> "{counter.as_posix()}"\necho 3.12\n')
        r = bash('fe_use_python && bash -c \'source "$0"; fe_use_python\' "' + (SETUP / "lib.sh").as_posix() + '"', self.env())
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(len(counter.read_text().split()), 1, "the second fe_use_python probed it again")

    def test_this_machines_own_lookup_finds_a_python_the_tools_can_run(self):
        # No fakes: the test run itself is on a Python the tools can use.
        r = bash("fe_use_python && \"$PYTHON\" -c 'import sys; print(sys.version_info >= (3, 12))'",
                 child_env(FE_PYTHON_EXTRA_DIRS=None))
        self.assertEqual(r.stdout.strip(), "True", r.stderr)

    @unittest.skipUnless(WINDOWS, "Windows PowerShell 5.1 only exists on Windows")
    def test_powershell_finds_a_python_at_the_minimum_and_names_the_bootstrap_command(self):
        r = subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command",
                            f". '{SETUP / 'lib.ps1'}'; Find-FePython; Get-FeBootstrapCommand; "
                            "Test-FeVersionAtLeast '3.9' '3.12'; Test-FeVersionAtLeast '3.12' '3.12'; "
                            "Test-FeVersionAtLeast '3.15' '3.12'; Test-FeVersionAtLeast '4.0' '3.12'"],
                           env=child_env(), capture_output=True, text=True, timeout=120)
        lines = r.stdout.split("\n")
        found = lines[0].strip()
        self.assertTrue(found and Path(found).is_file(), r.stdout + r.stderr)
        self.assertIn("bootstrap.ps1", lines[1])
        self.assertEqual([x.strip() for x in lines[2:6]], ["False", "True", "True", "True"])

    @unittest.skipUnless(WINDOWS, "Windows PowerShell 5.1 only exists on Windows")
    def test_powershell_refuses_a_python_variable_below_the_minimum(self):
        old = self.tmp / "old" / "oldpython.cmd"
        old.parent.mkdir()
        old.write_text("@echo off\r\necho 3 9\r\n")
        r = subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command",
                            f". '{SETUP / 'lib.ps1'}'; $p = Find-FePython; if ($p) {{ 'FOUND ' + $p }} else {{ 'NONE' }}"],
                           env=child_env(PYTHON=str(old)), capture_output=True, text=True, timeout=120)
        self.assertEqual(r.stdout.strip(), "NONE", r.stdout + r.stderr)
        self.assertIn("below the 3.12", r.stderr)


class GodotOpenTests(Scratch):
    """The wrapper the Herdr buttons run, with a fake Godot that prints its arguments. It runs from a tree of its own
    (the wrapper files and tools/setup), so that whether this checkout has been imported (.godot/) does not matter: a
    tree has the class cache, or not (a fresh clone). Every call of the fake Godot is also noted, one line each."""

    def tree(self, imported: bool = True) -> Path:
        tree = self.tmp / "tree"
        (tree / "tools").mkdir(parents=True)
        for name in ("godot_open.sh", "godot_open.ps1", "godot_open.cmd"):
            shutil.copy2(ROOT / "tools" / name, tree / "tools" / name)
        shutil.copytree(SETUP, tree / "tools" / "setup", ignore=shutil.ignore_patterns("__pycache__"))
        if imported:
            (tree / ".godot").mkdir()
            (tree / ".godot" / "global_script_class_cache.cfg").write_text("")
        return tree

    def fake_godot(self, windows: bool = False) -> Path:
        """Prints `ARGS <arguments>` and notes the same line in the file $FAKE_GODOT_LOG."""
        if windows:
            fake = self.bin / "fakegodot.cmd"
            fake.write_text("@echo ARGS %*\r\n@echo %* >> \"%FAKE_GODOT_LOG%\"\r\n")
            return fake
        return write_exe(self.bin / "fakegodot", '#!/usr/bin/env bash\necho "ARGS $*"\necho "$*" >> "$FAKE_GODOT_LOG"\n')

    def calls(self) -> list[str]:
        log = self.tmp / "godot_calls.txt"
        return [line.strip() for line in log.read_text().splitlines()] if log.exists() else []

    def env(self, fake: Path, **over) -> dict:
        return child_env(GODOT=str(fake), FAKE_GODOT_LOG=str(self.tmp / "godot_calls.txt"), **over)

    def test_bash_wrapper_edits_or_plays_this_checkout(self):
        tree = self.tree()
        env = self.env(self.fake_godot())
        for args, flags in (([], ""), (["--editor"], "--editor ")):
            r = subprocess.run([BASH, str(tree / "tools" / "godot_open.sh"), *args], env=env, capture_output=True, text=True,
                               timeout=60)
            self.assertEqual(r.returncode, 0, r.stderr)
            line = r.stdout.strip()
            self.assertTrue(line.startswith("ARGS " + flags + "--path "), line)
            self.assertTrue(same(native(line.split("--path ", 1)[1], env), str(tree)), line)
        self.assertEqual(len(self.calls()), 2, "an imported checkout is not imported again")

    def test_bash_wrapper_imports_a_fresh_clone_before_playing(self):
        tree = self.tree(imported=False)
        r = subprocess.run([BASH, str(tree / "tools" / "godot_open.sh")], env=self.env(self.fake_godot()), capture_output=True,
                           text=True, timeout=60)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("importing the project (first run)...", r.stdout)
        calls = self.calls()
        self.assertEqual(len(calls), 2, calls)
        self.assertTrue(calls[0].startswith("--headless --path ") and calls[0].endswith(" --import"), calls[0])
        self.assertTrue(calls[1].startswith("--path ") and "--import" not in calls[1], calls[1])
        self.assertTrue(r.stdout.strip().endswith("ARGS " + calls[1]), r.stdout)

    def test_bash_wrapper_goes_on_when_the_import_fails(self):
        tree = self.tree(imported=False)
        fake = write_exe(self.bin / "fakegodot", '#!/usr/bin/env bash\necho "$*" >> "$FAKE_GODOT_LOG"\n'
                         '[[ " $* " == *" --import "* ]] && exit 3\necho "ARGS $*"\n')
        r = subprocess.run([BASH, str(tree / "tools" / "godot_open.sh")], env=self.env(fake), capture_output=True, text=True,
                           timeout=60)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(len(self.calls()), 2)

    def test_bash_wrapper_does_not_import_before_the_editor(self):
        # The editor imports by itself on opening.
        tree = self.tree(imported=False)
        r = subprocess.run([BASH, str(tree / "tools" / "godot_open.sh"), "--editor"], env=self.env(self.fake_godot()),
                           capture_output=True, text=True, timeout=60)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(len(self.calls()), 1, self.calls())
        self.assertNotIn("importing", r.stdout)

    def test_bash_wrapper_without_a_godot_fails_with_a_message_naming_the_bootstrap(self):
        if MACOS and list(Path("/Applications").glob("Godot*.app")):
            self.skipTest("this Mac has a Godot in /Applications")
        r = subprocess.run([BASH, str(self.tree() / "tools" / "godot_open.sh")], env=self.godot_env(), capture_output=True,
                           text=True, timeout=60)
        self.assertEqual(r.returncode, 2)
        self.assertIn("Godot binary not found", r.stderr)
        self.assertIn("bootstrap.ps1" if WINDOWS else "tools/setup/bootstrap.sh", r.stderr)

    def test_the_cmd_file_hands_over_to_bash_in_a_posix_shell(self):
        tree = self.tree()
        r = subprocess.run([BASH, str(tree / "tools" / "godot_open.cmd"), "--editor"], env=self.env(self.fake_godot()),
                           capture_output=True, text=True, timeout=60)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(r.stdout.startswith("ARGS --editor --path "), r.stdout)

    @unittest.skipUnless(WINDOWS, "cmd.exe and Windows PowerShell only exist on Windows")
    def test_the_cmd_file_hands_over_to_powershell_in_cmd_exe(self):
        tree = self.tree()
        env = self.env(self.fake_godot(windows=True))
        for args, flags in (([], ""), (["--editor"], "--editor ")):
            r = subprocess.run(["cmd", "/c", str(tree / "tools" / "godot_open.cmd"), *args], env=env,
                               capture_output=True, text=True, timeout=120)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertTrue(r.stdout.strip().startswith("ARGS " + flags + "--path "), r.stdout)
        self.assertEqual(len(self.calls()), 2, "an imported checkout is not imported again")

    @unittest.skipUnless(WINDOWS, "cmd.exe and Windows PowerShell only exist on Windows")
    def test_powershell_imports_a_fresh_clone_before_playing_and_not_before_the_editor(self):
        tree = self.tree(imported=False)
        env = self.env(self.fake_godot(windows=True))
        r = subprocess.run(["cmd", "/c", str(tree / "tools" / "godot_open.cmd")], env=env, capture_output=True, text=True,
                           timeout=120)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("importing the project (first run)...", r.stdout)
        calls = self.calls()
        self.assertEqual(len(calls), 2, calls)
        self.assertTrue(calls[0].startswith("--headless --path ") and calls[0].endswith(" --import"), calls[0])
        self.assertTrue(calls[1].startswith("--path ") and "--import" not in calls[1], calls[1])
        (self.tmp / "godot_calls.txt").unlink()
        r = subprocess.run(["cmd", "/c", str(tree / "tools" / "godot_open.cmd"), "--editor"], env=env, capture_output=True,
                           text=True, timeout=120)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(len(self.calls()), 1, self.calls())
        self.assertNotIn("importing", r.stdout)

    @unittest.skipUnless(WINDOWS, "cmd.exe and Windows PowerShell only exist on Windows")
    def test_the_cmd_file_without_a_godot_exits_2_in_cmd_exe_naming_the_bootstrap(self):
        r = subprocess.run(["cmd", "/c", str(self.tree() / "tools" / "godot_open.cmd")], env=self.godot_env(),
                           capture_output=True, text=True, timeout=120)
        self.assertEqual(r.returncode, 2)
        self.assertIn("Godot binary not found", r.stderr)
        self.assertIn("tools\\setup\\bootstrap.ps1", r.stderr)

    def test_the_herdr_buttons_run_it(self):
        config = (ROOT / ".herdr" / "config.yaml").read_text()
        self.assertEqual(re.findall(r"command: (.*)", config), ["./tools/godot_open.cmd --editor", "./tools/godot_open.cmd"])


class NoCopiesTests(unittest.TestCase):
    """The lookups live in tools/setup/ only."""

    SKIP = {"lib.sh", "fe_env.py", "lib.ps1", "test_setup_resolvers.py"}

    def files(self, *patterns: str):
        for pattern in patterns:
            for path in sorted(ROOT.glob(pattern)):
                if path.is_file() and path.name not in self.SKIP and "fixtures" not in path.parts[:-1] or \
                        path.name == "run_tests.sh":
                    yield path

    def test_no_script_names_a_godot_install_place(self):
        for path in self.files("tools/*.sh", "tools/**/*.py", ".githooks/*", "tools/coverage/tests/fixtures/project/tools/*.sh",
                               ".skillshare/skills/godot-run/SKILL.md", "tools/coverage/README.md"):
            self.assertNotIn("/Applications/Godot", path.read_text(encoding="utf-8"), str(path.relative_to(ROOT)))

    def test_no_script_runs_a_bare_python3(self):
        # A comment or a docstring may show `python3 tools/x.py` as a user's command; a script of ours must not run one.
        for path in self.files("tools/*.sh", ".githooks/*", "tools/coverage/tests/fixtures/project/tools/*.sh"):
            for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                if not line.lstrip().startswith("#") and re.search(r"\bpython3\b", line):
                    self.fail(f"{path.relative_to(ROOT)}:{n} runs python3: {line.strip()}")

    def test_the_scripts_that_run_python_resolve_it_first(self):
        for path in self.files("tools/*.sh", ".githooks/*"):
            text = path.read_text(encoding="utf-8")
            if '"$PYTHON"' in text:
                self.assertIn("fe_use_python", text, str(path.relative_to(ROOT)))


if __name__ == "__main__":
    unittest.main()
