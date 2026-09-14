#!/usr/bin/env bash
# tests/versioncurrent_test.sh -- the area's only version check: it pins the
# CURRENT version's behavior and nothing else (change optimize-test-suite,
# sub-spec 05; scenario ids versioncurrent-01..03).
#
# The re-scoped law: the test area pins no version history. No append-only
# guarantee, no entry ordering/uniqueness/dating check, no git-HEAD
# comparison, no per-version content pin. The nine frozen-history bump
# suites, the prose-pinning versioning-rule suite, and the interim
# consolidated changelog-history suite are all deleted (versioncurrent-01),
# and what survives is exactly two assertions (versioncurrent-02):
#   1. VERSION's entire content is a semver X.Y.Z plus one trailing newline;
#   2. VERSION equals the version in the newest (topmost) "## [X.Y.Z]" entry
#      heading of CHANGELOG.md.
# Both are relative -- they bind whatever VERSION and CHANGELOG.md the tree
# under test carries, never a literal version -- so a future bump needs no
# edit to this suite (versioncurrent-03 proves it on staged fixture trees,
# in both directions).
#
# Hermetic and render-free: reads only VERSION and CHANGELOG.md of the tree
# under test -- no install.sh invocation, no network, no git query; every
# fixture tree lives under the harness run root; nothing in the working tree
# is ever mutated.
#
# Shares the harness library (tests/harness.sh): output contract (PASS/FAIL/
# SKIP lines + final "pass=<n> fail=<n> skip=<n>" line, exit 0 iff no
# failure), temp-dir bookkeeping, and cleanup trap. Run directly:
#   sh tests/versioncurrent_test.sh

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
# shellcheck source=tests/harness.sh
. "$SCRIPT_DIR/tests/harness.sh"

# ---- the one version check (exactly the two assertions above) ----------------

check_version() {
  # $1 = tree under test. Reads only $1/VERSION and $1/CHANGELOG.md; the
  # verdict binds whatever those two files carry -- never a literal.
  # Every variable is cv_-prefixed: the harness runs plain functions with
  # shared globals, so none may shadow a caller's.
  cv_tree="$1"
  cv_vf="$cv_tree/VERSION"
  cv_cl="$cv_tree/CHANGELOG.md"
  if [ ! -f "$cv_vf" ]; then echo "  missing VERSION in $cv_tree"; return 1; fi
  if [ ! -f "$cv_cl" ]; then echo "  missing CHANGELOG.md in $cv_tree"; return 1; fi
  cv_ok=0

  # Assertion 1: VERSION's ENTIRE content is a semver X.Y.Z plus exactly one
  # trailing newline -- the first line must be a semver, and regenerating
  # "first line + one newline" must reproduce the file byte-for-byte (a
  # missing or extra newline, or any further line, breaks the cmp).
  cv_first=$(sed -n '1p' "$cv_vf")
  if ! printf '%s' "$cv_first" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "  VERSION's line reads '$cv_first', not a semver X.Y.Z"; cv_ok=1
  fi
  if ! printf '%s\n' "$cv_first" | cmp -s - "$cv_vf"; then
    echo "  VERSION's content is not exactly the value plus one trailing newline"; cv_ok=1
  fi

  # Assertion 2: VERSION equals the version in the newest (topmost)
  # "## [X.Y.Z]" entry heading of CHANGELOG.md. Nothing else about the
  # entries is checked -- no dating, ordering, uniqueness, or append-only
  # claim; a tree with no such heading has no newest version to agree with,
  # so agreement fails rather than passing vacuously.
  cv_newest=$(sed -nE 's/^## \[([0-9]+\.[0-9]+\.[0-9]+)\].*/\1/p' "$cv_cl" | sed -n '1p')
  if [ "$cv_first" != "$cv_newest" ]; then
    echo "  VERSION reads '$cv_first' but the newest CHANGELOG.md entry heading is '${cv_newest:-none}'"
    cv_ok=1
  fi
  return $cv_ok
}

vc_next_version() {
  # Prints $1 (a semver) with its patch component bumped by one -- so the
  # staged future bump is computed from the tree, never hardcoded.
  printf '%s' "$1" | awk -F. '{ printf "%d.%d.%d", $1, $2, $3 + 1 }'
}

