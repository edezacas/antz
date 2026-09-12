#!/usr/bin/env bash
# Unit tests for spdd/changes/fix-orchestrator-flow/03-roles.feature
# (roles-01..05): the coder prompt's directory-ownership bullet rewritten by
# write surface, the verifier prompt's Merge & Archive move as a plain mv with
# its reason, the AGENTS.md/CLAUDE.md strict-ownership gotcha bullet following
# the write-surface contract byte-identically, and the loud retirement of the
# prompt guards that pinned every pre-change line.
#
# Self-contained bash test harness (no external framework/dependency -- this
# repo has no package manager or build system), mirroring the harness style of
# tests/skills-activation-prompts_test.sh. Run directly:
#   ./tests/roles_test.sh

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CODER_PROMPT="$SCRIPT_DIR/agents/prompts/coder.prompt"
VERIFIER_PROMPT="$SCRIPT_DIR/agents/prompts/verifier.prompt"
AGENTS_MD="$SCRIPT_DIR/AGENTS.md"
CLAUDE_MD="$SCRIPT_DIR/CLAUDE.md"

pass_count=0
fail_count=0

# ---- tiny test runner (mirrors tests/skills-activation-prompts_test.sh) -----

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

# Extract the single gotcha bullet line matching the fixed prefix from a
# policy doc (the Strict-ownership bullet is one physical line).
extract_bullet_line() {
  # $1 = file, $2 = fixed prefix, $3 = output file
  grep -F -- "$2" "$1" > "$3"
}

# Section extractions, done once so every test reads only the scoped text.
CODER_OWNS=$(mktemp)
CODER_INPUT=$(mktemp)
CODER_RECEIPT=$(mktemp)
VERIFIER_MERGE=$(mktemp)
extract_section "$CODER_PROMPT" "Owns" "$CODER_OWNS"
extract_section "$CODER_PROMPT" "Input Rule" "$CODER_INPUT"
extract_section "$CODER_PROMPT" "Receipt" "$CODER_RECEIPT"
extract_section "$VERIFIER_PROMPT" "Merge & Archive, only on approved or approved-with-warnings" "$VERIFIER_MERGE"

# =============================================================================
# roles-01: the coder prompt's Input Rule directory-ownership bullet is
# rewritten by write surface; the old read-surface phrasing is gone; the rest
# of the Input Rule keeps its meaning.
# =============================================================================
test_roles_01() {
  ok=0
  # The ownership bullet states the surface by write surface.
  require "$CODER_INPUT" 'read `spdd/changes/` and `spdd/specs/`' || ok=1
  require "$CODER_INPUT" 'as read-only context' || ok=1
  require "$CODER_INPUT" '`spdd/specs/` never written' || ok=1
  require "$CODER_INPUT" 'write the code and tests the sub-spec calls for wherever they belong in the project' || ok=1
  require "$CODER_INPUT" 'receipt in `spdd/changes/<slug>/`' || ok=1
  require "$CODER_INPUT" 'never touch `spdd/archive/`' || ok=1

  # The old read-surface phrasing and its never-touch-specs clause are gone
  # from the whole prompt (with the contradiction against the Owns line).
  refuse "$CODER_PROMPT" 'Read only from' || ok=1
  refuse "$CODER_PROMPT" 'Never touch `spdd/specs/`' || ok=1

  # The rest of the Input Rule is unchanged, one bullet per stop: missing
  # change dir, missing sub-spec, OPEN_QUESTIONS.md hard stop, multi-layer
  # refusal, plus the one rewritten ownership bullet -- five in total.
  require "$CODER_INPUT" 'If `spdd/changes/<change-slug>/` doesn'"'"'t exist in the working root, stop and report there'"'"'s no sub-spec to implement.' || ok=1
  require "$CODER_INPUT" 'If the named sub-spec isn'"'"'t in that change directory, stop and report it wasn'"'"'t found.' || ok=1
  require "$CODER_INPUT" 'If `OPEN_QUESTIONS.md` exists in the change directory, stop without reading further or implementing anything, and report that it must be resolved first.' || ok=1
  require "$CODER_INPUT" 'If given a full multi-layer plan instead of one sub-spec, refuse it and ask for a single sub-spec.' || ok=1
  n=$(grep -c '^- ' "$CODER_INPUT")
  [ "$n" -eq 5 ] || { echo "  Input Rule has $n bullets, expected 5"; ok=1; }
  return $ok
}

