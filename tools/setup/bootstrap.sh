#!/usr/bin/env bash
# The Mac bootstrap: installs or upgrades what Forced-Entry needs, one step at a time, each logged as installed,
# upgraded or up to date. Every version is pinned in tools/setup/versions.env. Safe to re-run: it carries on where it
# stopped (a half-finished venv, weights or Godot unpack is detected and redone), a second run installs nothing, and a
# run with the network off succeeds when everything is already there (no step goes to the network unless it has work).
#
#   tools/setup/bootstrap.sh [--check] [--skip=STEP,...]
#     --check        look, install nothing and touch no network: log each step as up to date or missing/outdated;
#                    exit 1 when any is
#     --skip=STEPS   leave these steps out (comma list of: git python godot skillshare hooks venv weights)
# Steps, in order: git, python (3.12 for the Von venv), godot (the pinned standard build), skillshare, hooks (git hooks
# and the skills links, tools/install_hooks.sh), venv (the Von venv under <von home> with von-sdk), weights (the Von
# weights under <von home>/checkpoints/von-1.2). The per-user root is tools/setup/lib.sh's fe_home (FORCED_ENTRY_HOME).
# Exit codes: 0 every step is up to date or done; 1 a step failed (the log names it; re-run to carry on) or, with
# --check, something is missing; 2 a bad argument.
# Other environment: FE_VON_PYTHON=/path/to/python builds the Von venv from that Python instead of a 3.12 (its version
# is then not checked). Windows runs tools/setup/bootstrap.ps1; here a step that needs an install on Windows or Linux
# stops with that message, but --check works on every OS (the tool tests run it in Git Bash).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
ROOT="$PWD"
source tools/setup/lib.sh

CHECK=0
SKIP=","
for a in "$@"; do
  case "$a" in
    --check) CHECK=1 ;;
    --skip=*) SKIP=",${a#--skip=}," ;;
    -h | --help) sed -n '2,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "bootstrap: unknown argument: $a (tools/setup/bootstrap.sh [--check] [--skip=STEP,...])" >&2; exit 2 ;;
  esac
done

OS="$(fe_os)"
HOME_DIR="$(fe_home)"
VON_HOME="$(fe_von_home)"
VENV="$VON_HOME/venv"
WEIGHTS="$VON_HOME/checkpoints/von-1.2"
# The files Von loads from the weights folder, and the marker that says which revision they are.
WEIGHT_FILES="config.json tokenizer.json calibration.json marker_calibration.json model.safetensors option_marker.pt"
MARKER=".fe-revision"
if [[ "$OS" == windows ]]; then VENV_BIN="$VENV/Scripts"; EXE=".exe"; else VENV_BIN="$VENV/bin"; EXE=""; fi

N_INSTALLED=0; N_UPGRADED=0; N_OK=0; N_MISSING=0; N_SKIPPED=0
NOTES=()
log() { echo "bootstrap: $*"; }
ok() { N_OK=$((N_OK + 1)); log "$1: up to date ($2)"; }
installed() { N_INSTALLED=$((N_INSTALLED + 1)); log "$1: installed ($2)"; }
upgraded() { N_UPGRADED=$((N_UPGRADED + 1)); log "$1: upgraded ($2)"; }
# With --check a step that has work to do reports it here and goes on; otherwise the caller installs.
missing() { N_MISSING=$((N_MISSING + 1)); log "$1: $2"; }
fail() { log "$1: FAILED: $2"; log "fix the cause and run the bootstrap again; it carries on from here"; exit 1; }
M() { fe_manifest_get "$1"; }

# Download URL to FILE (a partial file never stays) and check its checksum: sum_cmd is "shasum -a 512" or similar.
download() { # url dest
  mkdir -p "$(dirname "$2")"
  curl -fL --retry 3 --retry-delay 2 -sS -o "$2.part" "$1" || { rm -f "$2.part"; return 1; }
  mv -f "$2.part" "$2"
}
checksum() { # algo(256|512) file
  if command -v shasum >/dev/null 2>&1; then shasum -a "$1" "$2" | cut -d' ' -f1
  else "sha$1"sum "$2" | cut -d' ' -f1; fi
}
TMP=""
# Sets $TMP to a scratch folder removed on exit (not run in a $(...), which would lose the variable and the trap).
mk_tmp() { [[ -n "$TMP" ]] || { TMP="$(mktemp -d "${TMPDIR:-/tmp}/fe-bootstrap.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT; }; }

# ---- git ---------------------------------------------------------------------------------------------------------
step_git() {
  local v
  if v="$(git --version 2>/dev/null)"; then ok git "$v"; return; fi
  [[ $CHECK -eq 1 ]] && { missing git "missing"; return; }
  if [[ "$OS" == macos ]]; then fail git "git is not installed: run 'xcode-select --install', then this again"; fi
  fail git "git is not installed: install it for this OS, then run this again"
}

