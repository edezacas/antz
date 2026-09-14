#!/usr/bin/env bash
# tests/runner_test.sh -- unit tests for the documented runner
# tests/run_all.sh, covering every scenario of
# spdd/changes/optimize-test-suite/02-runner.feature (runner-01..05).
#
# Seam under test: the runner's documented process boundary -- invoked as
# `sh tests/run_all.sh` against the suite directory named by ANTZ_TESTS_DIR
# (the runner's own documented override for hermetic testing; the default is
# the repo's tests/), observing stdout, the exit status, and the fixture
# suites' own side effects. The fixture suites are synthetic scripts carrying
# the harness output contract, so the runner's behavior is verified
# deterministically without executing (or coupling to) the real suite area.
# The real-tree full-run properties (the 120s wall-clock budget over the
# actual tests/, the committed-and-archived-era green verdict) belong to the
# verifier's e2e-qa suite, not to unit-level TDD.
#
# Everything here runs in temp space (new_tmp_dir from tests/harness.sh);
# nothing writes into the repo working tree or the real user config.
#
# Run directly:  ./tests/runner_test.sh

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

# shellcheck source=tests/harness.sh
. "$SCRIPT_DIR/tests/harness.sh"

RUNNER="$SCRIPT_DIR/tests/run_all.sh"

# ---- fixture builders ---------------------------------------------------------
# A fixture suite announces each execution by appending its own filename to
# $RUNNER_MARKER (the runner passes its environment through to suites), so
# "ran exactly once, in order" is observed, not inferred from output shape.

fx_suite() {
  # $1=fixture dir, $2=suite filename, $3=scenario-id prefix, $4=pass_n,
  # $5=fail_n, $6=skip_n, $7=exit rc, $8=1 prints the contract final line
  # (pass=/fail=/skip=), 0 omits it (crash-shaped suite).
  # fname, not name: the harness run_test global "name" must survive
  # registration output intact.
  dir="$1"; fname="$2"; pfx="$3"; p="$4"; f="$5"; s="$6"; rc="$7"; contract="${8:-1}"
  {
    echo '#!/bin/sh'
    printf 'printf "%%s\\n" "%s" >> "${RUNNER_MARKER:-/dev/null}"\n' "$fname"
    i=1
    while [ "$i" -le "$p" ]; do
      printf 'echo "PASS: %s-%02d: green fixture test"\n' "$pfx" "$i"
      i=$((i + 1))
    done
    i=1
    while [ "$i" -le "$f" ]; do
      printf 'echo "FAIL: %s-%02d: failing fixture test"\n' "$pfx" "$((p + i))"
      i=$((i + 1))
    done
    i=1
    while [ "$i" -le "$s" ]; do
      printf 'echo "SKIP: %s-%02d: skipped fixture test (fixture: parked)"\n' \
        "$pfx" "$((p + f + i))"
      i=$((i + 1))
    done
    [ "$contract" = "1" ] && printf 'echo "pass=%s fail=%s skip=%s"\n' "$p" "$f" "$s"
    printf 'exit %s\n' "$rc"
  } > "$dir/$fname"
}

fx_run_runner() {
  # $1 = stdout capture file; runs the runner over $fx_dir; real rc to "$1.rc".
  out="$1"
  ( cd "$SCRIPT_DIR" && env ANTZ_TESTS_DIR="$fx_dir" RUNNER_MARKER="$fx_marker" \
      sh "$RUNNER" ) > "$out" 2>&1
  printf '%s' "$?" > "$out.rc"
}

fx_rc() { cat "$1.rc"; }

# ---- runner-01 ----------------------------------------------------------------

test_runner_01_every_suite_exactly_once_sorted_order() {
  fx_dir=$(new_tmp_dir); fx_marker="$fx_dir/marker"
  # Created out of sort order on purpose; plus a helper and a text file that
  # match no suite glob and must never run (mirrors tests/bash32-sh.sh).
  fx_suite "$fx_dir" c_test.sh cc 1 0 0 0
  fx_suite "$fx_dir" a_test.sh aa 1 0 0 0
  fx_suite "$fx_dir" b_test.sh bb 1 0 0 0
  printf '#!/bin/sh\nexit 3\n' > "$fx_dir/bash32-sh.sh"
  printf 'not a suite\n' > "$fx_dir/notes.txt"

  fx_run_runner "$fx_dir/run1"
  [ "$(fx_rc "$fx_dir/run1")" = "0" ] || { echo "  runner exit: $(fx_rc "$fx_dir/run1")"; return 1; }
  printf '%s\n' a_test.sh b_test.sh c_test.sh > "$fx_dir/want"
  cmp -s "$fx_dir/want" "$fx_marker" \
    || { echo "  suites did not run exactly once each, in sorted order:"; cat "$fx_marker"; return 1; }
  # The helper never ran: it would have exited 3 and appeared nowhere.
  grep -qF 'bash32-sh.sh' "$fx_marker" && { echo "  helper ran as a suite"; return 1; }
  return 0
}

