""".githooks/commit-msg: a commit whose `Co-Authored-By: Claude <model> <…>` line names another model than the branch's
earlier Claude commits (`git log <base>..HEAD`, base `origin/main`, else `main`; merges walked too, commits without a
Claude line ignored), or whose own Claude lines disagree, is refused, naming both models, the earlier commits' short
hashes and the fix. The fix's `git rebase --exec` command rewords the earlier commits with no editor, through the hook;
when the earlier commits name more than one model among themselves, the hint picks none of theirs. A message with no
Claude line, and the branch's first Claude commit, pass silently. An amend (`git commit --amend`, as a rebase's reword
makes one) replaces HEAD, so HEAD is left out of the earlier commits.

Each case is a temp git repo: `main` holds one human commit, and the work is on the branch `work`. The hook is run as
git runs it (from the repo, the message file its argument), or through `git commit` with core.hooksPath set to a
folder holding a copy of this checkout's hook.
"""
import shutil
import subprocess
import unittest
from pathlib import Path

from tools.coverage.tests.support import TempDir, clean_env, git

ROOT = Path(__file__).resolve().parents[2]
HOOK = ROOT / ".githooks" / "commit-msg"

OPUS = "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
HAIKU = "Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>"


def message(subject: str, *trailers: str) -> str:
    return subject + "\n\nWhy it changed.\n" + ("\n" + "\n".join(trailers) + "\n" if trailers else "")


class Repo:
    def __init__(self, root: Path):
        self.root = root
        root.mkdir()
        git(root, "init", "-q", "-b", "main")
        (root / ".githooks").mkdir()
        shutil.copy2(HOOK, root / ".githooks" / "commit-msg")
        self.commit("base", message("Base, by a person"))
        git(root, "checkout", "-q", "-b", "work")
        self.n = 0

    def commit(self, name: str, text: str, hooks: bool = False) -> subprocess.CompletedProcess:
        """Commit a change to `name` with message `text`; through the hook when `hooks`, else around it."""
        (self.root / name).write_text(text)
        git(self.root, "add", name)
        return self.git_commit("-m", text, hooks=hooks)

    def git_commit(self, *args: str, hooks: bool = True) -> subprocess.CompletedProcess:
        cmd = ["git", "-c", "user.name=t", "-c", "user.email=t@example.com"]
        if hooks:
            cmd += ["-c", "core.hooksPath=.githooks"]
        return subprocess.run(cmd + ["commit", "-q", *args], cwd=self.root, env=clean_env(), capture_output=True,
                              text=True, timeout=60)

    def short(self, ref: str = "HEAD") -> str:
        return git(self.root, "rev-parse", "--short", ref).strip()

    def hook(self, text: str) -> subprocess.CompletedProcess:
        msg = self.root.parent / "COMMIT_EDITMSG"
        msg.write_text(text)
        return subprocess.run(["bash", str(self.root / ".githooks" / "commit-msg"), str(msg)], cwd=self.root,
                              env=clean_env(), capture_output=True, text=True, timeout=60)