# =============================================================================
# versioncurrent-01: the frozen-history suites are gone -- the nine
# per-version bump suites, versioning-rule, and the interim changelog-history
# no longer exist under tests/. Thinned by change optimize-test-suite
# (sub-spec 09): the id-absence scan across every suite source and the
# sibling registration clause asserted OTHER suites' content -- law 2
# ("no suite asserts another existing suite's source content or output"),
# so both were deleted with the hygiene law rather than re-keyed. The
# files-gone fact binds only this tree's tests/ listing, not any sibling.
# =============================================================================
test_versioncurrent_01() {
  ok=0
  tests="$HARNESS_REPO/tests"

  # (1) The deleted suites no longer exist under tests/.
  for f in bump440_test.sh bump450_test.sh bump460_test.sh bump470_test.sh \
           bump471_test.sh bump480_test.sh skills-activation-bump_test.sh \
           skills-desc-match-bump_test.sh docs-bump_test.sh \
           versioning-rule_test.sh changelog-history_test.sh; do
    if [ -e "$tests/$f" ]; then
      echo "  still present: tests/$f"; ok=1
    fi
  done

  return $ok
}

# =============================================================================
# versioncurrent-02: the version check carries exactly two assertions --
# each enforced on a staged fixture tree (so no third assertion and no
# vacuity), and relative (it binds the tree under test, never a literal).
# =============================================================================
test_versioncurrent_02() {
  ok=0
  # Pristine snapshot of the real CHANGELOG.md, re-compared at the end to
  # prove the fixtures below only ever read it, never mutate it.
  intact=$(new_tmp_dir)
  cp "$HARNESS_REPO/CHANGELOG.md" "$intact/CHANGELOG.md"

  # (a) The real tree currently satisfies both assertions.
  if ! check_version "$HARNESS_REPO"; then
    echo "  the check rejects the current working tree"; ok=1
  fi

  # (b) Assertion 1 is enforced, isolated: VERSION reads as a clean semver
  # agreeing with the topmost entry, yet anything beyond "value + exactly
  # one trailing newline" in the file's ENTIRE content trips it.
  version=$(sed -n '1p' "$HARNESS_REPO/VERSION")
  for bad in "extra-newline" "second-line" "leading-space"; do
    fx=$(new_tmp_dir); cp "$HARNESS_REPO/CHANGELOG.md" "$fx/CHANGELOG.md"
    case $bad in
      extra-newline) printf '%s\n\n' "$version" > "$fx/VERSION" ;;
      second-line)   printf '%s\nextra line\n' "$version" > "$fx/VERSION" ;;
      leading-space) printf ' %s\n' "$version" > "$fx/VERSION" ;;
    esac
    if check_version "$fx" >/dev/null 2>&1; then
      echo "  VERSION shape '$bad' was accepted (only value + one trailing newline passes)"; ok=1
    fi
  done
  # Non-semver values fail too (shape, not just agreement).
  fx=$(new_tmp_dir); cp "$HARNESS_REPO/CHANGELOG.md" "$fx/CHANGELOG.md"
  printf '4.8\n' > "$fx/VERSION"
  if check_version "$fx" >/dev/null 2>&1; then
    echo "  non-semver VERSION '4.8' was accepted"; ok=1
  fi

  # (c) Assertion 2 is enforced: a perfectly shaped VERSION that disagrees
  # with the topmost entry fails -- and a CHANGELOG with no entry heading at
  # all fails too, so the check never passes vacuously.
  fx=$(new_tmp_dir); printf '9.9.9\n' > "$fx/VERSION"
  cp "$HARNESS_REPO/CHANGELOG.md" "$fx/CHANGELOG.md"
  if check_version "$fx" >/dev/null 2>&1; then
    echo "  VERSION 9.9.9 against the unchanged CHANGELOG was accepted"; ok=1
  fi
  fx=$(new_tmp_dir); printf '9.9.9\n' > "$fx/VERSION"
  printf '# Changelog\n\nno entry headings here\n' > "$fx/CHANGELOG.md"
  if check_version "$fx" >/dev/null 2>&1; then
    echo "  a CHANGELOG.md with no '## [X.Y.Z]' heading passed vacuously"; ok=1
  fi

  # (d) Relative, never literal: a tree carrying a version unrelated to the
  # current one passes when its own two files agree.
  fx=$(new_tmp_dir); printf '9.9.9\n' > "$fx/VERSION"
  printf '# Changelog\n\n## [9.9.9] - 2026-01-01\n\n- fixture entry\n' > "$fx/CHANGELOG.md"
  if ! check_version "$fx"; then
    echo "  the self-consistent 9.9.9 fixture was rejected (assertion is literal-pinned?)"; ok=1
  fi

  # (e) Exactly two, not more: history chaos BELOW the topmost matching
  # entry -- a non-semver "## [Unreleased]" heading above it, a duplicate
  # version, an ascending-order violation, an undated heading -- must not
  # trip the check (no ordering, uniqueness, dating, or heading-shape
  # assertion may regrow; a git-HEAD/append-only check is out of the
  # check's world entirely -- it never opens git).
  fx=$(new_tmp_dir); printf '%s\n' "$version" > "$fx/VERSION"
  {
    printf '# Changelog\n\n'
    printf '## [Unreleased] - TBD\n\n### Changed\n- pending note\n\n'
    printf '## [%s] - 2026-09-13\n\n### Added\n- newest entry\n\n' "$version"
    printf '## [%s] - 2020-01-01\n\n- duplicate of the newest version\n\n' "$version"
    printf '## [5.0.0] - 2019-01-01\n\n- ascending order violation\n\n'
    printf '## [0.0.1]\n\n- undated heading\n'
  } > "$fx/CHANGELOG.md"
  if ! check_version "$fx"; then
    echo "  history chaos below the newest entry tripped the check (more than two assertions?)"; ok=1
  fi

  # The fixture work above must not have touched the real tree.
  cmp -s "$intact/CHANGELOG.md" "$HARNESS_REPO/CHANGELOG.md" || {
    echo "  the working tree's CHANGELOG.md was mutated by a fixture"; ok=1; }
  return $ok
}

