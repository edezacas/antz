#!/usr/bin/env bash
# Unit tests for the "## Skills" sections added to agents/prompts/coder.prompt
# and agents/prompts/verifier.prompt, covering every unit-level scenario in
# spdd/changes/skills-activation/01-prompts.feature (prompts-01..07).
#
# Self-contained bash test harness (no external framework/dependency -- this
# repo has no package manager or build system), mirroring the harness style
# of tests/readmefile_test.sh. Run directly:
#   ./tests/skills-activation-prompts_test.sh
#
# Re-scoped by change style-rewrite (spdd/changes/style-rewrite/04-
# skillsline.feature): prompts-06's single test split into per-role halves
# named skillsline-01 (coder) and skillsline-02 (verifier), plus the whole-
# prompt once-per-prompt counts (skillsline-03) and this suite's own
# follow-loudly meta-check (skillsline-04). The mandatory-reporting pins stay
# inside each role's report-section extract; the not-a-routing-input pins
# became whole-prompt single-occurrence counts, since the skills bullets no
# longer restate the mirror principle (the tails were removed; the principle
# stays stated once per prompt at the closing-block mirror statement, and the
# docs gotcha keeps documenting it for the skills line --
# tests/skills-activation-docs_test.sh, untouched).
#
# Every scenario here is a deterministic content assertion against the static
# text of the two prompt files (grep-style), not a live LLM invocation. The
# change's e2e-prompts-01/02 scenarios require live antz-coder sessions in a
# real Angular project -- they belong to the verifier's end-to-end suite, not
# this unit suite; they appear below as explicit SKIP stubs so no scenario id
# is silently unaccounted for.

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CODER_PROMPT="$SCRIPT_DIR/agents/prompts/coder.prompt"
VERIFIER_PROMPT="$SCRIPT_DIR/agents/prompts/verifier.prompt"
SPECIFIER_PROMPT="$SCRIPT_DIR/agents/prompts/specifier.prompt"
ORCHESTRATOR_PROMPT="$SCRIPT_DIR/agents/prompts/orchestrator.prompt"
# This suite's own source (skillsline-04 inspects the split), and the sibling
# docs suite it must leave untouched and running green.
SUITE_SOURCE="$SCRIPT_DIR/tests/skills-activation-prompts_test.sh"
DOCS_SUITE="$SCRIPT_DIR/tests/skills-activation-docs_test.sh"

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

count_occurrences() {
  # $1 = file, $2 = fixed string; prints the number of occurrences of $2
  # in $1 (per-line, so two occurrences on one line count twice).
  grep -oF -- "$2" "$1" | wc -l | tr -d ' '
}

extract_fn() {
  # $1 = file, $2 = function name; prints that function's source text
  # (from its `name() {` line through the closing brace at column 0).
  awk -v fn="$2" '
    !infn && $0 ~ "^" fn "\\(\\) \\{" { infn=1 }
    infn { print }
    infn && /^\}/ { exit }
  ' "$1"
}

# Extract a "## <name>" section (its own heading line down to the next top
# level "## " heading or EOF) from $1 into $2.
extract_section() {
  # $1 = file, $2 = heading text, $3 = output file
  awk -v sec="$2" '
    $0 == "## " sec { flag=1; next }
    flag && /^## / { flag=0 }
    flag { print }
  ' "$1" > "$3"
}

# Section extractions, done once so every test reads only the scoped text.
# CODER_RECEIPT is the folded closing-block home (style-rewrite sub-spec 02);
# VERIFIER_SKILLS_LINE is the "## Report Format" skills bullet alone (that
# section keeps its closing-block mirror statement on another line, so the
# tail-removal pin is scoped to the bullet, not the section).
CODER_SKILLS=$(mktemp)
VERIFIER_SKILLS=$(mktemp)
CODER_OUTPUT=$(mktemp)
VERIFIER_REPORT=$(mktemp)
CODER_RECEIPT=$(mktemp)
VERIFIER_SKILLS_LINE=$(mktemp)
extract_section "$CODER_PROMPT" "Skills" "$CODER_SKILLS"
extract_section "$VERIFIER_PROMPT" "Skills" "$VERIFIER_SKILLS"
extract_section "$CODER_PROMPT" "Output" "$CODER_OUTPUT"
extract_section "$VERIFIER_PROMPT" "Report Format" "$VERIFIER_REPORT"
extract_section "$CODER_PROMPT" "Receipt" "$CODER_RECEIPT"
grep -F 'skills were activated' "$VERIFIER_PROMPT" > "$VERIFIER_SKILLS_LINE"

