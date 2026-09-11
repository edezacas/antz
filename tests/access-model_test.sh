#!/usr/bin/env bash
# Unit tests for the role access model (the specifier-write-access change),
# covering every scenario in
# spdd/changes/specifier-write-access/01-meta.feature (meta-01..03).
# Later sub-specs of the same change extend this suite: render-01..04
# (02-render.feature), docs-01..04 (03-docs.feature), bump-01..03
# (04-bump.feature), each as its own test named with its scenario id.
#
# The docs-01..04 tests are deterministic content assertions against the
# two policy docs (AGENTS.md, CLAUDE.md) and docs/orchestrator.md: the
# corrected access-model gotcha bullet (byte-identical between the two
# policy docs), the no-role-declares-readonly note kept alongside
# install.sh's still-defined readonly mapping, and the delegation-scoping
# paragraph's kept platform fact.
#
# Self-contained bash test harness (no external framework/dependency -- this
# repo has no package manager or build system), mirroring the harness style
# of tests/versioning-rule_test.sh. Run directly:
#   ./tests/access-model_test.sh
#
# These are deterministic content assertions against the four role metadata
# files under agents/meta/ (grep/cmp-style). meta-03's byte-for-byte
# regression guard compares against git HEAD's copy of the untouched files
# (this change's base), so it keeps passing after the change is committed.
#
# The change's end-to-end scenarios (e2e-meta-01..02 in 01-meta.feature) are
# observable only by invoking the installed agents and reading the artifacts
# they produce, so the sub-spec's Verification levels assign them to the
# verifier's e2e suite, not to this unit suite. They appear below as
# explicit SKIP stubs so no scenario id is silently unaccounted for.

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
META_SPECIFIER="$SCRIPT_DIR/agents/meta/specifier.yaml"
META_CODER="$SCRIPT_DIR/agents/meta/coder.yaml"
META_VERIFIER="$SCRIPT_DIR/agents/meta/verifier.yaml"
META_ORCHESTRATOR="$SCRIPT_DIR/agents/meta/orchestrator.yaml"
INSTALL_SH="$SCRIPT_DIR/install.sh"
AGENTS_MD="$SCRIPT_DIR/AGENTS.md"
CLAUDE_MD="$SCRIPT_DIR/CLAUDE.md"
ORCHESTRATOR_MD="$SCRIPT_DIR/docs/orchestrator.md"
VERSION_FILE="$SCRIPT_DIR/VERSION"
CHANGELOG_MD="$SCRIPT_DIR/CHANGELOG.md"
ORCHESTRATOR_PROMPT="$SCRIPT_DIR/agents/prompts/orchestrator.prompt"
ANTZ_FLOW_TEST="$SCRIPT_DIR/tests/antz-flow_test.sh"
BUMP_410_SECTION=$(mktemp)
tmp_roots+=("$BUMP_410_SECTION")

pass_count=0
fail_count=0
skip_count=0

# ---- temp-dir bookkeeping (mirrors tests/installsh-posixsh_test.sh) ---------

tmp_roots=()
new_tmp_dir() {
  d=$(mktemp -d)
  tmp_roots+=("$d")
  printf '%s' "$d"
}

cleanup() {
  for d in "${tmp_roots[@]:-}"; do
    [ -n "$d" ] && rm -rf "$d"
  done
  return 0
}
trap cleanup EXIT

# ---- tiny test runner (mirrors tests/versioning-rule_test.sh) ---------------

