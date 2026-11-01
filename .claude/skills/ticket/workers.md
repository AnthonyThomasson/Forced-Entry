# Coordinating workers: the inbox

- **Heartbeats:** each `--phase` is a 1–2 sentence status, never a bare word; relay each to the user in one line with the
  worker's name. Read the inbox with `tools/orca_inbox.py` (its header holds flags and output lines), never a hand-written
  parser; `error: <code>` with exit 1 is an error, not an empty inbox.
- **Ack or resend:** tell every worker: on reading your message, before acting, send `orca orchestration send --subject
  "received <message id>" --body "<one line: what it will do>"`; once a batch is handled, the next `orca orchestration
  check` passes `--ack <its deliveryId>`; a decision it must wait on goes through the blocking `orca orchestration ask
  --question "<text>"`, and a timed-out `ask` is still pending (`ask --resume <its message id>`). `check` replays the oldest
  unacknowledged batch and later messages wait behind it, so a repeated message means a missing ack.
- **Answering:** read the whole inbox each time and answer each question with `reply --id <that question's id>`. No
  `received <id>` within ~5 min: `worker-read --dispatch <id> --source terminal`, find what it is blocked on, reply or
  `send --to dispatch:<id>`. A worker waiting on an answer you sent is stuck behind an unacknowledged batch: `orca terminal
  send --terminal <its handle> --text "Run orca orchestration check --ack <your last batch's deliveryId>: my answer is
  behind it." --enter`. A `reply` does not wake an idle worker: after a reply to an `ask` older than its timeout (10
  min), `orca terminal send` it "Your question <id> is answered: run orca orchestration check." as well.
- **Waiting:** `.claude/skills/ticket/wait.sh [ack_delivery_id]` in the background (it wakes on a worker's `status` too).
  It prints `PID=<pid>` first and `DELIVERY=<id>` last (the next call's argument; `none` acks nothing). Stop it with
  `kill <PID>`; a `pkill` of a wrapper leaves an orphan waiter that refuses every new wait (`waiter_exists`).
