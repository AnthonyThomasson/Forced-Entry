# Forced-Entry

A small top-down Godot 4.4 demo of squad tactics, organized into seventeen domains under `scenes/`. The NPCs decide with
[Von](https://huggingface.co/wfzyx/von), a local decision model the game starts as a server when it runs from the editor.
`AGENTS.md` is the map for working in the code.

## Set up a machine

One command per OS installs and updates everything the game, Von and the dev tooling need, at the versions pinned in
[`tools/setup/versions.env`](tools/setup/versions.env). Run it from the checkout.

**Windows** (Windows PowerShell 5.1 or newer, with `winget`; a machine with no Git yet first runs
`winget install --id Git.Git -e`, opens a new terminal and clones the repository):

```
powershell -NoProfile -ExecutionPolicy Bypass -File tools\setup\bootstrap.ps1
```

**Mac** (Homebrew for Python; `git` comes with the Xcode command line tools):

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
| `hooks` | `tools/install_hooks.sh` through Git Bash: the git hooks and the skills links | the same |
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