run_test() {
  # $1 = reported test name (must contain its scenario id), $2 = function
  # name, $3.. = optional arguments passed through to the function (used by
  # the Scenario Outline tests below).
  name="$1"; fn="$2"; shift 2
  if "$fn" "$@"; then
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

# meta_field <file> <field>: prints the value of a top-level single-line
# YAML field (the meta files are three flat "key: value" lines).
meta_field() {
  sed -n "s/^$2: //p" "$1"
}

# extract_bullet <md-file> <fixed line prefix>: prints the first matching
# bullet line (the gotcha bullets are single lines, mirroring
# tests/docs-bump_test.sh's shared-bullet convention).
extract_bullet() {
  grep -F -- "$2" "$1" | head -n 1
}

# The access-model gotcha bullet, extracted once per policy doc so the
# docs-01..04 tests grep the bullet alone -- a phrase elsewhere in the file
# must never satisfy or trip a bullet-scoped assertion. After this sub-spec
# the bullet is byte-identical between the two files (docs-02 pins it).
ACCESS_BULLET_PREFIX='- `access` is `readonly | readwrite | orchestrateonly`'
AGENTS_ACCESS_BULLET=$(mktemp)
CLAUDE_ACCESS_BULLET=$(mktemp)
printf '%s\n' "$(extract_bullet "$AGENTS_MD" "$ACCESS_BULLET_PREFIX")" > "$AGENTS_ACCESS_BULLET"
printf '%s\n' "$(extract_bullet "$CLAUDE_MD" "$ACCESS_BULLET_PREFIX")" > "$CLAUDE_ACCESS_BULLET"

# The "## Gotchas" sections, for docs-03's section-scoped refusal: the old
# bullet's "(no edit/write capability)" wording must be gone from the
# Gotchas text specifically (the Client Integration mapping bullet keeps a
# "maps to no edit/write capability" clause, which must survive).
AGENTS_GOTCHAS=$(mktemp)
CLAUDE_GOTCHAS=$(mktemp)
sed -n '/^## Gotchas$/,/^## Client Integration$/p' "$AGENTS_MD" > "$AGENTS_GOTCHAS"
sed -n '/^## Gotchas$/,/^## Client Integration$/p' "$CLAUDE_MD" > "$CLAUDE_GOTCHAS"

# byte-identical to git HEAD's copy of the same path (meta-03's regression
# guard for the two files this change must not touch).
byte_identical_to_head() {
  git -C "$SCRIPT_DIR" show "HEAD:${1#"$SCRIPT_DIR"/}" 2>/dev/null | cmp -s - "$1"
}

# =============================================================================
# meta-01: the specifier role's access is corrected from readonly to
# readwrite -- it authors spdd/changes/<slug>/ (README.md, numbered .feature
# files, OPEN_QUESTIONS.md), which no readonly grant can write. name and
# description stay unchanged.
# =============================================================================
test_meta_01() {
  ok=0
  [ "$(meta_field "$META_SPECIFIER" access)" = "readwrite" ] \
    || { echo "  specifier access is not readwrite: $(meta_field "$META_SPECIFIER" access)"; ok=1; }
  refuse "$META_SPECIFIER" 'access: readonly' || ok=1
  [ "$(meta_field "$META_SPECIFIER" name)" = "antz-specifier" ] \
    || { echo "  specifier name changed: $(meta_field "$META_SPECIFIER" name)"; ok=1; }
  [ "$(meta_field "$META_SPECIFIER" description)" = "Turns a natural-language request into Gherkin behavior specs and an end-to-end QA suite under spdd/changes/. Use first for any non-trivial feature or change." ] \
    || { echo "  specifier description changed"; ok=1; }
  return $ok
}

# =============================================================================
# meta-02: the verifier role's access is corrected from readonly to readwrite
# -- it merges into spdd/specs/, moves approved changes to spdd/archive/,
# and appends spdd/changes/<slug>/REJECTED.md. name and description stay
# unchanged.
# =============================================================================
test_meta_02() {
  ok=0
  [ "$(meta_field "$META_VERIFIER" access)" = "readwrite" ] \
    || { echo "  verifier access is not readwrite: $(meta_field "$META_VERIFIER" access)"; ok=1; }
  refuse "$META_VERIFIER" 'access: readonly' || ok=1
  [ "$(meta_field "$META_VERIFIER" name)" = "antz-verifier" ] \
    || { echo "  verifier name changed: $(meta_field "$META_VERIFIER" name)"; ok=1; }
  [ "$(meta_field "$META_VERIFIER" description)" = "QA agent. Validates the coder's work against spdd/changes/ Gherkin sub-specs and the end-to-end QA suite. Merges approved changes into spdd/specs/ and archives them." ] \
    || { echo "  verifier description changed"; ok=1; }
  return $ok
}

# =============================================================================
# meta-03: the other two roles are untouched -- coder stays readwrite,
# orchestrator stays orchestrateonly, byte-for-byte unchanged.
# =============================================================================
test_meta_03() {
  ok=0
  [ "$(meta_field "$META_CODER" access)" = "readwrite" ] \
    || { echo "  coder access is not readwrite"; ok=1; }
  [ "$(meta_field "$META_ORCHESTRATOR" access)" = "orchestrateonly" ] \
    || { echo "  orchestrator access is not orchestrateonly"; ok=1; }
  byte_identical_to_head "$META_CODER" \
    || { echo "  agents/meta/coder.yaml differs from HEAD (must be byte-for-byte unchanged)"; ok=1; }
  byte_identical_to_head "$META_ORCHESTRATOR" \
    || { echo "  agents/meta/orchestrator.yaml differs from HEAD (must be byte-for-byte unchanged)"; ok=1; }
  return $ok
}

# =============================================================================
# render fixtures: install.sh's render path is exercised the way
# tests/installsh-posixsh_test.sh does it -- `sh install.sh --all` against
# isolated temp HOMEs and staged local checkouts, never the real ~/.claude or
# ~/.config/opencode. Rendered output is deterministic from (prompt body,
# meta access, source VERSION); the staged checkouts below vary exactly one
# input at a time so each comparison isolates the meta access change.
# =============================================================================

# stage_checkout <dest>: materializes a minimal install.sh checkout at <dest>
# from the working tree -- install.sh, VERSION, CHANGELOG.md, and the whole
# agents/ tree -- so `sh <dest>/install.sh --all` renders from the staged
# tree (install.sh resolves sources relative to its own directory).
stage_checkout() {
  dest="$1"
  mkdir -p "$dest"
  cp "$INSTALL_SH" "$dest/install.sh"
  cp "$SCRIPT_DIR/VERSION" "$dest/VERSION"
  cp "$SCRIPT_DIR/CHANGELOG.md" "$dest/CHANGELOG.md"
  mkdir -p "$dest/agents/prompts" "$dest/agents/meta" "$dest/scripts/orchestration"
  cp "$SCRIPT_DIR"/agents/prompts/*.prompt "$dest/agents/prompts/"
  cp "$SCRIPT_DIR"/agents/meta/*.yaml "$dest/agents/meta/"
  # The orchestrator prompt's include markers are substituted from
  # scripts/orchestration/ at render time (orchestrator-fast-path), so the
  # staged tree must carry them or the render fails.
  cp "$SCRIPT_DIR"/scripts/orchestration/*.sh "$dest/scripts/orchestration/"
}

# head_meta_at <path>: overwrites the staged meta file at <path> with git
# HEAD's copy (the pre-change values -- HEAD also holds this change's base
# for specifier/verifier, and byte-identical copies for coder/orchestrator).
head_meta_at() {
  git -C "$SCRIPT_DIR" show "HEAD:agents/meta/$(basename -- "$1")" > "$1"
}

# render_tree <home> <staged-checkout-dir> <log>: renders all four agents for
# both clients into <home> via install.sh's real render path.
render_tree() {
  home="$1"; tree="$2"; log="$3"
  mkdir -p "$home"
  HOME="$home" sh "$tree/install.sh" --all > "$log" 2>&1
}

# The monthly fixture, rendered lazily on first use:
#   RENDER_HOME      -- working tree as-is (readwrite specifier/verifier)
#   HEADMETA_HOME    -- identical checkout but meta files from git HEAD
#                       (pre-change readonly), so every rendered artifact
#                       pair differs only by the meta access values
#   READONLY_HOME    -- identical checkout but every meta file forced to
#                       access: readonly, exercising the readonly mapping
#                       branches (render-04)
RENDER_HOME="" HEADMETA_HOME="" READONLY_HOME=""

ensure_render_fixtures() {
  [ -n "$RENDER_HOME" ] && return 0
  render_home_root=$(new_tmp_dir)
  headmeta_root=$(new_tmp_dir)
  readonly_root=$(new_tmp_dir)
  RENDER_HOME="$render_home_root/home"
  HEADMETA_HOME="$headmeta_root/home"
  READONLY_HOME="$readonly_root/home"

  render_tree "$RENDER_HOME" "$SCRIPT_DIR" "$render_home_root/render.log" \
    || { echo "  working-tree render failed:"; cat "$render_home_root/render.log"; return 1; }

  stage_checkout "$headmeta_root/tree"
  for staged_role in specifier coder verifier orchestrator; do
    head_meta_at "$headmeta_root/tree/agents/meta/$staged_role.yaml"
  done
  render_tree "$HEADMETA_HOME" "$headmeta_root/tree" "$headmeta_root/render.log" \
    || { echo "  HEAD-meta render failed:"; cat "$headmeta_root/render.log"; return 1; }

  stage_checkout "$readonly_root/tree"
  for staged_role in specifier coder verifier orchestrator; do
    sed -i 's/^access: .*/access: readonly/' "$readonly_root/tree/agents/meta/$staged_role.yaml"
  done
  render_tree "$READONLY_HOME" "$readonly_root/tree" "$readonly_root/render.log" \
    || { echo "  readonly render failed:"; cat "$readonly_root/render.log"; return 1; }

  return 0
}

# The unchanged marker format (the fixed invariant text install.sh prints
# into every rendered file's frontmatter).
MARKER_LINE_PREFIX='# antz:generated version='
MARKER_LINE_SUFFIX=' -- do not edit by hand; regenerate with install.sh'

# agent_md <home> <client> <role>: the rendered agent file path.
agent_md() {
  case "$2" in
    claude) printf '%s/.claude/agents/antz-%s.md' "$1" "$3" ;;
    opencode) printf '%s/.config/opencode/agents/antz-%s.md' "$1" "$3" ;;
  esac
}

