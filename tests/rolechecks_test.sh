#!/usr/bin/env bash
# Unit tests for change precision-gaps, sub-spec 02
# (spdd/changes/precision-gaps/02-rolechecks.feature, scenarios
# rolechecks-01..05): the coder prompt's pre-planning id check becomes a
# literal grep of the id in the project's test files (rolechecks-01), the
# coder's plan threshold is fixed at more than 8 implementation steps or more
# than 1 shared contract needing change (rolechecks-02), the verifier's
# "code present" gate becomes mechanical -- the same literal grep or the
# result receipt's existence (rolechecks-03), the verifier's merge bullet
# states the per-domain spec-file rule with kebab-case naming and
# create-when-new (rolechecks-04), and tests/roles_test.sh's roles-03
# exact-string pin of the merge bullet is re-scoped to the extended bullet
# (rolechecks-05).
#
# The two working-vs-HEAD window assertions this suite uses -- the
# appended-sentence-yields-HEAD's-bullet check (rolechecks-01) and the
# roles-03 re-scope inversion with its Given and the roles-01/02/04/05
# byte-identity loop (rolechecks-05) -- gate on the change_pending() pattern
# of tests/bump440_test.sh, tests/bump450_test.sh and tests/bump460_test.sh
# (retiro ruidoso por gating, stacking-robust, adopted by change
# fix-test-regression-precision-gaps sub-spec 02): enforced only while the
# guarded artifact differs from HEAD and HEAD does not yet carry this
# change's marker content, retired with a loud "note:" line otherwise. The
# predicates are per-artifact (agents/prompts/coder.prompt gates
# independently of tests/roles_test.sh). The absolute content pins and the
# observable criterion never read git HEAD and stay enforced in every repo
# state.
#
# Amended by change style-rewrite (sub-spec 06-terminology, terminology-01):
# the verifier prompt's `<change-slug>` -> `<slug>` unification rewrites two
# of the bullets this suite byte-compares against HEAD (rolechecks-03's
# missing-change-dir Input Rule bullet and rolechecks-04's archive-move
# bullet). Those two windows are gated from birth on the same pattern:
# enforced only while verifier.prompt differs from HEAD AND HEAD's bullet
# still reads `<change-slug>` (the unification pending), retired with a loud
# "note:" otherwise; within the window the working bullet must equal HEAD's
# bullet with exactly the placeholder rewrite applied, so any change beyond
# the unification still fails.
#
# Self-contained bash test harness (no external framework/dependency -- this
# repo has no package manager or build system), mirroring the harness style
# of tests/roles_test.sh. Run directly:
#   ./tests/rolechecks_test.sh

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CODER_PROMPT="$SCRIPT_DIR/agents/prompts/coder.prompt"
VERIFIER_PROMPT="$SCRIPT_DIR/agents/prompts/verifier.prompt"
ROLES_SUITE="$SCRIPT_DIR/tests/roles_test.sh"

# The id-search convention, stated identically by the coder's pre-planning
# check and the verifier's code-present criterion (sub-spec invariant).
ID_SEARCH='literal grep of the id in the project'"'"'s test files (the files carrying the unit-test suite)'

pass_count=0
fail_count=0

# ---- tiny test runner (mirrors tests/roles_test.sh) --------------------------

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

# Extract a "## <name>" section (its own heading line down to the next top
# level "## " heading or EOF) from $1 into $3.
extract_section() {
  # $1 = file, $2 = heading text, $3 = output file
  awk -v sec="$2" '
    $0 == "## " sec { flag=1; next }
    flag && /^## / { flag=0 }
    flag { print }
  ' "$1" > "$3"
}

# Extract one physical line (a prompt bullet or a shell function's matching
# line) by fixed substring from $1 into $3; first match only.
extract_line() {
  # $1 = file, $2 = fixed substring, $3 = output file
  grep -m1 -F -- "$2" "$1" > "$3"
}

# Extract the shell function named $2 (from its "name() {" line to the first
# column-0 "}") from file $1 into $3.
extract_fn() {
  # $1 = file, $2 = function name, $3 = output file
  awk -v fn="$2" '
    index($0, fn "() {") == 1 { flag = 1 }
    flag { print }
    flag && $0 == "}" { exit }
  ' "$1" > "$3"
}

