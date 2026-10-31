#!/usr/bin/env python3
"""Read the coordinator's Orca inbox: `orca orchestration check --json`, decoded.

  tools/orca_inbox.py [--run R] [--ack ID] [--wait] [--types T,...] [--timeout-ms N] [--state PATH]

The flags except --state reach orca unchanged, except `--ack none`: no --ack. Keepalive lines (`_keepalive`, the
deprecated `_heartbeat`) are dropped on either stream. A heartbeat's phase lives in the message's `payload`, a JSON
string; this decodes it.

Output (stdout):
  PID=<this pid>          first line, with --wait only: `kill` it to stop the wait (orca, its child, is stopped too)
  DELIVERY=<id|none>      the batch to pass as the next --ack (`none`, fed back, acks nothing); with --wait it is
                          repeated as the last line
  <id> <type> <worker> <subject> | <body> | <phase>      one line per message (`no messages` when there are none)
  <id> heartbeat <worker> (phase unchanged)              a heartbeat repeating that worker's last printed phase,
                                                         on a message other than the one that printed it
  error: <code>: <message>                               orca's `ok:false` (e.g. waiter_exists); exit 1
The worker is named from `task-list` (`display_name`, the worker's --task-title), else through `worker-list`, else the
sender's raw handle. The last message and phase per worker are kept in $TMPDIR/orca-inbox-<run_id>.json (--state to
move it); a state file that cannot be written is a warning on stderr, not a failed read.
"""
import argparse
import json
import os
import signal
import subprocess
import sys
import tempfile

KEEPALIVE_KEYS = ("_keepalive", "_heartbeat")


def objects(text: str) -> list:
    """Every JSON object in `text`, one after another, however they are separated; text that is not JSON is skipped."""
    decoder = json.JSONDecoder()
    found, i = [], 0
    while i < len(text):
        i = text.find("{", i)
        if i < 0:
            break
        try:
            obj, i = decoder.raw_decode(text, i)
        except ValueError:
            i += 1
            continue
        found.append(obj)
    return found


def is_keepalive(obj) -> bool:
    return isinstance(obj, dict) and any(k in obj for k in KEEPALIVE_KEYS)


def reply_of(out: str):
    """The `{"ok": ...}` object orca printed, keepalives and any other text around it ignored; None when absent."""
    return next((o for o in reversed(objects(out)) if isinstance(o, dict) and "ok" in o and not is_keepalive(o)), None)


def delivery_line(result: dict) -> str:
    return "DELIVERY=" + (result.get("deliveryId") or "none")


def one_line(text) -> str:
    return " ".join(str(text or "").split())


def payload_of(msg: dict) -> dict:
    """The message's `payload`: a JSON string in Orca's store (an object is taken as it is)."""
    payload = msg.get("payload")
    if isinstance(payload, str):
        try:
            payload = json.loads(payload)
        except ValueError:
            return {}
    return payload if isinstance(payload, dict) else {}


def parse_args(argv: list) -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Read the coordinator's Orca inbox.")
    ap.add_argument("--run")
    ap.add_argument("--ack")
    ap.add_argument("--wait", action="store_true")
    ap.add_argument("--types")
    ap.add_argument("--timeout-ms")
    ap.add_argument("--state", help="the state file of the last phase per worker (default in $TMPDIR, per run)")
    return ap.parse_args(argv)


def check_argv(args: argparse.Namespace) -> list:
    """The orca call: the passthrough flags as given, except `--ack none` (a DELIVERY=none fed back): no ack."""
    argv = ["orca", "orchestration", "check", "--json"]
    for flag, value in (("--run", args.run), ("--ack", args.ack)):
        if value is not None and not (flag == "--ack" and value == "none"):
            argv += [flag, value]
    if args.wait:
        argv.append("--wait")
    for flag, value in (("--types", args.types), ("--timeout-ms", args.timeout_ms)):
        if value is not None:
            argv += [flag, value]
    return argv


class Names:
    """A message's sender, named from the task list (its `display_name`, the worker's `--task-title`), else through the
    worker list (terminal handle or dispatch -> task -> title), else the raw handle. Each list is asked for once, and
    only when a message needs a name."""

    def __init__(self, run):
        self.run = run
        self._titles = None
        self._workers = None

    def _ask(self, sub: str, key: str) -> list:
        argv = ["orca", "orchestration", sub, "--json"] + (["--run", self.run] if self.run else [])
        proc = subprocess.run(argv, capture_output=True, text=True)
        reply = reply_of(proc.stdout)
        result = reply.get("result") if reply and reply["ok"] else None
        rows = result.get(key) if isinstance(result, dict) else None
        return [row for row in rows if isinstance(row, dict)] if isinstance(rows, list) else []

    def titles(self) -> dict:
        if self._titles is None:
            self._titles = {t["id"]: t.get("display_name") or t.get("task_title")
                            for t in self._ask("task-list", "tasks") if t.get("id")}
        return self._titles

    def workers(self) -> list:
        if self._workers is None:
            self._workers = self._ask("worker-list", "workers")
        return self._workers

    def of(self, msg: dict, payload: dict) -> str:
        sender = str(msg.get("from_handle") or "")
        title = self.titles().get(payload.get("taskId")) if isinstance(payload.get("taskId"), str) else None
        if title:
            return title
        ids = {sender, sender.removeprefix("dispatch:"), payload.get("dispatchId")}
        for w in self.workers():
            if ids & {w.get("agentTerminalHandle"), w.get("dispatchId")}:
                title = self.titles().get(w.get("taskId"))
                if title:
                    return title
        return sender