# render-01: the corrected roles render on Claude Code with Edit and Write
# granted -- and, since the skills-activation change MODIFIED this contract,
# the readwrite tools string now ends in Skill (tests/
# skills-activation-render_test.sh owns that mapping's render-level tests).
test_render_01() {
  role="$1"
  ensure_render_fixtures || return 1
  f=$(agent_md "$RENDER_HOME" claude "$role")
  [ -f "$f" ] || { echo "  missing rendered file: $f"; return 1; }
  [ "$(sed -n 's/^tools: //p' "$f")" = "Read, Grep, Glob, Bash, Edit, Write, Skill" ] \
    || { echo "  tools line is: $(sed -n 's/^tools: //p' "$f")"; return 1; }
  grep -qF -- "${MARKER_LINE_PREFIX}" "$f" || { echo "  marker version prefix missing"; return 1; }
  grep -qF -- "$MARKER_LINE_SUFFIX" "$f" || { echo "  marker suffix missing"; return 1; }
  return 0
}

# render-02: the corrected roles render on OpenCode with edit allowed, task
# delegation denied, subagent mode kept.
test_render_02() {
  role="$1"
  ensure_render_fixtures || return 1
  f=$(agent_md "$RENDER_HOME" opencode "$role")
  [ -f "$f" ] || { echo "  missing rendered file: $f"; return 1; }
  require "$f" 'mode: subagent' || return 1
  require "$f" '  edit: allow' || return 1
  require "$f" '  task: deny' || return 1
  return 0
}

