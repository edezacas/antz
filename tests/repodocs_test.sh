#!/usr/bin/env bash
# Unit tests for change hardening-installsh, sub-spec 05
# (spdd/changes/hardening-installsh/05-repodocs.feature, scenarios
# repodocs-01..03): the one "spdd/" Structure bullet in each of the repo's
# two policy docs (AGENTS.md, CLAUDE.md) must state the real directory state
# (the three directories exist in the checkout; spdd/changes/ holds in-flight
# changes, empty between flows; spdd/specs/ the governing per-domain specs;
# spdd/archive/ the archived changes) while keeping the ownership half (the
# specifier creates spdd/changes/<slug>/; the verifier creates/updates
# spdd/specs/ and moves approved changes to spdd/archive/); the corrected
# bullet must be byte-for-byte identical between the two docs; and the false
# "not present yet; created on first run" claim must be gone from both files.
#
# Self-contained bash test harness (no external framework/dependency -- this
# repo has no package manager or build system), mirroring the harness style of
# tests/conventions_test.sh. Read-only over the repo: these tests assert on
# the docs as they sit in the working tree and mutate nothing.
#
# Run directly:
#   ./tests/repodocs_test.sh

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
AGENTS_MD="$SCRIPT_DIR/AGENTS.md"
CLAUDE_MD="$SCRIPT_DIR/CLAUDE.md"

pass_count=0
fail_count=0
skip_count=0

# ---- tiny test runner (mirrors tests/conventions_test.sh) --------------------

run_test() {
  # $1 = reported test name (must contain its scenario id), $2 = function name
  name="$1"; fn="$2"
  if "$fn"; then
    echo "PASS: $name"
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $name"
    fail_count=$((fail_count + 1))
  fi
}

require() {
  # $1 = file, $2 = fixed string that must appear in it
  if grep -qF -- "$2" "$1"; then return 0; fi
  echo "  missing required text: $2"
  return 1
}

refuse() {
  # $1 = file, $2 = fixed string that must NOT appear in it
  if grep -qF -- "$2" "$1"; then
    echo "  found forbidden text: $2"
    return 1
  fi
  return 0
}

# ---- scoped extract: the one "spdd/" bullet of the "## Structure" section ---