class Phases:
    """The last message id and phase printed per worker, kept in a JSON file per run, so it holds across calls."""

    def __init__(self, path_override):
        self.path_override = path_override
        self.path = None
        self.last = {}
        self.dirty = False

    def load_for(self, run_id: str) -> None:
        self.path = self.path_override or os.path.join(tempfile.gettempdir(), f"orca-inbox-{run_id}.json")
        try:
            with open(self.path) as f:
                loaded = json.load(f)
            self.last = loaded if isinstance(loaded, dict) else {}
        except (OSError, ValueError):
            self.last = {}

    def repeats(self, worker: str, message_id, phase: str) -> bool:
        """True when `phase` is the worker's last printed one, on a message other than the one that
        printed it (a replayed message prints in full again); otherwise records the message and phase as the last."""
        if not phase:
            return False
        last = self.last.get(worker)
        if isinstance(last, dict) and last.get("phase") == phase:
            return last.get("id") != message_id
        self.last[worker] = {"id": message_id, "phase": phase}
        self.dirty = True
        return False

    def save(self) -> None:
        """Write the file atomically. A state that cannot be kept is a warning: the read it came with still stands."""
        if not (self.dirty and self.path):
            return
        tmp = None
        try:
            fd, tmp = tempfile.mkstemp(dir=os.path.dirname(self.path) or ".", prefix=".orca-inbox-")
            with os.fdopen(fd, "w") as f:
                json.dump(self.last, f)
            os.replace(tmp, self.path)
        except (OSError, TypeError, ValueError) as e:
            print(f"warning: could not keep the phase state in {self.path}: {e}", file=sys.stderr)
            if tmp:
                try:
                    os.unlink(tmp)
                except OSError:
                    pass


def run_orca(argv: list) -> tuple:
    """Run orca as a child and return (returncode, stdout, stderr). On SIGTERM, SIGINT or SIGHUP the child is
    terminated before this process exits, so a killed wait leaves no waiter behind (`waiter_exists`)."""
    child = None
    pending = None

    def stop_child(signum):
        if child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
        sys.exit(128 + signum)

    def on_signal(signum, _frame):
        nonlocal pending
        if child is None:
            pending = signum
        else:
            stop_child(signum)

    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(sig, on_signal)
    child = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    # A signal that landed before `child` was set only left a note: act on it now.
    if pending is not None:
        stop_child(pending)
    out, err = child.communicate()
    return child.returncode, out, err


def main() -> int:
    args = parse_args(sys.argv[1:])
    if args.wait:
        print(f"PID={os.getpid()}", flush=True)
    code, out, err = run_orca(check_argv(args))
    # Keepalives are dropped on either stream; any other stderr text is passed on as it came.
    stray = [line for line in err.splitlines() if line.strip() and not any(is_keepalive(o) for o in objects(line))]
    for line in stray:
        print(line, file=sys.stderr)
    reply = reply_of(out)
    if reply is None:
        print(f"error: no_reply: orca exited {code} without a reply: {one_line(' '.join(stray))}".rstrip())
        return 1
    if not reply["ok"]:
        error = reply.get("error") if isinstance(reply.get("error"), dict) else {}
        message = one_line(error.get("message"))
        print(f"error: {error.get('code', 'unknown')}" + (f": {message}" if message else ""))
        return 1
    result = reply.get("result")
    if not isinstance(result, dict) or not isinstance(result.get("messages"), list):
        print(f"error: bad_reply: no result.messages in {one_line(json.dumps(reply))[:200]}")
        return 1
    print(delivery_line(result))
    messages = [m for m in result["messages"] if isinstance(m, dict)]
    run_id = (messages[0].get("run_id") if messages else None) or args.run or "run"
    names = Names(args.run or (run_id if messages else None))
    phases = Phases(args.state)
    if messages:
        phases.load_for(run_id)
    else:
        print("no messages")
    for m in messages:
        payload = payload_of(m)
        name = names.of(m, payload)
        phase = one_line(payload.get("phase"))
        worker = str(payload.get("taskId") or m.get("from_handle"))
        if m.get("type") == "heartbeat" and phases.repeats(worker, m.get("id"), phase):
            print(f"{m.get('id')} heartbeat {name} (phase unchanged)")
        else:
            print(f"{m.get('id')} {m.get('type')} {name} {one_line(m.get('subject'))} | {one_line(m.get('body'))} | {phase}")
    phases.save()
    if args.wait:
        print(delivery_line(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
