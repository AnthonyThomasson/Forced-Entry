# Forced-Entry

A small top-down Godot 4.4 demo of squad tactics, organized into seventeen domains under `scenes/`. The NPCs decide with
[Von](https://huggingface.co/wfzyx/von), a local decision model the game starts as a server when it runs from the editor.
`AGENTS.md` is the map for working in the code.

## Set up a machine

One command per OS installs and updates everything the game, Von and the dev tooling need, at the versions pinned in
[`tools/setup/versions.env`](tools/setup/versions.env). Run it from the checkout.

**Before you start.** On a Mac with no Homebrew, install it first (the official one-liner from <https://brew.sh>):

```
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

then put it on your `PATH` for this shell with `eval "$(/opt/homebrew/bin/brew shellenv)"` (`/usr/local/bin/brew` on an
Intel Mac; the installer prints the line to add to `~/.zprofile`). The bootstrap finds `brew` in both places even when
the shell does not. Whichever machine, tell git who you are before your first commit, since the repo's hooks run on it:
`git config --global user.name "Your Name"` and `git config --global user.email you@example.com`.

**Windows** (Windows PowerShell 5.1 or newer, with `winget`; a machine with no Git yet first runs
`winget install --id Git.Git -e`, which may show a UAC prompt and needs an administrator, then you open a new terminal
and clone the repository):

```
powershell -NoProfile -ExecutionPolicy Bypass -File tools\setup\bootstrap.ps1
```

**Mac** (Homebrew for Python, see above; `git` comes with the Xcode command line tools):

```
tools/setup/bootstrap.sh
```

What it does, step by step (each is logged as `installed`, `upgraded` or `up to date`):

| Step | Windows | Mac |
|---|---|---|
| `git` | Git for Windows through `winget` (it brings Git Bash, which the repo's `tools/*.sh` run in) | already there |
| `python` | Python 3.12 through `winget` | `python@3.12` through `brew` |
| `godot` | the standard Godot 4.4.1 (no .NET, no C# in this project) from the GitHub release, checked against the pinned SHA-512, in the per-user folder below | the same, or the Godot already in `/Applications` when it is exactly that version (mono or not) |
| `skillshare` | one at or above the pinned version is kept where it is; otherwise the pinned release (checked against its pinned SHA-256) goes into `<per-user folder>\bin` | the same, into `<per-user folder>/bin` |
| `hooks` | `tools/install_hooks.sh` through Git Bash: the git hooks and the skills links; then the pinned gdstyle (the lint's formatter) into `<per-user folder>\gdstyle`, so the first lint works offline | the same, into `<per-user folder>/gdstyle` |
| `venv` | a venv under the Von home with `von-sdk` at the pinned version (built from Python 3.12 even when a newer Python is installed) | the same |
| `weights` | the Von weights at the pinned revision into `<von home>/checkpoints/von-1.2` (about 3 GB) | the same |

Everything it installs outside the system packages goes into one per-user folder, the **Von home** and Godot's among it:
`%LOCALAPPDATA%\Forced-Entry` on Windows, `~/Library/Application Support/Forced-Entry` on a Mac. Set `FORCED_ENTRY_HOME` to
use another folder (the same one for the bootstrap, the game and the scripts). Inside: `von/` (the venv at `von/venv` and
the weights) and `godot/<version>/`.

**Running it again is safe.** A step that is already done is only checked, so a second run installs nothing and its last
line says so (`done: 0 installed, 0 upgraded, 7 up to date`), and a run with the network off succeeds when everything is
present. A run that stopped (a failed download, a pip error, a closed terminal) leaves something the next run recognises
and finishes: a half-built venv or unpacked Godot is redone, a stopped weights download resumes. When a step changes your
`PATH` (a `winget` install, the skillshare folder) the log ends with a note to open a new terminal; the bootstrap itself
carries on in the same run.

The bootstrap never writes skillshare over another install or into a package manager's folder, and never downgrades
one. The repo's scripts (the hooks, `tools/sync_skills.sh`) look in `<per-user folder>/bin` for skillshare themselves, so
they need no `PATH` change. To run `skillshare` by hand: on Windows the bootstrap adds that folder to your user `PATH`; on a
Mac it prints the line to add to your shell profile (it edits no profile), and until you do, `skillshare` on the command
line is whichever one your `PATH` already finds.

Options (the Windows spelling first): `-Check` / `--check` looks, installs nothing and touches no network, and exits 1 when
any step is missing or out of date; `-Skip a,b` / `--skip=a,b` leaves steps out (`git python godot skillshare hooks venv
weights`). `GODOT` and `PYTHON` pick a Godot or a Python for every script (otherwise they look on `PATH`, in the per-user
folder and in the usual install places); `FE_VON_PYTHON` builds the Von venv from a Python of your choice, whatever version.
The dev tools (lint, the tool tests, the hooks) need Python 3.12 or newer (`PYTHON_MIN` in `versions.env`): a script skips
an older `python3` (a fresh Mac's `/usr/bin/python3` is 3.9) and finds `python3.12` from Homebrew by itself, and a
`PYTHON` below that is refused with a message.

Optional: `jq`. The hook that tells you a session is waiting on you (`.claude/hooks/needs_you_hook.sh`, a Mac banner) needs
it; macOS before 15 has none (`brew install jq`), and without it the hook does nothing and says nothing.

## Start Von by hand

The game starts Von itself when you press Play in the editor. To run it yourself (for `tools/von_probe.py`, or a game that
should not start its own):

```
powershell -NoProfile -ExecutionPolicy Bypass -File tools\von\boot.ps1 [-Port 8000] [-Device cpu]   # Windows
tools/von/boot.sh [--port 8000] [--device cpu]                                                        # Mac
```

Von reads its weights only from `checkpoints/von-1.2` next to where it is started, so the script starts it from the Von
home. It installs nothing: when the setup is missing or broken it exits with code 3 and one line naming the cause and the
bootstrap command that fixes it. `-Check` / `--check` only checks (exit 0, `von: ready`) and also runs `von --version`.
Stop it with Ctrl+C, or by ending its process (`kill <pid>` on a Mac). On Windows the server is bound to the script: ending
`boot.ps1` ends the server.

## Checks

`tools/run_tests.sh` runs the game's tests, `tools/tool_tests.sh` the tool tests, `tools/lint.sh` the lint; `AGENTS.md`
says when each runs on its own.

The `tools/*.sh` scripts are bash scripts. On Windows run them from Git Bash, or from PowerShell through Git's bash:
`& "$env:ProgramFiles\Git\bin\bash.exe" tools/run_tests.sh --list` (the same for `tools/lint.sh` and the rest).