# =============================================================================
# roles-02: the Owns line, the rewritten bullet, and the Receipt section name
# the same surfaces; the receipt duty itself (02-receipts' grammar) is
# unchanged by this sub-spec.
# =============================================================================
test_roles_02() {
  ok=0
  # Owns: both spec surfaces for context, unchanged by this sub-spec.
  require "$CODER_OWNS" 'starting from `spdd/changes/<change-slug>/` and existing `spdd/specs/` for context' || ok=1

  # The bullet names the same read pair and the receipt location inside
  # spdd/changes/<slug>/ (asserted again here for the consistency claim).
  require "$CODER_INPUT" 'read `spdd/changes/` and `spdd/specs/`' || ok=1
  require "$CODER_INPUT" 'receipt in `spdd/changes/<slug>/`' || ok=1

  # Receipt section: the receipt path it names is the same surface the bullet
  # writes.
  require "$CODER_RECEIPT" 'result receipt `spdd/changes/<slug>/NN-<feature>.result`' || ok=1

  # The receipt duty is unchanged by this sub-spec: the ## Receipt section
  # still carries 02-receipts' sentinel grammar verbatim (those are
  # receipts-01/05's own pins, mirrored here to prove non-disturbance).
  require "$CODER_RECEIPT" 'the literal sentinel `none` — the line reads exactly `test_command=none`, never an empty value' || ok=1
  require "$CODER_RECEIPT" 'test_command=<discovered unit-suite run command>' || ok=1
  return $ok
}

# =============================================================================
# roles-03: the verifier's archive step is a plain mv as the only mechanism,
# the reason stated in the prompt itself, the release-gate half surviving;
# the rest of Merge & Archive unchanged.
# =============================================================================
test_roles_03() {
  ok=0
  # The section is still there under its unchanged heading (extraction
  # matched the full heading verbatim above; the guard lives in the heading
  # text itself).
  require "$VERIFIER_PROMPT" '## Merge & Archive, only on approved or approved-with-warnings' || ok=1

  # Plain mv is the only instruction, and the reason is in the prompt.
  require "$VERIFIER_MERGE" 'move `spdd/changes/<change-slug>/` to `spdd/archive/<change-slug>/` unmodified' || ok=1
  require "$VERIFIER_MERGE" 'plain `mv`' || ok=1
  require "$VERIFIER_MERGE" 'the only mechanism' || ok=1
  require "$VERIFIER_MERGE" '`git mv` on untracked files always fails' || ok=1
  require "$VERIFIER_MERGE" 'nothing here is ever committed' || ok=1
  # The release-gate half of the reason survives.
  require "$VERIFIER_MERGE" 'release gate only reads the working tree' || ok=1

  # `git mv` is no longer offered as an option anywhere in the prompt: the
  # old offered-alternative shapes are gone, and its only remaining mention
  # is the stated failure reason (one occurrence, on the reason line).
  refuse "$VERIFIER_PROMPT" 'via `git mv`' || ok=1
  refuse "$VERIFIER_PROMPT" '`git mv`, or a plain `mv`' || ok=1
  n=$(grep -cF 'git mv' "$VERIFIER_PROMPT")
  [ "$n" -eq 1 ] || { echo "  'git mv' appears $n times in the verifier prompt, expected exactly 1 (the reason)"; ok=1; }
  grep -F 'git mv' "$VERIFIER_PROMPT" | grep -qF 'always fails' \
    || { echo "  the surviving 'git mv' mention is not the stated failure reason"; ok=1; }

  # The rest of Merge & Archive is unchanged: merge-by-scenario with the
  # never-overwrite rule, and never archiving a rejected change.
  require "$VERIFIER_MERGE" 'Merge each scenario (ADD/MODIFY/REMOVE) into the matching `spdd/specs/` domain file, reading the existing spec first and merging rather than overwriting it.' || ok=1
  require "$VERIFIER_MERGE" 'Never archive a rejected change, leaving it in `spdd/changes/` for the coder.' || ok=1
  return $ok
}

# =============================================================================
# roles-04: the policy docs' strict-ownership gotcha bullet follows the
# write-surface contract, byte-identical between AGENTS.md and CLAUDE.md,
# and neither doc anywhere keeps the old read-surface claims.
# =============================================================================
test_roles_04() {
  ok=0
  AGENTS_BULLET=$(mktemp)
  CLAUDE_BULLET=$(mktemp)
  extract_bullet_line "$AGENTS_MD" '- Strict directory ownership' "$AGENTS_BULLET"
  extract_bullet_line "$CLAUDE_MD" '- Strict directory ownership' "$CLAUDE_BULLET"

  n_a=$(grep -c '^- Strict directory ownership' "$AGENTS_MD")
  n_c=$(grep -c '^- Strict directory ownership' "$CLAUDE_MD")
  [ "$n_a" -eq 1 ] || { echo "  AGENTS.md has $n_a strict-ownership bullets, expected exactly 1"; ok=1; }
  [ "$n_c" -eq 1 ] || { echo "  CLAUDE.md has $n_c strict-ownership bullets, expected exactly 1"; ok=1; }
  [ -s "$AGENTS_BULLET" ] || { echo "  AGENTS.md has no strict-ownership gotcha bullet"; ok=1; }
  [ -s "$CLAUDE_BULLET" ] || { echo "  CLAUDE.md has no strict-ownership gotcha bullet"; ok=1; }

  # Byte-identical between the two files (the shared-bullet convention).
  cmp -s "$AGENTS_BULLET" "$CLAUDE_BULLET" \
    || { echo "  strict-ownership bullet differs between AGENTS.md and CLAUDE.md"; diff "$AGENTS_BULLET" "$CLAUDE_BULLET" | head -4; ok=1; }

  # The shared bullet states the write-surface contract.
  for b in "$AGENTS_BULLET" "$CLAUDE_BULLET"; do
    require "$b" 'the coder reads `spdd/changes/` and `spdd/specs/`' || ok=1
    require "$b" 'as read-only context' || ok=1
    require "$b" '`spdd/specs/` never written' || ok=1
    require "$b" 'writes the code and tests the sub-spec calls for wherever they belong in the project' || ok=1
    require "$b" 'plus its receipt in `spdd/changes/<slug>/`' || ok=1
    require "$b" 'never touches `spdd/archive/`' || ok=1
    require "$b" 'the verifier role merges into specs and archives changes, but never overwrites a domain spec file wholesale (merge scenario-by-scenario, ADD/MODIFY/REMOVE)' || ok=1
  done

  # Neither doc anywhere keeps the old claims: the coder only reading
  # spdd/changes/, or never touching spdd/specs/.
  for f in "$AGENTS_MD" "$CLAUDE_MD"; do
    refuse "$f" 'only reads `spdd/changes/`' || ok=1
    refuse "$f" 'never touch `spdd/specs/`' || ok=1
  done
  rm -f "$AGENTS_BULLET" "$CLAUDE_BULLET"
  return $ok
}