test_runner_01_discovery_is_mechanical_no_runner_edit() {
  # The SAME runner file, unchanged between two runs, picks up a suite added
  # and a suite removed from the directory -- proof discovery is the glob.
  runner_cksum=$(cksum < "$RUNNER")
  fx_dir=$(new_tmp_dir); fx_marker="$fx_dir/marker"
  fx_suite "$fx_dir" z_test.sh zz 1 0 0 0
  fx_suite "$fx_dir" m_test.sh mm 1 0 0 0
  fx_run_runner "$fx_dir/run1"
  printf '%s\n' m_test.sh z_test.sh > "$fx_dir/want1"
  cmp -s "$fx_dir/want1" "$fx_marker" || { echo "  first run missed a suite"; return 1; }

  fx_dir=$(new_tmp_dir); fx_marker="$fx_dir/marker"
  fx_suite "$fx_dir" z_test.sh zz 1 0 0 0
  fx_suite "$fx_dir" new_test.sh nn 1 0 0 0
  fx_run_runner "$fx_dir/run2"
  printf '%s\n' new_test.sh z_test.sh > "$fx_dir/want2"
  cmp -s "$fx_dir/want2" "$fx_marker" || { echo "  added/removed suite not reflected"; return 1; }
  [ "$runner_cksum" = "$(cksum < "$RUNNER")" ] || { echo "  runner file changed mid-test"; return 1; }
  # And the second run's summary counts the new set, mechanically.
  grep -qx 'suites=2 passed=2 failed=0' <(sed 's/ tests_failed=.*//' "$fx_dir/run2") \
    || { echo "  summary did not see the new suite set:"; cat "$fx_dir/run2"; return 1; }
  return 0
}

test_runner_01_sorted_order_is_mechanical_filename_byte_order() {
  # "Sorted filename order" must not depend on the ambient locale's
  # collation: under an en_US.UTF-8 shell, a bare glob puts ab_test.sh
  # before a_test.sh (punctuation-ignoring collation); filename order is
  # the byte order, so the runner must run a_test.sh first.
  fx_dir=$(new_tmp_dir); fx_marker="$fx_dir/marker"
  fx_suite "$fx_dir" ab_test.sh ab 1 0 0 0
  fx_suite "$fx_dir" a_test.sh a 1 0 0 0
  fx_run_runner "$fx_dir/run1"
  printf '%s\n' a_test.sh ab_test.sh > "$fx_dir/want"
  cmp -s "$fx_dir/want" "$fx_marker" \
    || { echo "  discovery order followed locale collation, not filename byte order:"; cat "$fx_marker"; return 1; }
  return 0
}

# ---- runner-02 ----------------------------------------------------------------

test_runner_02_all_green_status_lines_summary_exit_zero() {
  fx_dir=$(new_tmp_dir); fx_marker="$fx_dir/marker"
  fx_suite "$fx_dir" a_test.sh aa 2 0 1 0
  fx_suite "$fx_dir" b_test.sh bb 1 0 0 0

  fx_run_runner "$fx_dir/run1"
  [ "$(fx_rc "$fx_dir/run1")" = "0" ] \
    || { echo "  all-green pass must exit 0, got $(fx_rc "$fx_dir/run1")"; return 1; }
  # One status line per suite, naming the suite file with its counts...
  grep -qxF "$fx_dir/a_test.sh pass=2 fail=0 skip=1 -> ok" "$fx_dir/run1" \
    || { echo "  missing a_test.sh status line with counts:"; cat "$fx_dir/run1"; return 1; }
  grep -qxF "$fx_dir/b_test.sh pass=1 fail=0 skip=0 -> ok" "$fx_dir/run1" \
    || { echo "  missing b_test.sh status line with counts:"; cat "$fx_dir/run1"; return 1; }
  [ "$(grep -c ' pass=[0-9]* fail=[0-9]* skip=[0-9]* -> ' "$fx_dir/run1")" -eq 2 ] \
    || { echo "  not exactly one status line per suite:"; cat "$fx_dir/run1"; return 1; }
  # ...and the final line is the aggregate summary.
  tail -n 1 "$fx_dir/run1" | grep -qE '^suites=2 passed=2 failed=0 tests_failed=0 elapsed=[0-9]+s$' \
    || { echo "  final line is not the aggregate summary:"; tail -n 1 "$fx_dir/run1"; return 1; }
  return 0
}

