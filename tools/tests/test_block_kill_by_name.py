"""The PreToolUse hook that refuses killing processes by name (.claude/hooks/block_kill_by_name.sh, rules in
block_kill_by_name.py), and its wiring in .claude/settings.json and .skillshare/config.yaml.

The rules are tried on command lines directly; the shim is run the way Claude Code runs it, the hook's JSON on stdin
and the shim reading it without jq, and exit 2 with the reason on stderr is a refusal. The wiring: settings.json and
the skillshare config declare the same PreToolUse matcher and command, so a `skillshare sync` does not drop it.
"""
import json
import os
import shutil
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HOOKS = ROOT / ".claude" / "hooks"
SHIM = HOOKS / "block_kill_by_name.sh"
sys.path.insert(0, str(HOOKS))
import block_kill_by_name as rules  # noqa: E402  (the hook's own rules)

REFUSED = [
    'pkill -f "von serve"',
    "pkill python",
    "killall python3",
    "sudo pkill foo",
    "FOO=1 pkill foo",
    "echo hi && pkill x",
    "echo a; pkill -f x",
    "sleep 1 || killall x",
    "xargs pkill",
    "ls | xargs killall",
    "/usr/bin/pkill foo",
    "echo $(pkill x)",
    "if true; then pkill x; fi",
    'bash -c "pkill -f x"',
    "sh -c 'killall x'",
    'bash -lc "pkill x"',
    'bash -c "echo \\"a\\"; pkill x"',
    'eval "pkill x"',
    "bash <<EOF\npkill x\nEOF",
    "taskkill /F /IM python.exe",
    "taskkill //IM python.exe //F",
    "taskkill -im python.exe",
    'taskkill /f /fi "IMAGENAME eq python.exe"',
    "cmd /c taskkill /IM x.exe",
    "C:/Windows/System32/taskkill.exe /IM a.exe",
    "C:\\Windows\\System32\\taskkill.exe /IM a.exe",
    "Stop-Process -Name python",
    "Stop-Process -ProcessName python -Force",
    "Stop-Process -n python",
    "timeout 5 pkill x",
    "nice -n 10 pkill x",
    "sudo -u root pkill -f x",
    "sudo -n pkill x",
    "env -i FOO=1 killall x",
    "kill -n python",
    "kill -pr python",
    'powershell "Stop-Process -Name x"',
    'pwsh -NoProfile "Stop-Process -ProcessName x"',
    'powershell -NoProfile -ExecutionPolicy Bypass "pkill x"',
    "Get-Process python | % { Stop-Process -Id $_.Id }",
    "gps python | foreach { $_ | Stop-Process }",
    "Get-Process -Name python | ForEach-Object { $_.Kill() }",
    "Get-Process x | % { kill $_.Id }",
    'powershell -Command "Get-Process python | % { Stop-Process -Id $_.Id }"',
    "kill $(pgrep -f von)",
    "kill `pgrep von`",
    'kill "$(pgrep x)"',
    "kill -9 $(pidof python)",
    "pgrep -f von | xargs kill",
    "pgrep von | xargs -r kill -9",
    "bash -c 'kill $(pgrep x)'",
    "spps -na python",
    'powershell -Command "Stop-Process -Name python"',
    'powershell.exe -NoProfile -Command "Stop-Process -ProcessName python"',
    'powershell -c "kill -Name x"',
    'powershell.exe -NoProfile -Command "Get-Process python | Stop-Process"',
    "Get-Process -Name python | Stop-Process -Force",
]
ALLOWED = [
    "kill 123",
    "kill -9 123",
    "kill -TERM $!",
    "kill -n 9 123",
    "kill -n TERM 123",
    "kill -n SIGKILL 5",
    "powershell -File x.ps1",
    "powershell -NoProfile -File x.ps1 Stop-Process",
    'powershell "Get-Date"',
    "pwsh -NoProfile",
    "pgrep von",
    "pgrep von | wc -l",
    "kill $(cat pid)",
    "echo 'kill $(pgrep x)'",
    "Get-Process -Id 5 | % { Stop-Process -Id $_.Id }",
    "command -v pkill",
    "sudo grep pkill file",
    "timeout 5 sleep 1",
    "taskkill /PID 123 /T /F",
    "taskkill //PID 123",
    "Stop-Process -Id 123",
    'powershell -Command "Stop-Process -Id 12"',
    "Get-Process -Id 5 | Stop-Process",
    "Get-Process python",
    "tools/von_stop.sh 123",
    "grep -rn -E 'pkill|killall' .skillshare docs",
    "rg killall",
    "cat pkill.txt",
    "ls | grep pkill",
    "ps aux | grep von",
    'git commit -m "no pkill"',
    'git commit -m "x" -m "never taskkill /IM"',
    "echo pkill",
    'bash -c "echo hi"',
    "python - <<'EOF'\nprint('pkill -f x')\nEOF",
    "python -c \"print('hi')\"",
]


