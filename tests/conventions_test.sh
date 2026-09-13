#!/usr/bin/env bash
# Unit tests for change precision-gaps, sub-spec 01
# (spdd/changes/precision-gaps/01-conventions.feature, scenarios
# conventions-01..04): the three specifier-prompt convention bullets of
# agents/prompts/specifier.prompt -- the two-zero-padded-digit scenario
# <index> (conventions-01), the one-e2e-qa.feature-per-change-dir reconciliation
# (conventions-02), the per-sub-spec relevant-files + declared-destination-
# domain section rule (conventions-03) -- and the loud by-gating retirement of
# the specifier diff-window pins the rewordings trip:
# tests/skills-activation-prompts_test.sh's prompts-05 specifier guard and
# tests/closingblock_test.sh's two closingblock-05 specifier diff-window
# assertions (conventions-04).
#
# Self-contained bash test harness (no external framework/dependency -- this
# repo has no package manager or build system), mirroring the harness style of
# tests/readmefile_test.sh. The conventions-04 gating is exercised against
# throwaway git-repo fixtures under mktemp -d (the tests/antz-flow_test.sh
# new_repo precedent): a copy of the working tree, git init, one fixture-local
# commit -- the real repo is never committed to and nothing under $SCRIPT_DIR
# is mutated.
#
# Run directly:
#   ./tests/conventions_test.sh

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SPECIFIER_PROMPT="$SCRIPT_DIR/agents/prompts/specifier.prompt"
PROMPTS_SUITE="tests/skills-activation-prompts_test.sh"
CLOSINGBLOCK_SUITE="tests/closingblock_test.sh"

pass_count=0
fail_count=0
skip_count=0

# ---- tiny test runner (mirrors tests/readmefile_test.sh) --------------------

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