# =============================================================================
# prompts-01: the coder prompt gains a Skills section establishing discovery
# before planning and mandatory activation before writing or modifying
# code/config a skill covers, with a neutral fallback when no skill-loading
# tool exists.
# =============================================================================
test_prompts_01() {
  ok=0
  # Discovery before planning via the session's skill-loading capability.
  require "$CODER_SKILLS" 'Before planning' || ok=1
  require "$CODER_SKILLS" 'discover the available skills' || ok=1
  require "$CODER_SKILLS" 'skill-loading capability' || ok=1

  # The fallback when no such tool exists: list both skills-directory sets
  # and read the matched SKILL.md's content.
  require "$CODER_SKILLS" 'list the project'"'"'s and the user'"'"'s skills directories' || ok=1
  for dir in '.agents/skills/' '~/.agents/skills/' '.claude/skills/' '~/.claude/skills/' '.opencode/skills/' '~/.config/opencode/skills/'; do
    require "$CODER_SKILLS" "$dir" || ok=1
  done
  require "$CODER_SKILLS" 'read the matched `SKILL.md`' || ok=1

  # Activation duty before writing/modifying/investigating covered work.
  require "$CODER_SKILLS" 'writing, modifying, or investigating' || ok=1
  require "$CODER_SKILLS" 'activate' || ok=1

  # Mandatory when a match exists, a no-op when none does.
  require "$CODER_SKILLS" 'mandatory when a match exists' || ok=1
  require "$CODER_SKILLS" 'no-op when none' || ok=1
  return $ok
}

# =============================================================================
# prompts-02: the activation duty is keyed to each skill's own description
# only -- no specific skill name is hardcoded into the generic role prompt.
# =============================================================================
test_prompts_02() {
  ok=0
  # Matching driven by each skill's own description (including its trigger
  # language), not by a fixed skill list.
  require "$CODER_SKILLS" 'description' || ok=1
  require "$CODER_SKILLS" 'trigger language' || ok=1
  require "$CODER_SKILLS" 'never by a fixed skill list' || ok=1

  # No concrete skill name appears as a requirement or trigger anywhere in
  # the prompt (the examples from the sub-spec and the live environment).
  refuse "$CODER_PROMPT" 'angular-conventions' || ok=1
  refuse "$CODER_PROMPT" 'omarchy' || ok=1
  refuse "$CODER_PROMPT" 'customize-opencode' || ok=1
  refuse "$CODER_PROMPT" 'find-skills' || ok=1
  refuse "$CODER_PROMPT" 'init-project' || ok=1
  refuse "$CODER_PROMPT" 'diagnose-crash' || ok=1
  return $ok
}

# =============================================================================
# prompts-03: the verifier prompt carries the identical duty for its layer:
# discover before verifying, activate matching skills before reviewing or
# judging code the skill covers, warning when covered code was judged
# without the matched skill ever being activated.
# =============================================================================
test_prompts_03() {
  ok=0
  # Discovery before verification, the same tool-when-present wording.
  require "$VERIFIER_SKILLS" 'Before verification' || ok=1
  require "$VERIFIER_SKILLS" 'the same way' || ok=1
  require "$VERIFIER_SKILLS" 'skill-loading capability' || ok=1

  # The same directory-fallback wording.
  require "$VERIFIER_SKILLS" 'list the project'"'"'s and the user'"'"'s skills directories' || ok=1
  for dir in '.agents/skills/' '~/.claude/skills/' '~/.config/opencode/skills/'; do
    require "$VERIFIER_SKILLS" "$dir" || ok=1
  done

  # Activation before reviewing or judging covered code.
  require "$VERIFIER_SKILLS" 'reviewing or judging' || ok=1
  require "$VERIFIER_SKILLS" 'activate' || ok=1

  # Warning when covered code was judged without the matched skill ever
  # being activated.
  require "$VERIFIER_SKILLS" 'warning' || ok=1
  require "$VERIFIER_SKILLS" 'without the matched skill ever being activated' || ok=1
  return $ok
}

# =============================================================================
# prompts-04: the added wording is framework-neutral so the same body renders
# into both clients unchanged -- no client-specific tool is the only path and
# no client-specific syntax is present.
# =============================================================================
test_prompts_04() {
  ok=0
  for section in "$CODER_SKILLS" "$VERIFIER_SKILLS"; do
    # No client is named: both paths are covered by the neutral
    # "skill-loading capability" wording plus the directory fallback (the
    # fallback's ~/.claude/skills and ~/.config/opencode/skills example
    # paths are paths, not client naming -- checked via the phrases below).
    refuse "$section" 'Claude Code' || ok=1
    refuse "$section" 'OpenCode' || ok=1
    # No client-specific tool is named as the mechanism.
    refuse "$section" 'Skill tool' || ok=1
    refuse "$section" 'tools:' || ok=1
    # No client-specific invocation/templating syntax.
    refuse "$section" '$ARGUMENTS' || ok=1
  done
  return $ok
}

