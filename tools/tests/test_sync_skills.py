"""tools/sync_skills.sh and .githooks/post-checkout, run in a repo of their own with a fake skillshare."""
import os
import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "sync_skills.sh"
HOOK = ROOT / ".githooks" / "post-checkout"
BASE_PATH = "/usr/bin:/bin"


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
        env = {"PATH": f"{self.bin}:{BASE_PATH}", "HOME": str(self.home)}
        return subprocess.run(command, cwd=self.repo, env=env, capture_output=True, text=True, timeout=30)

    def calls(self) -> list[str]:
        return self.log.read_text().splitlines() if self.log.exists() else []

    def test_it_syncs_the_project_from_the_repo_root(self):
        self.fake_skillshare(self.bin)
        r = self.run_in_repo("tools/sync_skills.sh")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.calls(), [f"{os.path.realpath(self.repo)} sync -p --quiet"])

    def test_it_falls_back_to_the_go_bin_folder(self):
        self.fake_skillshare(self.home / "go" / "bin")
        r = self.run_in_repo("tools/sync_skills.sh")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(len(self.calls()), 1)

    def test_without_the_cli_it_fails_naming_where_to_get_it(self):
        r = self.run_in_repo("tools/sync_skills.sh")
        self.assertEqual(r.returncode, 1)
        self.assertIn("github.com/runkids/skillshare", r.stderr)

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
