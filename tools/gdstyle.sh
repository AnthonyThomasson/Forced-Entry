#!/usr/bin/env bash
# Run gdstyle (https://github.com/atelico/gdstyle), at the version pinned in tools/setup/versions.env (GDSTYLE_*), with
# the arguments given:
#   tools/gdstyle.sh fmt [--check] [PATH...]   format (or report what fmt would change)
#   tools/gdstyle.sh check [PATH...]           lint; gdstyle.toml at the root holds the config
#   tools/gdstyle.sh --fetch                   only make sure the binary is cached; print its path (the bootstrap's hooks
#                                              step runs this, so the first lint works offline)
#   tools/gdstyle.sh --cached                  print the cached binary's path and exit 0, or exit 1 when there is none
# A `fmt` that writes (no --check) goes through tools/gdstyle_reflow.py, which fills each comment paragraph gdstyle
# broke (it moves an over-long line's tail onto a line of its own) back to 100 columns.
# The first run fetches this platform's release asset, checks its sha256 against the one pinned in versions.env, refuses
# to run on a mismatch, and keeps the binary in a cache outside the tree (under the per-user root, tools/setup/lib.sh's
# fe_home); later runs reuse it. tools/lint.sh runs it.
# It runs in the caller's directory and exits with gdstyle's status (2 when no binary can be had).
#   GDSTYLE_CACHE         the cache (default: <fe home>/gdstyle)
#   GDSTYLE_RELEASE_URL   where the assets are fetched from (default: GDSTYLE_BASE_URL in versions.env)
set -uo pipefail

source "$(dirname "$0")/setup/lib.sh"
VERSION="$(fe_manifest_get GDSTYLE_VERSION)"
RELEASE_URL="${GDSTYLE_RELEASE_URL:-$(fe_manifest_get GDSTYLE_BASE_URL)}"
CACHE="${GDSTYLE_CACHE:-$(fe_home)/gdstyle}"

# The command-line assets the release publishes, with their sha256 (the manifest's GDSTYLE_<ARCH>_<OS>_SHA256).
pinned_sha256() {
  case "$1" in
    gdstyle-aarch64-apple-darwin.tar.gz) fe_manifest_get GDSTYLE_AARCH64_MACOS_SHA256 ;;
    gdstyle-x86_64-apple-darwin.tar.gz) fe_manifest_get GDSTYLE_X86_64_MACOS_SHA256 ;;
    gdstyle-x86_64-unknown-linux-gnu.tar.gz) fe_manifest_get GDSTYLE_X86_64_LINUX_SHA256 ;;
    gdstyle-x86_64-pc-windows-msvc.zip) fe_manifest_get GDSTYLE_X86_64_WINDOWS_SHA256 ;;
  esac
}

fail() { echo "gdstyle.sh: $*" >&2; exit 2; }

arch=$(uname -m)
case "$arch" in arm64 | aarch64) arch=aarch64 ;; x86_64 | amd64) arch=x86_64 ;; esac
case "$(uname -s)" in
  Darwin) asset="gdstyle-$arch-apple-darwin.tar.gz"; exe=gdstyle ;;
  Linux) asset="gdstyle-$arch-unknown-linux-gnu.tar.gz"; exe=gdstyle ;;
  MINGW* | MSYS* | CYGWIN*) asset="gdstyle-$arch-pc-windows-msvc.zip"; exe=gdstyle.exe ;;
  *) asset="" ;;
esac
sha=$( [[ -n "$asset" ]] && pinned_sha256 "$asset" )
[[ -n "$sha" ]] || fail "gdstyle v$VERSION has no release for $(uname -s) $(uname -m)"

dir="$CACHE/v$VERSION/${asset%%.tar.gz}"; dir="${dir%%.zip}"
binary="$dir/$exe"

sha256_of() { fe_hash_file 256 "$1"; }

# Unpack the zip $1 into the folder $2. Git for Windows may ship no `unzip`: Python's zipfile does it then.
unzip_to() {
  if command -v unzip >/dev/null 2>&1; then
    unzip -q -o "$1" -d "$2"
  else
    fe_use_python || return 1
    "$PYTHON" -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$(cygpath -w "$1")" "$(cygpath -w "$2")"
  fi
}

if [[ "${1:-}" == --cached ]]; then
  [[ -x "$binary" ]] && { echo "$binary"; exit 0; }
  exit 1
fi

if [[ ! -x "$binary" ]]; then
  mkdir -p "$dir" || fail "cannot create the cache $dir"
  tmp=$(mktemp -d "$dir/fetch.XXXXXX") || fail "cannot write to the cache $dir"
  trap 'rm -rf "$tmp"' EXIT
  echo "gdstyle.sh: fetching gdstyle v$VERSION ($asset)..." >&2
  curl -fsSL --retry 2 -o "$tmp/$asset" "$RELEASE_URL/$asset" || fail "could not fetch $RELEASE_URL/$asset"
  got=$(sha256_of "$tmp/$asset")
  [[ "$got" == "$sha" ]] || fail "sha256 mismatch for $asset: expected $sha, got $got; refusing to run it"
  case "$asset" in
    *.zip) unzip_to "$tmp/$asset" "$tmp/x" ;;
    *) mkdir "$tmp/x" && tar -xzf "$tmp/$asset" -C "$tmp/x" ;;
  esac || fail "could not unpack $asset"
  [[ -f "$tmp/x/$exe" ]] || fail "$asset holds no $exe"
  chmod +x "$tmp/x/$exe"
  # A rename is atomic: a run started meanwhile sees no binary or the whole one.
  mv -f "$tmp/x/$exe" "$binary" || fail "could not cache $binary"
  rm -rf "$tmp"
  trap - EXIT
fi

if [[ "${1:-}" == --fetch ]]; then
  echo "$binary"
  exit 0
fi

if [[ "${1:-}" == fmt && " $* " != *" --check "* ]]; then
  fe_use_python || exit $?
  exec "$PYTHON" "$(cd "$(dirname "$0")" && pwd)/gdstyle_reflow.py" "$binary" "$@"
fi
exec "$binary" "$@"