skip_test() {
  # $1 = reported test name (must contain its scenario id), $2 = reason.
  # An explicit, accounted-for stub for a scenario that is out of scope for
  # unit-level TDD (never a silent omission).
  name="$1"; reason="$2"
  echo "SKIP: $name ($reason)"
  skip_count=$((skip_count + 1))
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

# Extract a "## <name>" section (its own heading line down to the next top
# level "## " heading or EOF) from $1 into $3.
extract_section() {
  awk -v sec="$2" '
    $0 == "## " sec { flag=1; next }
    flag && /^## / { flag=0 }
    flag { print }
  ' "$1" > "$3"
}

# ---- scoped extracts (a required phrase elsewhere in the prompt must never
# satisfy a section- or bullet-scoped assertion) -------------------------------

SPEC_RULES=$(mktemp)
E2E_SECTION=$(mktemp)
OUTPUT_SECTION=$(mktemp)
extract_section "$SPECIFIER_PROMPT" "Specification Rules" "$SPEC_RULES"
extract_section "$SPECIFIER_PROMPT" "End-To-End QA Suite" "$E2E_SECTION"
# "## Output, written to `spdd/changes/<change-slug>/`" -- the whole-section
# extraction, identical to tests/readmefile_test.sh's.
awk '
  /^## Output/ { flag=1 }
  flag && /^## / && !/^## Output/ { flag=0 }
  flag { print }
' "$SPECIFIER_PROMPT" > "$OUTPUT_SECTION"

# The scenario-naming bullet (identified by the id shape it defines) and the
# first bullet of the QA section, each isolated so the assertions below are
# bullet-scoped.
NAMING_BULLET=$(mktemp)
E2E_BULLET=$(mktemp)
grep -m1 -- '<feature>-<index>' "$SPEC_RULES" > "$NAMING_BULLET"
grep '^[-*] ' "$E2E_SECTION" | head -n 1 > "$E2E_BULLET"

# =============================================================================
# conventions-01: the <index> of a scenario id is defined -- two zero-padded
# digits, sequential from 01 within the sub-spec (first <feature>-01, next
# <feature>-02, and so on); the rest of the naming bullet keeps its meaning
# (one-word <feature> rule, tag-comment format with the id on its first line,
# no other scenario's id in a tag's description).
# =============================================================================
test_conventions_01() {
  ok=0
  # The <index> is defined: two zero-padded digits, sequential from 01.
  require "$NAMING_BULLET" '<index>' || ok=1
  require "$NAMING_BULLET" 'two zero-padded digits' || ok=1
  require "$NAMING_BULLET" 'sequential from 01' || ok=1
  # The worked example the scenario demands: first is -01, next is -02.
  require "$NAMING_BULLET" '<feature>-01' || ok=1
  require "$NAMING_BULLET" '<feature>-02' || ok=1
  # The rest of the bullet keeps its meaning: the one-word <feature> rule...
  require "$NAMING_BULLET" 'one word (letters/digits/underscores only — no hyphens or spaces)' || ok=1
  # ...the tag-comment format with the id on its first line...
  require "$NAMING_BULLET" 'tag comment immediately above it whose first line carries the ADD/MODIFY/REMOVE marker and the id' || ok=1
  # ...and the tag-description rule.
  require "$NAMING_BULLET" "Don't put other scenarios' ids in a tag's description" || ok=1
  # The id shape itself survives in the bullet.
  require "$NAMING_BULLET" '<feature>-<index>' || ok=1
  return $ok
}

# =============================================================================
# conventions-02: the end-to-end QA suite is one file per change dir, in the
# fixed file e2e-qa.feature -- not one per feature; the section's operating
# rules survive; the "One per feature" wording is gone.
# =============================================================================
test_conventions_02() {
  ok=0
  # The first bullet states: exactly one suite per change...
  require "$E2E_BULLET" 'Exactly one end-to-end QA suite per change' || ok=1
  # ...written to the fixed file e2e-qa.feature in the change directory...
  require "$E2E_BULLET" 'the fixed file `e2e-qa.feature`' || ok=1
  require "$E2E_BULLET" 'in the change directory' || ok=1
  # ...and the one-per-change (not per-feature) contrast explicitly.
  require "$E2E_BULLET" 'one per change, not one per feature' || ok=1
  # The section keeps its operating rules: the UI/no-internal-API rule in the
  # first bullet, the affordance rule, the user-visible-workflow rule.
  require "$E2E_BULLET" 'operates at the UI, no internal API calls' || ok=1
  require "$E2E_SECTION" 'CLI flags/QA commands allowed only as UI affordances.' || ok=1
  require "$E2E_SECTION" 'Specify user-visible workflows, inputs, outputs, observable states.' || ok=1
  # "One per feature" is gone from the section and from the whole prompt.
  refuse "$E2E_SECTION" 'One per feature' || ok=1
  refuse "$SPECIFIER_PROMPT" 'One per feature' || ok=1
  return $ok
}

# =============================================================================
# conventions-03: the relevant-files bullet becomes one section per sub-spec,
# carrying that sub-spec's relevant files (pointers only, not a code
# walkthrough) and its declared destination domain (kebab-case); the bullet
# never names README.md itself; the overview bullet's enumeration is
# byte-for-byte unchanged and the section still states the fixed name exactly
# once (the readmefile-01/02 pins stay green unmodified).
# =============================================================================
test_conventions_03() {
  ok=0
  REL_BULLET=$(mktemp)
  grep -F -- '- Relevant files found during investigation' "$OUTPUT_SECTION" > "$REL_BULLET"
  n=$(grep -c . "$REL_BULLET")
  if [ "$n" != "1" ]; then
    echo "  expected exactly one relevant-files bullet in ## Output, found $n"
    rm -f "$REL_BULLET"
    return 1
  fi
  # One section per sub-spec, in the overview file...
  require "$REL_BULLET" 'one section per sub-spec' || ok=1
  require "$REL_BULLET" 'overview file' || ok=1
  # ...each carrying that sub-spec's relevant files (pointers only, not a
  # code walkthrough) and its declared destination domain...
  require "$REL_BULLET" 'pointers only rather than a code walkthrough' || ok=1
  require "$REL_BULLET" 'declared destination domain' || ok=1
  # ...the domain name kebab-case...
  require "$REL_BULLET" 'kebab-case' || ok=1
  # ...and the original re-discovery purpose survives.
  require "$REL_BULLET" "the coder doesn't have to re-discover them" || ok=1
  # The bullet does not name README.md -- it refers to the overview file.
  refuse "$REL_BULLET" 'README.md' || ok=1
  rm -f "$REL_BULLET"

  # The section as a whole still states the fixed name exactly once
  # (readmefile-02's invariant, unmodified).
  occurrences=$(grep -oF 'README.md' "$OUTPUT_SECTION" | wc -l | tr -d ' ')
  if [ "$occurrences" != "1" ]; then
    echo "  expected exactly one README.md occurrence in the Output section, found $occurrences"
    ok=1
  fi

  # The overview bullet's own enumeration is byte-for-byte unchanged vs HEAD.
  HEAD_OVERVIEW_BULLET=$(git -C "$SCRIPT_DIR" show HEAD:agents/prompts/specifier.prompt 2>/dev/null | grep -F -- 'Write the change')
  if [ -z "$HEAD_OVERVIEW_BULLET" ]; then
    echo "  cannot read HEAD's overview bullet (fixture problem?)"
    ok=1
  elif ! grep -qxF -- "$HEAD_OVERVIEW_BULLET" "$SPECIFIER_PROMPT"; then
    echo "  the overview bullet is no longer byte-for-byte unchanged: $HEAD_OVERVIEW_BULLET"
    ok=1
  fi
  return $ok
}

# =============================================================================
# conventions-04: the specifier diff-window pins retire by gating, loudly.
#
# Fixture roots are throwaway git repos (the tests/antz-flow_test.sh new_repo
# precedent: mktemp -d, one local commit) -- the real repo is never committed
# to and nothing under $SCRIPT_DIR is mutated. The note a gated guard prints
# when the working copy differs from HEAD is matched by NOTE_RE.
# =============================================================================

NOTE_RE='note:.*specifier\.prompt.*retir'

run_suite() {
  # $1 = repo root to run in, $2 = suite path relative to that root; sets
  # fx_out (stdout+stderr) and fx_rc.
  fx_out=$(CDPATH= sh -c 'cd "$1" && sh "$2" 2>&1' _ "$1" "$2")
  fx_rc=$?
}

fixture_tree() {
  # $1 = dest root: copy the working tree minus .git and spdd/ (neither
  # gated suite reads either).
  mkdir -p "$1"
  tar -C "$SCRIPT_DIR" --exclude=./.git --exclude=./spdd -cf - . | tar -C "$1" -xf -
}

fixture_commit() {
  # $1 = fixture root: git init plus one fixture-local commit of the copy.
  git -C "$1" init -q
  git -C "$1" add .
  git -C "$1" -c user.email=t@example.invalid -c user.name=t commit -q -m "conventions-04 fixture"
}

# The session state, synthesized inside the fixture (fix-test-regression-
# precision-gaps 03-conventions): copy the working tree (minus .git and
# spdd/), commit the copy as-is as the fixture's one local commit, then
# mutate the fixture's working specifier.prompt so it differs from the
# FIXTURE's own HEAD -- reading no content from the real repository's git
# HEAD, so the retirement path is covered whether the conventions-01..03
# rewordings are pending or committed. The mutation is this fixed,
# deterministic reword of one line in the specifier prompt's Verification
# section -- outside the report/Output section, the only text of that file
# the ungated assertions of the two exercised suites read -- so every
# ungated assertion keeps passing and only the gated retirements fire. The
# build fails loudly if the anchor line is ever gone, rather than silently
# yielding a fixture that does not differ.
MUTATE_ANCHOR='- Do not run mutation testing or other verification tools.'
MUTATE_REWORD='- Do not run mutation testing or other verification tooling.'

make_fixture_differs() {
  fixture_tree "$1"
  fixture_commit "$1"
  prompt="$1/agents/prompts/specifier.prompt"
  tmp="$1/.specifier.mutate.tmp"
  if ! awk -v old="$MUTATE_ANCHOR" -v new="$MUTATE_REWORD" '
      $0 == old && !done { print new; done = 1; next }
      { print }
      END { exit done ? 0 : 1 }
    ' "$prompt" > "$tmp"; then
    echo "  fixture mutation anchor line not found in specifier.prompt -- the diff window cannot be synthesized (fixture problem?)"
    rm -f "$tmp"
    return 1
  fi
  mv "$tmp" "$prompt"
}

# The post-commit state: the working copy is byte-identical to HEAD (the
# rewording already committed) -- the pins must stay enforced, quietly.
make_fixture_identical() {
  fixture_tree "$1"
  fixture_commit "$1"
}

# The degenerate state check's bite: no diff vs HEAD but the committed prompt
# lacks the closing-block bullet -- the kept no-diff check must still fail.
make_fixture_no_bullet() {
  fixture_tree "$1"
  grep -v 'closing block' "$1/agents/prompts/specifier.prompt" > "$1/.specifier.tmp"
  mv "$1/.specifier.tmp" "$1/agents/prompts/specifier.prompt"
  fixture_commit "$1"
}

fails_of() {
  # $1 = suite output: print its FAIL lines (none when there are none).
  printf '%s\n' "$1" | grep '^FAIL' || true
}

test_conventions_04_working_suites_green_guards_registered() {
  ok=0
  run_suite "$SCRIPT_DIR" "$PROMPTS_SUITE"
  prompts_out=$fx_out; prompts_rc=$fx_rc
  run_suite "$SCRIPT_DIR" "$CLOSINGBLOCK_SUITE"
  closing_out=$fx_out; closing_rc=$fx_rc
  if [ "$prompts_rc" -ne 0 ]; then
    echo "  $PROMPTS_SUITE must pass while the rewordings are in the working tree:"
    fails_of "$prompts_out"; ok=1
  fi
  if [ "$closing_rc" -ne 0 ]; then
    echo "  $CLOSINGBLOCK_SUITE must pass while the rewordings are in the working tree:"
    fails_of "$closing_out"; ok=1
  fi
  # The guards stay registered -- retired by gating, not deleted.
  printf '%s\n' "$prompts_out" | grep -q '^PASS: prompts-05' \
    || { echo "  prompts-05 is no longer registered in $PROMPTS_SUITE"; ok=1; }
  if [ "$(printf '%s\n' "$closing_out" | grep -c '^PASS: closingblock-05')" != "2" ]; then
    echo "  both closingblock-05 assertions must stay registered in $CLOSINGBLOCK_SUITE"; ok=1
  fi
  # Time-robust (the 94938da lesson): the loud note is expected exactly while
  # the working copy differs from HEAD; once a human commits, the pin runs
  # again and the note is gone.
  if ! git -C "$SCRIPT_DIR" diff HEAD --quiet -- agents/prompts/specifier.prompt; then
    printf '%s\n' "$prompts_out" | grep -qE "$NOTE_RE" \
      || { echo "  prompts-05 prints no loud retirement note though the copy differs from HEAD"; ok=1; }
    if [ "$(printf '%s\n' "$closing_out" | grep -cE "$NOTE_RE")" != "2" ]; then
      echo "  the two closingblock-05 assertions print no loud retirement notes though the copy differs from HEAD"; ok=1
    fi
  fi
  return $ok
}

test_conventions_04_prompts05_retires_loudly_when_copy_differs() {
  ok=0
  fx=$(mktemp -d)
  make_fixture_differs "$fx" \
    || { echo "  cannot build the differs fixture"; rm -rf "$fx"; return 1; }
  run_suite "$fx" "$PROMPTS_SUITE"
  printf '%s\n' "$fx_out" | grep -q '^PASS: prompts-05' \
    || { echo "  prompts-05 must stay registered and pass once the copy differs from HEAD:"; fails_of "$fx_out"; ok=1; }
  printf '%s\n' "$fx_out" | grep -qE "$NOTE_RE" \
    || { echo "  prompts-05 must print a loud retirement note when the copy differs from HEAD"; ok=1; }
  # The skipped checks must really be skipped: the rewording removes lines,
  # so a still-enforced additive-shape check fails the suite.
  if [ "$fx_rc" -ne 0 ]; then
    echo "  the gated prompts suite must exit 0 with the legitimate rewording:"
    fails_of "$fx_out"; ok=1
  fi
  rm -rf "$fx"
  return $ok
}

test_conventions_04_prompts05_pin_enforced_quietly_when_copy_identical() {
  ok=0
  fx=$(mktemp -d)
  make_fixture_identical "$fx"
  run_suite "$fx" "$PROMPTS_SUITE"
  if [ "$fx_rc" -ne 0 ]; then
    echo "  the prompts suite must pass with a byte-identical copy:"
    fails_of "$fx_out"; ok=1
  fi
  printf '%s\n' "$fx_out" | grep -q '^PASS: prompts-05' \
    || { echo "  prompts-05 must pass while the copy is byte-identical to HEAD"; ok=1; }
  if printf '%s\n' "$fx_out" | grep -qE 'note:.*specifier\.prompt'; then
    echo "  prompts-05 must not retire while the copy is byte-identical to HEAD (the pin is enforced)"
    ok=1
  fi
  rm -rf "$fx"
  return $ok
}

test_conventions_04_closingblock05_retires_loudly_when_copy_differs() {
  ok=0
  fx=$(mktemp -d)
  make_fixture_differs "$fx" \
    || { echo "  cannot build the differs fixture"; rm -rf "$fx"; return 1; }
  run_suite "$fx" "$CLOSINGBLOCK_SUITE"
  if [ "$fx_rc" -ne 0 ]; then
    echo "  the gated closingblock suite must exit 0 with the legitimate rewording:"
    fails_of "$fx_out"; ok=1
  fi
  if [ "$(printf '%s\n' "$fx_out" | grep -c '^PASS: closingblock-05')" != "2" ]; then
    echo "  both closingblock-05 assertions must stay registered and pass when the copy differs from HEAD"; ok=1
  fi
  if [ "$(printf '%s\n' "$fx_out" | grep -cE "$NOTE_RE")" != "2" ]; then
    echo "  each of the two closingblock-05 assertions must print its own loud retirement note"; ok=1
  fi
  rm -rf "$fx"
  return $ok
}

test_conventions_04_closingblock05_enforced_quietly_when_copy_identical() {
  ok=0
  fx=$(mktemp -d)
  make_fixture_identical "$fx"
  run_suite "$fx" "$CLOSINGBLOCK_SUITE"
  if [ "$fx_rc" -ne 0 ]; then
    echo "  the closingblock suite must pass with a byte-identical copy:"
    fails_of "$fx_out"; ok=1
  fi
  if [ "$(printf '%s\n' "$fx_out" | grep -c '^PASS: closingblock-05')" != "2" ]; then
    echo "  both closingblock-05 assertions must pass while the copy is byte-identical to HEAD"; ok=1
  fi
  if printf '%s\n' "$fx_out" | grep -qE 'note:.*specifier\.prompt'; then
    echo "  closingblock-05 must not retire while the copy is byte-identical to HEAD (the checks are enforced)"
    ok=1
  fi
  rm -rf "$fx"
  return $ok
}

# The fixture-builder contract itself (fix-test-regression-precision-gaps
# 03-conventions): the diff window is synthesized inside the fixture -- the
# copy committed as-is, only the fixture's working specifier.prompt mutated
# by a fixed deterministic reword -- so the builder never reads the real
# repository's git HEAD and covers the retirement path in every repo state.
test_conventions_04_differs_fixture_is_synthesized_inside_the_fixture() {
  ok=0
  fx=$(mktemp -d)
  make_fixture_differs "$fx" \
    || { echo "  cannot build the differs fixture"; rm -rf "$fx"; return 1; }
  # The window lives inside the fixture: the working specifier.prompt
  # differs from the fixture's OWN HEAD (what trips the gated retirements,
  # in every repo state).
  if git -C "$fx" diff HEAD --quiet -- agents/prompts/specifier.prompt; then
    echo "  the fixture's working specifier.prompt does not differ from the fixture's own HEAD (window not synthesized)"; ok=1
  fi
  # The fixture commits the copy as-is -- never a blob taken from the real
  # repo's git HEAD: its HEAD copy is byte-identical to the working tree's
  # specifier.prompt.
  if ! git -C "$fx" show HEAD:agents/prompts/specifier.prompt 2>/dev/null | cmp -s - "$SPECIFIER_PROMPT"; then
    echo "  the fixture's committed specifier.prompt is not the working copy as-is (a real-HEAD read?)"; ok=1
  fi
  # The post-commit mutation touched only that fixture file...
  changed=$(git -C "$fx" diff HEAD --name-only)
  if [ "$changed" != "agents/prompts/specifier.prompt" ]; then
    echo "  the mutation touched more than the fixture's specifier.prompt: $changed"; ok=1
  fi
  if cmp -s "$fx/agents/prompts/specifier.prompt" "$SPECIFIER_PROMPT"; then
    echo "  the fixture's working specifier.prompt is unmutated (identical to the working tree's)"; ok=1
  fi
  # ...and it is fixed and deterministic: a second build yields a
  # byte-identical fixture working copy.
  fx2=$(mktemp -d)
  make_fixture_differs "$fx2" \
    || { echo "  cannot build the differs fixture (second run)"; rm -rf "$fx" "$fx2"; return 1; }
  if ! cmp -s "$fx/agents/prompts/specifier.prompt" "$fx2/agents/prompts/specifier.prompt"; then
    echo "  the fixture mutation is not deterministic"; ok=1
  fi
  rm -rf "$fx" "$fx2"
  return $ok
}

test_conventions_04_closingblock05_degenerate_no_diff_check_kept() {
  ok=0
  fx=$(mktemp -d)
  make_fixture_no_bullet "$fx"
  run_suite "$fx" "$CLOSINGBLOCK_SUITE"
  # The no-diff state degrades to the kept state check: a prompt without the
  # closing-block bullet must still fail it -- the gating retired only the
  # diff-window assertions, not the degenerate check.
  if [ "$fx_rc" -eq 0 ]; then
    echo "  the kept degenerate no-diff state check must fail a committed prompt without the closing-block bullet"
    ok=1
  fi
  printf '%s\n' "$fx_out" | grep -qF "FAIL: closingblock-05: the specifier prompt's diff" \
    || { echo "  the failing assertion must still be the kept closingblock-05 state check"; ok=1; }
  if printf '%s\n' "$fx_out" | grep -qE 'note:.*specifier\.prompt'; then
    echo "  no retirement note is expected in the no-diff state (the gate keys on the copy differing from HEAD)"
    ok=1
  fi
  rm -rf "$fx"
  return $ok
}

# ---- run everything ----------------------------------------------------------

run_test "conventions-01: the Specification Rules scenario-naming bullet defines the index as two zero-padded digits sequential from 01 while keeping the one-word feature rule, the tag-comment format, and the tag-description rule" test_conventions_01
run_test "conventions-02: the End-To-End QA Suite first bullet states exactly one suite per change in the fixed file e2e-qa.feature, keeps the operating rules, and drops the One per feature wording" test_conventions_02
run_test "conventions-03: the Output relevant-files bullet states one section per sub-spec with relevant files and the declared kebab-case destination domain, names no README.md, and leaves the overview bullet byte-for-byte unchanged" test_conventions_03
run_test "conventions-04: both suites carrying the specifier diff-window pins pass with the guards still registered, and print the loud notes while the rewording is uncommitted" test_conventions_04_working_suites_green_guards_registered
run_test "conventions-04: prompts-05's specifier guard retires by gating -- loud retirement note, additive-shape checks skipped -- when the fixture copy differs from HEAD" test_conventions_04_prompts05_retires_loudly_when_copy_differs
run_test "conventions-04: the differs-fixture synthesizes its window inside the fixture -- the copy committed as-is, only the fixture's working specifier.prompt mutated by a fixed deterministic reword, no read of the real git HEAD" test_conventions_04_differs_fixture_is_synthesized_inside_the_fixture
run_test "conventions-04: prompts-05's byte-for-byte pin is still enforced quietly when the fixture copy is byte-identical to HEAD" test_conventions_04_prompts05_pin_enforced_quietly_when_copy_identical
run_test "conventions-04: closingblock-05's two specifier diff-window assertions retire by gating with two loud notes when the fixture copy differs from HEAD" test_conventions_04_closingblock05_retires_loudly_when_copy_differs
run_test "conventions-04: closingblock-05's specifier assertions stay enforced quietly when the fixture copy is byte-identical to HEAD" test_conventions_04_closingblock05_enforced_quietly_when_copy_identical
run_test "conventions-04: closingblock-05's degenerate no-diff state check is kept -- a committed prompt without the closing-block bullet still fails it, with no note" test_conventions_04_closingblock05_degenerate_no_diff_check_kept

rm -f "$SPEC_RULES" "$E2E_SECTION" "$OUTPUT_SECTION" "$NAMING_BULLET" "$E2E_BULLET"

echo ""
echo "$pass_count passed, $fail_count failed, $skip_count skipped"
[ "$fail_count" -eq 0 ]
