#!/usr/bin/env bash
# Run gdstyle (https://github.com/atelico/gdstyle), pinned to v0.4.0, with the arguments given:
#   tools/gdstyle.sh fmt [--check] [PATH...]   format (or report what fmt would change)
#   tools/gdstyle.sh check [PATH...]           lint; gdstyle.toml at the root holds the config
# The first run fetches this platform's release asset, checks its sha256 against the one pinned below, refuses to run
# on a mismatch, and keeps the binary in a cache outside the tree; later runs reuse it. tools/lint.sh runs it.
# It runs in the caller's directory and exits with gdstyle's status (2 when no binary can be had).
#   GDSTYLE_CACHE         the cache (default: ${XDG_CACHE_HOME:-~/.cache}/forced-entry-gdstyle)
#   GDSTYLE_RELEASE_URL   where the assets are fetched from (default: the v0.4.0 release on GitHub)
set -uo pipefail

VERSION=0.4.0
RELEASE_URL="${GDSTYLE_RELEASE_URL:-https://github.com/atelico/gdstyle/releases/download/v$VERSION}"
CACHE="${GDSTYLE_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/forced-entry-gdstyle}"

# The command-line assets v0.4.0 publishes, with their sha256.
pinned_sha256() {
  case "$1" in
    gdstyle-aarch64-apple-darwin.tar.gz) echo 0599c5860c99f147f91ed7233c4b5d085deb39a6e3604ea7576c0158f10ee83d ;;
    gdstyle-x86_64-apple-darwin.tar.gz) echo c0b2b7075660ff6fc0193174116b8b2c6ba41321a1dd10b60d140cbb20389b8e ;;
    gdstyle-x86_64-unknown-linux-gnu.tar.gz) echo 4ae7abf49468e751472eb79136e5e28e30bee9b6aaeb8e8286a6a3c06bd95499 ;;
    gdstyle-x86_64-pc-windows-msvc.zip) echo 1601f481f4f181752d80a780f92f19822ac8031f06118ad0cb0cb7c9ed454ec8 ;;
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

sha256_of() {
  if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1
}

if [[ ! -x "$binary" ]]; then
  mkdir -p "$dir" || fail "cannot create the cache $dir"
  tmp=$(mktemp -d "$dir/fetch.XXXXXX") || fail "cannot write to the cache $dir"
  trap 'rm -rf "$tmp"' EXIT
  echo "gdstyle.sh: fetching gdstyle v$VERSION ($asset)..." >&2
  curl -fsSL --retry 2 -o "$tmp/$asset" "$RELEASE_URL/$asset" || fail "could not fetch $RELEASE_URL/$asset"
  got=$(sha256_of "$tmp/$asset")
  [[ "$got" == "$sha" ]] || fail "sha256 mismatch for $asset: expected $sha, got $got; refusing to run it"
  case "$asset" in
    *.zip) unzip -q -o "$tmp/$asset" -d "$tmp/x" ;;
    *) mkdir "$tmp/x" && tar -xzf "$tmp/$asset" -C "$tmp/x" ;;
  esac || fail "could not unpack $asset"
  [[ -f "$tmp/x/$exe" ]] || fail "$asset holds no $exe"
  chmod +x "$tmp/x/$exe"
  # A rename is atomic: a run started meanwhile sees no binary or the whole one.
  mv -f "$tmp/x/$exe" "$binary" || fail "could not cache $binary"
  rm -rf "$tmp"
  trap - EXIT
fi

exec "$binary" "$@"