# ---- scoped extracts (bullet-scoped, so a phrase elsewhere never satisfies
# an assertion) ----------------------------------------------------------------

CODER_PROCESS=$(mktemp)
IDCHECK_BULLET=$(mktemp)
PLAN_BULLET=$(mktemp)
STUB_BULLET=$(mktemp)
VERIFIER_INPUT=$(mktemp)
CODEPRESENT_BULLET=$(mktemp)
VERIFIER_MERGE=$(mktemp)
extract_section "$CODER_PROMPT" "Process" "$CODER_PROCESS"
extract_line "$CODER_PROCESS" 'check the working tree for scenario ids' "$IDCHECK_BULLET"
extract_line "$CODER_PROCESS" 'Plan briefly.' "$PLAN_BULLET"
extract_line "$CODER_PROCESS" 'When refusing or escalating instead of finishing' "$STUB_BULLET"
extract_section "$VERIFIER_PROMPT" "Input Rule" "$VERIFIER_INPUT"
extract_line "$VERIFIER_INPUT" 'code present' "$CODEPRESENT_BULLET"
extract_section "$VERIFIER_PROMPT" "Merge & Archive, only on approved or approved-with-warnings" "$VERIFIER_MERGE"

# HEAD baselines for the working-vs-HEAD window assertions (the repo is a
# git checkout). HEAD is NOT assumed to be the pre-change state: precision-
# gaps (Change C) is committed at HEAD today, so the window assertions that
# read HEAD gate on the per-artifact predicates below, while the absolute
# content pins never read HEAD. rolechecks-02/03/04's surrounding-bullet
# byte-identity comparisons pass in both repo states (out of the gating
# fix's scope).
HEAD_CODER=$(mktemp)
HEAD_VERIFIER=$(mktemp)
HEAD_ROLES=$(mktemp)
git -C "$SCRIPT_DIR" show HEAD:agents/prompts/coder.prompt > "$HEAD_CODER" 2>/dev/null \
  || { echo "FATAL: cannot read HEAD:agents/prompts/coder.prompt"; exit 1; }
git -C "$SCRIPT_DIR" show HEAD:agents/prompts/verifier.prompt > "$HEAD_VERIFIER" 2>/dev/null \
  || { echo "FATAL: cannot read HEAD:agents/prompts/verifier.prompt"; exit 1; }
git -C "$SCRIPT_DIR" show HEAD:tests/roles_test.sh > "$HEAD_ROLES" 2>/dev/null \
  || { echo "FATAL: cannot read HEAD:tests/roles_test.sh"; exit 1; }

# Extract the single line (first match) containing the fixed substring $2
# from file $1 into $3 -- used to pull one physical bullet out of a file.
line_of() {
  # $1 = file, $2 = fixed substring, $3 = output file
  grep -m1 -F -- "$2" "$1" > "$3"
}

# HEAD's marker carriers: HEAD's pre-planning bullet (marker: the appended
# id-search sentence) and HEAD's test_roles_03 function (marker: the re-
# scoped pin of the extended merge bullet), read by the gates below.
HEAD_IDCHECK_BULLET=$(mktemp)
line_of "$HEAD_CODER" 'check the working tree for scenario ids' "$HEAD_IDCHECK_BULLET"
HEAD_ROLES_03=$(mktemp)
extract_fn "$HEAD_ROLES" test_roles_03 "$HEAD_ROLES_03"

# HEAD baselines for the terminology-01 windows: the two verifier bullets
# whose `spdd/changes/<change-slug>/` placeholder this change rewrites to
# `<slug>` (rolechecks-03's missing-change-dir Input Rule bullet,
# rolechecks-04's archive-move bullet). The extraction keys are the stable
# prose around the placeholder ("doesn't exist", the move-verb prefix), so
# they find the bullet in HEAD under either spelling.
HEAD_B1_BULLET=$(mktemp)
line_of "$HEAD_VERIFIER" "doesn't exist" "$HEAD_B1_BULLET"
HEAD_M1_BULLET=$(mktemp)
line_of "$HEAD_VERIFIER" 'move `spdd/changes/' "$HEAD_M1_BULLET"

