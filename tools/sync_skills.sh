#!/usr/bin/env bash
# Link the skills in .skillshare/skills/ into .claude/skills/ (gitignored) for this checkout. Run by
# tools/install_hooks.sh and .githooks/post-checkout; run it by hand after adding or removing a skill folder.
#   tools/sync_skills.sh               link them: `skillshare sync -p`. It makes symlinks on a Mac and NTFS junctions on
#                                      Windows, which need no administrator rights and no Developer Mode.
#   tools/sync_skills.sh --mode copy   copy them instead, for a machine where linking does not work (a share, a
#                                      filesystem with neither symlinks nor junctions). A copy goes stale: run it again
#                                      after every change to a skill. (skillshare's own `target claude --mode copy`
#                                      rewrites the tracked .skillshare/config.yaml, so this does not use it.)
# Finds skillshare in the setup's own <per-user root>/bin first (tools/setup/lib.sh: fe_home: the pinned one the bootstrap
# installs), then on PATH, in ~/go/bin and, on
# Windows, in %LOCALAPPDATA%\Programs\skillshare. Exits 1, naming where to
# get it, when there is none (the copy mode needs none).
set -euo pipefail
cd "$(dirname "$0")/.."

mode=link
case "${1:-}" in
  "") ;;
  --mode=copy | "--mode copy") mode=copy ;;
  --mode)
    [[ "${2:-}" == copy || "${2:-}" == link ]] || { echo "usage: tools/sync_skills.sh [--mode copy]" >&2; exit 2; }
    mode="$2" ;;
  *) echo "usage: tools/sync_skills.sh [--mode copy]" >&2; exit 2 ;;
esac

# A link (symlink, or an NTFS junction, which Git Bash reports as a symlink) is removed on its own, never its target's
# files: a junction goes by rmdir, which cannot delete what it points to.
remove_link() {
  rm -- "$1" 2>/dev/null && return 0
  if command -v cmd >/dev/null 2>&1; then cmd //c rmdir "$(cygpath -w "$1")" >/dev/null 2>&1 && return 0; fi
  return 1
}

if [[ "$mode" == copy ]]; then
  mkdir -p .claude/skills
  for source in .skillshare/skills/*/; do
    name="$(basename "$source")"
    dest=".claude/skills/$name"
    if [[ -L "$dest" ]]; then remove_link "$dest" || { echo "cannot remove the link $dest" >&2; exit 1; }
    elif [[ -e "$dest" ]]; then rm -rf -- "$dest"; fi
    cp -R "$source" "$dest"
  done
  echo "copied $(ls -d .skillshare/skills/*/ | wc -l | tr -d ' ') skills into .claude/skills/ (a copy: run this again after a change)"
  exit 0
fi

# The pinned one the bootstrap installs (<per-user root>/bin) wins; then PATH, ~/go/bin and Windows' installer folder.
fe_bin=""
if [[ -f tools/setup/lib.sh ]]; then source tools/setup/lib.sh; fe_bin="$(fe_home)/bin"; fi
skillshare=""
for candidate in "${fe_bin:+$fe_bin/skillshare}" "${fe_bin:+$fe_bin/skillshare.exe}" "$(command -v skillshare || true)"     "$HOME/go/bin/skillshare" "$HOME/go/bin/skillshare.exe"     "${LOCALAPPDATA:+$(cygpath -u "$LOCALAPPDATA" 2>/dev/null)/Programs/skillshare/skillshare.exe}"     "$HOME/AppData/Local/Programs/skillshare/skillshare.exe"; do
  if [[ -n "$candidate" && -x "$candidate" ]]; then skillshare="$candidate"; break; fi
done
if [[ -z "$skillshare" ]]; then
  echo "skillshare not found, so .claude/skills/ was not linked: install it from https://github.com/runkids/skillshare" >&2
  echo "(or copy the skills instead: tools/sync_skills.sh --mode copy)" >&2
  exit 1
fi
"$skillshare" sync -p --quiet