# ---- python (the 3.12 the Von venv is built from) ------------------------------------------------------------------
py_minor() { "$1" -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null | tr -d '\r'; }
find_von_python() {
  local want c exe
  [[ -n "${FE_VON_PYTHON:-}" ]] && { echo "$FE_VON_PYTHON"; return 0; }
  want="$(M VON_PYTHON)"
  for c in "python$want" /opt/homebrew/bin/python$want /usr/local/bin/python$want \
      /opt/homebrew/opt/python@$want/bin/python$want /usr/local/opt/python@$want/bin/python$want \
      "$(fe_posix_path "${LOCALAPPDATA:-$HOME/AppData/Local}")/Programs/Python/Python${want/./}/python.exe"; do
    command -v "$c" >/dev/null 2>&1 || [[ -x "$c" ]] || continue
    [[ "$(py_minor "$c")" == "$want" ]] && { command -v "$c"; return 0; }
  done
  if command -v py >/dev/null 2>&1; then
    exe="$(py "-$want" -c 'import sys; print(sys.executable)' 2>/dev/null | tr -d '\r')"
    [[ -n "$exe" ]] && { fe_posix_path "$exe"; return 0; }
  fi
  return 1
}
step_python() {
  local want py
  want="$(M VON_PYTHON)"
  if py="$(find_von_python)"; then ok python "$("$py" --version 2>&1) at $py"; return; fi
  [[ $CHECK -eq 1 ]] && { missing python "missing (Python $want for the Von venv)"; return; }
  [[ "$OS" == macos ]] || fail python "no Python $want: on Windows run tools/setup/bootstrap.ps1; Linux is not supported yet"
  command -v brew >/dev/null 2>&1 || fail python "Homebrew is needed to install Python $want: https://brew.sh"
  brew install "python@$want" || fail python "brew install python@$want failed"
  py="$(find_von_python)" || fail python "python@$want installed but no python$want found; open a new shell and re-run"
  installed python "$("$py" --version 2>&1) at $py"
}

# ---- godot (the pinned standard build; an existing build of that version, mono or not, is kept) --------------------
godot_matches() { # binary: its --version starts with the pin (the manifest's X-stable reads X.stable.<flavour>.<hash>)
  local want v
  want="$(M GODOT_VERSION)"; want="${want/-/.}"
  v="$("$1" --version 2>/dev/null | tr -d '\r' | head -n1)" || return 1
  [[ "$v" == "$want" || "$v" == "$want".* ]]
}
step_godot() {
  local want cur pinned zip dir tmp
  want="$(M GODOT_VERSION)"
  if cur="$(fe_find_godot)" && godot_matches "$cur"; then ok godot "$want at $cur"; return; fi
  if pinned="$(_fe_godot_in "$(fe_godot_dir)")" && godot_matches "$pinned"; then
    ok godot "$want at $pinned"
    [[ -n "${cur:-}" ]] && log "godot: note: $cur comes first in the lookup and is not $want; unset GODOT or remove it"
    return
  fi
  [[ $CHECK -eq 1 ]] && { missing godot "missing ($want${cur:+; $cur is another version})"; return; }
  [[ "$OS" == macos ]] || fail godot "no Godot $want: on Windows run tools/setup/bootstrap.ps1; Linux is not supported yet"
  zip="$(M GODOT_MACOS_ZIP)"; mk_tmp; tmp="$TMP"
  log "godot: downloading $zip"
  download "$(M GODOT_BASE_URL)/$zip" "$tmp/$zip" || fail godot "download of $(M GODOT_BASE_URL)/$zip failed (network?)"
  [[ "$(checksum 512 "$tmp/$zip")" == "$(M GODOT_MACOS_SHA512)" ]] || fail godot "$zip does not match the SHA-512 pinned in versions.env"
  dir="$(fe_godot_dir)"
  rm -rf "$dir" "$dir.partial"
  mkdir -p "$dir.partial" && unzip -q "$tmp/$zip" -d "$dir.partial" || fail godot "unpacking $zip failed"
  mv "$dir.partial" "$dir"
  pinned="$(_fe_godot_in "$dir")" && godot_matches "$pinned" || fail godot "the unpacked Godot in $dir does not report $want"
  installed godot "$want at $pinned"
  [[ -n "${cur:-}" ]] && log "godot: note: $cur comes first in the lookup and is not $want; unset GODOT or remove it"
}

