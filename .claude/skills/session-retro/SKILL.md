---
name: session-retro
description: Retro the session through `mattpocock-skills:retro`, file the improvement tickets the user picks, then ask whether to finish. Use on the ticket workflow's "retro" answer, or from `finish` on a bare `/finish`.
model: opus
---

# Session retro

A retro of the session, before `finish` lands the work. `mattpocock-skills:retro` is slash-only (the Skill tool
refuses it), so a worker runs it (`orchestration`; load it if this session has not).

1. **Start it.** The session began when the branch was made: the date on the last line of
   `git reflog show --date=iso <branch>`. Start the worker with
   `orca orchestration worker-start --task-title "retro" --spec "<spec>" --worktree current --agent claude
   --model claude-sonnet-5-5` and name its tab `retro` (`orca terminal rename`, the handle read from `worker-list` as `ticket` → "Work in phases" says).
   Spec, its first line `/mattpocock-skills:retro`, then:
   - **Session:** the ticket (`#<n>`, read with `gh issue view <n> --comments`; none: the branch's work), worktree and
     branch. Its transcripts are the `*.jsonl` in `~/.claude/projects/<slug>/` (`<slug>`: the worktree's absolute path
     with every `/` and `.` as `-`) modified since that date: the coordinator's and every worker's. Its own is the
     newest; skip it.
   - **Constraints:** report only: no edit in the tree, no commit, no issue created or commented, no Orca workers.
     Each `--phase` is a 1–2 sentence status.
   - **Observable acceptance:** one report file in its scratch directory: the candidates high → low severity, each with
     its retro category, the evidence (which session, what happened), the change (file, check or tool) and a ticket
     draft (title; body `## Problem`, `## Proposal`, `## Evidence`). `worker_done` gives the count and the path. No
     candidates is a valid report.
2. **Drop the known ones.** Read the report. Per candidate, search the open issues
   (`gh issue list --state open --search "<key words>"`); one covers it already: name it and file nothing.
3. **Ask.** Show the rest, one line each (severity, title, the change), and ask with `AskUserQuestion` which to file
   (multi-select, one option per candidate; more than four: high only / high and medium / all / none). None is a
   fine answer.
4. **File** each picked one: its body (ending `Found in the retro of #<n>.`) to a scratchpad file, then
   `gh issue create --title "<title>" --body-file <file> --label harness --label needs-triage` (`bug` instead of
   `harness` for a defect in the game itself). Report the new issue numbers; `finish` repeats them in its report.
5. **Ask to finish.** Release the retro worker, then ask with `AskUserQuestion`: **finish** (commit, merge into `main`,
   push, close the ticket, remove the workspace) or **not yet**. Finish: invoke `finish`, which lands the work on its
   own model. Not yet: stop and wait.
