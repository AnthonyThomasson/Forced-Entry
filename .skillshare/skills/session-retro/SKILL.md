---
name: session-retro
description: Use when asked for a retro on a session or ticket run, or from `finish` on a bare `/finish`.
model: opus
---

# Session retro

A retro of the session through `mattpocock-skills:retro`, before `finish` lands the work. It is slash-only (the Skill tool
refuses it), so a headless session runs it.

1. **Start it.** The session began when the branch was made: the date on the last line of `git reflog show --date=iso
   <branch>`. Write its spec to a scratchpad file, then run it in the background from the worktree
   root, on Kimi K3.1 Pro through the user's `claudep` alias: `zsh -ic 'claudep --model kimi-k3.1-pro -p "$(cat <spec file>)"'`. The
   spec's first line is `/mattpocock-skills:retro`, then:
   - **Session:** the ticket (`#<n>`, read with `gh issue view <n> --comments`; none: the branch's work), worktree and
     branch. Its transcripts are the `*.jsonl` in `~/.claude/projects/<slug>/` (`<slug>`: the worktree's absolute path with
     every `/` and `.` as `-`) modified since that date: every session's on this branch. Its own is the newest; skip it.
   - **Constraints:** report only: no edit in the tree, no commit, no issue created or commented, no other sessions started.
   - **Observable acceptance:** one report file in its scratch directory: the candidates high → low severity, each with its
     retro category, the evidence (which session, what happened), the change (file, check or tool) and a ticket draft
     (title; body `## Problem`, `## Proposal`, `## Evidence`). Its last line gives the count and the path. No candidates is a
     valid report.
2. **Match the known ones.** Per candidate, search the open issues (`gh issue list --state open --search "<key words>"`); one
   covers it already: the candidate is a **repeat** of that issue, and is never filed again.
3. **Ask.** Show the new candidates, one line each (severity, title, the change), and the repeats, one line each (severity,
   `#<issue>` title, the evidence). Ask with `AskUserQuestion`, one multi-select question each: which new ones to file, which
   repeats to mark seen again (one option per item; more than four: high only / high and medium / all / none). None is a fine
   answer to either.
4. **File** each picked new one: its body (ending `Found in the retro of #<n>.`) to a scratchpad file, then `gh issue create
   --title "<title>" --body-file <file> --label harness` (`bug` instead of `harness` for a defect in the
   game itself). **Mark** each picked repeat: `gh issue comment <issue> --body "Seen again in the retro of #<n>: <the
   evidence, one line>."`. The comments are the tally, one per retro that hit it. Report the new and the marked issue
   numbers; `finish` repeats them in its report.
5. **Ask to finish.** Ask with `AskUserQuestion`: **finish** (commit, merge into `main`, push,
   close the ticket, remove the workspace) or **not yet**. Finish: invoke `finish`, which lands the work on its own model.
   Not yet: stop and wait.