# ---- per-artifact change_pending() gates (the bump440/450/460 pattern) -------
# A working-vs-HEAD window assertion is enforced only while the guarded
# artifact differs from HEAD AND HEAD does not yet carry this change's marker
# content for that artifact; otherwise it retires vacuously with a loud
# "note:" and the test still passes. The conjunction is the stacking lesson:
# once HEAD carries the marker, any current diff of the artifact is a LATER
# change's legitimate edit and must not resurrect the window. The predicates
# are per-artifact, so the coder.prompt window and the roles_test.sh window
# gate independently.

coder_change_pending() {
  # The coder.prompt reword is pending: the file differs from HEAD and HEAD's
  # pre-planning bullet does not yet carry the appended id-search sentence.
  ! git -C "$SCRIPT_DIR" diff --quiet HEAD -- agents/prompts/coder.prompt 2>/dev/null \
    && ! grep -qF "$ID_SEARCH" "$HEAD_IDCHECK_BULLET"
}

roles_change_pending() {
  # The roles_test.sh re-scope is pending: the file differs from HEAD and
  # HEAD's roles-03 does not yet pin the extended bullet's new content.
  ! git -C "$SCRIPT_DIR" diff --quiet HEAD -- tests/roles_test.sh 2>/dev/null \
    && ! grep -qF 'one spec file per domain, at `spdd/specs/<domain>.md`, with kebab-case domain names' "$HEAD_ROLES_03"
}

# The two terminology-01 windows (style-rewrite 06-terminology): each is
# enforced only while verifier.prompt differs from HEAD AND the bullet's HEAD
# baseline still reads `<change-slug>` — the unification pending. Once HEAD
# carries the `<slug>` form (the committed state) the window is retired for
# good: a later legitimate edit of the prompt differs from HEAD but HEAD no
# longer reads the old spelling, so the window never resurrects against it.

b1_slug_rewrite_pending() {
  ! git -C "$SCRIPT_DIR" diff --quiet HEAD -- agents/prompts/verifier.prompt 2>/dev/null \
    && grep -qF 'change-slug' "$HEAD_B1_BULLET"
}

m1_slug_rewrite_pending() {
  ! git -C "$SCRIPT_DIR" diff --quiet HEAD -- agents/prompts/verifier.prompt 2>/dev/null \
    && grep -qF 'change-slug' "$HEAD_M1_BULLET"
}

# =============================================================================
# rolechecks-01: the coder prompt's pre-planning bullet states the search
# mechanism -- a literal grep of the sub-spec's scenario id in the project's
# test files (the files carrying the unit-test suite) -- and keeps the
# bullet's meaning otherwise unchanged (ids with a passing or skipped test are
# done, not redone); in this repository the criterion is observable: a literal
# grep of an implemented id in "tests/" finds the test named after it.
# =============================================================================
test_rolechecks_01() {
  ok=0
  # The bullet is there, scoped to the ## Process section's pre-planning check.
  require "$IDCHECK_BULLET" 'Before planning' || ok=1
  require "$IDCHECK_BULLET" 'scenario ids (`<feature>-<index>`)' || ok=1

  # The search mechanism is stated: the shared id-search convention.
  require "$IDCHECK_BULLET" "$ID_SEARCH" || ok=1

  # The meaning otherwise unchanged: passing-or-skipped detection, done-not-
  # redo routing, both surviving verbatim.
  require "$IDCHECK_BULLET" 'that already have a passing or skipped test' || ok=1
  require "$IDCHECK_BULLET" 'treat those as done rather than redoing them' || ok=1

  # Window assertion (the only HEAD read in this test): the original bullet
  # survives byte-unchanged with the mechanism stated as an appended
  # sentence -- stripping that sentence from the working bullet yields HEAD's
  # line exactly. Gated on the coder.prompt reword being pending; once HEAD's
  # bullet carries the id-search sentence (the committed state) it retires
  # vacuously with a loud note -- the content pins above are the durable,
  # HEAD-independent coverage.
  if ! coder_change_pending; then
    echo "  note: the coder.prompt id-search reword is committed vs HEAD (HEAD's pre-planning bullet already carries the appended id-search sentence); the stripping-yields-HEAD's-bullet window check is vacuously retired, the content pins stay enforced"
  elif [ "$(sed -e 's/ The search is .* unit-test suite)\.$//' "$IDCHECK_BULLET")" \
       != "$(cat "$HEAD_IDCHECK_BULLET")" ]; then
    echo "  removing the appended mechanism sentence does not yield HEAD's pre-planning bullet"
    ok=1
  fi

  # Invariant: the id-search convention is used identically by the verifier's
  # code-present criterion (same fixed string in the Input Rule bullet).
  require "$CODEPRESENT_BULLET" "$ID_SEARCH" || ok=1

  # Observable in this repository: a literal grep of an implemented id in
  # tests/ finds the test named after it (a run_test-registered name).
  grep -qF 'run_test "rolechecks-01:' "$SCRIPT_DIR/tests/rolechecks_test.sh" \
    || { echo "  no run_test name carrying the id rolechecks-01 in tests/"; ok=1; }
  return $ok
}