# render-03: regression guard -- coder and orchestrator renders are
# byte-for-byte identical to rendering the pre-change meta files, for both
# clients. The staged HEAD-meta checkout shares everything else with the
# working-tree render (prompts, VERSION, CHANGELOG.md, install.sh), so any
# difference is attributable to a meta change -- which must not exist for
# these two roles.
test_render_03() {
  ensure_render_fixtures || return 1
  ok=0
  for client in claude opencode; do
    for role in coder orchestrator; do
      a=$(agent_md "$RENDER_HOME" "$client" "$role")
      b=$(agent_md "$HEADMETA_HOME" "$client" "$role")
      if ! cmp -s "$a" "$b"; then
        echo "  render differs from HEAD-meta render: $client/$role"
        diff "$b" "$a" | head -5
        ok=1
      fi
    done
  done
  return $ok
}

# render-04: the readonly mapping semantics are preserved in install.sh even
# though no meta file declares readonly anymore. Two proofs: (a) install.sh
# is byte-for-byte identical to git HEAD (the mapping functions cannot have
# changed behavior), and (b) functionally, rendering a readonly meta file
# produces exactly the readonly grants on both clients, in the unchanged
# marker format.
test_render_04() {
  ok=0
  # The skills-activation change legitimately modified only the readwrite
  # branch of claude_tools_for_access; pin the unchanged branches
  # functionally, line-anchored in install.sh (the old byte-identical-to-HEAD
  # install.sh guard no longer applies to any post-skills-activation tree).
  grep -qF 'readonly) printf '"'"'Read, Grep, Glob, Bash'"'"' ;;' "$INSTALL_SH" \
    || { echo "  readonly mapping line changed in install.sh"; ok=1; }
  grep -qF 'orchestrateonly) printf '"'"'Read, Grep, Glob, Bash, Agent'"'"' ;;' "$INSTALL_SH" \
    || { echo "  orchestrateonly mapping line changed in install.sh"; ok=1; }
  ensure_render_fixtures || return 1
  cf=$(agent_md "$READONLY_HOME" claude specifier)
  of=$(agent_md "$READONLY_HOME" opencode specifier)
  [ "$(sed -n 's/^tools: //p' "$cf")" = "Read, Grep, Glob, Bash" ] \
    || { echo "  readonly tools line is: $(sed -n 's/^tools: //p' "$cf")"; ok=1; }
  # The tools line itself must grant neither Edit nor Write (the prompt body
  # legitimately mentions those words; anchor the refusal on the line).
  sed -n 's/^tools: //p' "$cf" | grep -q 'Edit' && { echo "  readonly tools line grants Edit"; ok=1; }
  sed -n 's/^tools: //p' "$cf" | grep -q 'Write' && { echo "  readonly tools line grants Write"; ok=1; }
  require "$of" 'mode: subagent' || ok=1
  require "$of" '  edit: deny' || ok=1
  require "$of" '  task: deny' || ok=1
  grep -qF -- "$MARKER_LINE_PREFIX" "$cf" || { echo "  marker version prefix missing in readonly render"; ok=1; }
  grep -qF -- "$MARKER_LINE_SUFFIX" "$cf" || { echo "  marker suffix missing in readonly render"; ok=1; }
  return $ok
}


