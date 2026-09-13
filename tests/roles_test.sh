#!/usr/bin/env bash
# Unit tests for spdd/changes/fix-orchestrator-flow/03-roles.feature
# (roles-01..05): the coder prompt's directory-ownership bullet rewritten by
# write surface, the verifier prompt's Merge & Archive move as a plain mv with
# its reason, the AGENTS.md/CLAUDE.md strict-ownership gotcha bullet following
# the write-surface contract byte-identically, and the loud retirement of the
# prompt guards that pinned every pre-change line.
#
# Also hosts spdd/changes/style-rewrite/03-verifier.feature (verifier-01..02):
# the verifier's "## On Rejection" opening bullet rewritten from one
# 100-130-word run-on sentence into a lead line plus a short list, with the
# rejection contract (literal machine-countable heading, append-never-overwrite,
# via Bash, blockers content, attribution) intact.
#
# Also hosts spdd/changes/style-rewrite/06-terminology.feature
# (terminology-01..03): the `<change-slug>` -> `<slug>` unification at the
# seven sites with the suite pins following, the one-form-per-concept sweep
# over the four prompts (with its declared machine-format / byte-pinned
# exemptions), and the Working-Root triplication rule -- three prompts
# byte-identical, one identical gotcha bullet in AGENTS.md and CLAUDE.md.
#
# Self-contained bash test harness (no external framework/dependency -- this
# repo has no package manager or build system), mirroring the harness style of
# tests/skills-activation-prompts_test.sh. Run directly:
#   ./tests/roles_test.sh

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CODER_PROMPT="$SCRIPT_DIR/agents/prompts/coder.prompt"
SPECIFIER_PROMPT="$SCRIPT_DIR/agents/prompts/specifier.prompt"
VERIFIER_PROMPT="$SCRIPT_DIR/agents/prompts/verifier.prompt"
ORCHESTRATOR_PROMPT="$SCRIPT_DIR/agents/prompts/orchestrator.prompt"
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
VERIFIER_INPUT=$(mktemp)
VERIFIER_MERGE=$(mktemp)
VERIFIER_REJECT=$(mktemp)
SPECIFIER_OUTPUT=$(mktemp)
extract_section "$CODER_PROMPT" "Owns" "$CODER_OWNS"
extract_section "$CODER_PROMPT" "Input Rule" "$CODER_INPUT"
extract_section "$CODER_PROMPT" "Receipt" "$CODER_RECEIPT"
extract_section "$VERIFIER_PROMPT" "Input Rule" "$VERIFIER_INPUT"
extract_section "$VERIFIER_PROMPT" "Merge & Archive, only on approved or approved-with-warnings" "$VERIFIER_MERGE"
extract_section "$VERIFIER_PROMPT" "On Rejection" "$VERIFIER_REJECT"
# The specifier's report section, keyed on the post-terminology-01 heading
# text (`<slug>`); the WR_* files are the three role prompts' "## Working
# Root" sections, whose byte-identity is the documented triplication.
extract_section "$SPECIFIER_PROMPT" 'Output, written to `spdd/changes/<slug>/`' "$SPECIFIER_OUTPUT"
WR_SPECIFIER=$(mktemp)
WR_CODER=$(mktemp)
WR_VERIFIER=$(mktemp)
extract_section "$SPECIFIER_PROMPT" "Working Root" "$WR_SPECIFIER"
extract_section "$CODER_PROMPT" "Working Root" "$WR_CODER"
extract_section "$VERIFIER_PROMPT" "Working Root" "$WR_VERIFIER"

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
  require "$CODER_INPUT" 'If `spdd/changes/<slug>/` doesn'"'"'t exist in the working root, stop and report there'"'"'s no sub-spec to implement.' || ok=1
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
  require "$CODER_OWNS" 'starting from `spdd/changes/<slug>/` and existing `spdd/specs/` for context' || ok=1

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
  require "$VERIFIER_MERGE" 'move `spdd/changes/<slug>/` to `spdd/archive/<slug>/` unmodified' || ok=1
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

  # The merge bullet's exact-string pin, re-scoped (precision-gaps
  # rolechecks-05) to the bullet extended by rolechecks-04: alongside the
  # surviving merge and never-overwrite sentence pinned above, the pin now
  # asserts the new content -- the per-domain file rule, the kebab-case
  # naming, the README resolution, and the create-when-new rule.
  require "$VERIFIER_MERGE" 'one spec file per domain, at `spdd/specs/<domain>.md`, with kebab-case domain names' || ok=1
  require "$VERIFIER_MERGE" 'destination domain is read from the change README'"'"'s section for that sub-spec' || ok=1
  require "$VERIFIER_MERGE" 'When the domain is new (no `spdd/specs/<domain>.md` exists), the verifier creates the file' || ok=1
  require "$VERIFIER_MERGE" 'a `# Domain: <domain>` header plus the merged scenarios, under the same merge rules' || ok=1
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

