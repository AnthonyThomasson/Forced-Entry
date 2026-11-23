# Sourced, not run: the one lookup of where Forced-Entry's per-user setup lives and which Godot and Python to use.
# tools/setup/fe_env.py (Python) and tools/setup/lib.ps1 (Windows PowerShell 5.1) do the same lookups; keep the three
# in step (tools/tests/test_setup_resolvers.py checks that bash and Python agree). Works on macOS (bash 3.2), Windows
# (Git Bash) and Linux, with no jq, pgrep or lsof.
#
#   source "$(dirname "${BASH_SOURCE[0]}")/setup/lib.sh"      # from a tools/*.sh script
#
# The per-user root (fe_home), where everything the bootstrap installs goes:
#   $FORCED_ENTRY_HOME if set; else Windows %LOCALAPPDATA%\Forced-Entry, macOS ~/Library/Application Support/Forced-Entry,
#   Linux ${XDG_DATA_HOME:-~/.local/share}/Forced-Entry. Inside it: von/ (<von home>: the venv and
#   checkpoints/von-1.2; Von is started with it as its working directory) and godot/<GODOT_VERSION>/.
#
# Functions (a path is printed POSIX-style, so /c/Users/... on Windows; the `fe_find_*` print nothing and return 1
# when there is none):
#   fe_os                      windows | macos | linux
#   fe_manifest_get KEY        the value of KEY in tools/setup/versions.env (prints nothing, returns 1, when it has none)
#   fe_home                    the per-user root
#   fe_von_home                <root>/von
#   fe_godot_dir [VERSION]     <root>/godot/<VERSION> (default: the manifest's GODOT_VERSION)
#   fe_find_godot              the Godot binary: $GODOT as it is; godot / godot4 on PATH; the install folder above; then
#                              the usual per-OS places (macOS /Applications/Godot*.app, mono or not; Windows
#                              %LOCALAPPDATA%\Programs, winget, Program Files, scoop)
#   fe_use_godot               fe_find_godot, exported as $GODOT; on none, says so on stderr and returns 2
#   fe_find_python             the Python, at PYTHON_MIN (versions.env) or newer: $PYTHON when it is that (below it, a
#                              warning and none); else python3.14 / python3.13 / python3.12 on PATH, then in
#                              /opt/homebrew/bin and /usr/local/bin (a Homebrew `python@3.12` has only python3.12);
#                              then python3 (PATH, then those folders) only if it really runs and is new enough (on
#                              Windows it is the Microsoft Store stub; a fresh Mac's /usr/bin/python3 is 3.9); py -3;
#                              python. One executable (`py -3` is resolved to its python.exe)
#   fe_use_python              fe_find_python, exported as $PYTHON; on none, says so on stderr and returns 2
#   fe_bootstrap_cmd           the command that runs the setup bootstrap on this OS
#   fe_hash [ALGO]             stdin's digest in hex (ALGO 1, 256 or 512; default 1), with a tool that is in /usr/bin
#                              on a Mac and in Git Bash's /usr/bin on Windows: `shasum` is not on PATH outside a login Git Bash
#   fe_hash_file ALGO FILE     the same for a file
# A caller under `set -e` writes `fe_use_godot || exit $?`.

FE_SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fe_os() {
  case "$(uname -s)" in
    Darwin) echo macos ;;
    MINGW* | MSYS* | CYGWIN*) echo windows ;;
    *) echo linux ;;
  esac
}

# A path as bash on this OS reads it: on Windows C:\x and C:/x become /c/x (cygpath).
fe_posix_path() {
  if [[ "$(fe_os)" == windows ]] && command -v cygpath >/dev/null 2>&1; then
    cygpath -u "$1"
  else
    printf '%s\n' "$1"
  fi
}

fe_manifest_get() {
  local key="$1" line k
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" == \#* || "$line" != *=* ]] && continue
    k="${line%%=*}"
    if [[ "$k" == "$key" ]]; then
      printf '%s\n' "${line#*=}"
      return 0
    fi
  done < "$FE_SETUP_DIR/versions.env"
  return 1
}

fe_home() {
  if [[ -n "${FORCED_ENTRY_HOME:-}" ]]; then
    fe_posix_path "$FORCED_ENTRY_HOME"
    return 0
  fi
  case "$(fe_os)" in
    windows) printf '%s/Forced-Entry\n' "$(fe_posix_path "${LOCALAPPDATA:-$HOME/AppData/Local}")" ;;
    macos) printf '%s/Library/Application Support/Forced-Entry\n' "$HOME" ;;
    *) printf '%s/Forced-Entry\n' "${XDG_DATA_HOME:-$HOME/.local/share}" ;;
  esac
}

