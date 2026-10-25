---
name: show-me
description: Open a Godot editor on this worktree with autorun, named after it, and play the change's tests in a window, so the user can verify the change live. Use once a ticket's plan is accepted (or a bug agreed) or a `ticket-assets` showroom is ready, when the user should see finished work, and when asked to "show me".
model: haiku
---

# Show me

Safe to rerun: it reuses an editor already open on the worktree and replaces the test window it opened before. It
plays the change's tests in a window for the user to watch; it runs no test batch and edits no files.

1. From the worktree root, Bash sandbox disabled (`dangerouslyDisableSandbox: true`); the script names the editor after
   the worktree directory, so pass no name:

   ```bash
   tools/editor.sh --autorun
   ```

2. `editor already running` (with pid, port, log): report it and go to step 4. If no game was running on its port, the
   script also opened the game window on its own (`game window opened`, with its pid and log): check that log for
   `[cmd] listening` and any `SCRIPT ERROR` as below. A game already running is left as it is. Otherwise it
   prints the pid, command-server port and log path; after ~10 s check the log (`$TMPDIR/editor_<name>.log`) for
   `[cmd] listening on 127.0.0.1:<port>` and any `SCRIPT ERROR`.
3. Report the name, port and pid in a line or two, whether it was already running, and any log errors. Leave the
   editor open. A game window this run opened (`game window opened`) gets its pid in the report, with "the ticket
   workflow closes it after the feedback gate". The setup window shows the worktree name at the top. The editor picks
   up file changes when focused; a running game needs Play restarted.
4. Play the change's tests, from the worktree root, sandbox disabled:

   ```bash
   tools/play_tests.sh
   ```

   With no arguments it queues every `tests/**/*_test.gd` added or changed since the merge-base with `origin/main`
   (committed, uncommitted or untracked), by id, opens one game window that plays them one after another, and returns
   at once. Fire and forget: report the window's pid and log from its `test window pid … | log …` line, with "the
   ticket workflow closes it after the feedback gate", and list the queued tests by each one's `"name"` from
   `describe()` in `tests/<id>_test.gd` (e.g. `Falling body keeps its draw order`), one per line, not the id or file
   name. The user watches it; each verdict and a final `Queue done:` line go to that log. Exit 2 with `nothing to
   play` means no tests yet (right after planning): say so; any other exit 2 (no merge-base, no Godot found): report
   its message. A sandbox under `sandboxes/showroom/` (`ticket-assets`) is not played: name it by its `describe()`
   name and say it opens from Tests → SANDBOXES.