# =============================================================================
# versioncurrent-03: a staged copy of the working tree with a new dated
# '## [X.Y.Z]' entry prepended atop CHANGELOG.md and VERSION bumped to match
# passes the UNEDITED check -- and the inverse (bump without entry) fails.
# =============================================================================
test_versioncurrent_03() {
  ok=0
  base=$(sed -n '1p' "$HARNESS_REPO/VERSION")
  next=$(vc_next_version "$base")
  [ "$next" != "$base" ] || { echo "  computed no future version from '$base'"; return 1; }

  # The future bump, staged: prepend the dated entry, bump VERSION to match.
  fx=$(new_tmp_dir)
  cp "$HARNESS_REPO/CHANGELOG.md" "$fx/CHANGELOG.md"
  { printf '## [%s] - %s\n\n' "$next" "$(date +%F)"; cat "$fx/CHANGELOG.md"; } \
    > "$fx/CHANGELOG.md.new" && mv "$fx/CHANGELOG.md.new" "$fx/CHANGELOG.md"
  printf '%s\n' "$next" > "$fx/VERSION"

  # The fixture really carries the future state (not a silent no-op).
  grep -qF -- "## [$next] - " "$fx/CHANGELOG.md" \
    || { echo "  staged tree does not carry the prepended entry [$next]"; return 1; }

  # The unedited suite passes on it -- no test edit for a bump.
  if ! check_version "$fx"; then
    echo "  the staged future bump $next was rejected by the unedited check"; ok=1
  fi
  return $ok
}

test_versioncurrent_03_inverse() {
  ok=0
  base=$(sed -n '1p' "$HARNESS_REPO/VERSION")
  next=$(vc_next_version "$base")

  # The inverse: VERSION bumped but NO new entry added -- the check fails,
  # proving it never passes vacuously.
  fx=$(new_tmp_dir)
  cp "$HARNESS_REPO/CHANGELOG.md" "$fx/CHANGELOG.md"
  printf '%s\n' "$next" > "$fx/VERSION"
  if check_version "$fx" >/dev/null 2>&1; then
    echo "  VERSION bumped to $next with an unchanged CHANGELOG was accepted"; ok=1
  fi
  return $ok
}

# ---- run everything ---------------------------------------------------------

run_test "versioncurrent-01: the eleven frozen-history suites (nine bump suites, versioning-rule, interim changelog-history) no longer exist under tests/" test_versioncurrent_01
run_test "versioncurrent-02: the version check carries exactly two assertions -- VERSION's entire content is a semver X.Y.Z plus one trailing newline, and VERSION equals the version in the newest (topmost) '## [X.Y.Z] - <date>' heading of CHANGELOG.md -- each enforced on fixture trees, relative (never a literal version), and history chaos below the newest entry trips nothing" test_versioncurrent_02
run_test "versioncurrent-03: a staged tree prepending a new dated '## [X.Y.Z]' entry atop CHANGELOG.md and bumping VERSION to match passes the unedited check -- a future bump needs no test edit" test_versioncurrent_03
run_test "versioncurrent-03: the inverse holds -- VERSION bumped with no new entry added fails the check, which never passes vacuously" test_versioncurrent_03_inverse

finish_suite
