"""tools/orca_inbox.py and .claude/skills/ticket/wait.sh, run the way a coordinator runs them: as subprocesses, with a
fake `orca` first on PATH in a temp dir, checking stdout and the exit code.

The fake `orca` answers from files in its own directory (nothing is written in the checkout):
  check.stdout / check.stderr   what `orca orchestration check` prints (stderr carries the --wait keepalives)
  task-list.json, worker-list.json   the replies to `task-list` / `worker-list`
  argv.log                      one JSON argv per call, appended
  block                         when present, `check` records its pid in orca.pid and sleeps until killed
The shapes are the ones Orca prints live: `{"ok":true,"result":{"messages":[...],"count":N,"deliveryId":...}}`, a
message's `payload` a JSON string, keepalives `{"_keepalive":...}` lines.
"""
import json
import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
READER = ROOT / "tools" / "orca_inbox.py"
WAIT = ROOT / ".claude" / "skills" / "ticket" / "wait.sh"

FAKE_ORCA = """#!/usr/bin/env python3
import json, os, sys, time
d = os.environ["FAKE_ORCA_DIR"]
with open(os.path.join(d, "argv.log"), "a") as f:
    f.write(json.dumps(sys.argv[1:]) + "\\n")
sub = sys.argv[2]
if sub == "check" and os.path.exists(os.path.join(d, "block")):
    with open(os.path.join(d, "orca.pid"), "w") as f:
        f.write(str(os.getpid()))
    time.sleep(600)
if sub == "check":
    sys.stderr.write(open(os.path.join(d, "check.stderr")).read())
    sys.stdout.write(open(os.path.join(d, "check.stdout")).read())
else:
    sys.stdout.write(open(os.path.join(d, sub + ".json")).read())
"""

RUN = "run_1111"
TASK_A, TASK_B = "task_aaaa", "task_bbbb"
CTX_A, CTX_B = "ctx_aaaa", "ctx_bbbb"
TERM_A, TERM_B = "term_aaaa", "term_bbbb"


def message(mid, mtype="heartbeat", sender=TERM_A, task=TASK_A, ctx=CTX_A, subject="alive", body="", **payload):
    payload_doc = {"taskId": task, "dispatchId": ctx, **payload}
    return {"id": mid, "run_id": RUN, "from_handle": sender, "subject": subject, "body": body, "type": mtype,
            "payload": json.dumps(payload_doc)}


def reply(messages, delivery="delivery_1"):
    result = {"messages": messages, "count": len(messages)}
    if messages:
        result["deliveryId"] = delivery
    return json.dumps({"id": "req_1", "ok": True, "result": result})


def keepalive(key="_keepalive"):
    return json.dumps({key: True, "ts": 1})


TASKS = {"ok": True, "result": {"runId": RUN, "tasks": [
    {"id": TASK_A, "task_title": "coding", "display_name": "coding"},
    {"id": TASK_B, "task_title": "review", "display_name": "review"}]}}
WORKERS = {"ok": True, "result": {"workers": [
    {"dispatchId": CTX_A, "taskId": TASK_A, "agentTerminalHandle": TERM_A},
    {"dispatchId": CTX_B, "taskId": TASK_B, "agentTerminalHandle": TERM_B}]}}


class InboxCase(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.dir = Path(tmp.name)
        self.fake = self.dir / "fake"
        self.fake.mkdir()
        orca = self.fake / "orca"
        orca.write_text(FAKE_ORCA)
        orca.chmod(0o755)
        self.tmpdir = self.dir / "tmp"
        self.tmpdir.mkdir()
        self.env = {**os.environ, "PATH": f"{self.fake}{os.pathsep}{os.environ['PATH']}",
                    "FAKE_ORCA_DIR": str(self.fake), "TMPDIR": str(self.tmpdir)}
        self.set_check(reply([]))
        self.set_json("task-list", {"ok": True, "result": {"runId": RUN, "tasks": []}})
        self.set_json("worker-list", {"ok": True, "result": {"workers": []}})

    def set_json(self, sub, doc):
        (self.fake / f"{sub}.json").write_text(json.dumps(doc))

    def set_check(self, stdout, stderr=""):
        (self.fake / "check.stdout").write_text(stdout + "\n")
        (self.fake / "check.stderr").write_text(stderr)

    def argv_calls(self, sub):
        log = self.fake / "argv.log"
        calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
        return [c for c in calls if c[1] == sub]

    def run_cmd(self, cmd, **kw):
        return subprocess.run(cmd, env=self.env, capture_output=True, text=True, timeout=30, **kw)

    def reader(self, *args):
        return self.run_cmd([sys.executable, str(READER), *args])


class ReaderParse(InboxCase):
    def test_keepalives_dropped_and_phase_read_from_payload(self):
        hb = message("msg_1", phase="Reading the ticket. Slice one is red.")
        self.set_check(keepalive() + "\n" + reply([hb]) + "\n" + keepalive("_heartbeat"),
                       stderr=keepalive() + "\n" + keepalive("_heartbeat") + "\n")
        r = self.reader()
        self.assertEqual(r.returncode, 0, r.stderr)
        lines = r.stdout.splitlines()
        self.assertEqual(lines[0], "DELIVERY=delivery_1")
        self.assertEqual(lines[1], "msg_1 heartbeat term_aaaa alive |  | Reading the ticket. Slice one is red.")
        self.assertEqual(len(lines), 2)
        self.assertNotIn("_keepalive", r.stdout + r.stderr)
        self.assertNotIn("_heartbeat", r.stdout + r.stderr)


class ReaderPassthrough(InboxCase):
    def test_flags_reach_orca_unchanged(self):
        flags = ["--run", RUN, "--ack", "delivery_0", "--wait", "--types", "worker_done,status", "--timeout-ms", "5000"]
        r = self.reader(*flags)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.argv_calls("check"), [["orchestration", "check", "--json", *flags]])