def run_shim(command: str, tool: str = "Bash", env: dict = None) -> subprocess.CompletedProcess:
    event = json.dumps({"hook_event_name": "PreToolUse", "tool_name": tool, "tool_input": {"command": command}})
    return subprocess.run([find_bash(), SHIM.as_posix()], input=event, capture_output=True, text=True, timeout=120,
                          env={**os.environ, "PYTHON": sys.executable, **(env or {})})


def find_bash() -> str:
    """Git Bash on Windows (not the System32 WSL launcher `bash` finds first), `bash` elsewhere."""
    if os.name == "nt":
        for folder in Path(shutil.which("git") or "").parents:
            if (folder / "bin" / "bash.exe").exists():
                return str(folder / "bin" / "bash.exe")
    return shutil.which("bash") or "bash"


class RulesTests(unittest.TestCase):
    def test_every_kill_by_name_form_is_refused(self):
        for command in REFUSED:
            with self.subTest(command=command):
                self.assertIsNotNone(rules.refusal(command))

    def test_killing_by_pid_and_mentioning_the_words_are_allowed(self):
        for command in ALLOWED:
            with self.subTest(command=command):
                self.assertIsNone(rules.refusal(command))

    def test_the_refusal_names_the_way_out(self):
        self.assertIn("kill <pid>", rules.MESSAGE)
        self.assertIn("tools/von_stop.sh <game pid>", rules.MESSAGE)


@unittest.skipUnless(shutil.which("bash"), "no bash to run the hook's shim")
class ShimTests(unittest.TestCase):
    def test_a_kill_by_name_exits_2_and_says_why_on_stderr(self):
        run = run_shim('pkill -f "von serve"')
        self.assertEqual(run.returncode, 2, run.stderr)
        self.assertIn("`pkill`", run.stderr)
        self.assertIn("tools/von_stop.sh <game pid>", run.stderr)

    def test_the_powershell_tool_is_checked_the_same_way(self):
        self.assertEqual(run_shim("Stop-Process -Name python", tool="PowerShell").returncode, 2)

    def test_a_kill_by_pid_passes(self):
        run = run_shim("kill 123")
        self.assertEqual((run.returncode, run.stderr), (0, ""))

    def test_an_event_without_a_command_passes(self):
        run = subprocess.run([find_bash(), SHIM.as_posix()], input='{"tool_name": "AskUserQuestion"}',
                             capture_output=True, text=True, timeout=120, env={**os.environ, "PYTHON": sys.executable})
        self.assertEqual(run.returncode, 0, run.stderr)


class WiringTests(unittest.TestCase):
    COMMAND = '"$CLAUDE_PROJECT_DIR"/.claude/hooks/block_kill_by_name.sh'

    def test_settings_run_the_hook_before_every_bash_and_powershell_call(self):
        settings = json.loads((ROOT / ".claude" / "settings.json").read_text())
        entries = [e for e in settings["hooks"]["PreToolUse"]
                   if any(h["command"] == self.COMMAND for h in e["hooks"])]
        self.assertEqual([e["matcher"] for e in entries], ["Bash|PowerShell"])

    def test_the_skillshare_config_declares_the_same_hook(self):
        text = (ROOT / ".skillshare" / "config.yaml").read_text()
        self.assertIn("block_kill_by_name.sh", text)
        self.assertIn("matcher: Bash|PowerShell", text)

    def test_the_hook_files_are_executable_in_git(self):
        listing = subprocess.run(["git", "ls-files", "-s", "--", ".claude/hooks/block_kill_by_name.sh"], cwd=ROOT,
                                 capture_output=True, text=True).stdout
        if listing:  # not yet added: nothing to check
            self.assertTrue(listing.startswith("100755"), listing)


if __name__ == "__main__":
    unittest.main()