# =============================================================================
# verifier-01 / verifier-02 (style-rewrite/03-verifier): the verifier's
# "## On Rejection" opening bullet is a lead line plus a short list, with the
# rejection contract (append never overwrite, via Bash, the literal
# machine-countable heading, the blockers content, and the unchanged
# attribution bullet) intact.
# =============================================================================

# The canonical strings of the new short list (scenario verifier-01's parts).
# The lead line's path placeholder carries the terminology-01 `<slug>`
# spelling (the one form per concept; the old `<change-slug>` shape appears
# nowhere in the prompts any more).
REJECT_LEAD='- Before reporting, append (never overwrite) one entry to `spdd/changes/<slug>/REJECTED.md`, via Bash. The entry:'
REJECT_ITEM_HEADING='is headed by its own line reading exactly `## Rejection <n>` and nothing else (`<n>` = 1 for the first entry in the file, incrementing by one per further entry)'
REJECT_ITEM_REASON="must keep that heading literal, because the orchestrator's probe script counts this exact heading, not just numbered in spirit"
REJECT_ITEM_CONTENT='carries the reported blockers on the lines that follow the heading (severity, evidence, offending scenario — the same content already in the Report Format)'

# The old run-on sentence's nesting shape (scenario verifier-02's refusals):
# the exact span the sub-spec quotes ("the strings ... no longer appear as
# one line"), plus the old lead-into-heading join.
REJECT_OLD_JOIN='and nothing else (`<n>` = 1 for the first entry in the file, incrementing by one per further entry) — the orchestrator'"'"'s probe script counts this exact heading, so it must be literal, not just numbered in spirit. Put the reported blockers'
REJECT_OLD_LEAD_JOIN='`spdd/changes/<change-slug>/REJECTED.md` (via Bash), headed by'

# The section's second bullet, unchanged by this sub-spec.
REJECT_ATTRIBUTION='- For each blocker, name the sub-spec it traces to when one applies (via its scenario id), or state explicitly that it doesn'"'"'t trace to a single sub-spec (e.g. cross-feature coherence, or an e2e QA step not owned by any one sub-spec).'

# Writes the section's lead-plus-list region (the lines before the unchanged
# attribution bullet) into $2; returns 1 when the attribution bullet is gone.
reject_lead_region() {
  # $1 = section extract, $2 = output file
  split_at=$(grep -n 'For each blocker' "$1" | head -n 1 | cut -d: -f1)
  if [ -z "$split_at" ]; then
    : > "$2"
    return 1
  fi
  head -n $((split_at - 1)) "$1" > "$2"
}

# The contract parts both verifier scenarios pin inside the extract: the
# lead-line duty, the exact-heading item, the probe-counts reason, and the
# blockers-content item.
on_rejection_contract() {
  # $1 = section extract file
  cok=0
  require "$1" "$REJECT_LEAD" || cok=1
  require "$1" "$REJECT_ITEM_HEADING" || cok=1
  require "$1" "$REJECT_ITEM_REASON" || cok=1
  require "$1" "$REJECT_ITEM_CONTENT" || cok=1
  return $cok
}