# ---- skillshare --------------------------------------------------------------------------------------------------
find_skillshare() {
  local c
  for c in "$(command -v skillshare 2>/dev/null)" "$HOME_DIR/bin/skillshare$EXE" "$HOME/go/bin/skillshare"; do
    [[ -n "$c" && -x "$c" ]] && { echo "$c"; return 0; }
  done
  return 1
}
step_skillshare() {
  local want have bin dir tmp name sha arch
  want="$(M SKILLSHARE_VERSION)"
  if bin="$(find_skillshare)"; then
    have="$("$bin" --version 2>/dev/null | tr -d '\r' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)"
    [[ "$have" == "$want" ]] && { ok skillshare "v$want at $bin"; return; }
  fi
  if [[ $CHECK -eq 1 ]]; then
    if [[ -n "${bin:-}" ]]; then missing skillshare "outdated (v${have:-?}), needs v$want"; else missing skillshare "missing (needs v$want)"; fi
    return
  fi
  [[ "$OS" == macos ]] || fail skillshare "no skillshare $want: on Windows run tools/setup/bootstrap.ps1; Linux is not supported yet"
  case "$(uname -m)" in
    arm64 | aarch64) name="$(M SKILLSHARE_MACOS_ARM64_TGZ)"; sha="$(M SKILLSHARE_MACOS_ARM64_SHA256)" ;;
    *) name="$(M SKILLSHARE_MACOS_AMD64_TGZ)"; sha="$(M SKILLSHARE_MACOS_AMD64_SHA256)" ;;
  esac
  # An old one is replaced where it is (so the PATH still finds the new one); else it goes into <home>/bin.
  if [[ -n "${bin:-}" ]]; then dir="$(dirname "$bin")"; else dir="$HOME_DIR/bin"; fi
  mk_tmp; tmp="$TMP"
  log "skillshare: downloading $name"
  download "$(M SKILLSHARE_BASE_URL)/$name" "$tmp/$name" || fail skillshare "download of $name failed (network?)"
  [[ "$(checksum 256 "$tmp/$name")" == "$sha" ]] || fail skillshare "$name does not match the SHA-256 pinned in versions.env"
  mkdir -p "$tmp/ss" "$dir" && tar -xzf "$tmp/$name" -C "$tmp/ss" skillshare || fail skillshare "unpacking $name failed"
  mv -f "$tmp/ss/skillshare" "$dir/skillshare" && chmod +x "$dir/skillshare" || fail skillshare "could not write $dir/skillshare"
  if [[ -n "${bin:-}" ]]; then upgraded skillshare "v${have:-?} to v$want at $dir"; else installed skillshare "v$want at $dir"; fi
  case ":$PATH:" in *":$dir:"*) ;; *) NOTES+=("add $dir to your PATH (for example: echo 'export PATH=\"$dir:\$PATH\"' >> ~/.zshrc), then open a new shell") ;; esac
}

# ---- hooks and skills --------------------------------------------------------------------------------------------
step_hooks() {
  local ss
  if [[ "$(git config core.hooksPath 2>/dev/null)" == .githooks && -n "$(ls -A .claude/skills 2>/dev/null)" ]]; then
    ok hooks "core.hooksPath=.githooks, skills linked"; return
  fi
  [[ $CHECK -eq 1 ]] && { missing hooks "missing (tools/install_hooks.sh has not run in this checkout)"; return; }
  # install_hooks.sh runs sync_skills.sh, which needs skillshare on the PATH: it may have just been put elsewhere.
  if ss="$(find_skillshare)"; then PATH="$(dirname "$ss"):$PATH"; export PATH; fi
  bash tools/install_hooks.sh || fail hooks "tools/install_hooks.sh failed (see above)"
  installed hooks "git hooks enabled, skills linked"
}