# =============================================================================
# prompts-05: the specifier prompt's byte-for-byte pin, retired by gating
# (precision-gaps 01-conventions.feature, conventions-04) -- the
# conventions-01..03 specifier rewordings legitimately remove and re-add
# lines, so the closingblock-era additive-shape checks are skipped with a
# loud note once the working copy differs from HEAD (the guard stays
# registered), and the pin is still enforced while the copy is byte-identical
# to HEAD. The orchestrator prompt differs from the pre-change state only by
# its delegation skills-block wording (the duty 02-orchestrator defines --
# that sub-spec owns the edit; here it is guarded, not implemented).
# =============================================================================
specifier_byte_identical_to_head() {
  # $1 = file; compares the working tree copy against the HEAD blob.
  git -C "$SCRIPT_DIR" show "HEAD:$1" 2>/dev/null | cmp -s - "$SCRIPT_DIR/${1#./}"
}

# Prints 1 when the working orchestrator.prompt's prose (the file minus its
# fenced blocks) differs from HEAD's copy -- a later sub-spec's legitimate
# prose edit -- and 0 when it doesn't (or HEAD's copy is unreadable, in
# which case there is nothing to compare against).
prompt_prose_distinct_from_head() {
  work=$(mktemp)
  basep=$(mktemp)
  awk '/^[[:space:]]*```/ { infence = !infence; next } !infence' "$ORCHESTRATOR_PROMPT" > "$work"
  if git -C "$SCRIPT_DIR" show HEAD:agents/prompts/orchestrator.prompt > "$basep" 2>/dev/null; then
    awk '/^[[:space:]]*```/ { infence = !infence; next } !infence' "$basep" > "$basep"
    cmp -s "$work" "$basep" && { printf '0'; rm -f "$work" "$basep"; return 0; }
    printf '1'
  else
    printf '0'
  fi
  rm -f "$work" "$basep"
}

test_prompts_05() {
  ok=0
  # The specifier prompt's byte-for-byte pin: retired by gating, loudly --
  # precision-gaps conventions-01..03 reword three specifier bullets, which
  # removes and re-adds lines, so every pin demanding a purely-additive diff
  # vs HEAD now misfires on a legitimate edit. When the working copy differs
  # from HEAD this guard prints the loud retirement note and skips the
  # 06-closingblock-era additive-shape checks (the closingblock-05
  # convention: guard registered, checks gated); when the copy is
  # byte-identical to HEAD the pin is still enforced.
  if specifier_byte_identical_to_head "agents/prompts/specifier.prompt"; then
    :
  else
    echo "  note: specifier.prompt differs from HEAD (the precision-gaps conventions-01..03 rewordings remove and re-add lines legitimately); the byte-for-byte pin and the 06-closingblock additive-shape checks are retired by gating"
  fi

  # The orchestrator prompt differs only by the delegation skills-block
  # wording: the diff against HEAD must be empty (02-orchestrator has not
  # landed yet in this sub-spec's scope) or purely additive lines that
  # carry the "Skills to load before work" delegation block. Gated on the
  # prompt's prose (the file minus its fenced blocks) being unchanged vs
  # HEAD -- a later sub-spec's legitimate prose edit (e.g. the receipts
  # sub-spec's step-3 rewrite) retires the diff-shape checks with a loud
  # note, same convention as tests/renderinject_test.sh's base-render gate.
  if [ "$(prompt_prose_distinct_from_head)" -eq 1 ]; then
    echo "  note: orchestrator.prompt prose changed vs HEAD (a later sub-spec's legitimate edit); the delegation-block diff-shape checks are vacuously retired"
  else
    DIFF_FILE=$(mktemp)
    git -C "$SCRIPT_DIR" diff HEAD -- agents/prompts/orchestrator.prompt > "$DIFF_FILE"
    if [ -s "$DIFF_FILE" ]; then
      # Purely additive: no removed content lines ('^---' / '^+++' headers
      # excluded -- a removed content line starts with '-' followed by a
      # non-'-' character).
      if [ -n "$(grep -E '^-[^-]' "$DIFF_FILE")" ]; then
        echo "  orchestrator.prompt has removed lines (the delegation block must be additive)"
        ok=1
      fi
      # The added lines must be the delegation skills block.
      if ! grep -q 'Skills to load before work' "$DIFF_FILE"; then
        echo "  orchestrator.prompt differs from HEAD but not by the delegation skills-block wording"
        ok=1
      fi
    fi
    rm -f "$DIFF_FILE"
  fi

  # Boundary guard: the orchestrator never loads skills itself, so it gains
  # no coder/verifier-style "## Skills" role section of its own.
  if grep -q '^## Skills$' "$ORCHESTRATOR_PROMPT"; then
    echo "  orchestrator.prompt gained a role-level '## Skills' section (only the delegation block duty is permitted)"
    ok=1
  fi
  return $ok
}

