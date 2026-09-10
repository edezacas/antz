#!/bin/sh
# Provisions-or-surfaces a cached GNU bash 3.2.57 `bash` binary whose parser
# reproduces macOS /bin/sh's behavior (bash 3.2 in POSIX mode), for the
# posixsh-02 parse gate on install.sh (see
# spdd/changes/fix-install-sh-syntax/01-posixsh.feature).
#
# Usage:
#   tests/bash32-sh.sh [-f]    # prints one line, then exits 0 or 1
#
# Output contract (machine-readable first line):
#   success:  <bash32=/abs/path/to/bash>
#   failure:  state=<reason>        # machine line, exit 1
#     state=no_tools        gcc, make, curl or sha256sum not on PATH
#     state=no_network      the bash-3.2.57 tarball could not be fetched
#     state=no_tar          the fetched tarball's sha256 doesn't match the
#                           recorded upstream digest (refusing to build it)
#     state=build_failed    configure or make failed (see build log path in
#                           the following lines)
#
# Verified build recipe (from the specifier's investigation; pristine
# sources, no patches needed -- configure's own defaults plus modern-gcc
# compatibility flags make it build cleanly, and the resulting parser
# reproduces the macOS line-230 `;;` failure on un-fixed install.sh):
#   tarball: https://ftp.gnu.org/gnu/bash/bash-3.2.57.tar.gz
#     sha256 3fa9daf85ebf35068f090ce51283ddeeb3c75eb5bc70b1a4a7cb05868bfe06a4
#   CC="gcc -std=gnu89"
#   CFLAGS="-O1 -std=gnu89 -Wno-implicit-function-declaration -Wno-implicit-int"
#   ./configure && make
#
# The build is cached at "$TMPDIR_ROOT/antz-bash32-3.2.57/build/bash" (the
# whole build tree is kept so a re-run is a no-op); `-f` forces a fresh
# provision (deleting the cache first). The cache is validated on every run
# against a sanity fixture: a file whose heredoc body sits inside a command
# substitution with a `;;` inside it must FAIL to parse -- that defect is
# exactly the macOS parser behavior this helper exists to reproduce. A cache
# that parses the fixture (i.e. is not defect-faithful) is rebuilt.

set -u

CACHE_ROOT="${TMPDIR:-/tmp}/antz-bash32-3.2.57"
CACHE_BASH="$CACHE_ROOT/build/bash"
TARBALL_URL="https://ftp.gnu.org/gnu/bash/bash-3.2.57.tar.gz"
TARBALL_SHA256="3fa9daf85ebf35068f090ce51283ddeeb3c75eb5bc70b1a4a7cb05868bfe06a4"

force=0
[ "${1:-}" = "-f" ] && force=1

# Sanity fixture: a heredoc body captured by a command substitution, with a
# `;;` inside the body -- the construct class bash 3.2 mis-parses (macOS
# /bin/sh's failure), in the documented single-line shape. Must FAIL to
# parse; a shell that accepts it is not defect-faithful.
fixture_dir=""
fixture=""
cleanup() {
  [ -n "$fixture_dir" ] && rm -rf "$fixture_dir"
  return 0
}
trap cleanup EXIT
fixture_dir=$(mktemp -d)
fixture="$fixture_dir/fixture.sh"
cat > "$fixture" <<'FIXTURE'
x=$(cat <<'INNER'
case "$1" in
  a) echo one ;;
  b) echo two ;;
esac
INNER
)
echo "$x"
FIXTURE

fail() {
  echo "$1"
  exit 1
}

have_tools=1
for tool in gcc make curl sha256sum; do
  command -v "$tool" >/dev/null 2>&1 || have_tools=0
done
[ "$have_tools" -eq 1 ] || fail 'state=no_tools'

bash32_ok() {
  # $1 = candidate bash path: must run, self-report version 3.2, and be
  # defect-faithful (refuses to parse the fixture).
  b="$1"
  [ -x "$b" ] || return 1
  "$b" --version 2>/dev/null | head -n1 | grep -q 'version 3\.2' || return 1
  "$b" -n "$fixture" >/dev/null 2>&1 && return 1
  return 0
}

if [ "$force" -eq 0 ] && bash32_ok "$CACHE_BASH"; then
  echo "<bash32=$CACHE_BASH>"
  exit 0
fi

rm -rf "$CACHE_ROOT"
mkdir -p "$CACHE_ROOT"

build_log="$CACHE_ROOT/build.log"
src="$CACHE_ROOT/src"

if ! curl -fsSL "$TARBALL_URL" -o "$CACHE_ROOT/bash-3.2.57.tar.gz" 2>>"$build_log"; then
  fail 'state=no_network'
fi

echo "$TARBALL_SHA256  $CACHE_ROOT/bash-3.2.57.tar.gz" | sha256sum -c - >>"$build_log" 2>&1 ||
  fail 'state=no_tar'

mkdir -p "$src"
tar xzf "$CACHE_ROOT/bash-3.2.57.tar.gz" -C "$src" >>"$build_log" 2>&1 ||
  fail 'state=build_failed'

if ! (cd "$src/bash-3.2.57" &&
  CC="gcc -std=gnu89" \
  CFLAGS="-O1 -std=gnu89 -Wno-implicit-function-declaration -Wno-implicit-int" \
  ./configure >>"$build_log" 2>&1 && make >>"$build_log" 2>&1); then
  echo "state=build_failed"
  echo "build log: $build_log"
  exit 1
fi

mkdir -p "$CACHE_ROOT/build"
cp "$src/bash-3.2.57/bash" "$CACHE_ROOT/build/bash" >>"$build_log" 2>&1 ||
  fail 'state=build_failed'

if ! bash32_ok "$CACHE_BASH"; then
  echo "state=build_failed"
  echo "the built binary failed the sanity fixture check (see: $build_log)"
  exit 1
fi

echo "<bash32=$CACHE_BASH>"
exit 0
