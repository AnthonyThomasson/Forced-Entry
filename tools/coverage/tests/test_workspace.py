"""Tests for tools/coverage/workspace.py: the throwaway copy of the repo, the hit folder, the tree hashes, cleanup and
the sweep of what a killed run left.

  workspace.create(root) -> Path      a fresh folder directly in `root`'s artifacts/tmp/ (artifacts/.gdignore written
                                      first) holding the tracked files, the untracked files git does not ignore, and
                                      `.godot/` (the import cache); nothing else (no ignored file, no `.git`, nothing
                                      of artifacts/ even where git does not ignore it)
  workspace.hits_dir(root) -> Path    a fresh, empty folder directly in `root`'s artifacts/tmp/, for a run's shards
  workspace.copy_env(copy) -> dict    the environment of a process run in a copy: git there finds no repo, never the
                                      one the copy sits in
  workspace.tree_hash(root) -> str    a hash of everything under scenes/ and project.godot (paths and bytes, tracked
                                      or not): equal for byte-identical trees, different after any change there
  workspace.git_status(root) -> str   `git status --porcelain` of `root` ("" when clean)
  workspace.keep(folder)              marks a copy or hit folder kept: no sweep removes it
  workspace.cleanup(root, folder)     removes a copy or hit folder of `root` (and artifacts/tmp/ once empty); refuses
                                      (raises, deletes nothing) anything that is not a direct child of `root`'s
                                      artifacts/tmp/ named as the tool names them
  creating a copy or a hit folder first sweeps `root`'s artifacts/tmp/: the folders of a run that is gone (killed
  with SIGKILL), never one whose run is alive, in this process or another, and never a kept one

The source repos here are temp git repos built by the test; expected contents are listed by hand. A leftover is made
for real: a separate Python process creates the folders, and is then killed with SIGKILL (dead owner) or left running
(live owner).
"""
import shutil
import signal
import subprocess
import sys
import unittest
from pathlib import Path

from tools.coverage import workspace
from tools.coverage.tests.support import ROOT, TempDir, clean_env, commit_all, init_repo, tree_digest, git_status


def make_source(root: Path) -> None:
    """A small repo: tracked files, one untracked-but-not-ignored, ignored ones, and a .godot import cache."""
    files = {
        ".gitignore": ".godot/\n*.tmp\nartifacts/\n",
        "project.godot": "config_version=5\n",
        "scenes/main.gd": "extends Node\n",
        "scenes/ai/brain.gd": "extends RefCounted\n",
        "tools/run_tests.sh": "#!/usr/bin/env bash\n",
        "docs/notes.md": "notes\n",
    }
    for rel, text in files.items():
        (root / rel).parent.mkdir(parents=True, exist_ok=True)
        (root / rel).write_text(text)
    init_repo(root)
    (root / "scenes" / "new_untracked.gd").write_text("extends Node\n")
    (root / "scenes" / "junk.tmp").write_text("ignored\n")
    (root / "artifacts" / "coverage").mkdir(parents=True)
    (root / "artifacts" / "coverage" / "old.json").write_text("{}\n")
    (root / ".godot").mkdir()
    (root / ".godot" / "global_script_class_cache.cfg").write_text("list=[]\n")


def listing(root: Path) -> set[str]:
    return {str(p.relative_to(root)) for p in root.rglob("*") if p.is_file()}