# =============================================================================
# rolechecks-02: the coder prompt's "Plan briefly" bullet states the
# mechanical threshold -- more than 8 implementation steps for the sub-spec,
# or more than 1 shared contract needing change, marks the change for
# splitting (the coder flags that the specifier should split it further); the
# vague "is long" wording is gone; the escalation semantics (the BLOCKED:
# stub rule) are unchanged.
# =============================================================================
test_rolechecks_02() {
  ok=0
  # The threshold is stated mechanically: N fixed at 8, contracts at 1.
  require "$PLAN_BULLET" 'Plan briefly.' || ok=1
  require "$PLAN_BULLET" 'more than 8 implementation steps' || ok=1
  require "$PLAN_BULLET" 'more than 1 shared contract' || ok=1
  require "$PLAN_BULLET" 'marks the change for splitting' || ok=1

  # The splitting action is unchanged: the coder flags that the specifier
  # should split it further.
  require "$PLAN_BULLET" 'flag that the specifier should split it further' || ok=1

  # The vague wording is gone from the bullet and the whole section.
  refuse "$PLAN_BULLET" 'is long' || ok=1
  refuse "$CODER_PROCESS" 'If the plan for one sub-spec is long' || ok=1

  # The threshold is fixed -- no per-change negotiation, no configuration.
  refuse "$PLAN_BULLET" 'configurable' || ok=1
  refuse "$PLAN_BULLET" 'unless' || ok=1

  # Escalation semantics unchanged: the existing BLOCKED: stub bullet
  # survives byte-identical vs HEAD (plain colon, scenario-id tagging).
  STUB_HEAD=$(mktemp)
  line_of "$HEAD_CODER" 'When refusing or escalating instead of finishing' "$STUB_HEAD"
  cmp -s "$STUB_BULLET" "$STUB_HEAD" \
    || { echo "  the BLOCKED: stub bullet is not byte-identical vs HEAD"; ok=1; }
  rm -f "$STUB_HEAD"
  require "$STUB_BULLET" '`BLOCKED: <why>` (plain colon)' || ok=1

  # The ## Process section still carries exactly 9 bullets -- the two
  # reworded bullets are in-place edits.
  n=$(grep -c '^- ' "$CODER_PROCESS")
  [ "$n" -eq 9 ] || { echo "  ## Process has $n bullets, expected 9"; ok=1; }
  return $ok
}

