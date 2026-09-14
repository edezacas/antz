#!/usr/bin/env bash
# tests/roles_test.sh -- the role prompts' documented Working-Root
# triplication (change terminology/02-terminology, scenario terminology-03;
# kept alive through change optimize-test-suite, sub-spec 09).
#
# Sub-spec 09's revised scope retired every other assertion this suite
# carried: the prompt-section prose pins (roles-01..04, verifier-01,
# terminology-01's docs halves, testsuite-06/08) break the four permanent
# laws, and the self-shape meta-checks (rolesdecouple-01..04) were deleted
# with the suite decoupling they certified. What survives is the exact
# behavior the repo's Gotchas document as the reason the Working-Root
# section is triplicated across the three role prompts: drift between the
# three copies must fail loudly. That byte-identity check is the SOLE
# declared exception to hygiene law 4, delimited below by the
# hygiene:working-root-exception markers tests/hygiene_test.sh honors for
# this file only; see spdd/changes/optimize-test-suite/09-hygiene.feature.
#
# Run directly:  sh tests/roles_test.sh

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
# shellcheck source=tests/harness.sh
. "$SCRIPT_DIR/tests/harness.sh"

# hygiene:working-root-exception-begin -- the triplicated section extracted
# from each role prompt once; the three extracts must be byte-identical, and
# the orchestrator prompt must carry no fourth copy. The extraction and the
# compares read prompt prose, which the sole exception (sub-spec 09,
# hygiene-03) declares here and nowhere else.
SPECIFIER_PROMPT="$SCRIPT_DIR/agents/prompts/specifier.prompt"
CODER_PROMPT="$SCRIPT_DIR/agents/prompts/coder.prompt"
VERIFIER_PROMPT="$SCRIPT_DIR/agents/prompts/verifier.prompt"
ORCHESTRATOR_PROMPT="$SCRIPT_DIR/agents/prompts/orchestrator.prompt"
WR_SPECIFIER=$(new_tmp_dir)/wr_spec
WR_CODER=$(new_tmp_dir)/wr_coder
WR_VERIFIER=$(new_tmp_dir)/wr_verifier
test_working_root_triplication() {
  local ok=0
  extract_section "$SPECIFIER_PROMPT" "Working Root" "$WR_SPECIFIER"
  extract_section "$CODER_PROMPT" "Working Root" "$WR_CODER"
  extract_section "$VERIFIER_PROMPT" "Working Root" "$WR_VERIFIER"
  [ -s "$WR_SPECIFIER" ] && [ -s "$WR_CODER" ] && [ -s "$WR_VERIFIER" ] \
    || { echo "  a role prompt has no ## Working Root section (empty extract)"; ok=1; }
  cmp -s "$WR_SPECIFIER" "$WR_CODER" \
    || { echo "  the specifier's and coder's ## Working Root sections differ"; diff "$WR_SPECIFIER" "$WR_CODER" | head -4; ok=1; }
  cmp -s "$WR_SPECIFIER" "$WR_VERIFIER" \
    || { echo "  the specifier's and verifier's ## Working Root sections differ"; diff "$WR_SPECIFIER" "$WR_VERIFIER" | head -4; ok=1; }
  # each copy is the documented triplicated section, not an empty heading
  require "$WR_SPECIFIER" '**Working Root**' || ok=1
  require "$WR_CODER" '**Working Root**' || ok=1
  require "$WR_VERIFIER" '**Working Root**' || ok=1
  require "$WR_SPECIFIER" "cd '<working-root>'" || ok=1
  # the triplication is exactly three: the orchestrator prompt has no
  # "## Working Root" section of its own.
  local n
  n=$(grep -c '^## Working Root$' "$ORCHESTRATOR_PROMPT")
  [ "$n" -eq 0 ] \
    || { echo "  orchestrator.prompt carries a ## Working Root section ($n), expected none"; ok=1; }
  return $ok
}
# hygiene:working-root-exception-end

run_test "terminology-03: the three role prompts' Working Root sections are byte-identical to each other and the orchestrator prompt carries no copy" test_working_root_triplication

finish_suite