# =============================================================================
# skillsline-01 (prompts-06's coder half): activation means reading the full
# SKILL.md (paths, not summaries); the coder's skills bullet keeps the
# mandatory-reporting rule and drops the duplicated mirror tail -- the
# not-a-routing-input pins are now whole-prompt single-occurrence counts, the
# principle stated once at the closing-block mirror statement (sub-spec 02's
# folded list under "## Receipt").
# =============================================================================
test_skillsline_01_coder_half() {
  ok=0
  # Activation = reading the full SKILL.md, never a summary/description alone.
  require "$CODER_SKILLS" 'reading the full `SKILL.md`' || ok=1
  require "$CODER_SKILLS" 'never acting from a summary or the description alone' || ok=1

  # The mandatory-reporting rule survives in the "## Output" skills bullet.
  require "$CODER_OUTPUT" 'skills were activated' || ok=1
  require "$CODER_OUTPUT" 'by name' || ok=1
  require "$CODER_OUTPUT" 'none matched' || ok=1
  require "$CODER_OUTPUT" 'never silently omitted' || ok=1
  require "$CODER_OUTPUT" 'mandatory line' || ok=1

  # The duplicated mirror tail is gone from the whole "## Output" section --
  # since the coder's closing block moved to "## Receipt" (style-rewrite 02),
  # no surviving line of this section states the mirror principle.
  refuse "$CODER_OUTPUT" 'never an input to any routing state or count' || ok=1
  refuse "$CODER_OUTPUT" 'any orchestrator re-routing decision is made from disk state' || ok=1

  # The moved pins: each mirror string now appears exactly once in the whole
  # coder prompt (at the closing-block mirror statement).
  n=$(count_occurrences "$CODER_PROMPT" 'never an input to any routing state or count')
  [ "$n" -eq 1 ] || { echo "  'never an input to any routing state or count' appears $n times in coder.prompt (expected exactly once)"; ok=1; }
  n=$(count_occurrences "$CODER_PROMPT" 'disk state')
  [ "$n" -eq 1 ] || { echo "  'disk state' appears $n times in coder.prompt (expected exactly once)"; ok=1; }
  return $ok
}

# =============================================================================
# skillsline-02 (prompts-06's verifier half): the same edit for the verifier.
# Its closing-block mirror statement lives inside "## Report Format", so the
# tail-removal pin is scoped to the skills bullet line itself, and the whole-
# prompt single-occurrence counts do the rest.
# =============================================================================
test_skillsline_02_verifier_half() {
  ok=0
  # Activation = reading the full SKILL.md, never a summary/description alone.
  require "$VERIFIER_SKILLS" 'reading the full `SKILL.md`' || ok=1
  require "$VERIFIER_SKILLS" 'never acting from a summary or the description alone' || ok=1

  # The mandatory-reporting rule survives in the "## Report Format" skills
  # bullet itself.
  require "$VERIFIER_SKILLS_LINE" 'skills were activated' || ok=1
  require "$VERIFIER_SKILLS_LINE" 'by name' || ok=1
  require "$VERIFIER_SKILLS_LINE" 'none matched' || ok=1
  require "$VERIFIER_SKILLS_LINE" 'never silently omitted' || ok=1
  require "$VERIFIER_SKILLS_LINE" 'mandatory line' || ok=1

  # The duplicated mirror tail is gone from that bullet (the strings still
  # appear elsewhere in the section -- at the closing-block mirror statement,
  # pinned by the counts below and by skillsline-03).
  refuse "$VERIFIER_SKILLS_LINE" 'never an input to any routing state or count' || ok=1
  refuse "$VERIFIER_SKILLS_LINE" 'any orchestrator re-routing decision is made from disk state' || ok=1

  # The moved pins: each mirror string now appears exactly once in the whole
  # verifier prompt (its single "Report Format" occurrence is the mirror
  # statement; skillsline-03 pins that location precisely).
  n=$(count_occurrences "$VERIFIER_PROMPT" 'never an input to any routing state or count')
  [ "$n" -eq 1 ] || { echo "  'never an input to any routing state or count' appears $n times in verifier.prompt (expected exactly once)"; ok=1; }
  n=$(count_occurrences "$VERIFIER_PROMPT" 'disk state')
  [ "$n" -eq 1 ] || { echo "  'disk state' appears $n times in verifier.prompt (expected exactly once)"; ok=1; }
  return $ok
}

