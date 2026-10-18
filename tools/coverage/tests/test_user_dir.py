"""A coverage run never writes the developer's Godot user:// folder: the instrumented copy has a user:// of its own
(instrument.py sets `application/config/use_custom_user_dir` and `custom_user_dir_name` in the copy's project.godot,
workspace.user_dir_name), and the run removes it with the copy.

The real game writes user:// as a match starts (Main's `_on_setup_chosen` saves the setup with Settings.set_setup:
user://settings.json; the Von launcher appends to user://von_server.log). The fixture game here does the same: its
`_on_setup_chosen` is given a first line that writes user://settings.json, and the project a name of its own, so
the user:// folder Godot would use without the copy's setting (`app_userdata/<name>`) is known and new.
"""
import os
import shutil
import sys
import unittest
import uuid
from pathlib import Path

from tools.coverage import workspace
from tools.coverage.tests.support import TempDir, fixture_repo, init_repo, needs_godot, newest_run, read_json, run_cli

SETUP_HEADER = "func _on_setup_chosen(config: Dictionary) -> void:\n"
WRITE_SETTINGS = '\tFileAccess.open("user://settings.json", FileAccess.WRITE).store_string("{}")\n'


def godot_data_dir() -> Path:
    """The OS folder Godot keeps user data under (as Godot resolves it)."""
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support"
    if sys.platform.startswith("win"):
        return Path(os.environ.get("APPDATA", Path.home() / "AppData" / "Roaming"))
    return Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local" / "share")


def default_user_dir(project_name: str) -> Path:
    """The user:// Godot gives a project with no custom user dir: <data>/Godot/app_userdata/<name>."""
    godot = "godot" if sys.platform.startswith("linux") else "Godot"
    return godot_data_dir() / godot / "app_userdata" / project_name


def writes_user_dir(name: str):
    """An `edit` for fixture_repo: the project named `name`, and Main writing user://settings.json on setup."""
    def edit(repo: Path) -> None:
        project = repo / "project.godot"
        text = project.read_text()
        assert 'config/name="coverage-fixture"' in text
        project.write_text(text.replace('config/name="coverage-fixture"', f'config/name="{name}"'))
        main = repo / "scenes" / "main.gd"
        text = main.read_text()
        assert SETUP_HEADER in text
        main.write_text(text.replace(SETUP_HEADER, SETUP_HEADER + WRITE_SETTINGS, 1))
    return edit


@needs_godot
class UserDirTests(unittest.TestCase):
    def test_a_run_writes_its_own_user_dir_never_the_real_one_and_removes_it(self):
        name = f"coverage-fixture-userdir-{uuid.uuid4().hex[:12]}"
        real = default_user_dir(name)
        self.addCleanup(shutil.rmtree, real, True)  # only if a broken run created it: a name no one else uses
        copies = godot_data_dir() / workspace.USER_DIRS
        copies_before = set(copies.iterdir()) if copies.is_dir() else set()
        self.assertFalse(real.exists(), real)
        with TempDir() as d:
            repo = fixture_repo(d, writes_user_dir(name))
            r = run_cli(repo, "run", "--matches=1", "--jobs=1", "--seed=100")
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            folder = newest_run(repo, "matches")
            smap, data = read_json(folder / "map.json"), read_json(folder / "hits.json")
        write = [s["id"] for s in smap["statements"] if (s["file"], s["line"]) == ("scenes/main.gd", 27)]
        self.assertEqual(len(write), 1, "one statement on the line that writes user://settings.json")
        self.assertEqual(sum(u["counts"].get(str(write[0]), 0) for u in data["units"]), 1,
                         "the game wrote its user://settings.json during the run")
        self.assertFalse(real.exists(), f"the run wrote the real user dir {real}: {list(real.rglob('*'))}")
        copies_after = set(copies.iterdir()) if copies.is_dir() else set()
        self.assertEqual(copies_after - copies_before, set(), "the copy's own user dir is removed with the copy")


class OrphanTests(unittest.TestCase):
    def test_creating_a_copy_removes_the_user_dirs_of_copies_deleted_by_hand(self):
        """A copy `coverage.py instrument` printed is deleted by hand, not by cleanup: its user dir (the logs of the
        load check, lint and tests run in it) must not pile up."""
        with TempDir() as d:
            src = d / "src"
            (src / "scenes").mkdir(parents=True)
            (src / "project.godot").write_text("config_version=5\n")
            (src / "scenes" / "main.gd").write_text("extends Node\n")
            init_repo(src)
            live = workspace.create(src)
            self.addCleanup(workspace.cleanup, src, live)
            deleted = workspace.create(src)
            for copy in (live, deleted):
                (workspace.user_dir(copy) / "logs").mkdir(parents=True)
                (workspace.user_dir(copy) / "logs" / "godot.log").write_text("a run in the copy\n")
            shutil.rmtree(deleted)  # by hand: its user dir is left behind
            other = godot_data_dir() / workspace.USER_DIRS / "not-a-copy"
            other.mkdir(parents=True)
            self.addCleanup(shutil.rmtree, other, True)
            third = workspace.create(src)
            self.addCleanup(workspace.cleanup, src, third)
            self.assertFalse(workspace.user_dir(deleted).exists(), "the deleted copy's user dir is swept")
            self.assertTrue((workspace.user_dir(live) / "logs" / "godot.log").is_file(), "a live copy's is kept")
            self.assertTrue(other.is_dir(), "a folder that is not a copy's is left alone")


if __name__ == "__main__":
    unittest.main()
