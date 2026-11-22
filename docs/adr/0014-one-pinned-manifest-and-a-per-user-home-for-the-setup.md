# One pinned manifest and a per-user home for everything the setup installs

Forced-Entry has to boot from a fresh install on a Mac and on Windows (issue #213): the game, the Von decision server and the dev tooling. Until
then the setup was a Mac set up by hand (a Godot in `/Applications`, a venv in `~/.venvs/von`, a path in `project.godot`). Four choices
shape the bootstrap that replaces it, and a reader who meets the scripts will ask each.

## One manifest pins every version

`tools/setup/versions.env` holds every pin the setup installs: the Godot version, its release zips and their SHA-512, the Python the Von venv is
built from, the `von-sdk` version, the Von weights' repo and exact revision, and the skillshare release and its SHA-256. It is plain `KEY=value`
lines so bash, Windows PowerShell 5.1 and Python each read it with nothing installed (no `jq`, no extra module), and the two bootstraps, the
launcher, the Godot lookup and the tests all read the one file. A pin changes there and nowhere else (a test fails a script that repeats one).

Each step checks first and installs or upgrades only what is missing or out of date, so a second run installs nothing and a run with the network
off succeeds when everything is already there: no step goes to the network unless it has work.

## A per-user Forced-Entry home, overridable

Everything the bootstrap installs that is not a system package lives under one root: Windows `%LOCALAPPDATA%\Forced-Entry`, macOS
`~/Library/Application Support/Forced-Entry`, with `FORCED_ENTRY_HOME` replacing it. Inside it: `von/` (the **Von home**) and
`godot/<version>/`. It is per user (no admin rights, nothing in the checkout, so every worktree shares one install) and it is one place to look at or
delete. The override is how the tool tests and a trial run use a scratch root without touching the real one. The Mac's existing `~/.venvs/von` is
left alone: the bootstrap builds its own and does not adopt it.

## The standard Godot 4.4.1, no .NET

The project has no C# code, so the standard (non-mono) build is pinned exactly, and no .NET SDK is installed. The ticket first listed a mono
editor and the .NET 8 SDK; with no C# they would be a larger download and a second toolchain for nothing. A lookup still accepts an existing
mono build of the pinned version (the Mac has one in `/Applications`), because the engine behaves the same; only the version must match.

## Von is started from the Von home

Von reads its weights from `checkpoints/von-1.2/` relative to the folder it is started in and has no flag or variable for that, so the boot scripts
start it with the Von home as its working directory, and the bootstrap downloads the weights to `<von home>/checkpoints/von-1.2`. The venv is
`<von home>/venv`, so the Von home is the whole of Von's install. The venv is built from Python 3.12 even when a newer Python is installed,
because the wheels Von's dependencies need (PyTorch above all) lag behind the newest Python.

## Considered options

- **A checkout-relative install** (a venv and weights inside each worktree). Rejected: every worktree would download three gigabytes of weights and
  build its own venv, and the game launcher would have to find them from `res://`.
- **One shared system location chosen by a script** (`/opt`, `C:\Program Files`). Rejected: it needs admin rights on Windows, and a per-user root
  is just as findable through one function in each language.
- **A different manifest format** (JSON, TOML). Rejected: PowerShell 5.1 and bash cannot read either without a tool the fresh machine does not
  have yet; the manifest is read before anything is installed.

## Consequences

- A fresh machine needs one command per OS (`tools/setup/bootstrap.ps1`, `tools/setup/bootstrap.sh`; the README) and winget or Homebrew for the
  system packages. Anything else the bootstrap fetches comes from a pinned URL and is checked against a pinned checksum.
- Where Von is installed is no longer something a developer sets (`application/von/server_path` in `project.godot` goes); the launcher runs the
  boot script for the current OS, which finds the Von home itself.
- Moving Von to another Python, Godot or weights revision is a one-line change in the manifest and a re-run of the bootstrap.