test_verifier_01() {
  ok=0
  # The section still exists under its unchanged heading.
  require "$VERIFIER_PROMPT" '## On Rejection' || ok=1

  # The lead line states the duty, as its own line: before reporting, append
  # (never overwrite) one entry to the change's REJECTED.md, via Bash.
  grep -qxF -- "$REJECT_LEAD" "$VERIFIER_REJECT" \
    || { echo "  no lead line stating the append-never-overwrite duty on its own line"; ok=1; }

  # The lead introduces a short list: at least three sub-items before the
  # attribution bullet, carrying the heading / reason / content parts.
  LEAD_REGION=$(mktemp)
  reject_lead_region "$VERIFIER_REJECT" "$LEAD_REGION" \
    || { echo "  the unchanged attribution bullet is missing from the section"; rm -f "$LEAD_REGION"; return 1; }
  on_rejection_contract "$VERIFIER_REJECT" || ok=1
  n=$(grep -c '^  - ' "$LEAD_REGION")
  [ "$n" -ge 3 ] || { echo "  lead region has $n list items, expected at least 3"; ok=1; }

  # The old run-on's nesting shape is gone: no line opens more than one
  # parenthetical, and no line carries the old single 100-130-word sentence.
  shape=$(awk '
    {
      n = gsub(/\(/, "(")
      w = split($0, words, /[ \t]+/)
      if (n > 1) { print "  line " NR " opens " n " parentheticals: " $0; bad = 1 }
      if (w > 60) { print "  line " NR " carries a " w "-word sentence: " $0; bad = 1 }
    }
    END { exit bad ? 1 : 0 }
  ' "$LEAD_REGION")
  if [ -n "$shape" ]; then echo "$shape"; ok=1; fi
  rm -f "$LEAD_REGION"

  # The section's second bullet (per-blocker attribution) is unchanged.
  require "$VERIFIER_REJECT" "$REJECT_ATTRIBUTION" || ok=1
  return $ok
}

test_verifier_02() {
  ok=0
  # The new pins live with the verifier-suite home: roles_test.sh is extended
  # in the same change with test functions named after this sub-spec's ids,
  # and the reported test names carry the scenario ids.
  require "$SCRIPT_DIR/tests/roles_test.sh" 'test_verifier_01' || ok=1
  require "$SCRIPT_DIR/tests/roles_test.sh" 'test_verifier_02' || ok=1
  m=$(grep -c 'run_test "verifier-01:' "$SCRIPT_DIR/tests/roles_test.sh")
  [ "$m" -ge 1 ] || { echo "  no reported test name carrying the verifier-01 id"; ok=1; }
  m=$(grep -c 'run_test "verifier-02:' "$SCRIPT_DIR/tests/roles_test.sh")
  [ "$m" -ge 1 ] || { echo "  no reported test name carrying the verifier-02 id"; ok=1; }

  # The contract parts are required inside the "## On Rejection" extract...
  on_rejection_contract "$VERIFIER_REJECT" || ok=1

  # ...and the old run-on sentence's strings no longer appear as one line.
  refuse "$VERIFIER_REJECT" "$REJECT_OLD_JOIN" || ok=1
  refuse "$VERIFIER_PROMPT" "$REJECT_OLD_LEAD_JOIN" || ok=1

  # The rejection contract stays machine-countable: the probe suite passes
  # unmodified (its "## Rejection <n>" counting is script behavior), and the
  # probe script and the meta files are byte-unchanged by this sub-spec.
  # Split by change deembed-orchestration-scripts (testsuite-06): install.sh
  # is no longer inside the byte-frozen guard -- THIS change legitimately
  # edits it (the libdir install and the placeholder substitution are its
  # subject), and its contract is pinned forever by the install suites
  # (renderinject, libdirinstall, setmodeldeembed, sluglimit). Scripts and
  # meta stay frozen: the machine surfaces these tests pin must not move.
  sh "$SCRIPT_DIR/tests/orchestrator-status-probe_test.sh" >/dev/null 2>&1 \
    || { echo "  tests/orchestrator-status-probe_test.sh no longer passes"; ok=1; }
  git -C "$SCRIPT_DIR" diff --quiet HEAD -- scripts/orchestration/ agents/meta/ \
    || { echo "  scripts/orchestration/ or agents/meta/ changed -- forbidden by this sub-spec's invariants"; ok=1; }
  return $ok
}

# =============================================================================
# terminology-01 / terminology-02 / terminology-03
# (style-rewrite/06-terminology): the `<change-slug>` -> `<slug>` unification
# at the seven sites with the suite pins following; the one-form-per-concept
# sweep with its declared exemptions; the Working-Root triplication as a
# documented, pinned editing rule.
# =============================================================================

# The seven rewritten sites, each pinned inside its own section's extract.
SPEC_HEADING='## Output, written to `spdd/changes/<slug>/`'
SPEC_OPENQ='Write open questions, if any, to the fixed file `spdd/changes/<slug>/OPEN_QUESTIONS.md` rather than inlining them elsewhere, and only create it when something is actually blocked.'
CODER_OWNS_LINE='- Implementation of one approved sub-spec, starting from `spdd/changes/<slug>/` and existing `spdd/specs/` for context.'
CODER_STOP_LINE='- If `spdd/changes/<slug>/` doesn'"'"'t exist in the working root, stop and report there'"'"'s no sub-spec to implement.'
VERIFIER_STOP_LINE='- If `spdd/changes/<slug>/` doesn'"'"'t exist in the working root, stop and report there'"'"'s nothing to verify.'
VERIFIER_MOVE_LINE='- After merge succeeds, move `spdd/changes/<slug>/` to `spdd/archive/<slug>/` unmodified — plain `mv` is the only mechanism, since `git mv` on untracked files always fails: nothing here is ever committed, and the orchestrator'"'"'s release gate only reads the working tree.'

test_terminology_01() {
  ok=0
  # "change-slug" no longer appears in any of the four prompts.
  for p in "$SPECIFIER_PROMPT" "$CODER_PROMPT" "$VERIFIER_PROMPT" "$ORCHESTRATOR_PROMPT"; do
    refuse "$p" 'change-slug' || ok=1
  done

  # The seven sites read `<slug>`, each pinned at its own site: the specifier
  # heading line and OPEN_QUESTIONS bullet, the coder's Owns and Input Rule
  # bullets, the verifier's Input Rule, Merge & Archive move, and On Rejection
  # lead bullets.
  grep -qxF -- "$SPEC_HEADING" "$SPECIFIER_PROMPT" \
    || { echo "  the specifier's Output heading does not read the <slug> form"; ok=1; }
  require "$SPECIFIER_OUTPUT" "$SPEC_OPENQ" || ok=1
  grep -qxF -- "$CODER_OWNS_LINE" "$CODER_PROMPT" || { echo "  the coder's Owns bullet is not the <slug> line"; ok=1; }
  grep -qxF -- "$CODER_STOP_LINE" "$CODER_INPUT" || { echo "  the coder's missing-change-dir bullet is not the <slug> line"; ok=1; }
  grep -qxF -- "$VERIFIER_STOP_LINE" "$VERIFIER_INPUT" || { echo "  the verifier's missing-change-dir bullet is not the <slug> line"; ok=1; }
  grep -qxF -- "$VERIFIER_MOVE_LINE" "$VERIFIER_MERGE" || { echo "  the verifier's archive-move bullet is not the <slug> line"; ok=1; }
  grep -qxF -- "$REJECT_LEAD" "$VERIFIER_REJECT" || { echo "  the verifier's On Rejection lead line does not read the <slug> path"; ok=1; }

  # The machine-line formats are untouched by the sweep (hard constraints):
  # the delegation-header lines and the flow subcommand invocations, the
  # probe's output line, and the receipt/closing-block grammars survive
  # verbatim where they live.
  require "$ORCHESTRATOR_PROMPT" 'Working root: <repo root absolute path>' || ok=1
  require "$ORCHESTRATOR_PROMPT" 'Change slug: <slug>' || ok=1
  require "$ORCHESTRATOR_PROMPT" 'ensure <slug>' || ok=1
  # Re-keyed by change deembed-orchestration-scripts (testsuite-06): the
  # state invocation names the probe by path, not a tempfile argument.
  require "$ORCHESTRATOR_PROMPT" 'state <slug> "__ANTZ_SCRIPTS_DIR__/antz-probe.sh"' || ok=1
  require "$ORCHESTRATOR_PROMPT" 'release <slug>' || ok=1
  require "$ORCHESTRATOR_PROMPT" 'subspec=<file> ids=<id,id,...> receipt=<file|missing> covered=<n>/<N> complete=<yes|no> class=<done|blocked|in_progress>' || ok=1
  require "$ORCHESTRATOR_PROMPT" 'state=checkout_refused' || ok=1
  require "$ORCHESTRATOR_PROMPT" 'gate=refused reason=' || ok=1
  require "$CODER_RECEIPT" 'test_command=<discovered unit-suite run command>' || ok=1
  require "$CODER_RECEIPT" 'id=<feature>-<index> result=<green|skip|blocked> reason=<text>' || ok=1
  for p in "$SPECIFIER_PROMPT" "$CODER_PROMPT" "$VERIFIER_PROMPT" "$ORCHESTRATOR_PROMPT"; do
    require "$p" '`status=<value>`' || ok=1
    require "$p" '`ids=<id,id,...>`' || ok=1
    require "$p" '`results=<value>`' || ok=1
  done

  # The suite pins follow in the same change (static pins -- this suite must
  # not run rolechecks_test.sh, which runs this one; the whole-suite run
  # establishes their green): closingblock's specifier extract anchor is
  # re-keyed on the new heading text, and rolechecks-03/04's byte-identity
  # windows on the changed verifier bullets are born gated on the
  # change_pending pattern.
  require "$SCRIPT_DIR/tests/closingblock_test.sh" 'extract_section "$SPECIFIER_PROMPT" '"'"'Output, written to `spdd/changes/<slug>/`'"'"' "$SPECIFIER_REPORT"' || ok=1
  require "$SCRIPT_DIR/tests/rolechecks_test.sh" 'b1_slug_rewrite_pending' || ok=1
  require "$SCRIPT_DIR/tests/rolechecks_test.sh" 'm1_slug_rewrite_pending' || ok=1
  return $ok
}

test_terminology_02() {
  ok=0
  # The sweep: no variant spelling of the four concepts survives in any
  # prompt. `sub-spec` is the one form (never "sub spec" or "subspecs"),
  # `client` is the one word for what the delegation runs on (never
  # "framework" -- mechanically: the word appears nowhere in the prompts),
  # and the slug placeholder is `<slug>` everywhere prose names it.
  for p in "$SPECIFIER_PROMPT" "$CODER_PROMPT" "$VERIFIER_PROMPT" "$ORCHESTRATOR_PROMPT"; do
    refuse "$p" 'sub spec' || ok=1
    refuse "$p" 'subspecs' || ok=1
    if grep -qiF -- 'framework' "$p"; then
      echo "  found forbidden text (the client concept): framework"
      ok=1
    fi
    refuse "$p" '<change-slug>' || ok=1
  done

  # The sweep's declared exemptions hold untouched: the probe-output tokens
  # subspec= and <subspec-file>= (machine-line formats) are still there, the
  # delegation-header line "Working root: <repo root absolute path>" is
  # byte-intact, and the orchestrator's "main checkout" descriptions survive.
  require "$ORCHESTRATOR_PROMPT" 'subspec=' || ok=1
  require "$ORCHESTRATOR_PROMPT" '<subspec-file>=' || ok=1
  require "$ORCHESTRATOR_PROMPT" 'Working root: <repo root absolute path>' || ok=1
  require "$ORCHESTRATOR_PROMPT" 'main checkout' || ok=1

  # The sweep is a test named after this scenario id, so a future variant
  # spelling fails it.
  grep -qF 'run_test "terminology-02:' "$SCRIPT_DIR/tests/roles_test.sh" \
    || { echo "  no reported test name carrying the terminology-02 id"; ok=1; }
  return $ok
}

test_terminology_03() {
  ok=0
  # The triplication is real: all three role prompts carry a "## Working
  # Root" section, and the three extracts are byte-identical to each other,
  # so any future edit touching fewer than three sites fails this test.
  [ -s "$WR_SPECIFIER" ] && [ -s "$WR_CODER" ] && [ -s "$WR_VERIFIER" ] \
    || { echo "  a role prompt has no ## Working Root section (empty extract)"; ok=1; }
  cmp -s "$WR_SPECIFIER" "$WR_CODER" \
    || { echo "  the specifier's and coder's ## Working Root sections differ"; diff "$WR_SPECIFIER" "$WR_CODER" | head -4; ok=1; }
  cmp -s "$WR_SPECIFIER" "$WR_VERIFIER" \
    || { echo "  the specifier's and verifier's ## Working Root sections differ"; diff "$WR_SPECIFIER" "$WR_VERIFIER" | head -4; ok=1; }
  # The sections are the working-root law, not an empty shell.
  require "$WR_SPECIFIER" '**Working Root**' || ok=1
  require "$WR_SPECIFIER" "cd '<working-root>'" || ok=1
  # The tripulation is the three ROLE prompts: the orchestrator carries no
  # "## Working Root" section of its own.
  n=$(grep -c '^## Working Root$' "$ORCHESTRATOR_PROMPT")
  [ "$n" -eq 0 ] || { echo "  orchestrator.prompt carries a ## Working Root section ($n), expected none"; ok=1; }

  # The editing rule is documented: AGENTS.md and CLAUDE.md each carry one
  # new gotcha bullet, byte-identical between the two files, stating the
  # verbatim tripulation on purpose (per-prompt autonomy) and the all-three-
  # sites editing rule.
  A_TRIP=$(mktemp)
  C_TRIP=$(mktemp)
  extract_bullet_line "$AGENTS_MD" '- Working-Root triplication' "$A_TRIP"
  extract_bullet_line "$CLAUDE_MD" '- Working-Root triplication' "$C_TRIP"
  n_a=$(grep -c '^- Working-Root triplication' "$AGENTS_MD")
  n_c=$(grep -c '^- Working-Root triplication' "$CLAUDE_MD")
  [ "$n_a" -eq 1 ] || { echo "  AGENTS.md has $n_a Working-Root-triplication bullets, expected exactly 1"; ok=1; }
  [ "$n_c" -eq 1 ] || { echo "  CLAUDE.md has $n_c Working-Root-triplication bullets, expected exactly 1"; ok=1; }
  [ -s "$A_TRIP" ] || { echo "  AGENTS.md has no Working-Root triplication gotcha bullet"; ok=1; }
  [ -s "$C_TRIP" ] || { echo "  CLAUDE.md has no Working-Root triplication gotcha bullet"; ok=1; }
  cmp -s "$A_TRIP" "$C_TRIP" \
    || { echo "  Working-Root tripulation bullet differs between AGENTS.md and CLAUDE.md"; diff "$A_TRIP" "$C_TRIP" | head -4; ok=1; }
  for b in "$A_TRIP" "$C_TRIP"; do
    require "$b" '`## Working Root`' || ok=1
    require "$b" 'duplicated verbatim across the three role prompts (specifier, coder, verifier)' || ok=1
    require "$b" 'on purpose' || ok=1
    require "$b" 'per-prompt autonomy' || ok=1
    require "$b" 'every future edit' || ok=1
    require "$b" 'all three sites' || ok=1
  done
  rm -f "$A_TRIP" "$C_TRIP"

  # The new docs bullet is additive: the docs' existing gotcha bullets pass
  # their own suites with the new line in place (closing-block bullet:
  # closingblock-04; receipt-convention bullet: receipts-10; access-model,
  # skills-activation, and Structure bullets: their suites; the write-
  # surface bullet: roles-04, which runs in this very suite).
  for t in closingblock_test.sh receipts_test.sh access-model_test.sh skills-activation-docs_test.sh repodocs_test.sh; do
    sh "$SCRIPT_DIR/tests/$t" >/dev/null 2>&1 \
      || { echo "  $t no longer passes with the new docs bullet"; ok=1; }
  done
  return $ok
}

# ---- run everything ----------------------------------------------------------

run_test "roles-01: the coder's Input Rule ownership bullet states the surface by write surface, the read-surface phrasing is gone, the other four bullets keep their meaning" test_roles_01
run_test "roles-02: the Owns line, the rewritten bullet, and the Receipt section name the same surfaces; the receipt duty is untouched" test_roles_02
run_test "roles-03: the verifier's archive move is a plain mv as the only mechanism with its reason stated; git mv is no longer offered; the rest of Merge & Archive stands" test_roles_03
run_test "roles-04: the strict-ownership gotcha bullet follows the write-surface contract, byte-identical in AGENTS.md and CLAUDE.md, with the old claims gone from both docs" test_roles_04
# testsuite-06 (change deembed-orchestration-scripts): the invocation-form
# hard constraints re-keyed. The state pin reads the path-based form, the
# ensure/release pins keep their unchanged subcommand forms, no non-comment
# line of the prompt or this suite still names the retired tempfile argument
# (the needle is split below so this scan cannot match itself), and the
# verifier-02 byte-frozen guard covers exactly the surfaces this change
# leaves frozen.
test_testsuite_06_roles_pins_rekeyed() {
  ok=0
  require "$ORCHESTRATOR_PROMPT" 'sh "__ANTZ_SCRIPTS_DIR__/antz-flow.sh" state <slug> "__ANTZ_SCRIPTS_DIR__/antz-probe.sh"' || ok=1
  require "$ORCHESTRATOR_PROMPT" 'sh "__ANTZ_SCRIPTS_DIR__/antz-flow.sh" ensure <slug>' || ok=1
  require "$ORCHESTRATOR_PROMPT" 'sh "__ANTZ_SCRIPTS_DIR__/antz-flow.sh" release <slug>' || ok=1
  for t in "$ORCHESTRATOR_PROMPT" "$SCRIPT_DIR/tests/roles_test.sh"; do
    if grep -v '^[[:space:]]*#' "$t" | grep -qF 'probe-temp''file'; then
      echo "  a non-comment line still pins the retired tempfile-argument form"
      ok=1
    fi
  done
  require "$SCRIPT_DIR/tests/roles_test.sh" 'diff --quiet HEAD -- scripts/orchestration/ agents/meta/' || ok=1
  return $ok
}

run_test "roles-05: the additive-vs-HEAD prompt guards are retired loudly, no other test pins the removed wording, and the surrounding suites stay green" test_roles_05
# =============================================================================
# testsuite-08 (change deembed-orchestration-scripts, sub-spec 05): whole-
# suite coherence. Every suite exits 0 with its scenario ids reported; no
# test extracts script content from agents/prompts/ or from any rendered
# command body anymore (prompts and renders carry no marker and no script
# fence at all, and the retired extractor helpers have no call sites
# anywhere in tests/); scripts are tested as installed files and as sources.
# Recursion-guarded like description-quoting's quoting-05 dynamic half: an
# invocation already running inside another suite's full-suite glob (flag
# set) returns 0 without re-globbing, and the two glob-running suites
# (roles_test.sh itself = this file, description-quoting_test.sh = its own
# dynamic half already proves the same coverage) are excluded from the loop.
# =============================================================================
test_testsuite_08_full_suite_coherence() {
  if [ -n "${ANTZ_COHERENCE_INNER:-}" ]; then
    echo "  note: invoked inside another suite's full-suite glob -- skipping the nested glob (recursion guard)"
    return 0
  fi
  ok=0
  d=$(mktemp -d)
  for t in "$SCRIPT_DIR"/tests/*_test.sh; do
    suite_name=$(basename -- "$t")
    case "$suite_name" in
      roles_test.sh) continue ;;  # self-recursion (this very suite)
      description-quoting_test.sh) continue ;;  # its quoting-05 runs the full glob, this-file included
    esac
    out=$(ANTZ_COHERENCE_INNER=1 env -u XDG_CONFIG_HOME HOME="$d" sh "$t" 2>&1) \
      || { echo "  suite failed: $suite_name"; printf '%s\n' "$out" | grep -E '^(FAIL|FATAL)' | head -5; ok=1; continue; }
    printf '%s\n' "$out" | grep -qE '^(PASS|FAIL|SKIP): [a-z0-9-]+-[0-9]+' \
      || { echo "  $suite_name reports no scenario ids"; ok=1; }
  done
  # The no-extraction surface: no prompt carries an include marker or a
  # script-content fence; the retired extraction-era idioms exist nowhere in
  # tests/'s non-comment lines -- the marker-substitution body rebuild
  # (renderinject's old reconstruct, keyed by its ${line##...} idiom), the
  # marker-tree assertion, and the fence walkers of the render-sync suite
  # (needles split so this scan can't match itself; invocations_test.sh's
  # same-named helper is the INVERTED oracle -- prompt+substitution with no
  # marker idiom -- so it correctly survives this scan).
  for p in "$SPECIFIER_PROMPT" "$CODER_PROMPT" "$VERIFIER_PROMPT" "$ORCHESTRATOR_PROMPT"; do
    [ "$(grep -c '# antz-include:' "$p")" -eq 0 ] \
      || { echo "  ${p##*/} carries an include marker"; ok=1; }
    [ "$(grep -c '```sh' "$p")" -eq 0 ] \
      || { echo "  ${p##*/} carries a script-content fence"; ok=1; }
  done
  subst_idiom='rel=${line##'"*'# antz-include"
  for t in "$SCRIPT_DIR"/tests/*_test.sh; do
    for needle in "$subst_idiom" 'assert_no_marker_''in_tree' 'extract_''fences' 'expected_''block'; do
      n=$(grep -v '^[[:space:]]*#' "$t" | grep -cF -- "$needle" || true)
      [ "$n" -eq 0 ] \
        || { echo "  ${t##*/} still carries the retired script-extraction idiom ($needle)"; ok=1; }
    done
  done
  # Scripts as installed files: a fresh hermetic render puts all four under
  # the resolved libdir, and no rendered agent/command body carries a marker
  # or script fence.
  (cd "$SCRIPT_DIR" && env -u XDG_CONFIG_HOME HOME="$d/render-home" sh ./install.sh --all > "$d/render.log" 2>&1) \
    || { echo "  hermetic render failed: $(head -3 "$d/render.log")"; ok=1; }
  for s in antz-flow antz-probe antz-skills antz-set-model; do
    [ -f "$d/render-home/.config/antz/scripts/$s.sh" ] \
      || { echo "  installed libdir script missing: $s.sh"; ok=1; }
  done
  if grep -rq '```sh' "$d/render-home/.claude" "$d/render-home/.config/opencode" 2>/dev/null; then
    echo "  a rendered client file still carries a script-content fence"
    ok=1
  fi
  if grep -rq '# antz-include:' "$d/render-home" 2>/dev/null; then
    echo "  a rendered file still carries an include marker"
    ok=1
  fi
  rm -rf "$d"
  return $ok
}

