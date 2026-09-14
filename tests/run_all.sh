#!/bin/sh
# tests/run_all.sh -- the documented one-command runner for the antz test
# area (tests the runner itself: tests/runner_test.sh).
#
# Usage:   sh tests/run_all.sh            (full pass; -h, --help prints this
#                                          usage and runs no suite)
#
# What it runs: each tests/*_test.sh suite exactly once, in sorted filename order
# -- discovery is the mechanical glob, listed in byte order (a helper
# like tests/bash32-sh.sh matches no suite glob), so adding or removing a
# suite needs no runner edit.
# ANTZ_TESTS_DIR overrides the suite directory (hermetic runner testing).
#
# What it prints: one status line per suite ("<path> pass=<n> fail=<n>
# skip=<n> -> ok|FAILED"), the captured output and one "FAILED <path>: <ids>"
# line for each failing suite (naming its failing scenario ids), and as the
# final line the aggregate summary:
#   suites= passed= failed= tests_failed= elapsed=<seconds>s
#
# Exit contract: the runner exits 0 exactly when every suite exits 0;
# a failing suite is isolated and named, never fatal to the run.
set -u

usage() {
  cat <<'EOF'
Usage: sh tests/run_all.sh            the one documented test-suite command
       sh tests/run_all.sh -h, --help prints this usage and runs no suite

What it runs: each tests/*_test.sh suite exactly once, in sorted filename order
-- discovery is the mechanical glob (helpers like tests/bash32-sh.sh
match no suite glob), so adding or removing a suite needs no runner edit.
ANTZ_TESTS_DIR overrides the suite directory (for hermetic runner testing).

What it prints: one status line per suite ("<path> pass=<n> fail=<n>
skip=<n> -> ok|FAILED"), the captured output and one "FAILED <path>: <ids>"
line for each failing suite (naming its failing scenario ids), and as the
final line the aggregate summary:
  suites= passed= failed= tests_failed= elapsed=<seconds>s

Exit contract: the runner exits 0 exactly when every suite exits 0; a
failing suite is isolated and named, never fatal to the run.
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  '') ;;
  *) printf 'run_all: unknown argument: %s (see -h/--help)\n' "$1" >&2
     exit 2 ;;
esac

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tests_dir=${ANTZ_TESTS_DIR:-$repo/tests}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/antz-run-all.XXXXXX")
trap 'rm -rf "$tmp"' EXIT INT TERM
: > "$tmp/failed"
: > "$tmp/dumps"

n_suites=0
n_failed=0
tests_failed=0
start=$(date +%s)

# Discovery: the mechanical tests/*_test.sh glob (find -name), listed in
# filename BYTE order (LC_ALL=C scoped to the sort itself, so suites keep
# the ambient environment) -- a bare glob would follow the locale collation.
# Suites read no stdin; give them /dev/null so the list survives the loop.
find "$tests_dir" -maxdepth 1 -type f -name '*_test.sh' | LC_ALL=C sort > "$tmp/suites"
while read -r suite; do
  log="$tmp/$(basename -- "$suite").log"
  sh "$suite" < /dev/null > "$log" 2>&1
  rc=$?
  n_suites=$((n_suites + 1))

  # Harness output contract: the suite's final line is the aggregate
  # "pass=<n> fail=<n> skip=<n>". When it is absent (a crashed suite), fall
  # back to tallying the PASS:/FAIL:/SKIP: lines, so no suite runs silent.
  p=""; f=""; s=""
  last=$(tail -n 1 "$log")
  case "$last" in
    pass=[0-9]*' fail=[0-9]* skip='*)
      p=${last#pass=}; p=${p%% *}
      f=${last#*fail=}; f=${f%% *}
      s=${last#*skip=}; s=${s%% *}
      ;;
  esac
  [ -n "$p" ] || p=$(grep -c '^PASS: ' "$log")
  [ -n "$f" ] || f=$(grep -c '^FAIL: ' "$log")
  [ -n "$s" ] || s=$(grep -c '^SKIP: ' "$log")

  if [ "$rc" -eq 0 ]; then
    status=ok
  else
    status=FAILED
    n_failed=$((n_failed + 1))
    # Scenario ids of the failing tests: the first token of each FAIL line's
    # test name, cut at the first ':' or space (the repo's id-prefix shapes,
    # "roles-01: ..." and 'quoting-03 (Says "hi"): ...').
    ids=$(awk '/^FAIL: / { id = $2; sub(/[ :].*$/, "", id); printf "%s ", id }' "$log")
    ids=${ids% }
    [ -n "$ids" ] || ids="(no FAIL lines reported; suite exited $rc)"
    printf 'FAILED %s: %s\n' "$suite" "$ids" >> "$tmp/failed"
    { printf -- '--- output: %s ---\n' "$suite"; cat "$log"; } >> "$tmp/dumps"
  fi
  tests_failed=$((tests_failed + f))
  printf '%s pass=%s fail=%s skip=%s -> %s\n' "$suite" "$p" "$f" "$s" "$status"
done < "$tmp/suites"

if [ "$n_suites" -eq 0 ]; then
  printf 'run_all: no tests/*_test.sh suites found under %s\n' "$tests_dir" >&2
  exit 1
fi

# Summary section: the failing suites' captured output (a full run never
# swallows a failure), then one FAILED line per failing suite naming its
# failing scenario ids, then the final aggregate summary line.
[ -s "$tmp/dumps" ] && { cat "$tmp/dumps"; printf '\n'; }
[ -s "$tmp/failed" ] && cat "$tmp/failed"
end=$(date +%s)
printf 'suites=%s passed=%s failed=%s tests_failed=%s elapsed=%ss\n' \
  "$n_suites" "$((n_suites - n_failed))" "$n_failed" "$tests_failed" "$((end - start))"
[ "$n_failed" -eq 0 ]
