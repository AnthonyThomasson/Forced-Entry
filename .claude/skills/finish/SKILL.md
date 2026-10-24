---
name: finish
description: Commit the worktree's work, merge it into main, push main, close its ticket and remove the Orca workspace. Runs after `session-retro`. Use only once the user answered "finish" (or "finish now, skip the retro") at the end of a ticket workflow, or on `/finish`.
model: haiku
---

# Finish

Run from the worktree root. Push `main` only, never the branch. It pushes and deletes the workspace, so it runs only on
the user's "finish" answer or `/finish`. Release every settled orchestration worker before step 1.

## Retro first

`session-retro` runs before this skill and invokes it once the user answers "finish". When it has not run this
session and the user did not say to skip it (a bare `/finish`), invoke `session-retro` now and stop here: it asks
whether to finish and invokes `finish` again.

1. **Preconditions.** The branch (`git branch --show-current`) and `main`'s directory (the `worktree` entry with
   `branch refs/heads/main` in `git worktree list --porcelain`). Stop and tell the user if the branch is `main`, there
   is nothing to commit and nothing ahead of `main`, or `main`'s directory is not clean
   (`git -C <main dir> status --short`). Then the branch's model: the `Co-Authored-By: Claude <model> <…>` lines of
   `git log origin/main..HEAD` name one model; when they name more than one, stop and tell the user which commits name
   which (the commit-msg hook refuses a mixed branch).
2. **Commit.** No analysis or tests. Review `git status --short`; stage this work's files by name, including the `.uid`
   beside every new or moved `.gd` (tracked here). Message: what changed and why, ending with the branch's model's
   `Co-Authored-By` line from step 1 (this skill runs pinned to another model, so the session's attribution line can
   name the wrong one), or the session's line when no commit names one. Anything left out is handled in step 6.
3. **Bring in main.** `git merge main`. Resolve only trivial conflicts; otherwise stop and show the conflicting files.
4. **Land.** `git -C <main dir> merge --ff-only <branch>`. Refused because `main` moved: back to step 3. Never force or
   `--no-verify`.
5. **Push.** `git -C <main dir> push origin main`. Rejected because `origin/main` moved:
   `git -C <main dir> pull --ff-only origin main`; if that brought changes, back to step 3, then land and push again.
   Never force-push.
6. **Make the worktree removable**, before closing anything (a failure leaves the ticket open). `git worktree remove`
   refuses any untracked, non-ignored file, and a running editor keeps writing `.uid`s.
   - Stop editors/games on this worktree (`show-me` leaves one): `pgrep -f -- "--path $PWD( |\$)"`, plain `kill` each,
     wait for exit.
   - `git status --short`: delete generated cruft (a `.uid` with no `.gd`, an `.import`); commit missed real work (back
     to step 2); unexplained scratch files: stop and ask, never delete silently.
   - Repeat until it prints nothing (ignored files like `.godot/` are fine). Won't go clean: stop and say why.
7. **Close the ticket.** `orca worktree current --json` (Orca CLI per `orca-cli`; `orca` on macOS): note
   `result.worktree.id` for step 9, and `linkedIssue` (GitHub), `linkedLinearIssue`, `linkedGitLabIssue`.
   - GitHub: `gh issue close <number> --comment "Fixed in <short hash>, merged to main."`
   - Linear: load `orca-linear` and finish it as it describes.
   - GitLab or no link: skip and say so. Never guess a ticket.
   Closing fails: report it and skip step 9.
8. **Report** before step 9: commits landed on `main` (hashes, subjects), `origin/main` matches, the ticket closed,
   anything deleted in step 6, the retro's new tickets.
9. **Remove the workspace, last.** `orca worktree rm --worktree id:<worktree id> --json` with step 7's id (not
   `current`). No `--force`, no `--run-hooks`. It removes the git worktree and the merged local branch. Refused: report
   and stop; never retry with `--force`. Nothing runs after this.