class CreateTests(unittest.TestCase):
    def test_copy_holds_tracked_untracked_and_godot_cache_only(self):
        with TempDir() as d:
            src = d / "src"
            src.mkdir()
            make_source(src)
            copy = workspace.create(src)
            try:
                self.assertEqual(listing(copy), {
                    ".gitignore", "project.godot", "scenes/main.gd", "scenes/ai/brain.gd", "tools/run_tests.sh",
                    "docs/notes.md", "scenes/new_untracked.gd", ".godot/global_script_class_cache.cfg",
                })
                self.assertEqual((copy / "scenes" / "main.gd").read_text(), "extends Node\n")
            finally:
                workspace.cleanup(src, copy)

    def test_each_copy_is_a_new_folder_directly_in_the_repos_artifacts_tmp(self):
        with TempDir() as d:
            src = d / "src"
            src.mkdir()
            make_source(src)
            first = workspace.create(src)
            second = workspace.create(src)
            try:
                self.assertNotEqual(first, second)
                for copy in (first, second):
                    self.assertEqual(copy.resolve().parent, (src / "artifacts" / "tmp").resolve())
            finally:
                workspace.cleanup(src, first)
                workspace.cleanup(src, second)

    def test_the_hit_folder_is_a_new_empty_folder_directly_in_the_repos_artifacts_tmp(self):
        with TempDir() as d:
            src = d / "src"
            src.mkdir()
            make_source(src)
            first = workspace.hits_dir(src)
            second = workspace.hits_dir(src)
            try:
                self.assertNotEqual(first, second)
                for folder in (first, second):
                    self.assertEqual(folder.resolve().parent, (src / "artifacts" / "tmp").resolve())
                    self.assertEqual(list(folder.iterdir()), [])
            finally:
                workspace.cleanup(src, first)
                workspace.cleanup(src, second)

    def test_a_fresh_repo_gets_artifacts_gdignore_before_its_first_copy(self):
        with TempDir() as d:
            src = d / "src"
            src.mkdir()
            make_source(src)
            shutil.rmtree(src / "artifacts")
            copy = workspace.create(src)
            try:
                self.assertTrue((src / "artifacts" / ".gdignore").is_file(), "Godot never imports the copy")
            finally:
                workspace.cleanup(src, copy)

    def test_a_copy_holds_nothing_of_artifacts_even_where_git_does_not_ignore_it(self):
        with TempDir() as d:
            src = d / "src"
            src.mkdir()
            make_source(src)
            (src / ".gitignore").write_text(".godot/\n*.tmp\n")
            commit_all(src)
            kept = workspace.create(src)
            workspace.keep(kept)
            (src / "artifacts" / "coverage" / "run").mkdir()
            (src / "artifacts" / "coverage" / "run" / "hits.json").write_text("{}\n")
            copy = workspace.create(src)
            try:
                self.assertFalse((copy / "artifacts").exists(), sorted(listing(copy)))
                self.assertIn("scenes/main.gd", listing(copy))
            finally:
                workspace.cleanup(src, copy)
                workspace.cleanup(src, kept)

    def test_git_in_a_copy_finds_no_repo_never_the_one_it_sits_in(self):
        with TempDir() as d:
            src = d / "src"
            src.mkdir()
            make_source(src)
            copy = workspace.create(src)
            try:
                r = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=copy / "scenes",
                                   env=workspace.copy_env(copy), capture_output=True, text=True)
                self.assertNotEqual(r.returncode, 0, f"git found a repo from the copy: {r.stdout}")
                self.assertIn("not a git repository", r.stderr)
            finally:
                workspace.cleanup(src, copy)

    def test_creating_a_copy_leaves_the_source_untouched(self):
        with TempDir() as d:
            src = d / "src"
            src.mkdir()
            make_source(src)
            def state():
                return (git_status(src), tree_digest(src), workspace.tree_hash(src),
                        {p for p in listing(src) if not p.startswith("artifacts/")})
            before = state()
            copy = workspace.create(src)
            (copy / "scenes" / "main.gd").write_text("changed in the copy only\n")
            try:
                self.assertEqual(state(), before, "the copy sits in the ignored artifacts/; nothing else changed")
            finally:
                workspace.cleanup(src, copy)