class CommitMsgTests(unittest.TestCase):
    def repo(self, d: Path) -> Repo:
        return Repo(d / "repo")

    def assert_passes(self, r: subprocess.CompletedProcess) -> None:
        self.assertEqual((r.returncode, r.stdout, r.stderr), (0, "", ""))

    def test_a_model_other_than_the_branchs_is_refused_naming_both_the_commits_and_the_fix(self):
        with TempDir("commit_msg_test.") as d:
            repo = self.repo(d)
            repo.commit("a.txt", message("First", OPUS))
            first = repo.short()
            repo.commit("b.txt", message("Second", OPUS))
            second = repo.short()
            r = repo.hook(message("Third", HAIKU))
            self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
            for text in ("Claude Haiku 5.5", "Claude Opus 5.5", first, second, OPUS, "rebase"):
                self.assertIn(text, r.stderr)

    def recipe(self, stderr: str) -> str:
        """The command the hint gives to reword the earlier commits: its line indented by two spaces."""
        lines = [ln.strip() for ln in stderr.splitlines() if ln.startswith("  git rebase")]
        self.assertEqual(len(lines), 1, "one rebase command line in the hint\n" + stderr)
        return lines[0]

    def test_the_hints_rebase_rewords_the_earlier_commits_without_an_editor(self):
        with TempDir("commit_msg_test.") as d:
            repo = self.repo(d)
            repo.commit("a.txt", message("First", HAIKU))
            git(repo.root, "checkout", "-q", "-b", "side", "main")
            repo.commit("side.txt", message("Side, by a person"))
            git(repo.root, "checkout", "-q", "work")
            git(repo.root, "-c", "user.name=t", "-c", "user.email=t@example.com", "merge", "-q", "--no-ff", "side",
                "-m", message("Merge side", HAIKU))
            # Written as the hook still reads it: GitHub's casing, the model spaced out.
            repo.commit("b.txt", message("Last", "co-authored-by: Claude  Haiku 5.5 <noreply@anthropic.com>"))
            r = repo.hook(message("Next", OPUS))
            self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
            # As the agent runs it: no editor to open (an interactive rebase would fail on it), the hooks on.
            for key, value in (("core.hooksPath", ".githooks"), ("user.name", "t"), ("user.email", "t@example.com")):
                git(repo.root, "config", key, value)
            done = subprocess.run(["bash", "-c", self.recipe(r.stderr)], cwd=repo.root,
                                  env=clean_env(GIT_EDITOR="false", GIT_SEQUENCE_EDITOR="false"), capture_output=True,
                                  text=True, timeout=120)
            self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
            log = git(repo.root, "log", "--format=%B", "main..work")
            self.assertNotIn("Haiku", log)
            self.assertEqual(log.count("Claude Opus 5.5 <"), 3,
                             "each earlier Claude commit reworded, the merge's included\n" + log)
            self.assertIn("side.txt", git(repo.root, "ls-files"), "the merge is kept")
            self.assert_passes(repo.hook(message("Next", OPUS)))

    def test_earlier_commits_that_disagree_are_named_without_picking_one(self):
        with TempDir("commit_msg_test.") as d:
            repo = self.repo(d)
            repo.commit("a.txt", message("First", OPUS))
            repo.commit("b.txt", message("Second", HAIKU))
            for mine in (OPUS, "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"):
                with self.subTest(mine=mine):
                    r = repo.hook(message("Third", mine))
                    self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
                    self.assertIn("more than one model", r.stderr)
                    self.assertNotIn("edit this message's line to", r.stderr, "neither earlier model is the right one")
                    self.assertIn("rebase", r.stderr)

    def test_the_branchs_model_passes(self):
        with TempDir("commit_msg_test.") as d:
            repo = self.repo(d)
            repo.commit("a.txt", message("First", OPUS))
            self.assert_passes(repo.hook(message("Second", OPUS)))

    def test_the_first_claude_commit_passes(self):
        with TempDir("commit_msg_test.") as d:
            repo = self.repo(d)
            self.assert_passes(repo.hook(message("First", HAIKU)))

    def test_a_person_commit_passes_and_is_no_history(self):
        with TempDir("commit_msg_test.") as d:
            repo = self.repo(d)
            repo.commit("a.txt", message("By a person", "Co-Authored-By: A Person <person@example.com>"))
            self.assert_passes(repo.hook(message("Also by a person")))
            self.assert_passes(repo.hook(message("First Claude", HAIKU)))
            repo.commit("b.txt", message("First Claude", OPUS))
            self.assert_passes(repo.hook(message("By a person again")))

    def test_a_message_whose_claude_lines_disagree_is_refused(self):
        with TempDir("commit_msg_test.") as d:
            repo = self.repo(d)
            r = repo.hook(message("Both", OPUS, HAIKU))
            self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
            self.assertIn("Claude Opus 5.5", r.stderr)
            self.assertIn("Claude Haiku 5.5", r.stderr)

    def test_commented_and_scissored_lines_are_not_the_message(self):
        # git strips them after the hook runs: a template's comment or `commit -v`'s diff names nobody.
        with TempDir("commit_msg_test.") as d:
            repo = self.repo(d)
            repo.commit("a.txt", message("First", OPUS))
            text = message("Second", OPUS) + "# " + HAIKU + "\n# ------------------------ >8 ------------------------\n"
            self.assert_passes(repo.hook(text + "+" + HAIKU + "\n" + HAIKU + "\n"))

    def test_a_merge_on_the_branch_counts(self):
        with TempDir("commit_msg_test.") as d:
            repo = self.repo(d)
            git(repo.root, "checkout", "-q", "-b", "side", "main")
            repo.commit("side.txt", message("Side, by a person"))
            git(repo.root, "checkout", "-q", "work")
            repo.commit("a.txt", message("Work, by a person"))
            git(repo.root, "-c", "user.name=t", "-c", "user.email=t@example.com", "merge", "-q", "--no-ff", "side",
                "-m", message("Merge side", OPUS))
            merge = repo.short()
            r = repo.hook(message("Next", HAIKU))
            self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
            self.assertIn(merge, r.stderr)

    def test_the_base_is_origin_main_when_there_is_one(self):
        with TempDir("commit_msg_test.") as d:
            repo = self.repo(d)
            repo.commit("a.txt", message("Landed already", HAIKU))
            git(repo.root, "update-ref", "refs/remotes/origin/main", "HEAD")  # main itself is behind it
            self.assert_passes(repo.hook(message("Since origin/main", OPUS)))
            git(repo.root, "update-ref", "-d", "refs/remotes/origin/main")
            self.assertEqual(repo.hook(message("Since main", OPUS)).returncode, 1, "without it, main")

    def test_through_git_a_clash_is_refused_and_no_commit_made(self):
        with TempDir("commit_msg_test.") as d:
            repo = self.repo(d)
            repo.commit("a.txt", message("First", OPUS))
            head = repo.short()
            r = repo.commit("b.txt", message("Second", HAIKU), hooks=True)
            self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertIn("Claude Haiku 5.5", r.stderr)
            self.assertEqual(repo.short(), head, "no commit was made")
            self.assertEqual(repo.commit("b.txt", message("Second", OPUS), hooks=True).returncode, 0)

    def test_an_amend_that_puts_heads_model_right_passes(self):
        with TempDir("commit_msg_test.") as d:
            repo = self.repo(d)
            repo.commit("a.txt", message("First", OPUS))
            repo.commit("b.txt", message("Second", HAIKU))  # made around the hook
            r = repo.git_commit("--amend", "-m", message("Second", OPUS))
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertIn(OPUS, git(repo.root, "log", "-1", "--format=%B"))
            r = repo.git_commit("--amend", "-m", message("Second", HAIKU))
            self.assertNotEqual(r.returncode, 0, "an amend is still held to the commits before HEAD")


if __name__ == "__main__":
    unittest.main()