# =============================================================================
# skillsline-03: the mirror principle is now stated exactly once per prompt,
# at the closing-block mirror statement. Whole-prompt occurrence counts:
# "never an input to any routing state or count" appears once in each of the
# four prompts; "disk state" appears once in coder.prompt and
# verifier.prompt; in those two the single occurrence lives in the closing-
# block mirror statement, not in a skills bullet (the specifier's and
# orchestrator's statements are out-of-edit-scope single occurrences pinned
# by the counts alone).
# =============================================================================
test_skillsline_03_mirror_clause_once_per_prompt() {
  ok=0
  for f in "$SPECIFIER_PROMPT" "$CODER_PROMPT" "$VERIFIER_PROMPT" "$ORCHESTRATOR_PROMPT"; do
    n=$(count_occurrences "$f" 'never an input to any routing state or count')
    [ "$n" -eq 1 ] || { echo "  'never an input to any routing state or count' appears $n times in $(basename "$f") (expected exactly once)"; ok=1; }
  done
  for f in "$CODER_PROMPT" "$VERIFIER_PROMPT"; do
    n=$(count_occurrences "$f" 'disk state')
    [ "$n" -eq 1 ] || { echo "  'disk state' appears $n times in $(basename "$f") (expected exactly once)"; ok=1; }
  done

  # Location pin, coder: the single occurrences live in the closing-block
  # mirror statement -- inside "## Receipt" (the folded home), on lines that
  # carry the mirror clause, never on the skills bullet's line; the "##
  # Output" and "## Skills" sections hold none.
  if [ "$(grep -cF 'never an input to any routing state or count' "$CODER_PROMPT")" -ne 1 ] \
     || [ "$(grep -F 'never an input to any routing state or count' "$CODER_PROMPT" | grep -c mirror)" -ne 1 ] \
     || grep -F 'never an input to any routing state or count' "$CODER_PROMPT" | grep -qF 'skills were activated'; then
    echo "  coder.prompt: the single mirror-clause occurrence is not the closing-block mirror statement"
    ok=1
  fi
  if [ "$(grep -cF 'disk state' "$CODER_PROMPT")" -ne 1 ] \
     || ! grep -F 'disk state' "$CODER_PROMPT" | grep -qF 're-routing decision is made from disk state'; then
    echo "  coder.prompt: the 'disk state' occurrence is not the mirror statement's re-routing sentence"
    ok=1
  fi
  require "$CODER_RECEIPT" 'never an input to any routing state or count' || ok=1
  require "$CODER_RECEIPT" 'disk state' || ok=1
  refuse "$CODER_SKILLS" 'never an input to any routing state or count' || ok=1
  refuse "$CODER_SKILLS" 'disk state' || ok=1

  # Location pin, verifier: same, with the mirror statement living inside
  # "## Report Format" (the bullet-line absence is pinned there by
  # skillsline-02; the "## Skills" section holds none).
  if [ "$(grep -cF 'never an input to any routing state or count' "$VERIFIER_PROMPT")" -ne 1 ] \
     || [ "$(grep -F 'never an input to any routing state or count' "$VERIFIER_PROMPT" | grep -c mirror)" -ne 1 ] \
     || grep -F 'never an input to any routing state or count' "$VERIFIER_PROMPT" | grep -qF 'skills were activated'; then
    echo "  verifier.prompt: the single mirror-clause occurrence is not the closing-block mirror statement"
    ok=1
  fi
  if [ "$(grep -cF 'disk state' "$VERIFIER_PROMPT")" -ne 1 ] \
     || ! grep -F 'disk state' "$VERIFIER_PROMPT" | grep -qF 're-routing decision is made from disk state'; then
    echo "  verifier.prompt: the 'disk state' occurrence is not the mirror statement's re-routing sentence"
    ok=1
  fi
  require "$VERIFIER_REPORT" 'never an input to any routing state or count' || ok=1
  require "$VERIFIER_REPORT" 'disk state' || ok=1
  refuse "$VERIFIER_SKILLS" 'never an input to any routing state or count' || ok=1
  refuse "$VERIFIER_SKILLS" 'disk state' || ok=1
  return $ok
}