class HashTests(unittest.TestCase):
    def setUp(self):
        self._dir = TempDir()
        self.root = self._dir.__enter__() / "src"
        self.root.mkdir()
        make_source(self.root)

    def tearDown(self):
        self._dir.__exit__(None, None, None)

    def test_the_same_tree_hashes_the_same_and_a_copy_hashes_like_its_source(self):
        first = workspace.tree_hash(self.root)
        self.assertEqual(workspace.tree_hash(self.root), first)
        copy = workspace.create(self.root)
        try:
            self.assertEqual(workspace.tree_hash(copy), first)
            self.assertEqual(workspace.tree_hash(self.root), first, "a copy inside the repo hashes nothing of it")
        finally:
            workspace.cleanup(self.root, copy)

    def test_any_change_under_scenes_or_to_project_godot_changes_the_hash(self):
        changes = {
            "a byte in a scene": lambda r: (r / "scenes" / "main.gd").write_text("extends Node2D\n"),
            "project.godot": lambda r: (r / "project.godot").write_text("config_version=5\n\n[autoload]\n"),
            "a new file under scenes": lambda r: (r / "scenes" / "ai" / "extra.gd").write_text(""),
            "a renamed scene": lambda r: (r / "scenes" / "ai" / "brain.gd").rename(r / "scenes" / "ai" / "mind.gd"),
            "a removed scene": lambda r: (r / "scenes" / "main.gd").unlink(),
        }
        for what, change in changes.items():
            with self.subTest(change=what), TempDir() as d:
                root = d / "src"
                root.mkdir()
                make_source(root)
                before = workspace.tree_hash(root)
                change(root)
                self.assertNotEqual(workspace.tree_hash(root), before)

    def test_changes_outside_scenes_and_project_godot_do_not_change_the_hash(self):
        before = workspace.tree_hash(self.root)
        (self.root / "docs" / "notes.md").write_text("rewritten\n")
        (self.root / "tools" / "new.py").write_text("")
        (self.root / ".godot" / "global_script_class_cache.cfg").write_text("list=[1]\n")
        self.assertEqual(workspace.tree_hash(self.root), before)

    def test_git_status_is_empty_when_clean_and_names_a_change(self):
        (self.root / "scenes" / "new_untracked.gd").unlink()
        self.assertEqual(workspace.git_status(self.root).strip(), "")
        (self.root / "scenes" / "main.gd").write_text("extends Node2D\n")
        self.assertIn("scenes/main.gd", workspace.git_status(self.root))
        commit_all(self.root)
        self.assertEqual(workspace.git_status(self.root).strip(), "")


def made_in_another_process(src: Path, alive: bool) -> tuple[Path, Path, subprocess.Popen]:
    """A copy and a hit folder of `src` made by a separate Python process, which is then killed with SIGKILL (a run
    that could not clean up) or, with `alive`, left running (a run still going); returns them and the process."""
    code = ("import sys, time\n"
            "from pathlib import Path\n"
            "from tools.coverage import workspace\n"
            "src = Path(sys.argv[1])\n"
            "print(workspace.create(src), flush=True)\n"
            "print(workspace.hits_dir(src), flush=True)\n"
            "time.sleep(600)\n")
    proc = subprocess.Popen([sys.executable, "-c", code, str(src)], cwd=ROOT, env=clean_env(), stdout=subprocess.PIPE,
                            text=True)
    copy, hits = Path(proc.stdout.readline().strip()), Path(proc.stdout.readline().strip())
    if not alive:
        stop(proc)
    return copy, hits, proc


def stop(proc: subprocess.Popen) -> None:
    if proc.poll() is None:
        proc.send_signal(signal.SIGKILL)
        proc.wait(timeout=30)
    proc.stdout.close()