# =============================================================================
# roles-05: the additive-vs-HEAD prompt guards are retired loudly (not
# silently) so the legitimate rewordings pass while the suites keep their
# other assertions, and no other test pins the removed wording.
# =============================================================================

# Prints 1 when the working copy of $1 differs from HEAD's blob (a later
# sub-spec's legitimate edit) and 0 when it doesn't (or HEAD is unreadable).
working_differs_from_head() {
  h=$(mktemp)
  if git -C "$SCRIPT_DIR" show "HEAD:$1" > "$h" 2>/dev/null; then
    cmp -s "$h" "$SCRIPT_DIR/$1" && { printf '0'; rm -f "$h"; return 0; }
    printf '1'
  else
    printf '0'
  fi
  rm -f "$h"
}

test_roles_05() {
  ok=0
  # The skills suite still exits 0 with the rewrites in the tree, and where a
  # prompt legitimately differs from HEAD its verbatim guard retired with a
  # loud printed note (not a silent deletion of the guard).
  SKILLS_OUT=$(mktemp)
  sh "$SCRIPT_DIR/tests/skills-activation-prompts_test.sh" > "$SKILLS_OUT" 2>&1 \
    || { echo "  skills-activation-prompts suite does not pass after the rewrites:"; tail -5 "$SKILLS_OUT"; ok=1; }
  if [ "$(working_differs_from_head agents/prompts/coder.prompt)" -eq 1 ]; then
    require "$SKILLS_OUT" 'coder.prompt changed vs HEAD' || ok=1
    require "$SKILLS_OUT" 'retired' || ok=1
  fi
  if [ "$(working_differs_from_head agents/prompts/verifier.prompt)" -eq 1 ]; then
    require "$SKILLS_OUT" 'verifier.prompt changed vs HEAD' || ok=1
    require "$SKILLS_OUT" 'retired' || ok=1
  fi
  # The guard functions themselves survive (retired-by-gating, not deleted):
  # both checks are still registered in the suite.
  require "$SCRIPT_DIR/tests/skills-activation-prompts_test.sh" 'test_coder_additive_only' || ok=1
  require "$SCRIPT_DIR/tests/skills-activation-prompts_test.sh" 'test_additive_only_verifier' || ok=1

  # No other test pins the removed wording: no suite outside this one
  # mentions the old offered-git-mv shape or the read-only-from wording.
  pin_hits=$(grep -lF -e 'git mv' -e 'Read only from' "$SCRIPT_DIR"/tests/*_test.sh | grep -v '/roles_test\.sh$' || true)
  if [ -n "$pin_hits" ]; then
    echo "  other suites still pin the removed wording:"
    printf '%s\n' "$pin_hits"
    ok=1
  fi

  # The suites pinning surrounding content stay green without edits.
  for t in receipts_test.sh closingblock_test.sh; do
    sh "$SCRIPT_DIR/tests/$t" >/dev/null 2>&1 \
      || { echo "  $t no longer passes"; ok=1; }
  done
  rm -f "$SKILLS_OUT"
  return $ok
}

# ---- run everything ----------------------------------------------------------

run_test "roles-01: the coder's Input Rule ownership bullet states the surface by write surface, the read-surface phrasing is gone, the other four bullets keep their meaning" test_roles_01
run_test "roles-02: the Owns line, the rewritten bullet, and the Receipt section name the same surfaces; the receipt duty is untouched" test_roles_02
run_test "roles-03: the verifier's archive move is a plain mv as the only mechanism with its reason stated; git mv is no longer offered; the rest of Merge & Archive stands" test_roles_03
run_test "roles-04: the strict-ownership gotcha bullet follows the write-surface contract, byte-identical in AGENTS.md and CLAUDE.md, with the old claims gone from both docs" test_roles_04
run_test "roles-05: the additive-vs-HEAD prompt guards are retired loudly, no other test pins the removed wording, and the surrounding suites stay green" test_roles_05

echo ""
echo "$pass_count passed, $fail_count failed"
[ "$fail_count" -eq 0 ]
