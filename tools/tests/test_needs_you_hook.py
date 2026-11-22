"""The needs-you hook (.claude/hooks/needs_you_hook.sh): a macOS banner and spoken alert. On Windows it has neither
osascript nor say (and Git Bash no jq), so it exits 0 at once and prints nothing, even in its dry-run mode."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HOOK = ROOT / ".claude" / "hooks" / "needs_you_hook.sh"
BASH = shutil.which("bash")
QUESTION = {"hook_event_name": "PreToolUse", "session_id": "s", "cwd": str(ROOT),
            "tool_input": {"questions": [{"question": "Which one?", "options": [{"label": "A"}, {"label": "B"}]}]}}


@unittest.skipUnless(BASH, "no bash")
class NeedsYouHookTests(unittest.TestCase):
    def run_hook(self, event: dict):
        tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, tmp, True)
        env = dict(os.environ, NEEDS_YOU_DRY_RUN="1", TMPDIR=tmp)
        return subprocess.run([BASH, str(HOOK)], input=json.dumps(event), env=env, capture_output=True, text=True, timeout=60)

    @unittest.skipUnless(sys.platform == "win32", "the quiet exit is the Windows behaviour")
    def test_on_windows_it_exits_0_and_says_nothing(self):
        r = self.run_hook(QUESTION)
        self.assertEqual((r.returncode, r.stdout, r.stderr), (0, "", ""))

    @unittest.skipIf(sys.platform == "win32", "needs jq, which Git Bash has not; Windows stays quiet")
    @unittest.skipUnless(shutil.which("jq"), "no jq")
    def test_a_question_is_printed_by_the_dry_run(self):
        r = self.run_hook(QUESTION)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("Which one? Options: A, B", r.stdout)


if __name__ == "__main__":
    unittest.main()