# =============================================================================
# docs-01: AGENTS.md's access-model gotcha states the corrected model --
# specifier/coder/verifier all readwrite with their prompt-owned artifact
# surfaces, orchestrator stays orchestrateonly, boundary at prompt level
# (path ownership + never-commits), and the old wrong claims are gone from
# the bullet.
# =============================================================================
test_docs_01() {
  ok=0
  [ -s "$AGENTS_ACCESS_BULLET" ] || { echo "  AGENTS.md has no access-model gotcha bullet"; return 1; }
  require "$AGENTS_ACCESS_BULLET" 'The specifier, coder, and verifier roles are all `readwrite`' || ok=1
  require "$AGENTS_ACCESS_BULLET" 'edit capability, each for its own prompt-owned artifact surfaces' || ok=1
  require "$AGENTS_ACCESS_BULLET" 'the specifier authors `spdd/changes/<slug>/`' || ok=1
  require "$AGENTS_ACCESS_BULLET" 'the coder implements sub-specs' || ok=1
  require "$AGENTS_ACCESS_BULLET" 'the verifier merges into `spdd/specs/` and owns `spdd/archive/` moves and `REJECTED.md` appends' || ok=1
  require "$AGENTS_ACCESS_BULLET" 'the orchestrator role remains `orchestrateonly`' || ok=1
  require "$AGENTS_ACCESS_BULLET" 'readonly-equivalent tools plus a delegation capability, used only by it' || ok=1
  require "$AGENTS_ACCESS_BULLET" 'prompt-level path ownership per role plus the never-commits law, not tool absence' || ok=1
  require "$AGENTS_ACCESS_BULLET" 'framework permissions cannot scope edits to paths' || ok=1
  require "$AGENTS_ACCESS_BULLET" 'granting Edit/Write grants artifact authorship, never commit authority' || ok=1
  refuse "$AGENTS_ACCESS_BULLET" 'are `readonly`' || ok=1
  refuse "$AGENTS_ACCESS_BULLET" 'the only role that modifies files' || ok=1
  refuse "$AGENTS_ACCESS_BULLET" 'no edit/write capability' || ok=1
  return $ok
}