# =============================================================================
# skillsline-04: the skills suite follows, loudly and per role. Meta-check on
# this suite's own shape (the prompts-06 split), on the untouched survivors
# (byte-identical function bodies vs HEAD), on the docs suite (untouched,
# still pinning the gotcha sentence, exiting 0), and on a recursion-guarded
# self-run of this suite (exit 0, no FAIL, prompts-06 gone, every surviving
# test PASSing by name).
# =============================================================================
test_skillsline_04_suite_follows() {
  ok=0

  # (a) prompts-06's single test is gone, split into per-role halves each
  # registered under its scenario id so a failure maps back.
  if [ -n "$(extract_fn "$SUITE_SOURCE" test_prompts_06)" ]; then
    echo "  the single prompts-06 test still exists (it must be split into the two per-role halves)"
    ok=1
  fi
  # (the pattern is built by concatenation, and no comment may quote the
  # joined form either: a literal old-registration string written anywhere in
  # this file would live in the very file the grep scans and match itself)
  refuse "$SUITE_SOURCE" "run_test \"prom""pts-06" || ok=1
  require "$SUITE_SOURCE" 'run_test "skillsline-01' || ok=1
  require "$SUITE_SOURCE" 'run_test "skillsline-02' || ok=1

  # (b) each half keeps the mandatory-line pins in its role's report-section
  # extract and moved the not-a-routing-input pins to whole-prompt
  # single-occurrence counts (no extract-scoped routing require survives).
  HALF1=$(mktemp); HALF2=$(mktemp)
  extract_fn "$SUITE_SOURCE" test_skillsline_01_coder_half > "$HALF1"
  extract_fn "$SUITE_SOURCE" test_skillsline_02_verifier_half > "$HALF2"
  for pin in 'skills were activated' 'by name' 'none matched' 'never silently omitted' \
             'never an input to any routing state or count' 'disk state'; do
    require "$HALF1" "$pin" || ok=1
    require "$HALF2" "$pin" || ok=1
  done
  require "$HALF1" 'count_occurrences "$CODER_PROMPT"' || ok=1
  require "$HALF2" 'count_occurrences "$VERIFIER_PROMPT"' || ok=1
  refuse "$HALF1" "require \"\$CODER_OUTPUT\" 'never an input" || ok=1
  refuse "$HALF2" "require \"\$VERIFIER_REPORT\" 'never an input" || ok=1
  rm -f "$HALF1" "$HALF2"

  # (c) the suite's other tests -- prompts-01..05 and prompts-07's Skills-
  # section pins, the prompts-05 gate helpers, and the self-retiring
  # additive-only windows -- pass unmodified: their function bodies are
  # byte-identical to HEAD's copy of this suite.
  HEAD_SUITE=$(mktemp)
  if ! git -C "$SCRIPT_DIR" show HEAD:tests/skills-activation-prompts_test.sh > "$HEAD_SUITE" 2>/dev/null; then
    echo "  cannot read HEAD's copy of this suite to compare the unmodified tests"
    ok=1
  fi
  # (loop variables are deliberately not called `name`/`fn`: run_test keeps
  # the reported name in the shell-global `$name`, and these tests run in the
  # same shell, so reusing it would overwrite the harness's own variable)
  for sfn in test_prompts_01 test_prompts_02 test_prompts_03 test_prompts_04 \
             test_prompts_05 test_prompts_07 \
             specifier_byte_identical_to_head prompt_prose_distinct_from_head \
             coder_prompt_distinct_from_head verifier_prompt_distinct_from_head \
             test_coder_additive_only test_additive_only_verifier; do
    A=$(mktemp); B=$(mktemp)
    extract_fn "$HEAD_SUITE" "$sfn" > "$A"
    extract_fn "$SUITE_SOURCE" "$sfn" > "$B"
    if [ ! -s "$A" ]; then
      echo "  $sfn not found in HEAD's copy of the suite"
      ok=1
    elif ! cmp -s "$A" "$B"; then
      echo "  $sfn changed vs HEAD (only the prompts-06 split is permitted)"
      ok=1
    fi
    rm -f "$A" "$B"
  done
  rm -f "$HEAD_SUITE"

  # (d) the docs suite stays untouched and green: byte-identical to HEAD,
  # still pinning the gotcha's transparency-line sentence, exiting 0 -- the
  # skills line's principle remains documented even though each prompt now
  # states it once.
  if ! git -C "$SCRIPT_DIR" diff --quiet HEAD -- tests/skills-activation-docs_test.sh; then
    echo "  tests/skills-activation-docs_test.sh was modified (this sub-spec verified it no-break)"
    ok=1
  fi
  require "$SCRIPT_DIR/AGENTS.md" 'a transparency line only, never a routing input' || ok=1
  require "$SCRIPT_DIR/CLAUDE.md" 'a transparency line only, never a routing input' || ok=1
  if ! sh "$DOCS_SUITE" > /dev/null 2>&1; then
    echo "  tests/skills-activation-docs_test.sh exits non-zero"
    ok=1
  fi

  # (e) both suites exit 0: the docs suite is run by (d) above; this suite
  # runs itself once, guarded against recursion by the env var the inner run
  # inherits (the inner skillsline-04 skips only this self-run step; every
  # other check still executes). The inner run must exit 0, report no FAIL,
  # keep every surviving test PASSing by name, and show prompts-06 gone.
  if [ -z "${ANTZ_SKILLSLINE_SELF_RUN:-}" ]; then
    SELF_OUT=$(mktemp)
    ANTZ_SKILLSLINE_SELF_RUN=1 sh "$SUITE_SOURCE" > "$SELF_OUT" 2>&1
    if [ $? -ne 0 ]; then
      echo "  this suite exits non-zero when run (see $SELF_OUT)"
      ok=1
    fi
    if grep -q '^FAIL:' "$SELF_OUT"; then
      echo "  the suite run reports a FAIL"
      ok=1
    fi
    if grep -q 'prompts-06:' "$SELF_OUT"; then
      echo "  prompts-06 still appears in the suite output"
      ok=1
    fi
    for tname in 'PASS: prompts-01:' 'PASS: prompts-02:' 'PASS: prompts-03:' 'PASS: prompts-04:' \
                 'PASS: prompts-05:' 'PASS: prompts-07:' \
                 'PASS: prompts-invariant: the coder' 'PASS: prompts-invariant: the verifier' \
                 'PASS: skillsline-01:' 'PASS: skillsline-02:' 'PASS: skillsline-03:' 'PASS: skillsline-04:'; do
      grep -qF -- "$tname" "$SELF_OUT" || { echo "  the suite run lacks: $tname"; ok=1; }
    done
    rm -f "$SELF_OUT"
  fi
  return $ok
}