test_runner_02_exit_nonzero_exactly_when_a_suite_exits_nonzero() {
  fx_dir=$(new_tmp_dir); fx_marker="$fx_dir/marker"
  fx_suite "$fx_dir" a_test.sh aa 1 0 0 0    # green
  fx_suite "$fx_dir" b_test.sh bb 1 1 0 1    # registered failure, exit 1
  fx_suite "$fx_dir" c_test.sh cc 1 0 0 9 0  # crash: exits 9, no contract line
  fx_suite "$fx_dir" d_test.sh dd 0 0 0 5    # exits 5 with zero failing tests

  fx_run_runner "$fx_dir/run1"
  [ "$(fx_rc "$fx_dir/run1")" != "0" ] || { echo "  runner exited 0 despite non-zero suites"; return 1; }
  # The crash-shaped suite still gets counts (tallied from its PASS/FAIL/SKIP
  # lines when no contract summary line is present), so nothing is silent.
  grep -qxF "$fx_dir/c_test.sh pass=1 fail=0 skip=0 -> FAILED" "$fx_dir/run1" \
    || { echo "  crashed suite not counted/statused:"; cat "$fx_dir/run1"; return 1; }
  grep -qxF "$fx_dir/b_test.sh pass=1 fail=1 skip=0 -> FAILED" "$fx_dir/run1" \
    || { echo "  failing suite not statused:"; cat "$fx_dir/run1"; return 1; }
  grep -qxF "$fx_dir/d_test.sh pass=0 fail=0 skip=0 -> FAILED" "$fx_dir/run1" \
    || { echo "  non-zero-exit-zero-failure suite not statused:"; cat "$fx_dir/run1"; return 1; }
  tail -n 1 "$fx_dir/run1" | grep -qE '^suites=4 passed=1 failed=3 tests_failed=1 elapsed=[0-9]+s$' \
    || { echo "  aggregate summary wrong:"; tail -n 1 "$fx_dir/run1"; return 1; }
  # All four suites still ran exactly once each (isolation is runner-03's
  # scenario; here it guards the exit-code bookkeeping from short-circuiting).
  [ "$(wc -l < "$fx_marker" | tr -d ' ')" -eq 4 ] \
    || { echo "  marker should carry four runs:"; cat "$fx_marker"; return 1; }
  return 0
}

# ---- runner-03 ----------------------------------------------------------------

test_runner_03_failing_suite_isolated_named_with_ids_run_survives() {
  # Middle failure and leading failure, both shapes: no other suite is lost.
  fx_dir=$(new_tmp_dir); fx_marker="$fx_dir/marker"
  fx_suite "$fx_dir" a_test.sh aa 2 0 1 0
  fx_suite "$fx_dir" m_test.sh mm 1 2 0 1    # failing registered tests: mm-02 mm-03
  fx_suite "$fx_dir" z_test.sh zz 1 0 0 0
  fx_run_runner "$fx_dir/run1"
  [ "$(fx_rc "$fx_dir/run1")" != "0" ] || { echo "  run with a failing suite exited 0"; return 1; }
  printf '%s\n' a_test.sh m_test.sh z_test.sh > "$fx_dir/want"
  cmp -s "$fx_dir/want" "$fx_marker" \
    || { echo "  other suites did not all run to completion:"; cat "$fx_marker"; return 1; }
  grep -qxF "FAILED $fx_dir/m_test.sh: mm-02 mm-03" "$fx_dir/run1" \
    || { echo "  aggregate summary does not name the failing suite with its scenario ids:"; cat "$fx_dir/run1"; return 1; }
  tail -n 1 "$fx_dir/run1" | grep -qE '^suites=3 passed=2 failed=1 tests_failed=2 elapsed=[0-9]+s$' \
    || { echo "  final aggregate line wrong:"; tail -n 1 "$fx_dir/run1"; return 1; }
  # The failing suite's captured output is shown, not swallowed.
  grep -qF 'FAIL: mm-02: failing fixture test' "$fx_dir/run1" \
    || { echo "  failing suite output not surfaced by the runner:"; cat "$fx_dir/run1"; return 1; }

  # Failure first in sorted order: the later suites still run.
  fx_dir=$(new_tmp_dir); fx_marker="$fx_dir/marker"
  fx_suite "$fx_dir" aaa_test.sh aa 0 1 0 1
  fx_suite "$fx_dir" zzz_test.sh zz 1 0 0 0
  fx_run_runner "$fx_dir/run2"
  [ "$(fx_rc "$fx_dir/run2")" != "0" ] || { echo "  leading failure exited 0"; return 1; }
  printf '%s\n' aaa_test.sh zzz_test.sh > "$fx_dir/want"
  cmp -s "$fx_dir/want" "$fx_marker" \
    || { echo "  a leading failure aborted the run:"; cat "$fx_marker"; return 1; }
  grep -qxF "$fx_dir/zzz_test.sh pass=1 fail=0 skip=0 -> ok" "$fx_dir/run2" \
    || { echo "  post-failure suite lost its ok status line"; return 1; }
  return 0
}