run_test "testsuite-08: the repo's full unit suite runs green with ids reported; no script content survives in prompts, renders, or extractor call sites" test_testsuite_08_full_suite_coherence
run_test "verifier-01: the ## On Rejection opening bullet is a lead line plus a short list — same duty, exact heading, probe-counts reason, blockers content, unchanged attribution, no run-on nesting" test_verifier_01
run_test "verifier-02: the new pins live in tests/roles_test.sh, the old run-on strings are refused, and the probe suite passes unmodified with the machine surfaces byte-unchanged" test_verifier_02
run_test "terminology-01: change-slug is gone from all four prompts, the seven sites read <slug>, the machine-line formats are byte-untouched, and the closingblock/rolechecks pins follow in the same change" test_terminology_01
run_test "terminology-02: the four prompts carry one form per concept (no sub spec/subspecs variants, no framework-where-client-is-meant, <slug> everywhere prose names it) and the declared machine-format/byte-pinned exemptions hold" test_terminology_02
run_test "terminology-03: the three role prompts' ## Working Root sections are byte-identical, AGENTS.md and CLAUDE.md carry one identical gotcha bullet stating the triplication editing rule, and the existing docs bullets pass their suites" test_terminology_03
run_test "testsuite-06: the invocation-form hard constraints re-keyed, the retired tempfile-argument form gone from non-comment lines, and the verifier-02 frozen guard split to scripts+meta" test_testsuite_06_roles_pins_rekeyed

echo ""
echo "$pass_count passed, $fail_count failed"
[ "$fail_count" -eq 0 ]