class SweepTests(unittest.TestCase):
    def test_a_new_copy_sweeps_the_folders_of_a_killed_run_and_keeps_a_live_runs(self):
        with TempDir() as d:
            src = d / "src"
            src.mkdir()
            make_source(src)
            live_copy, live_hits, live = made_in_another_process(src, alive=True)
            self.addCleanup(stop, live)
            dead_copy, dead_hits, _dead = made_in_another_process(src, alive=False)
            for folder in (dead_copy, dead_hits, live_copy, live_hits):
                self.assertTrue(folder.is_dir(), folder)
            (workspace.user_dir(dead_copy) / "logs").mkdir(parents=True, exist_ok=True)
            copy = workspace.create(src)
            try:
                self.assertFalse(dead_copy.exists(), "the killed run's copy is swept")
                self.assertFalse(dead_hits.exists(), "and its hit folder")
                self.assertFalse(workspace.user_dir(dead_copy).exists(), "and its copy's user:// folder")
                self.assertTrue(live_copy.is_dir(), "a live run's copy is kept")
                self.assertTrue(live_hits.is_dir(), "and its hit folder")
            finally:
                workspace.cleanup(src, copy)
                stop(live)
                workspace.cleanup(src, live_copy)
                workspace.cleanup(src, live_hits)

    def test_a_new_hit_folder_sweeps_too(self):
        with TempDir() as d:
            src = d / "src"
            src.mkdir()
            make_source(src)
            dead_copy, dead_hits, _dead = made_in_another_process(src, alive=False)
            hits = workspace.hits_dir(src)
            try:
                self.assertFalse(dead_copy.exists())
                self.assertFalse(dead_hits.exists())
            finally:
                workspace.cleanup(src, hits)

    def test_a_kept_folder_is_never_swept(self):
        with TempDir() as d:
            src = d / "src"
            src.mkdir()
            make_source(src)
            dead_copy, dead_hits, _dead = made_in_another_process(src, alive=False)
            workspace.keep(dead_copy)
            workspace.keep(dead_hits)
            copy = workspace.create(src)
            try:
                self.assertTrue(dead_copy.is_dir(), "a kept copy stays until it is deleted by hand")
                self.assertTrue(dead_hits.is_dir())
            finally:
                for folder in (copy, dead_copy, dead_hits):
                    workspace.cleanup(src, folder)

    def test_other_folders_in_artifacts_tmp_are_left_alone(self):
        with TempDir() as d:
            src = d / "src"
            src.mkdir()
            make_source(src)
            other = src / "artifacts" / "tmp" / "someone-elses"
            other.mkdir(parents=True)
            (other / "file.txt").write_text("not the tool's\n")
            copy = workspace.create(src)
            workspace.cleanup(src, copy)
            self.assertTrue((other / "file.txt").is_file())

    def test_a_symlink_named_for_a_dead_run_to_a_live_runs_copy_leaves_that_copy_intact(self):
        with TempDir() as d:
            src = d / "src"
            src.mkdir()
            make_source(src)
            live_copy, live_hits, live = made_in_another_process(src, alive=True)
            self.addCleanup(stop, live)
            link = src / "artifacts" / "tmp" / f"{workspace.PREFIX}{dead_pid()}.link"
            link.symlink_to(live_copy, target_is_directory=True)
            before = listing(live_copy)
            copy = workspace.create(src)
            try:
                self.assertTrue(live_copy.is_dir(), "the live run's copy is kept")
                self.assertEqual(listing(live_copy), before, "with every file in it")
                self.assertFalse(link.is_symlink(), "the link alone is swept")
            finally:
                workspace.cleanup(src, copy)
                stop(live)
                workspace.cleanup(src, live_copy)
                workspace.cleanup(src, live_hits)

    def test_a_symlink_named_for_a_dead_run_to_a_folder_outside_breaks_no_later_copy_or_hit_folder(self):
        with TempDir() as d:
            src = d / "src"
            src.mkdir()
            make_source(src)
            outside = d / "outside"
            outside.mkdir()
            (outside / "file.txt").write_text("not the tool's\n")
            tmp = src / "artifacts" / "tmp"
            tmp.mkdir(parents=True)
            for prefix in (workspace.PREFIX, workspace.HITS_PREFIX):
                (tmp / f"{prefix}{dead_pid()}.link").symlink_to(outside, target_is_directory=True)
            made = []
            try:
                made.append(workspace.create(src))
                made.append(workspace.hits_dir(src))
                made.append(workspace.create(src))
            finally:
                for folder in made:
                    workspace.cleanup(src, folder)
            self.assertEqual(listing(outside), {"file.txt"}, "nothing outside is deleted")
            self.assertEqual(scratch(src), [], "the links are swept and the run's folders cleaned up")


def dead_pid() -> int:
    """The pid of a process that has exited."""
    proc = subprocess.Popen([sys.executable, "-c", "pass"])
    proc.wait()
    return proc.pid