test_runner_03_failing_scenario_ids_taken_from_test_name_id_prefix() {
  # Scenario ids are the name's first token cut at ':' or space -- the two
  # real name shapes in this repo ("roles-01: ..." and 'quoting-03 (Says
  # "hi"): ...') must both yield the bare id.
  fx_dir=$(new_tmp_dir); fx_marker="$fx_dir/marker"
  cat > "$fx_dir/q_test.sh" <<'FXEOF'
#!/bin/sh
echo "PASS: q-01: green one"
echo "FAIL: q-02: colon-shaped name"
echo 'FAIL: q-03 (paren variant): space-shaped name'
echo "pass=1 fail=2 skip=0"
exit 1
FXEOF
  fx_run_runner "$fx_dir/run1"
  grep -qxF "FAILED $fx_dir/q_test.sh: q-02 q-03" "$fx_dir/run1" \
    || { echo "  failing scenario ids not extracted from both name shapes:"; cat "$fx_dir/run1"; return 1; }
  return 0
}

# ---- runner-04 ----------------------------------------------------------------

test_runner_04_elapsed_seconds_printed_and_under_budget() {
  # The unit-level half of runner-04: the summary's elapsed is a MEASURED
  # value (a 2s fixture suite must show through) and a full pass prints it
  # under the 120s budget. The real-tree budget claim -- ~393s today, bought
  # by the render-once cache (harness-03, green now), the removed nested
  # suite execution (sub-specs 03/04) and the dropped frozen-history suites
  # (sub-spec 05) -- is the committed-and-archived end state the verifier's
  # e2e-qa-02 measures end to end; running all 38 real suites inside a unit
  # test would BECOME the budget problem instead of checking it.
  fx_dir=$(new_tmp_dir); fx_marker="$fx_dir/marker"
  fx_suite "$fx_dir" a_test.sh aa 1 0 0 0
  {
    echo '#!/bin/sh'
    echo 'sleep 2'
    echo 'echo "PASS: s-01: slow but green"'
    echo 'echo "pass=1 fail=0 skip=0"'
  } > "$fx_dir/s_test.sh"
  fx_suite "$fx_dir" z_test.sh zz 1 0 0 0
  fx_run_runner "$fx_dir/run1"
  line=$(tail -n 1 "$fx_dir/run1")
  printf '%s' "$line" | grep -qE '^suites=3 passed=3 failed=0 tests_failed=0 elapsed=[0-9]+s$' \
    || { echo "  summary does not end with elapsed seconds:"; printf '%s\n' "$line"; return 1; }
  el=$(printf '%s' "$line" | sed 's/.*elapsed=//; s/s$//')
  [ "$el" -ge 2 ] || { echo "  elapsed=$el does not reflect the 2s suite (not measured)"; return 1; }
  [ "$el" -lt 120 ] || { echo "  elapsed=$el is not under the 120s budget"; return 1; }
  return 0
}

# ---- runner-05 ----------------------------------------------------------------