fe_von_home() { printf '%s/von\n' "$(fe_home)"; }

fe_godot_dir() { printf '%s/godot/%s\n' "$(fe_home)" "${1:-$(fe_manifest_get GODOT_VERSION)}"; }

# The Godot binary in the first of these folders (or .app bundles) that holds one: a Windows folder's _console.exe
# first (it writes to the terminal a script reads), then any other Godot*.exe; a macOS bundle's Contents/MacOS/Godot
# (the folder itself, or a Godot*.app in it); a Linux Godot file.
_fe_godot_in() {
  local dir f
  for dir in "$@"; do
    [[ -d "$dir" ]] || continue
    for f in "$dir"/Godot*_console.exe "$dir"/godot*_console.exe "$dir"/Godot*.exe "$dir"/godot*.exe \
        "$dir"/Contents/MacOS/Godot "$dir"/Godot*.app/Contents/MacOS/Godot "$dir"/Godot "$dir"/godot; do
      if [[ -f "$f" ]]; then
        printf '%s\n' "$f"
        return 0
      fi
    done
  done
  return 1
}

fe_find_godot() {
  if [[ -n "${GODOT:-}" ]]; then
    printf '%s\n' "$GODOT"
    return 0
  fi
  local name found d pf local_app
  for name in godot godot4; do
    found="$(command -v "$name" 2>/dev/null)" && { printf '%s\n' "$found"; return 0; }
  done
  _fe_godot_in "$(fe_godot_dir)" && return 0
  local -a dirs=()
  case "$(fe_os)" in
    macos)
      # /Applications before ~/Applications; Godot.app before Godot_mono.app (a glob sorts).
      for d in /Applications/Godot*.app "$HOME"/Applications/Godot*.app; do dirs+=("$d"); done ;;
    windows)
      local_app="$(fe_posix_path "${LOCALAPPDATA:-$HOME/AppData/Local}")"
      pf="$(fe_posix_path "${PROGRAMFILES:-C:/Program Files}")"
      for d in "$local_app"/Programs/Godot* "$local_app"/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_* \
          "$pf"/Godot* "$pf (x86)"/Godot* "$HOME"/scoop/apps/godot/current "$HOME"/scoop/apps/godot-mono/current; do
        dirs+=("$d")
      done ;;
    *)
      for d in /opt/godot* "$HOME"/.local/bin; do dirs+=("$d"); done ;;
  esac
  _fe_godot_in ${dirs[@]+"${dirs[@]}"}
}

fe_use_godot() {
  GODOT="$(fe_find_godot)" || {
    echo "Godot binary not found (set GODOT=/path/to/Godot, or run: $(fe_bootstrap_cmd))" >&2
    return 2
  }
  export GODOT
}

# The command that installs and pins everything on this OS (what a "not found" message tells the user to run).
fe_bootstrap_cmd() {
  if [[ "$(fe_os)" == windows ]]; then
    echo 'powershell -NoProfile -ExecutionPolicy Bypass -File tools\setup\bootstrap.ps1'
  else
    echo tools/setup/bootstrap.sh
  fi
}

# One digest tool, whichever of these the machine has: sha<N>sum is in /usr/bin on Windows (Git Bash) and Linux, shasum on
# a Mac. `shasum` alone is not on PATH outside a login Git Bash (it lives in /usr/bin/core_perl, which only /etc/profile
# adds), so a script run from PowerShell, cmd, VS Code or by git.exe cannot rely on it. The last resort is cksum
# (POSIX, everywhere): a CRC, enough to tell one tree state from another.
fe_hash() {
  local algo="${1:-1}"
  if command -v "sha${algo}sum" >/dev/null 2>&1; then
    "sha${algo}sum"
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a "$algo"
  else
    cksum
  fi | cut -d' ' -f1 | tr -d '\\'
}
fe_hash_file() { fe_hash "$1" < "$2"; }

# "MAJOR.MINOR" of the Python $1 (a command name or a path); nothing when it does not run (the Microsoft Store stub).
_fe_python_version() { "$1" -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null | tr -d '\r'; }