# =============================================================================
# rolechecks-03: the verifier prompt's Input Rule defines "code present"
# mechanically -- the declared scenario ids found by the same literal grep,
# or the result receipt exists (existence only, never the receipt's grammar)
# -- and keeps the routing meaning: the named form stops and reports nothing
# to verify, the whole-change form verifies every sub-spec with code present
# and flags the rest as unimplemented rather than stopping outright.
# =============================================================================
test_rolechecks_03() {
  ok=0
  # The mechanical definition is stated in the Input Rule bullet.
  require "$CODEPRESENT_BULLET" 'A sub-spec has code present when' || ok=1
  require "$CODEPRESENT_BULLET" 'declared scenario ids' || ok=1
  require "$CODEPRESENT_BULLET" "$ID_SEARCH" || ok=1

  # The second disjunct: the receipt's existence at its grammar's path, read
  # as existence only -- never the receipt's grammar (invariant).
  require "$CODEPRESENT_BULLET" 'or its result receipt (`spdd/changes/<slug>/NN-<feature>.result`) exists' || ok=1
  refuse "$CODEPRESENT_BULLET" 'test_command=' || ok=1
  refuse "$CODEPRESENT_BULLET" 'result=green' || ok=1
  refuse "$VERIFIER_INPUT" 'grammar' || ok=1

  # Routing meaning unchanged, both forms.
  require "$CODEPRESENT_BULLET" "If the named sub-spec has no code present, stop and report there's nothing to verify." || ok=1
  require "$CODEPRESENT_BULLET" 'whole-change form' || ok=1
  require "$CODEPRESENT_BULLET" 'verify every sub-spec that has code present' || ok=1
  require "$CODEPRESENT_BULLET" "flag any that don't as unimplemented in the report rather than stopping outright" || ok=1

  # The old vague criterion is gone from the whole prompt.
  refuse "$VERIFIER_PROMPT" 'code changes yet' || ok=1

  # The rest of the Input Rule is unchanged, byte-identical vs HEAD, and the
  # section keeps its 3 bullets -- the reword is an in-place edit. The
  # OPEN_QUESTIONS.md bullet is touched by no change, so it compares
  # unconditionally; the missing-change-dir bullet was rewritten by style-
  # rewrite terminology-01 (`<change-slug>` -> `<slug>`), so its window is
  # born gated: while the unification is pending the working bullet must
  # equal HEAD's bullet with exactly the placeholder rewrite applied, and
  # once committed vs HEAD the check retires vacuously with a loud note. The
  # absolute pins (the 3-bullet count, the mechanical code-present
  # definition above) stay enforced in every repo state.
  n=$(grep -c '^- ' "$VERIFIER_INPUT")
  [ "$n" -eq 3 ] || { echo "  Input Rule has $n bullets, expected 3"; ok=1; }
  B2_CUR=$(mktemp); B2_HEAD=$(mktemp)
  grep -F 'OPEN_QUESTIONS.md' "$VERIFIER_INPUT" > "$B2_CUR"
  grep -F 'OPEN_QUESTIONS.md' "$HEAD_VERIFIER" > "$B2_HEAD"
  cmp -s "$B2_CUR" "$B2_HEAD" \
    || { echo "  the OPEN_QUESTIONS.md bullet changed vs HEAD"; ok=1; }
  rm -f "$B2_CUR" "$B2_HEAD"
  B1_CUR=$(mktemp)
  line_of "$VERIFIER_INPUT" "doesn't exist" "$B1_CUR"
  if ! b1_slug_rewrite_pending; then
    echo "  note: the verifier prompt's missing-change-dir \`<change-slug>\` -> \`<slug>\` unification is committed vs HEAD (or HEAD's bullet no longer reads the old spelling); the byte-identity window is vacuously retired, the absolute pins stay enforced"
  elif [ "$(cat "$B1_CUR")" != "$(sed -e 's|<change-slug>|<slug>|g' "$HEAD_B1_BULLET")" ]; then
    echo "  the missing-change-dir bullet changed beyond the <change-slug> -> <slug> unification"
    ok=1
  fi
  rm -f "$B1_CUR"
  return $ok
}