class ReaderErrors(InboxCase):
    def test_ok_false_prints_the_code_and_exits_1(self):
        self.set_check(json.dumps({"ok": False, "error": {"code": "waiter_exists", "message": "a waiter is running"}}),
                       stderr=keepalive() + "\n")
        r = self.reader("--wait")
        self.assertEqual(r.returncode, 1)
        self.assertEqual(r.stdout.splitlines()[-1], "error: waiter_exists: a waiter is running")

    def test_no_reply_at_all_is_an_error_not_an_empty_result(self):
        self.set_check("", stderr=keepalive() + "\n")
        r = self.reader("--wait")
        self.assertEqual(r.returncode, 1)
        self.assertTrue(r.stdout.splitlines()[-1].startswith("error: no_reply:"), r.stdout)
        self.assertNotIn("_keepalive", r.stdout)

    def test_empty_result_prints_delivery_none_and_exits_0(self):
        r = self.reader()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout.splitlines(), ["DELIVERY=none", "no messages"])


class ReaderNaming(InboxCase):
    def names(self, *messages):
        self.set_check(reply(list(messages)))
        r = self.reader()
        self.assertEqual(r.returncode, 0, r.stderr)
        return [line.split()[2] for line in r.stdout.splitlines()[1:]]

    def test_sender_is_the_task_list_display_name(self):
        self.set_json("task-list", TASKS)
        self.assertEqual(self.names(message("msg_1", task=TASK_B, sender=TERM_A)), ["review"])

    def test_without_a_task_match_the_worker_list_route_names_it(self):
        self.set_json("task-list", TASKS)
        self.set_json("worker-list", WORKERS)
        by_handle = message("msg_1", task="task_zzzz", ctx="ctx_zzzz", sender=TERM_B)
        by_dispatch = message("msg_2", task="task_zzzz", ctx="ctx_zzzz", sender=f"dispatch:{CTX_A}")
        self.assertEqual(self.names(by_handle, by_dispatch), ["review", "coding"])

    def test_with_no_route_at_all_the_raw_handle_is_the_name(self):
        self.set_json("task-list", TASKS)
        self.set_json("worker-list", WORKERS)
        self.assertEqual(self.names(message("msg_1", task="task_zzzz", ctx="ctx_zzzz", sender="term_unknown")),
                         ["term_unknown"])

    def test_an_empty_inbox_asks_orca_for_no_names(self):
        self.reader()
        self.assertEqual(self.argv_calls("task-list") + self.argv_calls("worker-list"), [])

    def test_the_lists_are_asked_for_the_messages_run(self):
        self.set_json("task-list", TASKS)
        self.names(message("msg_1"))
        self.assertEqual(self.argv_calls("task-list"), [["orchestration", "task-list", "--json", "--run", RUN]])


class ReaderMalformed(InboxCase):
    def test_odd_messages_print_a_line_instead_of_crashing(self):
        object_payload = {**message("msg_1"), "payload": {"phase": "an object, not a string"}}
        bare = {"id": "msg_2", "type": "status"}
        list_task = {**message("msg_3"), "payload": json.dumps({"taskId": ["x"], "phase": "Working."})}
        self.set_check(reply([object_payload, bare, list_task]))
        r = self.reader()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual([line.split()[0] for line in r.stdout.splitlines()[1:]], ["msg_1", "msg_2", "msg_3"])

    def test_a_reply_without_a_result_is_an_error_not_a_crash(self):
        self.set_check(json.dumps({"ok": True}))
        r = self.reader()
        self.assertEqual(r.returncode, 1, r.stderr)
        self.assertTrue(r.stdout.splitlines()[-1].startswith("error: "), r.stdout)

    def test_ok_false_without_an_error_object_still_names_an_error(self):
        self.set_check(json.dumps({"ok": False}))
        r = self.reader()
        self.assertEqual((r.returncode, r.stdout.splitlines()[-1]), (1, "error: unknown"))