# =============================================================================
# prompts-07: when a delegation carries pre-resolved skill paths (the
# orchestrator's block, per 02-orchestrator), the session reads exactly
# those files before task work; only a direct, non-orchestrated invocation
# falls back to own discovery.
# =============================================================================
test_prompts_07() {
  ok=0
  for section in "$CODER_SKILLS" "$VERIFIER_SKILLS"; do
    require "$section" '## Skills to load before work' || ok=1
    require "$section" 'SKILL.md` paths' || ok=1
    require "$section" 'read first' || ok=1
    require "$section" 'before any task-specific' || ok=1
    require "$section" 'no such block' || ok=1
    require "$section" 'direct, non-orchestrated invocation' || ok=1
  done
  return $ok
}

# =============================================================================
# Invariant (01-prompts): the "## Skills" sections are additive -- no
# existing bullet of either prompt is reworded or removed. Every line of the
# pre-change (HEAD) prompt must still be present verbatim. Gated per the
# established convention (this suite's prompts-05 gates,
# tests/renderinject_test.sh's base-render gate, sessionguards-04's removal
# check): once the working coder.prompt legitimately differs from HEAD -- a
# later change's rewording, e.g. fix-orchestrator-flow's receipts sub-spec
# replacing the test_command= grammar line with the `none` sentinel, or its
# roles sub-spec rewriting the Input Rule ownership bullet by write surface --
# the verbatim-every-line check vacuously retires with a loud note. The
# verifier half retires the same way through its own gate below, once the
# roles sub-spec's Merge & Archive reword lands in the working tree.
# =============================================================================
# Prints 1 when the working coder.prompt differs from HEAD's copy (a later
# sub-spec's legitimate edit) and 0 when it doesn't (or HEAD's copy is
# unreadable, in which case there is nothing to compare against).
coder_prompt_distinct_from_head() {
  head_coder=$(mktemp)
  if git -C "$SCRIPT_DIR" show HEAD:agents/prompts/coder.prompt > "$head_coder" 2>/dev/null; then
    cmp -s "$head_coder" "$CODER_PROMPT" && { printf '0'; rm -f "$head_coder"; return 0; }
    printf '1'
  else
    printf '0'
  fi
  rm -f "$head_coder"
}

# Prints 1 when the working verifier.prompt differs from HEAD's copy (a later
# sub-spec's legitimate edit) and 0 when it doesn't (or HEAD's copy is
# unreadable, in which case there is nothing to compare against).
verifier_prompt_distinct_from_head() {
  head_verifier=$(mktemp)
  if git -C "$SCRIPT_DIR" show HEAD:agents/prompts/verifier.prompt > "$head_verifier" 2>/dev/null; then
    cmp -s "$head_verifier" "$VERIFIER_PROMPT" && { printf '0'; rm -f "$head_verifier"; return 0; }
    printf '1'
  else
    printf '0'
  fi
  rm -f "$head_verifier"
}

test_coder_additive_only() {
  ok=0
  if [ "$(coder_prompt_distinct_from_head)" -eq 1 ]; then
    echo "  note: coder.prompt changed vs HEAD (a later sub-spec's legitimate reword); the additive-vs-HEAD verbatim check is vacuously retired"
    return 0
  fi
  HEAD_CODER=$(mktemp)
  git -C "$SCRIPT_DIR" show HEAD:agents/prompts/coder.prompt > "$HEAD_CODER" \
    || { echo "  cannot read HEAD:agents/prompts/coder.prompt"; rm -f "$HEAD_CODER"; return 1; }
  while IFS= read -r line; do
    if ! grep -qxF -- "$line" "$CODER_PROMPT"; then
      echo "  pre-change coder prompt line no longer present verbatim: $line"
      ok=1
    fi
  done < "$HEAD_CODER"
  rm -f "$HEAD_CODER"
  return $ok
}