extract_spdd_bullet() {
  # $1 = doc path: every line of the "## Structure" section (heading to
  # heading) that starts a spdd/ bullet. An assertion must never be satisfied
  # by a passing mention of spdd/ outside the Structure bullet.
  awk '
    $0 == "## Structure" { inseg = 1; next }
    inseg && /^## /      { inseg = 0 }
    inseg && /^- `spdd\// { print }
  ' "$1"
}

AGENTS_BULLET=$(mktemp)
CLAUDE_BULLET=$(mktemp)
extract_spdd_bullet "$AGENTS_MD" > "$AGENTS_BULLET"
extract_spdd_bullet "$CLAUDE_MD" > "$CLAUDE_BULLET"

# The bullet must be exactly one line in each doc: the sub-spec corrects the
# single bullet, it does not split it into several or grow it into a block.
exactly_one_bullet() {
  # $1 = extracted-bullet file, $2 = doc label
  n=$(grep -c . "$1")
  if [ "$n" != "1" ]; then
    echo "  expected exactly one spdd/ bullet in $2's Structure section, found $n"
    return 1
  fi
  return 0
}

# =============================================================================
# repodocs-01: the Structure bullet states the real state -- the three
# directories exist in the checkout; spdd/changes/ holds in-flight changes
# (empty between flows, since approved changes are archived out); spdd/specs/
# holds the governing per-domain spec files; spdd/archive/ holds the archived
# changes -- and keeps the ownership half: the specifier creates
# spdd/changes/<slug>/; the verifier creates/updates spdd/specs/ and moves
# approved changes to spdd/archive/. No "absent / created on first run"
# claim survives. Asserted bullet-scoped in AGENTS.md (the doc the scenario
# names; repodocs-02 pins CLAUDE.md's copy to it byte-for-byte).
# =============================================================================
test_repodocs_01() {
  ok=0
  exactly_one_bullet "$AGENTS_BULLET" "AGENTS.md" || ok=1
  # No longer claims the directories are absent or created on first run.
  refuse "$AGENTS_BULLET" 'not present yet' || ok=1
  refuse "$AGENTS_BULLET" 'created on first run' || ok=1
  # States the three directories exist in the checkout.
  require "$AGENTS_BULLET" 'spdd/{changes,specs,archive}/' || ok=1
  require "$AGENTS_BULLET" 'exist in the checkout' || ok=1
  # spdd/changes/ holds in-flight changes, empty between flows.
  require "$AGENTS_BULLET" 'in-flight changes' || ok=1
  require "$AGENTS_BULLET" 'empty between flows' || ok=1
  # spdd/specs/ holds the governing per-domain spec files.
  require "$AGENTS_BULLET" 'governing per-domain spec' || ok=1
  # spdd/archive/ holds the archived changes.
  require "$AGENTS_BULLET" 'archived changes' || ok=1
  # The ownership half survives: the specifier creates spdd/changes/<slug>/...
  require "$AGENTS_BULLET" 'specifier creates `spdd/changes/<slug>/`' || ok=1
  # ...the verifier creates/updates spdd/specs/...
  require "$AGENTS_BULLET" 'verifier creates/updates `spdd/specs/`' || ok=1
  # ...and moves approved changes to spdd/archive/.
  require "$AGENTS_BULLET" 'moves approved changes to `spdd/archive/`' || ok=1
  return $ok
}

# =============================================================================
# repodocs-02: the two policy docs stay in sync -- the corrected "spdd/"
# Structure bullet is byte-for-byte identical between AGENTS.md and
# CLAUDE.md (the docs duplicate each other and must not fork on this line).
# =============================================================================
test_repodocs_02() {
  ok=0
  exactly_one_bullet "$AGENTS_BULLET" "AGENTS.md" || ok=1
  exactly_one_bullet "$CLAUDE_BULLET" "CLAUDE.md" || ok=1
  # It is the *corrected* bullet that must not fork -- two identical stale
  # copies (the pre-fix state) do not satisfy the scenario.
  refuse "$AGENTS_BULLET" 'not present yet' || ok=1
  refuse "$CLAUDE_BULLET" 'not present yet' || ok=1
  if ! cmp -s "$AGENTS_BULLET" "$CLAUDE_BULLET"; then
    echo "  the spdd/ Structure bullet is not byte-for-byte identical between AGENTS.md and CLAUDE.md:"
    echo "    AGENTS.md: $(cat "$AGENTS_BULLET")"
    echo "    CLAUDE.md: $(cat "$CLAUDE_BULLET")"
    ok=1
  fi
  return $ok
}

# =============================================================================
# repodocs-03: the false claim is gone everywhere -- neither policy doc
# contains "not present yet" in connection with spdd/ (or any equivalent
# non-existence claim about the spdd/ directories) anywhere in the full
# file, not just in the corrected bullet. The Overview sentences ("No
# application code lives here yet") are a different claim about a different
# subject, explicitly NOT corrected here -- so the non-existence scans are
# keyed to lines mentioning spdd/, and the Overview line must survive
# untouched.
# =============================================================================
test_repodocs_03() {
  ok=0
  for doc in "$AGENTS_MD" "$CLAUDE_MD"; do
    label=$(basename "$doc")
    # The known false phrases are gone from the whole file.
    refuse "$doc" 'not present yet' || { echo "  ($label)"; ok=1; }
    refuse "$doc" 'created on first run' || { echo "  ($label)"; ok=1; }
    # No spdd/-mentioning line claims non-existence in any other wording.
    bad=$(grep -n 'spdd/' "$doc" | grep -iE 'do not exist|does not exist|doesn.t exist|not (yet )?(there|present|created|exist)|do not yet exist|have not been created' || true)
    if [ -n "$bad" ]; then
      echo "  ($label) a line mentioning spdd/ still claims non-existence:"
      printf '    %s\n' "$bad"
      ok=1
    fi
    # The "No application code lives here yet" Overview sentence is out of
    # this sub-spec's scope and must still be there, untouched.
    if ! grep -qF 'No application code lives here yet' "$doc"; then
      echo "  ($label) the Overview's 'No application code lives here yet' sentence was removed -- out of this sub-spec's scope"
      ok=1
    fi
  done
  return $ok
}

# ---- run everything ----------------------------------------------------------

run_test "repodocs-01: the spdd/ Structure bullet in AGENTS.md states the real state (the three directories exist in the checkout; changes holds in-flight changes empty between flows, specs the governing per-domain specs, archive the archived changes) and keeps the specifier/verifier ownership, with no absent-or-created-on-first-run claim" test_repodocs_01
run_test "repodocs-02: the corrected spdd/ Structure bullet is byte-for-byte identical between AGENTS.md and CLAUDE.md" test_repodocs_02
run_test "repodocs-03: neither AGENTS.md nor CLAUDE.md anywhere says the spdd/ directories are 'not present yet', created on first run, or otherwise not yet existing, while the out-of-scope Overview 'No application code lives here yet' sentence survives untouched" test_repodocs_03

rm -f "$AGENTS_BULLET" "$CLAUDE_BULLET"

echo ""
echo "$pass_count passed, $fail_count failed, $skip_count skipped"
[ "$fail_count" -eq 0 ]