# =============================================================================
# docs-02: CLAUDE.md states the identical corrected model -- the access-model
# gotcha bullet is byte-identical between AGENTS.md and CLAUDE.md (the two
# policy docs duplicate each other and must not fork on this bullet).
# =============================================================================
test_docs_02() {
  ok=0
  [ -s "$AGENTS_ACCESS_BULLET" ] || { echo "  AGENTS.md has no access-model gotcha bullet"; ok=1; }
  [ -s "$CLAUDE_ACCESS_BULLET" ] || { echo "  CLAUDE.md has no access-model gotcha bullet"; ok=1; }
  ok=$([ $ok -eq 0 ] && echo 1 || echo 0); ok=0
  cmp -s "$AGENTS_ACCESS_BULLET" "$CLAUDE_ACCESS_BULLET" \
    || { echo "  access-model gotcha bullet differs between AGENTS.md and CLAUDE.md"; diff "$AGENTS_ACCESS_BULLET" "$CLAUDE_ACCESS_BULLET" | head -4; ok=1; }
  require "$CLAUDE_ACCESS_BULLET" 'The specifier, coder, and verifier roles are all `readwrite`' || ok=1
  require "$CLAUDE_ACCESS_BULLET" 'prompt-level path ownership per role plus the never-commits law, not tool absence' || ok=1
  return $ok
}

# =============================================================================
# docs-03: the wrong claim is gone everywhere in both policy docs, not only
# from the gotcha bullet -- no role-attributed readonly statement, no
# "only role that modifies files", and no "no edit/write capability" in the
# Gotchas text; the Client Integration mapping description still states the
# three levels, now noting that after this change no role declares readonly
# while install.sh keeps the mapping.
# =============================================================================
test_docs_03() {
  ok=0
  for f in "$AGENTS_MD" "$CLAUDE_MD"; do
    refuse "$f" 'roles are `readonly`' || ok=1
    refuse "$f" 'are `readonly` (no edit/write capability)' || ok=1
    refuse "$f" 'the only role that modifies files' || ok=1
  done
  refuse "$AGENTS_GOTCHAS" 'no edit/write capability' || ok=1
  refuse "$CLAUDE_GOTCHAS" 'no edit/write capability' || ok=1
  for f in "$AGENTS_MD" "$CLAUDE_MD"; do
    require "$f" '`access: readonly` maps to no edit/write capability' || ok=1
    require "$f" '`access: readwrite` maps to full edit access' || ok=1
    require "$f" '`access: orchestrateonly` maps to readonly plus a delegation capability' || ok=1
    require "$f" 'After this change no role declares `readonly`' || ok=1
    require "$f" 'but `install.sh` keeps the mapping' || ok=1
  done
  return $ok
}

# =============================================================================
# docs-04: docs/orchestrator.md's delegation-scoping paragraph no longer
# states that a specifier/verifier readonly boundary is real, while keeping
# the verified platform fact (Claude Code's subagent tools: list is a
# strict, enforced allowlist).
# =============================================================================
test_docs_04() {
  ok=0
  require "$ORCHESTRATOR_MD" "a subagent's \`tools:\` list is a strict, enforced allowlist" || ok=1
  require "$ORCHESTRATOR_MD" 'which is why the old readonly denial was real' || ok=1
  refuse "$ORCHESTRATOR_MD" 'readonly boundary is real' || ok=1
  refuse "$ORCHESTRATOR_MD" '`specifier`/`verifier` readonly boundary' || ok=1
  return $ok
}