# =============================================================================
# rolechecks-04: the verifier prompt's Merge & Archive merge bullet states
# the domain-file rule (one file per domain at spdd/specs/<domain>.md,
# kebab-case), the resolution (the destination domain is read from the change
# README's section for that sub-spec), and the creation rule (new domain: the
# verifier creates the file with a "# Domain: <domain>" header plus the
# merged scenarios under the same merge rules), keeping the never-overwrite
# rule verbatim.
# =============================================================================
test_rolechecks_04() {
  ok=0
  # The domain-file rule: one file per domain, kebab-case, at the specs path.
  require "$VERIFIER_MERGE" 'one spec file per domain, at `spdd/specs/<domain>.md`, with kebab-case domain names' || ok=1

  # The resolution: destination domain from the change README's section for
  # that sub-spec; the merge goes into that domain's file.
  require "$VERIFIER_MERGE" "destination domain is read from the change README's section for that sub-spec" || ok=1
  require "$VERIFIER_MERGE" "the merge goes into that domain's file" || ok=1

  # The creation rule for a new domain.
  require "$VERIFIER_MERGE" 'When the domain is new (no `spdd/specs/<domain>.md` exists), the verifier creates the file' || ok=1
  require "$VERIFIER_MERGE" 'a `# Domain: <domain>` header plus the merged scenarios, under the same merge rules' || ok=1

  # The never-overwrite rule is kept verbatim: HEAD's whole merge sentence
  # survives inside the extended bullet.
  HEAD_SENT=$(grep -m1 -F 'Merge each scenario' "$HEAD_VERIFIER")
  [ -n "$HEAD_SENT" ] || { echo "  HEAD verifier prompt has no merge sentence to survive"; return 1; }
  grep -qF -- "$HEAD_SENT" "$VERIFIER_MERGE" \
    || { echo "  HEAD's merge sentence no longer survives verbatim in the bullet"; ok=1; }
  require "$VERIFIER_MERGE" 'reading the existing spec first and merging rather than overwriting it' || ok=1

  # The bullet stays a single physical line, and the rest of Merge & Archive
  # (plain-mv bullet, rejected-change bullet) is unchanged vs HEAD. The
  # rejected-change bullet is touched by no change, so it compares
  # unconditionally; the plain-mv archive-move bullet was rewritten by style-
  # rewrite terminology-01 (`<change-slug>` -> `<slug>` at both of its
  # spots), so its window is born gated the same way -- within the pending
  # window the working bullet must equal HEAD's bullet with exactly the
  # placeholder rewrite applied, and it retires vacuously with a loud note
  # once the rewrite is committed vs HEAD.
  n=$(grep -c '^- ' "$VERIFIER_MERGE")
  [ "$n" -eq 3 ] || { echo "  Merge & Archive has $n bullets, expected 3"; ok=1; }
  M2_CUR=$(mktemp); M2_HEAD=$(mktemp)
  grep -F 'Never archive a rejected change' "$VERIFIER_MERGE" > "$M2_CUR"
  grep -F 'Never archive a rejected change' "$HEAD_VERIFIER" > "$M2_HEAD"
  cmp -s "$M2_CUR" "$M2_HEAD" \
    || { echo "  the rejected-change bullet changed vs HEAD"; ok=1; }
  rm -f "$M2_CUR" "$M2_HEAD"
  M1_CUR=$(mktemp)
  grep -F 'move `spdd/changes/' "$VERIFIER_MERGE" > "$M1_CUR"
  if ! m1_slug_rewrite_pending; then
    echo "  note: the verifier prompt's archive-move \`<change-slug>\` -> \`<slug>\` unification is committed vs HEAD (or HEAD's bullet no longer reads the old spelling); the byte-identity window is vacuously retired, the absolute pins stay enforced"
  elif [ "$(cat "$M1_CUR")" != "$(sed -e 's|<change-slug>|<slug>|g' "$HEAD_M1_BULLET")" ]; then
    echo "  the archive-move bullet changed beyond the <change-slug> -> <slug> unification"
    ok=1
  fi
  rm -f "$M1_CUR"
  return $ok
}