# ---- the Von venv ------------------------------------------------------------------------------------------------
VPY() { echo "$VENV_BIN/python$EXE"; }
# Why the venv is not usable, or nothing: a rebuild is needed when the answer starts with "rebuild".
venv_problem() {
  local cfg home want vminor
  [[ -d "$VENV" ]] || { echo "none"; return; }
  cfg="$VENV/pyvenv.cfg"
  [[ -f "$cfg" ]] || { echo "rebuild: $VENV has no pyvenv.cfg"; return; }
  home="$(sed -n 's/^home *= *//p' "$cfg" | head -n1 | tr -d '\r')"
  [[ -n "$home" && -d "$(fe_posix_path "$home")" ]] || { echo "rebuild: its base Python is gone (home = $home)"; return; }
  [[ -x "$(VPY)" ]] || { echo "rebuild: $(VPY) is missing"; return; }
  vminor="$(py_minor "$(VPY)")"
  [[ -n "$vminor" ]] || { echo "rebuild: its Python does not run"; return; }
  if [[ -z "${FE_VON_PYTHON:-}" && "$vminor" != "$(M VON_PYTHON)" ]]; then
    echo "rebuild: it is Python $vminor, Von needs $(M VON_PYTHON)"; return
  fi
  local have
  have="$("$(VPY)" -m pip show von-sdk 2>/dev/null | tr -d '\r' | sed -n 's/^Version: //p')"
  if [[ -z "$have" ]]; then echo "pip: von-sdk is not installed"; return; fi
  if [[ "$have" != "$(M VON_SDK_VERSION)" ]]; then echo "pip: von-sdk $have, want $(M VON_SDK_VERSION)"; return; fi
  "$VENV_BIN/von$EXE" --version >/dev/null 2>&1 || { echo "rebuild: von --version fails"; return; }
  echo ""
}
step_venv() {
  local want problem py have
  want="$(M VON_SDK_VERSION)"
  problem="$(venv_problem)"
  if [[ -z "$problem" ]]; then ok venv "von-sdk $want in $VENV"; return; fi
  if [[ $CHECK -eq 1 ]]; then
    [[ "$problem" == none ]] && problem="missing"
    problem="${problem#rebuild: }"; problem="${problem#pip: }"
    missing venv "$problem (needs von-sdk $want in $VENV)"; return
  fi
  py="$(find_von_python)" || fail venv "no Python $(M VON_PYTHON) to build the Von venv from (the python step installs it)"
  have=""
  if [[ "$problem" == pip:* ]]; then
    have="$("$(VPY)" -m pip show von-sdk 2>/dev/null | tr -d '\r' | sed -n 's/^Version: //p')"
  else
    [[ "$problem" == rebuild:* ]] && log "venv: rebuilding (${problem#rebuild: })"
    rm -rf "$VENV"
    [[ ! -e "$VENV" ]] || fail venv "could not remove the old venv $VENV (is a Von server or a shell using it? stop it and run this again)"
    mkdir -p "$VON_HOME" && "$py" -m venv "$VENV" || fail venv "$py -m venv $VENV failed"
  fi
  log "venv: pip install von-sdk==$want (a large download: PyTorch)"
  "$(VPY)" -m pip install --disable-pip-version-check "von-sdk==$want" || fail venv "pip install von-sdk==$want failed (network?)"
  "$VENV_BIN/von$EXE" --version >/dev/null 2>&1 || fail venv "von --version fails after the install"
  if [[ -n "$have" ]]; then upgraded venv "von-sdk $have to $want"; else installed venv "von-sdk $want in $VENV"; fi
}

# ---- the Von weights ---------------------------------------------------------------------------------------------
weights_present() { local f; for f in $WEIGHT_FILES; do [[ -s "$WEIGHTS/$f" ]] || return 1; done; }
step_weights() {
  local rev repo hf
  rev="$(M VON_WEIGHTS_REVISION)"; repo="$(M VON_WEIGHTS_REPO)"
  if weights_present && [[ "$(cat "$WEIGHTS/$MARKER" 2>/dev/null | tr -d '\r\n')" == "$rev" ]]; then
    ok weights "$repo@${rev:0:12} in $WEIGHTS"; return
  fi
  [[ $CHECK -eq 1 ]] && { missing weights "missing or not revision ${rev:0:12} in $WEIGHTS"; return; }
  hf="$VENV_BIN/hf$EXE"
  [[ -x "$hf" ]] || fail weights "$hf is missing: the venv step has not completed; run the bootstrap again"
  log "weights: hf download $repo@${rev:0:12} (about 3 GB; a stopped download resumes)"
  mkdir -p "$WEIGHTS"
  PYTHONUTF8=1 "$hf" download "$repo" --revision "$rev" --local-dir "$WEIGHTS" || fail weights "hf download failed (network?)"
  weights_present || fail weights "hf download finished but $WEIGHTS lacks one of: $WEIGHT_FILES"
  printf '%s\n' "$rev" > "$WEIGHTS/$MARKER"
  installed weights "$repo@${rev:0:12} in $WEIGHTS"
}

log "per-user root: $HOME_DIR$([[ $CHECK -eq 1 ]] && echo ' (check only: nothing is installed)')"
for step in git python godot skillshare hooks venv weights; do
  if [[ "$SKIP" == *",$step,"* ]]; then N_SKIPPED=$((N_SKIPPED + 1)); log "$step: skipped"; continue; fi
  "step_$step"
done
for n in ${NOTES[@]+"${NOTES[@]}"}; do log "NOTE: $n"; done
summary="$N_INSTALLED installed, $N_UPGRADED upgraded, $N_OK up to date"
[[ $N_SKIPPED -eq 0 ]] || summary="$summary, $N_SKIPPED skipped"
[[ $N_MISSING -eq 0 ]] || summary="$summary, $N_MISSING missing or outdated"
log "done: $summary"
[[ $N_MISSING -eq 0 ]]
