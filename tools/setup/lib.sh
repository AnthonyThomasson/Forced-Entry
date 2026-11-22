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
#   fe_find_python             the Python: $PYTHON as it is; python3 only if it really runs (on Windows it is the
#                              Microsoft Store stub); py -3; python. One executable (`py -3` is resolved to its python.exe)
#   fe_use_python              fe_find_python, exported as $PYTHON; on none, says so on stderr and returns 2
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
    echo "Godot binary not found (set GODOT=/path/to/Godot, or run the setup bootstrap)" >&2
    return 2
  }
  export GODOT
}

fe_find_python() {
  if [[ -n "${PYTHON:-}" ]]; then
    printf '%s\n' "$PYTHON"
    return 0
  fi
  local exe
  if command -v python3 >/dev/null 2>&1 && python3 -c 'import sys' >/dev/null 2>&1; then
    echo python3
    return 0
  fi
  if command -v py >/dev/null 2>&1; then
    exe="$(py -3 -c 'import sys; print(sys.executable)' 2>/dev/null | tr -d '\r')"
    if [[ -n "$exe" ]]; then
      fe_posix_path "$exe"
      return 0
    fi
  fi
  if command -v python >/dev/null 2>&1 && python -c 'import sys' >/dev/null 2>&1; then
    echo python
    return 0
  fi
  return 1
}

fe_use_python() {
  PYTHON="$(fe_find_python)" || {
    echo "Python not found (set PYTHON=/path/to/python, or run the setup bootstrap)" >&2
    return 2
  }
  export PYTHON
  # Windows Python ends every output line with CR LF; pysite/sitecustomize.py makes it write LF only, so what a
  # script captures from a tool has no stray CR. Know that PYTHONPATH is inherited: every child process of the script
  # (Python or not, a Von server started from it included) sees it; that a sitecustomize.py found through PYTHONPATH
  # shadows any other sitecustomize module on the path; and that `python -I` and `python -S` skip it (so a tool run
  # that way, like `python -I tools/audit_scan.py`, still writes CR LF on Windows).
  if [[ "$(fe_os)" == windows && ";${PYTHONPATH:-};" != *";$(cygpath -w "$FE_SETUP_DIR/pysite");"* ]]; then
    export PYTHONPATH="$(cygpath -w "$FE_SETUP_DIR/pysite")${PYTHONPATH:+;$PYTHONPATH}"
  fi
}