class ReaderCollapse(InboxCase):
    def setUp(self):
        super().setUp()
        self.set_json("task-list", TASKS)

    def read(self, *messages, args=()):
        self.set_check(reply(list(messages)))
        r = self.reader(*args)
        self.assertEqual(r.returncode, 0, r.stderr)
        return r.stdout.splitlines()[1:]

    def test_a_repeated_phase_collapses_on_a_second_separate_call(self):
        self.assertEqual(self.read(message("msg_1", phase="Reading the ticket.")),
                         ["msg_1 heartbeat coding alive |  | Reading the ticket."])
        self.assertEqual(self.read(message("msg_2", phase="Reading the ticket.")),
                         ["msg_2 heartbeat coding (phase unchanged)"])
        self.assertEqual(self.read(message("msg_3", phase="Slice one is green.")),
                         ["msg_3 heartbeat coding alive |  | Slice one is green."])
        self.assertTrue((self.tmpdir / f"orca-inbox-{RUN}.json").exists())

    def test_another_workers_same_phase_prints_in_full(self):
        self.read(message("msg_1", phase="Reading the ticket."))
        other = message("msg_2", task=TASK_B, ctx=CTX_B, sender=TERM_B, phase="Reading the ticket.")
        self.assertEqual(self.read(other), ["msg_2 heartbeat review alive |  | Reading the ticket."])

    def test_only_a_heartbeat_collapses(self):
        self.read(message("msg_1", phase="Same."))
        status = message("msg_2", mtype="status", subject="received msg_9", phase="Same.")
        self.assertEqual(self.read(status), ["msg_2 status coding received msg_9 |  | Same."])

    def test_state_path_is_overridable(self):
        state = self.dir / "elsewhere.json"
        self.read(message("msg_1", phase="Same."), args=["--state", str(state)])
        self.assertTrue(state.exists())
        self.assertFalse((self.tmpdir / f"orca-inbox-{RUN}.json").exists())
        self.assertEqual(self.read(message("msg_2", phase="Same."), args=["--state", str(state)]),
                         ["msg_2 heartbeat coding (phase unchanged)"])


WAIT_TYPES = "worker_done,escalation,question,heartbeat,status"


class WaitScript(InboxCase):
    def wait(self, *args):
        """Run wait.sh to its end; returns the process (its pid read from the PID= line) and its stdout lines."""
        proc = subprocess.Popen([str(WAIT), *args], env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True)
        out, err = proc.communicate(timeout=30)
        self.assertEqual(proc.returncode, 0, err)
        return proc, out.splitlines()

    def test_ack_wait_and_the_five_types_reach_orca(self):
        self.wait("delivery_9")
        self.assertEqual(self.argv_calls("check"),
                         [["orchestration", "check", "--json", "--ack", "delivery_9", "--wait", "--types", WAIT_TYPES]])

    def test_without_an_ack_it_waits_without_one_and_flags_pass_through(self):
        self.wait("--run", RUN, "--timeout-ms", "1000")
        self.assertEqual(self.argv_calls("check"),
                         [["orchestration", "check", "--json", "--run", RUN, "--wait", "--types", WAIT_TYPES,
                           "--timeout-ms", "1000"]])

    def test_pid_first_is_the_waiters_own_pid_and_delivery_last(self):
        self.set_check(reply([message("msg_1", phase="Working.")]), stderr=keepalive() + "\n")
        proc, lines = self.wait("delivery_9")
        self.assertEqual(lines[0], f"PID={proc.pid}")
        self.assertEqual(lines[1], "DELIVERY=delivery_1")
        self.assertEqual(lines[-1], "DELIVERY=delivery_1")
        self.assertEqual(len(lines), 4)


def alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    return True


def until(cond, seconds=10) -> bool:
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        if cond():
            return True
        time.sleep(0.05)
    return cond()


class NoOrphanWaiter(InboxCase):
    def kill_the_waiter(self, sig):
        (self.fake / "block").write_text("")
        proc = subprocess.Popen([str(WAIT), "delivery_9"], env=self.env, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, text=True)
        self.addCleanup(lambda: (proc.kill(), proc.communicate()))
        pid = int(proc.stdout.readline().strip().removeprefix("PID="))
        self.assertEqual(pid, proc.pid)
        orca_pid_file = self.fake / "orca.pid"
        self.assertTrue(until(orca_pid_file.exists), "the fake orca never started waiting")
        orca_pid = int(orca_pid_file.read_text())
        self.addCleanup(lambda: alive(orca_pid) and os.kill(orca_pid, signal.SIGKILL))
        self.assertTrue(alive(orca_pid))
        os.kill(pid, sig)
        proc.wait(timeout=10)
        self.assertTrue(until(lambda: not alive(orca_pid)), "orca is still running after the reader was killed")

    def test_sigterm(self):
        self.kill_the_waiter(signal.SIGTERM)

    def test_sigint(self):
        self.kill_the_waiter(signal.SIGINT)

    def test_sighup(self):
        self.kill_the_waiter(signal.SIGHUP)


if __name__ == "__main__":
    unittest.main()