# =============================================================================
# bump-01: the bump is present -- CHANGELOG.md gains a [4.1.0] - 2026-09-11
# section layered above the [4.0.0] section, describing the access-model
# correction, the unchanged coder/orchestrator render, the retained readonly
# mapping, and the docs correction. VERSION is NOT a byte-pinned literal:
# the repo recorded lesson (tests/docs-bump_test.sh comments) is that a
# cross-change pin breaks on the next legitimate bump (it broke exactly here
# when Change skills-activation bumped VERSION to 4.2.0), so the test instead
# asserts VERSION is a semver agreeing with the newest (topmost) CHANGELOG
# entry, which is this change's own [4.1.0] entry at bump time.
# =============================================================================
test_bump_01() {
  ok=0
  # VERSION is a semver (X.Y.Z) agreeing with the newest CHANGELOG entry.
  version=$(cat "$VERSION_FILE")
  if ! printf '%s' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "  VERSION reads '$version', not a semver (X.Y.Z)"; ok=1
  fi
  newest=$(sed -n 's/^## \[\([^]]*\)\].*/\1/p' "$CHANGELOG_MD" | head -n 1)
  if [ "$version" != "$newest" ]; then
    echo "  VERSION reads '$version' but the newest CHANGELOG entry is '$newest'"; ok=1
  fi
  # The [4.1.0] section exists and sits above [4.0.0].
  line_410=$(grep -nF '## [4.1.0] - 2026-09-11' "$CHANGELOG_MD" | head -n 1 | cut -d: -f1)
  line_400=$(grep -nF '## [4.0.0]' "$CHANGELOG_MD" | head -n 1 | cut -d: -f1)
  if [ -z "${line_410:-}" ]; then echo "  missing '## [4.1.0] - 2026-09-11' in CHANGELOG.md"; ok=1; fi
  if [ -z "${line_400:-}" ]; then echo "  missing '## [4.0.0]' in CHANGELOG.md"; ok=1; fi
  if [ -n "${line_410:-}" ] && [ -n "${line_400:-}" ] && [ "$line_410" -ge "$line_400" ]; then
    echo "  '## [4.1.0]' does not sit above '## [4.0.0]'"; ok=1
  fi
  return $ok
}

# =============================================================================
# bump-02: the [4.1.0] entry states the grade against the versioning table:
# minor (rendered-agent behavior change) and explicitly not major (taxonomy,
# mapping, marker format, layout, install locations all unchanged).
# =============================================================================
test_bump_02() {
  ok=0
  # The 4.1.0 section (header down to the next "## [" section) states both.
  sed -n '/^## \[4\.1\.0\]/,/^## \[/{/^## \[4\.1\.0\]/d;p}' "$CHANGELOG_MD" > "$BUMP_410_SECTION"
  require "$BUMP_410_SECTION" 'minor' || ok=1
  require "$BUMP_410_SECTION" 'major' || ok=1
  require "$BUMP_410_SECTION" 'readwrite' || ok=1
  for phrase in 'not major' 'marker format' 'install location'; do
    require "$BUMP_410_SECTION" "$phrase" || ok=1
  done
  return $ok
}

# =============================================================================
# bump-03: this change's shared-file edits are strictly additive over the
# pending flow-branch-checkout edits -- never reverting them. The pending
# content survives: the [4.0.0] section, the flow-branch gotcha wording in
# both policy docs, the orchestrator.prompt / antz-flow changes, and
# tests/antz-flow_test.sh are all still present.
# =============================================================================
test_bump_03() {
  ok=0
  # The pending [4.0.0] section's content survives untouched above.
  require "$CHANGELOG_MD" '**Breaking (workflow contract): the flow'"'"'s session now sits on the marker branch.**' || ok=1
  require "$CHANGELOG_MD" 'state=checkout_refused' || ok=1
  require "$CHANGELOG_MD" 'state=no_branch' || ok=1
  # The flow-branch gotcha wording survives in both policy docs.
  require "$AGENTS_MD" 'Branch-marked flow, never committed' || ok=1
  require "$CLAUDE_MD" 'Branch-marked flow, never committed' || ok=1
  require "$AGENTS_MD" 'state=checkout_refused' || ok=1
  require "$CLAUDE_MD" 'state=checkout_refused' || ok=1
  # The pending orchestrator.prompt / antz-flow changes survive.
  require "$ORCHESTRATOR_PROMPT" 'checkout_refused' || ok=1
  require "$ANTZ_FLOW_TEST" 'state=checkout_refused' || ok=1
  return $ok
}

# ---- run everything ---------------------------------------------------------

run_test "meta-01: agents/meta/specifier.yaml declares access: readwrite (name/description unchanged)" test_meta_01
run_test "meta-02: agents/meta/verifier.yaml declares access: readwrite (name/description unchanged)" test_meta_02
run_test "meta-03: coder.yaml stays access: readwrite and orchestrator.yaml stays access: orchestrateonly, byte-for-byte unchanged" test_meta_03

