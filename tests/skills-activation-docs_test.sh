#!/usr/bin/env bash
# Unit tests for the docs layer of change skills-activation
# (spdd/changes/skills-activation/04-docs.feature, scenarios docs-01..04):
# the skills-activation gotcha bullet added to AGENTS.md and CLAUDE.md
# (duty, mechanical enablement, directory-listing fallback, delegation
# block, adopt/reject register, report line) and the Client Integration
# `readwrite` mapping sentence corrected for the new
# full-edit-access-plus-`Skill`-tool Claude grant.
#
# Self-contained bash test harness (no external framework/dependency --
# this repo has no package manager or build system), mirroring the harness
# style of tests/docs-bump_test.sh. Run directly:
#   ./tests/skills-activation-docs_test.sh
#
# The skills gotcha bullet is a verbatim-identical twin across AGENTS.md and
# CLAUDE.md (docs-02 pins the sync; the two docs duplicate each other and
# must not fork), so every content test runs against both files' extracted
# bullet and a parity test compares them byte-for-byte. The Client
# Integration tests run against each file's own install/render bullet (the
# two files word the surrounding text differently, so only the `readwrite`
# mapping sentence itself is asserted, never the whole bullet).
#
# e2e-docs-01 (04-docs.feature) is observable only by driving live installs
# and comparing docs statements against the installed agent frontmatter --
# the verifier's Integration Verification, not this unit suite. It appears
# below as an explicit SKIP stub so no scenario id is silently unaccounted
# for.

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
AGENTS_MD="$SCRIPT_DIR/AGENTS.md"
CLAUDE_MD="$SCRIPT_DIR/CLAUDE.md"

pass_count=0
fail_count=0
skip_count=0

# ---- tiny test runner (mirrors tests/docs-bump_test.sh) ---------------------

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

# ---- fixture helpers ---------------------------------------------------------

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

extract_bullet() {
  # $1 = md file, $2 = fixed bullet prefix; prints the first matching line
  grep -F -- "$2" "$1" | head -n 1
}

# Extract each file's skills gotcha bullet once (single lines), so the
# content tests grep the bullet alone -- a required or forbidden phrase
# elsewhere in the file must never satisfy or trip a bullet-scoped
# assertion.
AGENTS_SKILLS=$(mktemp)
CLAUDE_SKILLS=$(mktemp)
printf '%s\n' "$(extract_bullet "$AGENTS_MD" '- Skills activation')" > "$AGENTS_SKILLS"
printf '%s\n' "$(extract_bullet "$CLAUDE_MD" '- Skills activation')" > "$CLAUDE_SKILLS"

both_skills_bullets() {
  # $1 = name of a check function taking one bullet file; runs it on
  # both docs' extracted skills gotcha bullet.
  "$1" "$AGENTS_SKILLS" && "$1" "$CLAUDE_SKILLS"
}

# =============================================================================
# docs-01: the skills-activation gotcha states the duty (discover before
# planning/verifying, activate by description match) and its mechanical
# enablement (Claude `Skill` grant, OpenCode native tool), plus the
# working-root directory-listing fallback -- without contradiction to the
# render or the prompts.
# =============================================================================

check_skills_duty() {
  ok=0
  require "$1" 'both roles discover the available skills before planning/verifying' || ok=1
  require "$1" 'activate any skill whose description matches the code or files about to be written, modified, or judged' || ok=1
  require "$1" 'matched by description, never by a hardcoded skill name' || ok=1
  return $ok
}

test_docs_01_duty_stated() {
  ok=0
  [ -s "$AGENTS_SKILLS" ] || { echo "  AGENTS.md has no skills-activation gotcha bullet"; ok=1; }
  [ -s "$CLAUDE_SKILLS" ] || { echo "  CLAUDE.md has no skills-activation gotcha bullet"; ok=1; }
  both_skills_bullets check_skills_duty || ok=1
  return $ok
}

check_skills_enablement() {
  ok=0
  require "$1" 'the rendered `readwrite` Claude grant includes the `Skill` tool' || ok=1
  require "$1" '(a subagent `tools:` list is an enforced allowlist on Claude Code)' || ok=1
  require "$1" 'OpenCode agents get the client'"'"'s native skill tool by default' || ok=1
  return $ok
}

test_docs_01_enablement_stated() {
  both_skills_bullets check_skills_enablement
}

check_skills_fallback() {
  ok=0
  require "$1" 'on a client without a skill tool, the fallback is a directory listing' || ok=1
  require "$1" "the working root's and the user's skills directories" || ok=1
  require "$1" '.claude/skills/' || ok=1
  require "$1" 'read the matched `SKILL.md` in full (paths, not summaries)' || ok=1
  return $ok
}

test_docs_01_directory_listing_fallback_stated() {
  both_skills_bullets check_skills_fallback
}