# Version $1 is $2 or newer (both MAJOR.MINOR; an unreadable $1 is older).
_fe_version_ge() {
  local a="${1%%.*}" b="${1#*.}" c="${2%%.*}" d="${2#*.}"
  [[ "$a" =~ ^[0-9]+$ && "$b" =~ ^[0-9]+$ ]] || return 1
  (( 10#$a > 10#$c || (10#$a == 10#$c && 10#$b >= 10#$d) ))
}

fe_python_min() { fe_manifest_get PYTHON_MIN || echo 3.12; }

# Prints $1 and succeeds when it is a Python that runs and is at least $2.
_fe_python_try() {
  local v
  command -v "$1" >/dev/null 2>&1 || return 1
  v="$(_fe_python_version "$1")"
  [[ -n "$v" ]] && _fe_version_ge "$v" "$2" || return 1
  printf '%s\n' "$1"
}

# The folders a Homebrew Python is in whether or not the shell has `brew shellenv` applied (a fresh Mac's PATH has no
# /opt/homebrew/bin). FE_PYTHON_EXTRA_DIRS overrides the list (the tests empty it).
_fe_python_dirs() { echo "${FE_PYTHON_EXTRA_DIRS-/opt/homebrew/bin /usr/local/bin}"; }

fe_find_python() {
  local min v exe c d
  min="$(fe_python_min)"
  if [[ -n "${PYTHON:-}" ]]; then
    # An earlier fe_use_python in a parent script already checked this one.
    [[ "${FE_PYTHON_CHECKED:-}" == "$PYTHON" ]] && { printf '%s\n' "$PYTHON"; return 0; }
    v="$(_fe_python_version "$PYTHON")"
    if [[ -n "$v" ]] && _fe_version_ge "$v" "$min"; then
      printf '%s\n' "$PYTHON"
      return 0
    fi
    if [[ -n "$v" ]]; then
      echo "warning: \$PYTHON ($PYTHON) is Python $v, below the $min the tools need; not using it" >&2
    else
      echo "warning: \$PYTHON ($PYTHON) is not a Python that runs; not using it" >&2
    fi
    return 1
  fi
  # The versioned names first: a Homebrew `python@3.12` installs python3.12 only, and a bare python3 may be the old one.
  for c in python3.14 python3.13 python3.12; do
    _fe_python_try "$c" "$min" && return 0
    for d in $(_fe_python_dirs); do
      _fe_python_try "$d/$c" "$min" && return 0
    done
  done
  _fe_python_try python3 "$min" && return 0
  for d in $(_fe_python_dirs); do
    _fe_python_try "$d/python3" "$min" && return 0
  done
  if command -v py >/dev/null 2>&1; then
    exe="$(py -3 -c 'import sys; print(sys.executable)' 2>/dev/null | tr -d '\r')"
    if [[ -n "$exe" ]]; then
      exe="$(fe_posix_path "$exe")"
      v="$(_fe_python_version "$exe")"
      if [[ -n "$v" ]] && _fe_version_ge "$v" "$min"; then
        printf '%s\n' "$exe"
        return 0
      fi
    fi
  fi
  _fe_python_try python "$min" && return 0
  return 1
}

fe_use_python() {
  local found
  found="$(fe_find_python)" || {
    echo "Python >= $(fe_python_min) not found; run $(fe_bootstrap_cmd)" >&2
    return 2
  }
  PYTHON="$found"
  export PYTHON
  # What a script started from this one need not check again (it is a few launches of Python per script otherwise).
  export FE_PYTHON_CHECKED="$PYTHON"
  # Windows Python ends every output line with CR LF; pysite/sitecustomize.py makes it write LF only, so what a
  # script captures from a tool has no stray CR. Know that PYTHONPATH is inherited: every child process of the script
  # (Python or not, a Von server started from it included) sees it; that a sitecustomize.py found through PYTHONPATH
  # shadows any other sitecustomize module on the path; and that `python -I` and `python -S` skip it (so a tool run
  # that way, like `python -I tools/audit_scan.py`, still writes CR LF on Windows).
  if [[ "$(fe_os)" == windows && ";${PYTHONPATH:-};" != *";$(cygpath -w "$FE_SETUP_DIR/pysite");"* ]]; then
    export PYTHONPATH="$(cygpath -w "$FE_SETUP_DIR/pysite")${PYTHONPATH:+;$PYTHONPATH}"
  fi
}