# The documented facts: each must appear in the tests/run_all.sh header AND
# in the -h/--help usage output.
RUNNER_DOC_FACTS='sh tests/run_all.sh
tests/*_test.sh
exactly once
sorted filename order
one status line per suite
suites= passed= failed= tests_failed= elapsed=
exits 0 exactly when every suite exits 0
-h, --help'

fx_doc_facts_in() {
  # $1 = file holding text; every documented fact appears in it.
  file="$1"
  while IFS= read -r fact; do
    grep -qF -- "$fact" "$file" || { echo "  documented fact missing: $fact"; return 1; }
  done <<< "$RUNNER_DOC_FACTS"
  return 0
}

test_runner_05_help_documents_the_runner_and_runs_no_suite() {
  fx_dir=$(new_tmp_dir); fx_marker="$fx_dir/marker"
  fx_suite "$fx_dir" a_test.sh aa 1 0 0 0
  ( cd "$SCRIPT_DIR" && env ANTZ_TESTS_DIR="$fx_dir" RUNNER_MARKER="$fx_marker" \
      sh "$RUNNER" -h ) > "$fx_dir/h1" 2>&1
  rc1=$?
  ( cd "$SCRIPT_DIR" && env ANTZ_TESTS_DIR="$fx_dir" RUNNER_MARKER="$fx_marker" \
      sh "$RUNNER" --help ) > "$fx_dir/h2" 2>&1
  rc2=$?
  [ "$rc1" = "0" ] && [ "$rc2" = "0" ] \
    || { echo "  -h/--help must exit 0 (got $rc1/$rc2)"; return 1; }
  fx_doc_facts_in "$fx_dir/h1" || return 1
  fx_doc_facts_in "$fx_dir/h2" || return 1
  if [ -e "$fx_marker" ] && [ -s "$fx_marker" ]; then
    echo "  help run executed suites:"; cat "$fx_marker"; return 1
  fi
  return 0
}

test_runner_05_header_documents_and_runner_itself_is_no_suite() {
  # The header at the top of tests/run_all.sh carries the same documented
  # facts a reader (or the verifier's docs check) needs.
  head -n 40 "$RUNNER" > "$HARNESS_RUN_TMP/runner-head"
  fx_doc_facts_in "$HARNESS_RUN_TMP/runner-head" || return 1
  # Not a suite: no discovery glob can ever name it.
  case "$RUNNER" in
    *_test.sh) echo "  run_all.sh matches the suite name pattern"; return 1 ;;
  esac
  for t in "$SCRIPT_DIR"/tests/*_test.sh; do
    [ "${t##*/}" = "run_all.sh" ] && { echo "  runner appears under the real suite glob"; return 1; }
  done
  # Defines no harness helper (it consumes suites' output; it is not a suite).
  if grep -Eq '^[[:space:]]*(run_test|skip_test|finish_suite|require|refuse|new_tmp_dir|cleanup|stage_checkout|install_at|install_xdg|render_tree|extract_section|extract_bullet|extract_bullet_line|extract_line|extract_fn)[[:space:]]*\(\)' "$RUNNER"; then
    echo "  runner defines a harness helper"
    return 1
  fi
  return 0
}

# ---- run all -----------------------------------------------------------------

run_test "runner-01: every tests/*_test.sh suite runs exactly once under the runner, in sorted filename order, and no helper or non-suite file is discovered" test_runner_01_every_suite_exactly_once_sorted_order
run_test "runner-01: suite discovery is mechanical (the tests/*_test.sh glob) -- a suite added to or removed from the tests dir needs no runner edit" test_runner_01_discovery_is_mechanical_no_runner_edit
run_test "runner-01: sorted filename order is mechanical (byte order), not the ambient locale's collation -- a_test.sh runs before ab_test.sh under any locale" test_runner_01_sorted_order_is_mechanical_filename_byte_order

run_test "runner-02: an all-green pass prints one status line per suite naming the file with its pass/fail/skip counts, ends with the aggregate summary line, and exits 0" test_runner_02_all_green_status_lines_summary_exit_zero
run_test "runner-02: the runner exits non-zero exactly when a suite exits non-zero -- failing, crashed (counts tallied from PASS/FAIL/SKIP lines), and zero-failure non-zero-exit suites all marked FAILED" test_runner_02_exit_nonzero_exactly_when_a_suite_exits_nonzero

run_test "runner-03: one failing suite is isolated and named with its failing scenario ids, every other suite still runs to completion, and the runner exits non-zero" test_runner_03_failing_suite_isolated_named_with_ids_run_survives
run_test "runner-03: the failing scenario ids are extracted from the FAIL lines' name prefixes, both the colon-shaped and the space-shaped test-name forms" test_runner_03_failing_scenario_ids_taken_from_test_name_id_prefix

run_test "runner-04: the aggregate summary ends with a measured elapsed-seconds value and a full pass completes under the 120s budget (real-tree end-to-end budget is e2e-qa-02's, verifier-owned)" test_runner_04_elapsed_seconds_printed_and_under_budget

run_test "runner-05: -h and --help print usage documenting the one-command invocation, what it runs, the summary line, and the exit contract -- without executing any suite" test_runner_05_help_documents_the_runner_and_runs_no_suite
run_test "runner-05: the tests/run_all.sh header documents the same; the runner is not a suite -- matches no tests/*_test.sh glob and defines no harness helper" test_runner_05_header_documents_and_runner_itself_is_no_suite

finish_suite