check_no_skill_names_as_rules() {
  # Invariant: no skill name is named as a rule or trigger in the gotcha
  # (examples may illustrate; the duty itself stays name-agnostic).
  ok=0
  refuse "$1" 'angular-conventions' || ok=1
  refuse "$1" 'gentle-ai' || ok=1
  return $ok
}

test_docs_01_no_skill_name_named_as_a_rule() {
  both_skills_bullets check_no_skill_names_as_rules
}

# =============================================================================
# docs-02: the two docs duplicate each other and must not fork -- the
# skills-activation gotcha is byte-identical in AGENTS.md and CLAUDE.md.
# =============================================================================

test_docs_02_bullet_identical_in_both_files() {
  ok=0
  [ -s "$AGENTS_SKILLS" ] || { echo "  AGENTS.md has no skills-activation gotcha bullet"; ok=1; }
  [ -s "$CLAUDE_SKILLS" ] || { echo "  CLAUDE.md has no skills-activation gotcha bullet"; ok=1; }
  cmp -s "$AGENTS_SKILLS" "$CLAUDE_SKILLS" \
    || { echo "  skills-activation gotcha bullet differs between AGENTS.md and CLAUDE.md"; ok=1; }
  return $ok
}

# =============================================================================
# docs-04: the mechanism register -- the pre-resolved delegation block, the
# explicit none-matched line, the no-registry / no-refresh-automation
# rejection, and the mandatory report line.
# =============================================================================

check_delegation_block() {
  ok=0
  require "$1" 'Orchestrated (via `/antz`) delegations carry a pre-resolved `## Skills to load before work` block' || ok=1
  require "$1" 'absolute `SKILL.md` paths' || ok=1
  require "$1" 'derived mechanically from those standard skills directories at delegation time (paths, not summaries)' || ok=1
  return $ok
}

test_docs_04_delegation_block_stated() {
  both_skills_bullets check_delegation_block
}

check_none_matched_line() {
  require "$1" 'an explicit `Skills: none matched` line when no skill matches'
}

test_docs_04_none_matched_line_stated() {
  both_skills_bullets check_none_matched_line
}

check_adoptions_rejections() {
  ok=0
  require "$1" 'no persistent registry file is kept' || ok=1
  require "$1" 'no refresh hook, plugin, or CLI is introduced' || ok=1
  require "$1" 'freshness comes from per-delegation derivation' || ok=1
  require "$1" '`install.sh` never mutates user configuration (`settings.json`, permission blocks) for this' || ok=1
  return $ok
}

test_docs_04_no_registry_no_refresh_automation_stated() {
  both_skills_bullets check_adoptions_rejections
}

check_report_line() {
  require "$1" "which skills were activated (by name) or that none matched"
}

test_docs_04_report_line_stated() {
  both_skills_bullets check_report_line
}

# =============================================================================
# docs-03: the Client Integration `readwrite` mapping sentence is corrected
# for the new grant (full edit access plus the `Skill` tool on Claude Code;
# OpenCode inherits the native tool), while the `orchestrateonly` sentence,
# the never-commits law, and the boundary statement stay untouched.
# =============================================================================

check_readwrite_mapping() {
  ok=0
  require "$1" '`access: readwrite` maps to full edit access plus, on Claude Code, the `Skill` tool grant' || ok=1
  require "$1" "(on OpenCode, agents inherit the client's native skill tool by default)" || ok=1
  return $ok
}

# The Client Integration bullet's prefix differs per file (AGENTS.md and
# CLAUDE.md word the render sentence differently), so identify each file's
# install/render bullet by a substring the sentence shares, then check the
# `readwrite` mapping phrase within that bullet only.
AGENTS_CLIENT_LINE=$(mktemp)
CLAUDE_CLIENT_LINE=$(mktemp)
printf '%s\n' "$(extract_bullet "$AGENTS_MD" 'renders each')" > "$AGENTS_CLIENT_LINE"
printf '%s\n' "$(extract_bullet "$CLAUDE_MD" 'renders each')" > "$CLAUDE_CLIENT_LINE"

both_doc_files() {
  "$1" "$AGENTS_CLIENT_LINE" && "$1" "$CLAUDE_CLIENT_LINE"
}

test_docs_03_readwrite_mapping() {
  ok=0
  [ -s "$AGENTS_CLIENT_LINE" ] || { echo "  AGENTS.md Client Integration render bullet not found"; ok=1; }
  [ -s "$CLAUDE_CLIENT_LINE" ] || { echo "  CLAUDE.md Client Integration render bullet not found"; ok=1; }
  both_doc_files check_readwrite_mapping || ok=1
  return $ok
}


check_orchestrateonly_unchanged() {
  ok=0
  require "$1" '`access: orchestrateonly` maps to readonly plus a delegation capability' || ok=1
  return $ok
}