def scratch(src: Path) -> list[str]:
    tmp = src / "artifacts" / "tmp"
    return sorted(p.name for p in tmp.iterdir()) if tmp.is_dir() else []


class CleanupTests(unittest.TestCase):
    def test_cleanup_removes_a_copy_and_its_hit_folder_and_then_the_empty_artifacts_tmp(self):
        with TempDir() as d:
            src = d / "src"
            src.mkdir()
            make_source(src)
            copy = workspace.create(src)
            hits = workspace.hits_dir(src)
            (hits / "coverage_hits_1.json").write_text("{}\n")
            workspace.cleanup(src, copy)
            self.assertFalse(copy.exists())
            self.assertTrue(hits.is_dir(), "only the folder named")
            workspace.cleanup(src, hits)
            self.assertFalse(hits.exists())
            self.assertFalse((src / "artifacts" / "tmp").exists(), "artifacts/tmp/ goes once it is empty")
            self.assertTrue((src / "artifacts" / "coverage" / "old.json").is_file(), "the run folders stay")

    def test_cleanup_removes_its_own_folders_when_artifacts_or_artifacts_tmp_is_a_symlink(self):
        for linked in ("artifacts", "artifacts/tmp"):
            with self.subTest(symlink=linked), TempDir() as d:
                src = d / "src"
                src.mkdir()
                make_source(src)
                elsewhere = d / "elsewhere"
                (src / linked).parent.mkdir(parents=True, exist_ok=True)
                if (src / linked).exists():
                    shutil.move(src / linked, elsewhere)
                else:
                    elsewhere.mkdir()
                (src / linked).symlink_to(elsewhere, target_is_directory=True)
                copy = workspace.create(src)
                hits = workspace.hits_dir(src)
                for folder in (copy, hits):
                    workspace.cleanup(src, folder)
                    self.assertFalse(folder.exists(), folder)
                self.assertTrue((src / linked).is_symlink(), "the symlink itself stays")
                self.assertTrue(elsewhere.is_dir(), "and the folder it points to")
                if linked == "artifacts":
                    self.assertFalse((elsewhere / "tmp").exists(), "artifacts/tmp/ goes once it is empty")
                else:
                    self.assertEqual(list(elsewhere.iterdir()), [], "empty")

    def test_cleanup_refuses_anything_but_a_folder_it_made_in_this_repos_artifacts_tmp(self):
        with TempDir() as d:
            src = d / "src"
            src.mkdir()
            make_source(src)
            other = d / "other"
            other.mkdir()
            make_source(other)
            copy = workspace.create(src)
            elsewhere = workspace.create(other)
            tmp = src / "artifacts" / "tmp"
            plain = tmp / "plain-folder"
            plain.mkdir()
            nested = tmp / "plain-folder" / copy.name
            nested.mkdir()
            outside = d / copy.name
            outside.mkdir()
            link = tmp / f"{workspace.PREFIX}{dead_pid()}.link"
            link.symlink_to(copy, target_is_directory=True)
            refused = {
                "a symlink in artifacts/tmp/ named like a copy, to this repo's copy": link,
                "the repo root": src,
                "artifacts/": src / "artifacts",
                "artifacts/coverage/": src / "artifacts" / "coverage",
                "artifacts/tmp/ itself": tmp,
                "a folder outside the repo": other,
                "a folder outside the repo named like a copy": outside,
                "a folder in artifacts/tmp/ not named as the tool names them": plain,
                "a folder named like a copy, deeper in artifacts/tmp/": nested,
                "a copy of another repo": elsewhere,
            }
            before = (listing(src), listing(other), listing(d))
            for what, path in refused.items():
                with self.subTest(refused=what), self.assertRaises(ValueError):
                    workspace.cleanup(src, path)
            self.assertEqual((listing(src), listing(other), listing(d)), before, "nothing was deleted")
            self.assertTrue(copy.is_dir() and elsewhere.is_dir())
            workspace.cleanup(src, copy)
            workspace.cleanup(other, elsewhere)


if __name__ == "__main__":
    unittest.main()