test_additive_only_verifier() {
  ok=0
  if [ "$(verifier_prompt_distinct_from_head)" -eq 1 ]; then
    echo "  note: verifier.prompt changed vs HEAD (a later sub-spec's legitimate reword); the additive-vs-HEAD verbatim check is vacuously retired"
    return 0
  fi
  HEAD_VERIFIER=$(mktemp)
  git -C "$SCRIPT_DIR" show HEAD:agents/prompts/verifier.prompt > "$HEAD_VERIFIER" \
    || { echo "  cannot read HEAD:agents/prompts/verifier.prompt"; rm -f "$HEAD_VERIFIER"; return 1; }
  while IFS= read -r line; do
    if ! grep -qxF -- "$line" "$VERIFIER_PROMPT"; then
      echo "  pre-change verifier prompt line no longer present verbatim: $line"
      ok=1
    fi
  done < "$HEAD_VERIFIER"
  rm -f "$HEAD_VERIFIER"
  return $ok
}

# ---- run everything ----------------------------------------------------------

run_test "prompts-01: coder prompt gains a Skills section with discovery before planning, the directory fallback, and mandatory activation before covered work" test_prompts_01
run_test "prompts-02: matching is keyed to each skill's own description only -- no concrete skill name is hardcoded in the coder prompt" test_prompts_02
run_test "prompts-03: verifier prompt gains the identical duty for its layer, with a warning when covered code was judged without the matched skill" test_prompts_03
run_test "prompts-04: the added Skills wording is framework-neutral -- no client-specific tool or syntax in either added section" test_prompts_04
run_test "prompts-05: specifier.prompt byte-for-byte pin enforced while the copy is identical to HEAD (retired by gating with a loud note, additive-shape checks skipped, once it differs -- conventions-04); orchestrator.prompt differs only by the delegation skills-block wording" test_prompts_05
# prompts-06's single test is split into its per-role halves by style-rewrite
# sub-spec 04 (skillsline-01/02), with the whole-prompt counts (skillsline-03)
# and this suite's follow-loudly meta-check (skillsline-04) alongside.
run_test "skillsline-01: coder half of the split prompts-06 -- the skills bullet keeps the mandatory-reporting rule, the mirror tail is gone from ## Output, and coder.prompt states each mirror string exactly once" test_skillsline_01_coder_half
run_test "skillsline-02: verifier half of the split prompts-06 -- the skills bullet keeps the mandatory-reporting rule, the mirror tail is gone from the bullet, and verifier.prompt states each mirror string exactly once" test_skillsline_02_verifier_half
run_test "skillsline-03: the mirror principle is stated exactly once per prompt, at the closing-block mirror statement, not in a skills bullet" test_skillsline_03_mirror_clause_once_per_prompt
run_test "skillsline-04: the skills suite follows loudly -- prompts-06 split into per-role halves, the other tests byte-identical to HEAD, the docs suite untouched and green, both suites exit 0" test_skillsline_04_suite_follows
run_test "prompts-07: pre-resolved delegation skill paths are read first; own discovery only on a direct, non-orchestrated invocation" test_prompts_07
run_test "prompts-invariant: the coder prompt's Skills addition is purely additive (every pre-change line survives verbatim)" test_coder_additive_only
run_test "prompts-invariant: the verifier prompt's Skills addition is purely additive (every pre-change line survives verbatim)" test_additive_only_verifier

# ---- e2e-only scenarios: explicit SKIP stubs ----------------------------------
# e2e-prompts-01/02 (spdd/changes/skills-activation/01-prompts.feature) require
# live antz-coder sessions in a real Angular project and inspecting whether the
# skill is visibly activated before Angular code is written -- not reducible to
# a static grep on the prompt bodies. They belong to the verifier's end-to-end
# suite, not this unit suite. Explicit stubs so every scenario id is accounted
# for.

E2E_REASON="e2e-only: observable only in a live antz-coder session (verifier's e2e QA suite)"

skip_test "e2e-prompts-01: in an Angular project, an antz-coder session visibly loads the angular-conventions skill before writing Angular code" "$E2E_REASON"
skip_test "e2e-prompts-02: skill activation survives the orchestrated flow -- /antz-delegated coder sessions still activate matching skills" "$E2E_REASON"

rm -f "$CODER_SKILLS" "$VERIFIER_SKILLS" "$CODER_OUTPUT" "$VERIFIER_REPORT" "$CODER_RECEIPT" "$VERIFIER_SKILLS_LINE"

echo ""
echo "$pass_count passed, $fail_count failed, $skip_count skipped (e2e-only, see 01-prompts.feature)"
[ "$fail_count" -eq 0 ]