test_docs_03_orchestrateonly_mapping_unchanged() {
  both_doc_files check_orchestrateonly_unchanged
}

test_docs_03_access_gotcha_and_governing_rule_untouched() {
  # Invariant: only the added skills bullet and the readwrite mapping
  # sentence changed -- the access-model gotcha bullet and the Governing
  # rule stay byte-identical to git HEAD.
  ok=0
  for f in "$AGENTS_MD" "$CLAUDE_MD"; do
    base=$(basename "$f")
    if ! head_copy=$(git -C "$SCRIPT_DIR" show "HEAD:$base" 2>/dev/null); then
      echo "  $base not in git HEAD (cannot compare untouched bullets)"; ok=1; continue
    fi
    head_file=$(mktemp)
    printf '%s\n' "$head_copy" > "$head_file"
    while IFS= read -r line; do
      case "$line" in
        '- `access` is `readonly | readwrite | orchestrateonly`'*|'- **Governing rule'*)
          if ! grep -qF -- "$line" "$f"; then
            echo "  $base: an untouched gotcha bullet changed vs git HEAD: ${line:0:60}..."; ok=1
          fi
          ;;
      esac
    done < "$head_file"
    rm -f "$head_file"
  done
  return $ok
}

# ---- run everything ---------------------------------------------------------

run_test "docs-01: the skills-activation gotcha bullet states the discover-before-planning/verifying duty and the activate-what-matches-by-description, never-hardcoded rule (both files)" test_docs_01_duty_stated
run_test "docs-01: the skills-activation gotcha bullet states the mechanical enablement -- rendered readwrite Claude grant includes Skill (tools: is an enforced allowlist there) and OpenCode's native skill tool by default -- with no contradiction to the render (both files)" test_docs_01_enablement_stated
run_test "docs-01: the skills-activation gotcha bullet yields the working-root fallback wording for clients without a skill tool (directory listing, skills directories, SKILL.md read in full) (both files)" test_docs_01_directory_listing_fallback_stated
run_test "docs-01: the skills-activation gotcha bullet names no skill name as a rule or trigger (invariant: the duty is name-agnostic)" test_docs_01_no_skill_name_named_as_a_rule

run_test "docs-02: the skills-activation gotcha bullet is byte-identical between AGENTS.md and CLAUDE.md" test_docs_02_bullet_identical_in_both_files

run_test "docs-04: the skills-activation gotcha bullet states the orchestrated pre-resolved '## Skills to load before work' block with absolute SKILL.md paths derived at delegation time (paths, not summaries) (both files)" test_docs_04_delegation_block_stated
run_test "docs-04: the skills-activation gotcha bullet states the explicit 'Skills: none matched' line when no skill matches (both files)" test_docs_04_none_matched_line_stated
run_test "docs-04: the skills-activation gotcha bullet states the rejections -- no persistent registry, no refresh hook/plugin/CLI, per-delegation derivation for freshness, install.sh never mutates user configuration (both files)" test_docs_04_no_registry_no_refresh_automation_stated
run_test "docs-04: the skills-activation gotcha bullet states the roles' report line -- which skills were activated (by name) or that none matched (both files)" test_docs_04_report_line_stated

run_test "docs-03: the Client Integration readwrite mapping sentence states full edit access plus, on Claude Code, the Skill tool grant -- with the OpenCode side inheriting the native skill tool by default (both files)" test_docs_03_readwrite_mapping
run_test "docs-03: the orchestrateonly mapping sentence is unchanged (both files)" test_docs_03_orchestrateonly_mapping_unchanged
run_test "docs-03: only the added skills bullet and the readwrite mapping sentence changed -- the access-model gotcha bullet and the Governing rule are byte-identical to git HEAD (both files)" test_docs_03_access_gotcha_and_governing_rule_untouched

# ---- e2e-only scenario: explicit SKIP stub ------------------------------------
# e2e-docs-01 (spdd/changes/skills-activation/04-docs.feature) drives live
# installs and compares the docs' Skill-grant statement against the
# installed frontmatter (~/.claude/agents/antz-coder.md) -- the verifier's
# Integration Verification, not this unit suite. Explicit stub so the
# scenario id is accounted for (suite convention: see tests/docs-bump_test.sh).

skip_test "e2e-docs-01: a user reading the docs derives the real capability, with the doc statement of the Skill grant matching the installed antz-coder frontmatter exactly and no doc statement contradicting the prompts' ## Skills sections" \
  "e2e-only: live install / installed-frontmatter comparison, run by the verifier (04-docs.feature)"

rm -f "$AGENTS_SKILLS" "$CLAUDE_SKILLS" "$AGENTS_CLIENT_LINE" "$CLAUDE_CLIENT_LINE"

echo ""
echo "$pass_count passed, $fail_count failed, $skip_count skipped (e2e-only, see 04-docs.feature)"
[ "$fail_count" -eq 0 ]