# =============================================================================
# rolechecks-05: tests/roles_test.sh's roles-03 assertion, which pinned the
# pre-change merge-bullet sentence verbatim, is re-scoped to the extended
# bullet -- pinning the new content (per-domain file rule, kebab-case naming,
# create-when-new) alongside the surviving merge and never-overwrite wording
# -- while roles-01/02/04/05's assertions keep passing unmodified and the
# rest of the suite stays green.
# =============================================================================
test_rolechecks_05() {
  ok=0

  # The re-scope content pins, absolute (no git HEAD read, enforced in every
  # repo state): the working test_roles_03 asserts the surviving pre-change
  # merge-bullet sentence verbatim alongside the extended bullet's new
  # content -- the per-domain file rule, the kebab-case naming, the
  # create-when-new rule.
  CUR_R3=$(mktemp)
  extract_fn "$ROLES_SUITE" test_roles_03 "$CUR_R3"
  [ -s "$CUR_R3" ] || { echo "  test_roles_03 not found in the working roles_test.sh"; rm -f "$CUR_R3"; return 1; }
  require "$CUR_R3" 'Merge each scenario (ADD/MODIFY/REMOVE) into the matching `spdd/specs/` domain file, reading the existing spec first and merging rather than overwriting it.' || ok=1
  require "$CUR_R3" 'one spec file per domain, at `spdd/specs/<domain>.md`, with kebab-case domain names' || ok=1
  require "$CUR_R3" 'When the domain is new (no `spdd/specs/<domain>.md` exists), the verifier creates the file' || ok=1
  require "$CUR_R3" 'a `# Domain: <domain>` header plus the merged scenarios, under the same merge rules' || ok=1

  # The HEAD-relative window assertions -- HEAD's roles-03 pinning the
  # pre-change merge-bullet sentence (the Given), test_roles_03 differing
  # from HEAD's (equality reading "the pin was not re-scoped"), and
  # roles-01/02/04/05 byte-identical to HEAD -- gated on the roles_test.sh
  # re-scope being pending; once HEAD's roles-03 pins the extended bullet
  # (the committed state) they retire vacuously with one loud note. The
  # content pins above and the suite-green run below are the durable
  # HEAD-independent coverage.
  if ! roles_change_pending; then
    echo "  note: the roles_test.sh roles-03 re-scope is committed vs HEAD (HEAD's roles-03 already pins the extended bullet); the re-scope window assertions are vacuously retired, the content pins and the suite-green run stay enforced"
  else
    # Given: the pre-change roles-03 pinned the merge-bullet sentence
    # verbatim.
    grep -qF 'Merge each scenario (ADD/MODIFY/REMOVE) into the matching `spdd/specs/` domain file, reading the existing spec first and merging rather than overwriting it.' "$HEAD_ROLES_03" \
      || { echo "  HEAD's roles-03 does not pin the pre-change merge-bullet sentence verbatim"; ok=1; }

    # The re-scope inversion: the working test_roles_03 differs from HEAD's.
    cmp -s "$CUR_R3" "$HEAD_ROLES_03" \
      && { echo "  test_roles_03 is unmodified -- the pin was not re-scoped"; ok=1; }

    # roles-01, roles-02, roles-04, and roles-05's assertions keep passing
    # unmodified: their functions are byte-identical to HEAD's.
    for fn in test_roles_01 test_roles_02 test_roles_04 test_roles_05; do
      a=$(mktemp); b=$(mktemp)
      extract_fn "$ROLES_SUITE" "$fn" "$a"
      extract_fn "$HEAD_ROLES" "$fn" "$b"
      [ -s "$a" ] || { echo "  $fn not found in the working roles_test.sh"; ok=1; }
      cmp -s "$a" "$b" || { echo "  $fn differs from HEAD (must stay unmodified)"; ok=1; }
      rm -f "$a" "$b"
    done
  fi
  rm -f "$CUR_R3"

  # The rest of the suite stays green: all five roles tests pass. Absolute.
  ROLES_OUT=$(mktemp)
  sh "$ROLES_SUITE" > "$ROLES_OUT" 2>&1 \
    || { echo "  roles_test.sh does not pass after the rewordings:"; tail -5 "$ROLES_OUT"; ok=1; }
  n=$(grep -c '^PASS: roles-' "$ROLES_OUT")
  [ "$n" -eq 5 ] || { echo "  roles_test.sh reports $n passing roles tests, expected 5"; ok=1; }
  rm -f "$ROLES_OUT"
  return $ok
}

# ---- run everything ----------------------------------------------------------

run_test "rolechecks-01: the coder's pre-planning bullet states the id search as a literal grep of the id in the project's test files, keeps passing-or-skipped done-not-redo meaning, and the criterion is observable in tests/" test_rolechecks_01
run_test "rolechecks-02: the coder's Plan briefly bullet fixes the threshold at more than 8 implementation steps or more than 1 shared contract needing change, drops the is-long wording, and leaves the BLOCKED: stub rule byte-identical" test_rolechecks_02
run_test "rolechecks-03: the verifier's Input Rule defines code present mechanically as the shared literal grep finding the declared ids or the result receipt existing, keeps both routing forms, and reads existence only, never the receipt's grammar" test_rolechecks_03
run_test "rolechecks-04: the verifier's merge bullet states one kebab-case spec file per domain resolved from the change README's per-sub-spec section, creates a new domain's file with the Domain header under the same merge rules, and keeps HEAD's merge sentence verbatim" test_rolechecks_04
run_test "rolechecks-05: roles-03's exact-string pin is re-scoped to the extended merge bullet while roles-01, roles-02, roles-04, and roles-05 stay byte-identical to HEAD and the whole roles suite passes" test_rolechecks_05

echo ""
echo "$pass_count passed, $fail_count failed"
[ "$fail_count" -eq 0 ]