run_test "render-01 (specifier): Claude render of agents/meta/specifier.yaml carries tools: Read, Grep, Glob, Bash, Edit, Write, Skill" test_render_01 specifier
run_test "render-01 (verifier): Claude render of agents/meta/verifier.yaml carries tools: Read, Grep, Glob, Bash, Edit, Write, Skill" test_render_01 verifier
run_test "render-02 (specifier): OpenCode render of agents/meta/specifier.yaml carries mode: subagent, edit: allow, task: deny" test_render_02 specifier
run_test "render-02 (verifier): OpenCode render of agents/meta/verifier.yaml carries mode: subagent, edit: allow, task: deny" test_render_02 verifier
run_test "render-03: coder and orchestrator renders are byte-identical to rendering the pre-change meta files, both clients" test_render_03
run_test "render-04: readonly mapping unchanged (install.sh byte-identical to HEAD) and still maps to Read/Grep/Glob/Bash, edit: deny, task: deny" test_render_04

run_test "docs-01: AGENTS.md's access-model gotcha states specifier/coder/verifier readwrite with prompt-owned artifact surfaces, orchestrator orchestrateonly, prompt-level boundary + never-commits" test_docs_01
run_test "docs-02: CLAUDE.md states the identical corrected model -- the access-model gotcha bullet is byte-identical between AGENTS.md and CLAUDE.md" test_docs_02
run_test "docs-03: the wrong claims are gone from both policy docs everywhere; Client Integration keeps the mapping levels with the no-role-declares-readonly note" test_docs_03
run_test "docs-04: docs/orchestrator.md keeps the verified tools-allowlist fact and no longer states a specifier/verifier readonly boundary is real" test_docs_04

run_test "bump-01: CHANGELOG.md carries [4.1.0] - 2026-09-11 above [4.0.0] and VERSION is a semver agreeing with the newest entry (never a pinned literal)" test_bump_01
run_test "bump-02: the [4.1.0] entry grades minor (rendered-agent behavior change) and not major (taxonomy/mapping/marker/layout/locations unchanged)" test_bump_02
run_test "bump-03: the shared-file edits are strictly additive -- flow-branch-checkout's pending [4.0.0] section, docs wording, orchestrator.prompt and antz-flow test all survive" test_bump_03

# ---- e2e-only scenarios: explicit SKIP stubs ---------------------------------
# e2e-meta-01..02 (spdd/changes/specifier-write-access/01-meta.feature),
# e2e-render-01..02 (02-render.feature), and e2e-docs-01 (03-docs.feature)
# operate at the user's machine-level UI (installed agent files under the
# real ~, or reading the docs at the user surface) -- e2e only, run by the
# verifier. Explicit stubs so every scenario id is accounted for.

E2E_REASON="e2e-only: requires invoking the installed agents, run by the verifier (01-meta.feature)"
E2E_RENDER_REASON="e2e-only: requires running install.sh's CLI against the user's real HOME, run by the verifier (02-render.feature)"
E2E_DOCS_REASON="e2e-only: operates at the user-visible reading surface, run by the verifier (03-docs.feature)"
E2E_BUMP_REASON="e2e-only: reads VERSION/CHANGELOG.md and install.sh --check at the user surface for the 4.1.0 drift report, run by the verifier (04-bump.feature)"

skip_test "e2e-meta-01: a specifier invocation actually writes spdd/changes/<slug>/ artifacts (no silent no-op for lack of edit permission)" "$E2E_REASON"
skip_test "e2e-meta-02: a verifier invocation actually writes (spec merge + archive move, or a REJECTED.md append; no silent no-op)" "$E2E_REASON"
skip_test "e2e-render-01: ./install.sh --all overwrites the hand-patched temporary edit grants with the real renders, marker format unchanged" "$E2E_RENDER_REASON"
skip_test "e2e-render-02: ./install.sh --check reports the drift and prints the changelog before reinstall, and reports up to date after" "$E2E_RENDER_REASON"
skip_test "e2e-docs-01: a user reading the docs derives the real access model, with no contradiction left against the meta files or the roles' prompts" "$E2E_DOCS_REASON"
skip_test "e2e-bump-01: ./install.sh --check against pre-change installed copies reports the drift to 4.1.0 and prints the [4.1.0] entry; VERSION and the top CHANGELOG section agree" "$E2E_BUMP_REASON"

echo ""
echo "$pass_count passed, $fail_count failed, $skip_count skipped (e2e-only, see 01-meta.feature, 02-render.feature, 03-docs.feature, and 04-bump.feature)"
[ "$fail_count" -eq 0 ]
