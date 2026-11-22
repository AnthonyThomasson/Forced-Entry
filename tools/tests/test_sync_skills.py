"""tools/sync_skills.sh and .githooks/post-checkout, run in a repo of their own with a fake skillshare."""
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "sync_skills.sh"
HOOK = ROOT / ".githooks" / "post-checkout"
BASE_PATH = "/usr/bin:/bin"
WINDOWS = sys.platform == "win32"
BASH = shutil.which("bash") or "bash"


def search_path(front: Path) -> str:
    """PATH for the script's child: `front` first, then the system's bash tools. A Windows path list is ';'-separated (bash
    reads it as one), made of the folders of the Git for Windows that holds bash."""
    if not WINDOWS:
        return f"{front}:{BASE_PATH}"
    git = Path(BASH).resolve().parent
    return os.pathsep.join([str(front), str(git), str(git.parent / "usr" / "bin"), str(git.parent / "mingw64" / "bin")])


class SyncSkillsTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.repo = Path(tmp.name) / "repo"
        self.home = Path(tmp.name) / "home"
        self.bin = Path(tmp.name) / "bin"
        self.log = Path(tmp.name) / "calls"
        for folder in (self.repo / "tools", self.repo / ".githooks", self.home, self.bin):
            folder.mkdir(parents=True)
        shutil.copy2(SCRIPT, self.repo / "tools" / "sync_skills.sh")
        shutil.copy2(HOOK, self.repo / ".githooks" / "post-checkout")

    def fake_skillshare(self, folder: Path, status: int = 0):
        folder.mkdir(parents=True, exist_ok=True)
        fake = folder / "skillshare"
        fake.write_text(f'#!/bin/sh\necho "$PWD $*" >> "{self.log}"\nexit {status}\n')
        fake.chmod(fake.stat().st_mode | stat.S_IEXEC)

    def run_in_repo(self, *command: str) -> subprocess.CompletedProcess:
        env = {"PATH": search_path(self.bin), "HOME": str(self.home)}
        if WINDOWS:
            env["SYSTEMROOT"] = os.environ.get("SYSTEMROOT", r"C:\Windows")  # Windows will not start a process without it
            command = (BASH, *command)  # Windows runs no shebang
        return subprocess.run(command, cwd=self.repo, env=env, capture_output=True, text=True, timeout=30)

    def calls(self) -> list[str]:
        return self.log.read_text().splitlines() if self.log.exists() else []

    def test_it_syncs_the_project_from_the_repo_root(self):
        self.fake_skillshare(self.bin)
        r = self.run_in_repo("tools/sync_skills.sh")
        self.assertEqual(r.returncode, 0, r.stderr)
        # $PWD as bash prints it: the folder itself, but on Windows an MSYS path (/tmp/... for the temp folder)
        calls = self.calls()
        self.assertEqual(len(calls), 1)
        if WINDOWS:
            self.assertTrue(calls[0].endswith(f"/{self.repo.parent.name}/repo sync -p --quiet"), calls)
        else:
            self.assertEqual(calls, [f"{os.path.realpath(self.repo)} sync -p --quiet"])

    def test_it_falls_back_to_the_go_bin_folder(self):
        self.fake_skillshare(self.home / "go" / "bin")
        r = self.run_in_repo("tools/sync_skills.sh")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(len(self.calls()), 1)

    def test_without_the_cli_it_fails_naming_where_to_get_it(self):
        r = self.run_in_repo("tools/sync_skills.sh")
        self.assertEqual(r.returncode, 1)
        self.assertIn("github.com/runkids/skillshare", r.stderr)

    @unittest.skipUnless(sys.platform == "win32", "the install folder of skillshare's Windows installer")
    def test_it_finds_the_windows_install_folder(self):
        local = Path(self.home) / "AppData" / "Local"
        self.fake_skillshare(local / "Programs" / "skillshare")
        (local / "Programs" / "skillshare" / "skillshare").rename(local / "Programs" / "skillshare" / "skillshare.exe")
        env = {"PATH": search_path(self.bin), "HOME": str(self.home), "LOCALAPPDATA": str(local),
               "SYSTEMROOT": os.environ["SYSTEMROOT"]}
        r = subprocess.run([BASH, "tools/sync_skills.sh"], cwd=self.repo, env=env, capture_output=True, text=True, timeout=30)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(len(self.calls()), 1)

    def test_it_finds_the_skillshare_the_bootstrap_installs_in_the_setups_own_bin(self):
        shutil.copytree(ROOT / "tools" / "setup", self.repo / "tools" / "setup", ignore=shutil.ignore_patterns("__pycache__"))
        fe_home = Path(self.home) / "fe-home"
        self.fake_skillshare(fe_home / "bin")
        env = {"PATH": search_path(self.bin), "HOME": str(self.home), "FORCED_ENTRY_HOME": str(fe_home)}
        if WINDOWS:
            env["SYSTEMROOT"] = os.environ["SYSTEMROOT"]
        r = subprocess.run([*((BASH,) if WINDOWS else ()), "tools/sync_skills.sh"], cwd=self.repo, env=env,
                           capture_output=True, text=True, timeout=30)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(len(self.calls()), 1)

    def test_the_copy_mode_copies_every_skill_and_needs_no_skillshare(self):
        skills = self.repo / ".skillshare" / "skills"
        for name in ("alpha", "beta"):
            (skills / name).mkdir(parents=True)
            (skills / name / "SKILL.md").write_text(f"# {name}")
        r = self.run_in_repo("tools/sync_skills.sh", "--mode", "copy")
        self.assertEqual(r.returncode, 0, r.stderr)
        for name in ("alpha", "beta"):
            copy = self.repo / ".claude" / "skills" / name
            self.assertFalse(copy.is_symlink())
            self.assertEqual((copy / "SKILL.md").read_text(), f"# {name}")
        self.assertEqual(self.calls(), [], "skillshare was not run")

    def test_the_copy_mode_replaces_an_earlier_copy_without_touching_the_source(self):
        source = self.repo / ".skillshare" / "skills" / "alpha"
        source.mkdir(parents=True)
        (source / "SKILL.md").write_text("new")
        stale = self.repo / ".claude" / "skills" / "alpha"
        stale.mkdir(parents=True)
        (stale / "SKILL.md").write_text("old")
        (stale / "gone.md").write_text("removed skill file")
        self.assertEqual(self.run_in_repo("tools/sync_skills.sh", "--mode=copy").returncode, 0)
        self.assertEqual((stale / "SKILL.md").read_text(), "new")
        self.assertFalse((stale / "gone.md").exists())
        self.assertEqual((source / "SKILL.md").read_text(), "new")

    def test_an_unknown_argument_is_a_usage_error(self):
        self.assertEqual(self.run_in_repo("tools/sync_skills.sh", "--wat").returncode, 2)

    def test_a_failed_sync_fails_the_script(self):
        self.fake_skillshare(self.bin, status=3)
        self.assertEqual(self.run_in_repo("tools/sync_skills.sh").returncode, 3)

    def test_the_hook_syncs_on_a_branch_checkout(self):
        self.fake_skillshare(self.bin)
        r = self.run_in_repo(".githooks/post-checkout", "a", "b", "1")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(len(self.calls()), 1)

    def test_the_hook_skips_a_file_checkout(self):
        self.fake_skillshare(self.bin)
        self.assertEqual(self.run_in_repo(".githooks/post-checkout", "a", "b", "0").returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_the_hook_only_warns_when_the_sync_fails(self):
        r = self.run_in_repo(".githooks/post-checkout", "a", "b", "1")
        self.assertEqual(r.returncode, 0)
        self.assertIn("warning: tools/sync_skills.sh failed", r.stderr)

    def test_the_hook_passes_on_a_commit_without_the_script(self):
        (self.repo / "tools" / "sync_skills.sh").unlink()
        self.assertEqual(self.run_in_repo(".githooks/post-checkout", "a", "b", "1").returncode, 0)


if __name__ == "__main__":
    unittest.main()
