#!/usr/bin/env bash
# Unit tests for the delegation skills block added to
# agents/prompts/orchestrator.prompt (sub-spec
# spdd/changes/skills-activation/02-orchestrator.feature,
# scenarios orchestrator-01..04).
#
# The block is produced by an embedded POSIX sh snippet (the same temp-file
# convention as the flow script and the status probe), so the tests assert
# both halves of the contract:
#   - the prompt text carries the block's duty, explicit none-matched line,
#     and implementation constraints (orchestrator-01, -02 wording, -04), and
#   - the extracted snippet genuinely derives absolute SKILL.md paths from
#     the standard skills directories with the capped, tie-broken, keyword-
#     reasoned matching the scenarios demand (orchestrator-01..03 runtime).
#
# Self-contained bash test harness (no external framework/dependency -- this
# repo has no package manager or build system), mirroring the harness style
# of tests/orchestrator-status-probe_test.sh. Run directly:
#   ./tests/orchestrator-skills-block_test.sh
#
# Every reported test name embeds its scenario id so a failure maps straight
# back to the scenario it covers. All filesystem work happens in temp dirs;
# e2e-orchestrator-01 requires live orchestrated /antz sessions and is
# reported as an explicit SKIP stub (the verifier's end-to-end suite).
#
# Evolved by change skills-desc-match (spdd/changes/skills-desc-match/
# 01-descmatch.feature, scenarios descmatch-01..05): matching is keyed to the
# description field only (name/license/metadata-only keywords are no-matches),
# folded block scalars ('>' / '>-') accumulate their indented continuation
# lines into the match text, and the additive-vs-HEAD guard is scoped --
# removed lines are permitted only inside the antz-skills.sh fenced snippet.
# descmatch-04 (the change-time diff-scope check against the pre-change tree)
# is a transient verification, not a permanent regression test: explicit SKIP
# stub, verified by the coder at implementation time.

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ORCHESTRATOR_PROMPT="$SCRIPT_DIR/agents/prompts/orchestrator.prompt"

pass_count=0
fail_count=0
skip_count=0

# ---- tiny test runner ------------------------------------------------------

run_test() {
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

tmp_files=()
new_tmp() {
  f=$(mktemp)
  tmp_files+=("$f")
  printf '%s' "$f"
}

tmp_dirs=()
new_tmp_dir() {
  d=$(mktemp -d)
  tmp_dirs+=("$d")
  printf '%s' "$d"
}

cleanup() {
  for f in "${tmp_files[@]:-}"; do [ -n "$f" ] && rm -f "$f"; done
  for d in "${tmp_dirs[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done
  return 0
}
trap cleanup EXIT

# ---- extracting the embedded snippet from the prompt ------------------------

SKILLS_SCRIPT=$(new_tmp)
# The snippet is fenced with a plain fence (like antz-flow.sh) and carries
# its own "# antz-skills.sh" marker comment; extract marker-to-fence-close.
awk '
  /^ *# antz-skills.sh/ { s = 1 }
  s && /^ *```$/ { exit }
  s { print }
' "$ORCHESTRATOR_PROMPT" | sed 's/^   //' > "$SKILLS_SCRIPT"

# ---- fixture helpers --------------------------------------------------------

add_skill() {
  # $1 = skills dir (e.g. <root>/.claude/skills), $2 = skill name, $3 = desc
  mkdir -p "$1"
  printf -- '---\nname: %s\ndescription: %s\n---\n\nFixture body.\n' "$2" "$3" \
    > "$1/SKILL.md"
}

add_skill_fm() {
  # $1 = skill dir, $2 = full frontmatter body (the lines between the ---
  # fences, one string with embedded newlines), $3 (optional) = body text
  # below the frontmatter. For fixtures whose frontmatter carries keys the
  # simple add_skill cannot express (block scalars, license:, metadata:).
  mkdir -p "$1"
  { printf -- '---\n'
    printf '%s\n' "$2"
    printf -- '---\n\n%s\n' "${3:-Fixture body.}"
  } > "$1/SKILL.md"
}

run_snippet() {
  # Runs the extracted snippet with HOME pointed at a temp home.
  # $1 = temp home, $2 = working root, remaining args = match keywords.
  h="$1"; shift
  HOME="$h" sh "$SKILLS_SCRIPT" "$@"
}

# ---- descmatch-05: the snippet-scoped additive-vs-HEAD guard -----------------
# The antz-skills.sh snippet's lines legitimately change (the descmatch fix
# edits them), so the old "no removed lines at all" assertion no longer
# holds. The guard is scoped: a removed line is permitted only when it lies
# inside the antz-skills.sh fenced snippet -- judged by its old-side line
# number against the old (HEAD) copy's snippet region, or by its new-side
# position against the working-tree copy's region (whichever side carries a
# located snippet; 0/0 disables a side's check). Any removal outside the
# snippet still fails the guard.

region_start=0
region_end=0
compute_snippet_region() {
  # $1 = file holding the prompt text; sets region_start/region_end to the
  # antz-skills.sh fenced snippet's line range (0/0 when it has no snippet).
  region_start=0
  region_end=0
  local marker open close
  marker=$(grep -n '^ *# antz-skills.sh' "$1" | head -n 1 | cut -d: -f1)
  [ -n "$marker" ] || return 0
  open=$(awk -v m="$marker" 'NR < m && /^ *```$/ { l = NR } END { print l + 0 }' "$1")
  close=$(awk -v m="$marker" 'NR > m && /^ *```$/ { print NR; exit }' "$1")
  [ -n "$open" ] && [ "$open" -gt 0 ] || open=$marker
  if [ -n "$close" ] && [ "$close" -gt "$open" ]; then
    region_start=$open
    region_end=$close
  fi
  return 0
}

removals_outside_snippet() {
  # $1 = unified diff file; $2..$5 = os oe ns ne (old/new snippet regions,
  # 0 disables that side). Prints every removed diff line that lies outside
  # the snippet on both sides; empty output means the guard passes.
  awk -v os="$2" -v oe="$3" -v ns="$4" -v ne="$5" '
    /^@@ / {
      old = $2; new = $3
      sub(/^-/, "", old); sub(/^\+/, "", new)
      split(old, a, ","); oline = a[1] + 0
      split(new, b, ","); nline = b[1] + 0
      next
    }
    /^---/ { next }
    /^\+\+\+/ { next }
    /^\\/ { next }
    /^\+/ { nline++; next }
    /^-/ {
      inside = 0
      if (os > 0 && oline >= os && oline <= oe) inside = 1
      if (ns > 0 && nline >= ns && nline <= ne) inside = 1
      if (!inside) print
      oline++
      next
    }
    /^ / { oline++; nline++; next }
  ' "$1"
}

# =============================================================================
# orchestrator-01: every delegation gains the "## Skills to load before work"
# block -- present in the prompt's delegation preamble, additive only, with
# the absolute-verbatim-SKILL.md-path rule and the standard directories.
# =============================================================================
test_orchestrator_01_block() {
  ok=0
  require "$ORCHESTRATOR_PROMPT" '## Skills to load before work' || ok=1
  require "$ORCHESTRATOR_PROMPT" 'at delegation time' || ok=1
  # Absolute paths passed verbatim, never summarized.
  require "$ORCHESTRATOR_PROMPT" 'absolute `SKILL.md` paths verbatim' || ok=1
  require "$ORCHESTRATOR_PROMPT" 'paths, not summaries' || ok=1
  # Derived from disk per delegation; never cached or persisted under spdd/.
  require "$ORCHESTRATOR_PROMPT" 'never cached across changes' || ok=1
  require "$ORCHESTRATOR_PROMPT" 'never persisted anywhere' || ok=1
  # The standard skills directories of the working root and the user's home.
  for dir in '.agents/skills/' '~/.agents/skills/' '.claude/skills/' \
             '~/.claude/skills/' '.opencode/skills/' \
             '~/.config/opencode/skills/'; do
    require "$ORCHESTRATOR_PROMPT" "$dir" || ok=1
  done
  # Present in every delegation, specifier/coder/verifier alike.
  require "$ORCHESTRATOR_PROMPT" 'every delegation' || ok=1

  # The two pre-existing preamble lines survive verbatim.
  require "$ORCHESTRATOR_PROMPT" 'Working root: <repo root absolute path>' || ok=1
  require "$ORCHESTRATOR_PROMPT" 'Change slug: <slug>' || ok=1

  # The addition is additive except inside the antz-skills.sh fenced
  # snippet (descmatch-05): removed lines are permitted only inside it --
  # any removal outside the snippet still fails the guard.
  if command -v git >/dev/null 2>&1 && [ -e "$SCRIPT_DIR/.git" ]; then
    diff_file=$(new_tmp)
    git -C "$SCRIPT_DIR" diff HEAD -- agents/prompts/orchestrator.prompt > "$diff_file" \
      || { echo "  git diff failed"; ok=1; }
    compute_snippet_region "$ORCHESTRATOR_PROMPT"
    ns=$region_start; ne=$region_end
    os=0; oe=0
    if git -C "$SCRIPT_DIR" cat-file -e HEAD:agents/prompts/orchestrator.prompt 2>/dev/null; then
      head_prompt=$(new_tmp)
      git -C "$SCRIPT_DIR" show HEAD:agents/prompts/orchestrator.prompt > "$head_prompt" 2>/dev/null
      compute_snippet_region "$head_prompt"
      os=$region_start; oe=$region_end
    fi
    bad=$(removals_outside_snippet "$diff_file" "$os" "$oe" "$ns" "$ne")
    if [ -n "$bad" ]; then
      echo "  orchestrator.prompt has removed lines outside the antz-skills.sh snippet:"
      printf '%s\n' "$bad"
      ok=1
    fi
  fi
  return $ok
}

# =============================================================================
# orchestrator-01 (runtime): the derived listing carries absolute SKILL.md
# paths resolved from disk at delegation time -- re-derived fresh, never
# cached across delegations.
# =============================================================================
test_orchestrator_01_derivation_fresh() {
  root=$(new_tmp_dir); home=$(new_tmp_dir)
  ok=0

  add_skill "$root/.agents/skills/fixtureskill" "fixtureskill" \
    "Fixture skill about fixtureskill work"

  out=$(run_snippet "$home" "$root" fixtureskill)
  echo "$out" | grep -qF "path=$root/.agents/skills/fixtureskill/SKILL.md" \
    || { echo "  project-dir skill not derived with absolute path: $out"; ok=1; }

  # Re-derivation: a skill appearing on disk between delegations is picked
  # up by the next run (nothing is cached across delegations).
  add_skill "$home/.claude/skills/home-skill" "home-skill" "Fixture mentioning fixtureskill late"
  out2=$(run_snippet "$home" "$root" fixtureskill)
  echo "$out2" | grep -qF "path=$home/.claude/skills/home-skill/SKILL.md" \
    || { echo "  re-derivation did not pick up the new disk state: $out2"; ok=1; }

  return $ok
}

# =============================================================================
# orchestrator-02: the matching is mechanical and driven by each skill's own
# description against the delegated task's keywords; at most five best
# matches travel, ordered with a deterministic alphabetical tie-break; each
# entry's match reason is legible.
# =============================================================================
test_orchestrator_02_matching_cap_tiebreak() {
  root=$(new_tmp_dir); home=$(new_tmp_dir)
  ok=0

  # Description-keyed matching: only the description's own content matches.
  add_skill "$root/.agents/skills/angular-conventions" "angular-conventions" \
    "Mandatory Angular conventions for .ts and .html Angular code"
  add_skill "$root/.claude/skills/toml-style" "toml-style" \
    "Formatting rules for .toml files"
  out=$(run_snippet "$home" "$root" toml)
  echo "$out" | grep -qF 'path='"$root"'/../.claude/skills/toml-style/SKILL.md' && ok_missing=0
  echo "$out" | grep -qF "path=$root/.claude/skills/toml-style/SKILL.md" \
    || { echo "  matching keyword did not select the toml skill: $out"; ok=1; }
  echo "$out" | grep -qF 'angular-conventions' \
    && { echo "  unmatching skill was listed: $out"; ok=1; }

  # Cap at five, alphabetical among equal scores.
  for n in f e d c b a; do
    add_skill "$root/.claude/skills/skill-$n" "skill-$n" "covers capping work widely"
  done
  out=$(run_snippet "$home" "$root" capping)
  count=$(printf '%s\n' "$out" | grep -c '^skill=' || true)
  [ "$count" -eq 5 ] || { echo "  expected 5 matched skills (capped), got $count: $out"; ok=1; }
  first=$(printf '%s\n' "$out" | grep '^skill=' | head -n1)
  case "$first" in
    skill=skill-a*) ;;
    *) echo "  alphabetical tie-break violated (first: $first)"; ok=1 ;;
  esac
  printf '%s\n' "$out" | grep -qF 'skill-f' \
    && { echo "  cap ignored: a sixth skill got through: $out"; ok=1; }

  # Deterministic ordering: identical runs, byte-identical output.
  out1=$(run_snippet "$home" "$root" capping)
  out2=$(run_snippet "$home" "$root" capping)
  [ "$out1" = "$out2" ] || { echo "  ordering is not deterministic between runs"; ok=1; }

  # Match reason legible: each entry names the keyword(s) it matched.
  echo "$out1" | grep -qF 'matched=capping' \
    || { echo "  entry lacks its matched-keyword reason: $out1"; ok=1; }

  return $ok
}

# =============================================================================
# orchestrator-03: no-match is explicit, never silent -- "Skills: none
# matched" when nothing matches, and the same explicit line when no skills
# directory exists at all.
# =============================================================================
test_orchestrator_03_none_matched_explicit() {
  root=$(new_tmp_dir); home=$(new_tmp_dir)
  ok=0

  # A skills directory exists but no description matches the keyword.
  add_skill "$root/.agents/skills/angular-conventions" "angular-conventions" \
    "Mandatory Angular conventions for Angular code"
  out=$(run_snippet "$home" "$root" zzz-unrelated)
  [ "$out" = 'Skills: none matched' ] \
    || { echo "  expected exactly 'Skills: none matched', got: $out"; ok=1; }

  # No skills directory exists anywhere.
  empty_root=$(new_tmp_dir); empty_home=$(new_tmp_dir)
  out=$(run_snippet "$empty_home" "$empty_root" anything)
  status=$?
  [ "$status" -eq 0 ] || { echo "  expected exit 0 with no skills dirs, got $status"; ok=1; }
  [ "$out" = 'Skills: none matched' ] \
    || { echo "  no-directory case must yield the same explicit line, got: $out"; ok=1; }

  return $ok
}

# =============================================================================
# orchestrator-04: implementation constraints pinned -- a temp-file-executed
# POSIX sh snippet per the prompt's own convention (never an installed CLI),
# writing nothing to disk (no registry), and never parsing skill contents
# beyond the frontmatter name/description (paths and descriptions only).
# =============================================================================
test_orchestrator_04_tempfile_stateless_posix() {
  root=$(new_tmp_dir); home=$(new_tmp_dir)
  ok=0

  # Wording constraints in the prompt.
  require "$ORCHESTRATOR_PROMPT" 'temp file' || ok=1
  require "$ORCHESTRATOR_PROMPT" 'never a new installed command, CLI, hook, or plugin' || ok=1
  require "$ORCHESTRATOR_PROMPT" 'no registry file' || ok=1
  require "$ORCHESTRATOR_PROMPT" 'lists paths and descriptions only' || ok=1
  require "$ORCHESTRATOR_PROMPT" 'never reads or follows a SKILL.md' || ok=1
  require "$ORCHESTRATOR_PROMPT" 'nothing is ever written under `spdd/`' || ok=1

  # The snippet parses as POSIX sh (still fail-closed if no sh at all).
  if command -v sh >/dev/null 2>&1; then
    sh -n "$SKILLS_SCRIPT" || { echo "  snippet fails POSIX sh parse"; ok=1; }
  else
    echo "  no POSIX sh on PATH to parse-check the snippet"
    ok=1
  fi

  # Nothing is written to disk, in particular nothing under spdd/.
  add_skill "$root/.agents/skills/skill-x" "skill-x" "Stub description for x"
  mkdir -p "$root/spdd"
  run_snippet "$home" "$root" x > /dev/null
  created=$(find "$root/spdd" -mindepth 1 | wc -l | tr -d ' ')
  [ "$created" -eq 0 ] \
    || { echo "  the derivation wrote into spdd/: $created entries"; ok=1; }
  [ -e "$root/spdd/skill-registry.md" ] \
    && { echo "  a registry file was created"; ok=1; }

  # Registry-independence: the snippet runs identically when a stale resolver
  # exists from a previous delegation -- the listing never reads one back.
  echo 'no-op' > "$root/spdd/skill-registry.md"
  out=$(run_snippet "$home" "$root" x)
  echo "$out" | grep -qF "path=$root/.agents/skills/skill-x/SKILL.md" \
    || { echo "  derivation is not pure disk derivation: $out"; ok=1; }

  return $ok
}

# =============================================================================
# Invariant: only frontmatter data is read. The skill body's words are never
# matched and never executed -- a keyword that appears only in the body gets
# no listing, so the orchestrator truly never parses skill contents.
# =============================================================================
test_invariant_body_never_read() {
  root=$(new_tmp_dir); home=$(new_tmp_dir)
  ok=0
  mkdir -p "$root/.claude/skills/body-only"
  printf -- '---\nname: body-only\ndescription: Reads configuration files.\n---\n\nThe body mentions zzz-unrelated, which the orchestrator must never parse.\n' \
    > "$root/.claude/skills/body-only/SKILL.md"
  out=$(run_snippet "$home" "$root" zzz-unrelated)
  [ "$out" = 'Skills: none matched' ] \
    || { echo "  a body-only keyword was used as a match: $out"; ok=1; }
  return $ok
}

# =============================================================================
# descmatch-01: matching is keyed to the description field only -- a keyword
# that appears only in the frontmatter name: no longer matches (the point of
# the fix), while a description keyword still matches exactly as before.
# =============================================================================
test_descmatch_01_name_only_no_match() {
  root=$(new_tmp_dir); home=$(new_tmp_dir)
  ok=0

  add_skill "$root/.agents/skills/searchtool-fixture" "searchtool-fixture" \
    "Reads configuration files."

  # The keyword lives only in the name: field -- no match, explicitly.
  out=$(run_snippet "$home" "$root" searchtool)
  [ "$out" = 'Skills: none matched' ] \
    || { echo "  a name-only keyword still listed the skill: $out"; ok=1; }

  # A description keyword still matches, with the same line shape.
  out=$(run_snippet "$home" "$root" configuration)
  echo "$out" | grep -qF "skill=searchtool-fixture path=$root/.agents/skills/searchtool-fixture/SKILL.md matched=configuration" \
    || { echo "  a description keyword no longer matches as before: $out"; ok=1; }

  return $ok
}

# =============================================================================
# descmatch-02: multi-line YAML block scalars are matched -- the extraction
# accumulates indented continuation lines of 'description: >' / '>-' until
# the next top-level key or the end of the frontmatter; the '>' indicator
# line itself and any text after a following top-level key are not match
# text; the skill body below the '---' fence is still never matched.
# =============================================================================
test_descmatch_02_block_scalars() {
  root=$(new_tmp_dir); home=$(new_tmp_dir)
  ok=0

  # Fixture A: folded '>' block scalar, keyword only on a continuation line,
  # the block running to the end of the frontmatter.
  add_skill_fm "$root/.agents/skills/folded-skill" \
    'name: folded-skill
description: >
  End-user desktop customization guidance.
  Covers keybinding setup for the desktop session.'

  # Fixture B: folded-strip '>-', keyword only on a continuation line.
  add_skill_fm "$root/.claude/skills/foldstrip-skill" \
    'name: foldstrip-skill
description: >-
  Diagnose why a program crashed on this machine.
  The word segfault appears on a continuation line only.'

  # Fixture C: block scalar followed by a later top-level key; the body
  # below the fence carries its own keyword that must never match.
  add_skill_fm "$root/.claude/skills/block-third" \
    'name: block-third
description: >
  Desktop and window manager configuration.
  Covers keybinding rules for the desktop session.
license: Apache-2.0
metadata:
  author: someone' \
    'The body mentions bodyonlykw, which the orchestrator must never parse.'

  out=$(run_snippet "$home" "$root" keybinding)
  echo "$out" | grep -qF 'skill=folded-skill' \
    || { echo "  a '>' continuation-line keyword did not match: $out"; ok=1; }
  echo "$out" | grep -qF 'matched=keybinding' \
    || { echo "  the folded skill's entry lacks matched=keybinding: $out"; ok=1; }
  echo "$out" | grep -qF 'skill=block-third' \
    || { echo "  accumulation stopped working when a top-level key follows the block: $out"; ok=1; }

  out=$(run_snippet "$home" "$root" segfault)
  echo "$out" | grep -qF 'skill=foldstrip-skill' \
    || { echo "  a '>-' continuation-line keyword did not match: $out"; ok=1; }
  echo "$out" | grep -qF 'matched=segfault' \
    || { echo "  the folded-strip skill's entry lacks matched=segfault: $out"; ok=1; }

  # The extraction stops at the next top-level key: 'license' (and anything
  # after it) is not description text, and neither is the '>' indicator.
  out=$(run_snippet "$home" "$root" license)
  [ "$out" = 'Skills: none matched' ] \
    || { echo "  text at/after the 'license:' key was used as match text: $out"; ok=1; }
  out=$(run_snippet "$home" "$root" someone)
  [ "$out" = 'Skills: none matched' ] \
    || { echo "  metadata text after the block was used as match text: $out"; ok=1; }
  out=$(run_snippet "$home" "$root" '>')
  [ "$out" = 'Skills: none matched' ] \
    || { echo "  the '>' indicator line itself was used as match text: $out"; ok=1; }

  # The body below the closing '---' fence is still never matched.
  out=$(run_snippet "$home" "$root" bodyonlykw)
  [ "$out" = 'Skills: none matched' ] \
    || { echo "  a body-only keyword was used as a match: $out"; ok=1; }

  return $ok
}

# =============================================================================
# descmatch-03: other frontmatter keys are excluded from matching -- the
# false positives verified on the real tree (keyword 'apache' only in
# 'license: Apache-2.0'; keyword 'edezacas' only in a 'metadata:' author)
# become no-matches, while the description still matches.
# =============================================================================
test_descmatch_03_license_metadata_excluded() {
  root=$(new_tmp_dir); home=$(new_tmp_dir)
  ok=0

  add_skill_fm "$root/.claude/skills/docs-fixture" \
    'name: docs-fixture
description: Guidelines for creating project documentation files.
license: Apache-2.0
metadata:
  author: edezacas
  version: 1.0'

  out=$(run_snippet "$home" "$root" apache)
  [ "$out" = 'Skills: none matched' ] \
    || { echo "  a license-only keyword still listed the skill: $out"; ok=1; }

  out=$(run_snippet "$home" "$root" edezacas)
  [ "$out" = 'Skills: none matched' ] \
    || { echo "  a metadata-only keyword still listed the skill: $out"; ok=1; }

  out=$(run_snippet "$home" "$root" documentation)
  echo "$out" | grep -qF 'skill=docs-fixture' \
    || { echo "  the description keyword no longer matches: $out"; ok=1; }
  echo "$out" | grep -qF 'matched=documentation' \
    || { echo "  the entry lacks its matched reason: $out"; ok=1; }

  return $ok
}

# =============================================================================
# descmatch-05: the additive-vs-HEAD guard is snippet-scoped -- a removal
# inside the antz-skills.sh fenced snippet is permitted (on either the
# old-side or new-side region check), a removal outside it is still flagged,
# and the real tree's diff passes the scoped guard. (The snippet's POSIX sh
# parse is asserted by the orchestrator-04 constraint test.)
# =============================================================================
test_descmatch_05_guard_scoping() {
  ok=0
  if command -v git >/dev/null 2>&1 && [ -e "$SCRIPT_DIR/.git" ]; then
    compute_snippet_region "$ORCHESTRATOR_PROMPT"
    ns=$region_start; ne=$region_end
    [ "$ns" -gt 0 ] && [ "$ne" -gt "$ns" ] \
      || { echo "  could not locate the antz-skills.sh snippet region in the working tree"; ok=1; }

    # The real tree's diff vs HEAD passes the scoped guard.
    diff_file=$(new_tmp)
    git -C "$SCRIPT_DIR" diff HEAD -- agents/prompts/orchestrator.prompt > "$diff_file" \
      || { echo "  git diff failed"; ok=1; }
    os=0; oe=0
    if git -C "$SCRIPT_DIR" cat-file -e HEAD:agents/prompts/orchestrator.prompt 2>/dev/null; then
      head_prompt=$(new_tmp)
      git -C "$SCRIPT_DIR" show HEAD:agents/prompts/orchestrator.prompt > "$head_prompt" 2>/dev/null
      compute_snippet_region "$head_prompt"
      os=$region_start; oe=$region_end
    fi
    bad=$(removals_outside_snippet "$diff_file" "$os" "$oe" "$ns" "$ne")
    [ -z "$bad" ] || { echo "  the scoped guard flags the real tree's diff: $bad"; ok=1; }

    # Synthetic hunks: a removal whose new-side position lies inside the
    # snippet region is permitted...
    syn=$(new_tmp)
    printf '@@ -1,2 +%d,2 @@\n context\n-removed inside the snippet\n+added inside the snippet\n context\n' "$ns" > "$syn"
    bad=$(removals_outside_snippet "$syn" 0 0 "$ns" "$ne")
    [ -z "$bad" ] || { echo "  a removal inside the snippet region was flagged: $bad"; ok=1; }

    # ...a removal outside it is still flagged...
    printf '@@ -1,2 +1,2 @@\n context\n-removed outside the snippet\n+added outside the snippet\n context\n' > "$syn"
    bad=$(removals_outside_snippet "$syn" 0 0 "$ns" "$ne")
    [ -n "$bad" ] || { echo "  a removal outside the snippet region was not flagged"; ok=1; }

    # ...and the old-side region check behaves the same way.
    bad=$(removals_outside_snippet "$syn" 1 100 0 0)
    [ -z "$bad" ] || { echo "  a removal inside the old-side region was flagged: $bad"; ok=1; }
    bad=$(removals_outside_snippet "$syn" 500 600 0 0)
    [ -n "$bad" ] || { echo "  a removal outside the old-side region was not flagged"; ok=1; }
  fi
  return $ok
}

# ---- run everything ---------------------------------------------------------

run_test "orchestrator-01: the delegation preamble gains the additive, absolutely-pathed skills block derived per delegation from the standard directories" test_orchestrator_01_block
run_test "orchestrator-01-derivation: the snippet resolves absolute SKILL.md paths from disk fresh at each delegation, never cached" test_orchestrator_01_derivation_fresh
run_test "orchestrator-02: matching is description-keyed and mechanical, capped at five with a deterministic alphabetical tie-break and legible reasons" test_orchestrator_02_matching_cap_tiebreak
run_test "orchestrator-03: no match -- and no skills directory at all -- still yields the explicit 'Skills: none matched' line" test_orchestrator_03_none_matched_explicit
run_test "orchestrator-04: the derivation is a temp-file POSIX sh snippet, stateless (no registry, nothing under spdd/), never reading skill bodies" test_orchestrator_04_tempfile_stateless_posix
run_test "skills-invariant: the orchestrator never parses skill contents (body text alone never matches)" test_invariant_body_never_read
run_test "descmatch-01: matching is keyed to the description field only -- a keyword only in name: no longer matches, a description keyword still matches exactly as before" test_descmatch_01_name_only_no_match
run_test "descmatch-02: 'description: >' and '>- ' block scalars match via their indented continuation lines, accumulated until the next top-level key or the end of the frontmatter -- the '>' indicator and post-key text are not match text, and the body is still never read" test_descmatch_02_block_scalars
run_test "descmatch-03: license-only and metadata-only keywords ('apache', 'edezacas') no longer list a skill; the description still matches" test_descmatch_03_license_metadata_excluded
run_test "descmatch-05: the additive-vs-HEAD guard is snippet-scoped -- removals inside the antz-skills.sh fenced snippet are permitted, any removal outside it still fails, and the real tree's diff passes" test_descmatch_05_guard_scoping

# ---- change-time scenario: explicit SKIP stub ---------------------------------
# descmatch-04 (spdd/changes/skills-desc-match/01-descmatch.feature) inspects
# the diff of agents/prompts/orchestrator.prompt against the pre-change tree
# -- a transient verification of this change's own edit scope (every changed
# line inside the snippet fence, the prose bullets and the other listed files
# byte-for-byte unchanged). It cannot be a permanent regression test: once
# the change is committed, that diff no longer exists. The coder verified it
# mechanically at implementation time; the verifier re-checks it at review.
skip_test "descmatch-04: the change's orchestrator.prompt diff lies entirely inside the antz-skills.sh fenced snippet, with the prose bullets and all other listed files byte-for-byte unchanged" \
  "change-time diff-scope check against the pre-change tree (transient; verified by the coder, re-checkable at review)"

# ---- e2e-only scenario: explicit SKIP stub -----------------------------------
# e2e-orchestrator-01 (spdd/changes/skills-activation/02-orchestrator.feature)
# requires a live orchestrated /antz flow in a real Angular project with antz
# installed from a post-change checkout -- not reducible to a static grep or a
# snippet run. It belongs to the verifier's end-to-end QA suite, not this
# unit suite; an explicit stub so the scenario id is accounted for.
skip_test "e2e-orchestrator-01: an orchestrated flow's coder delegation visibly carries the skills block and the delegated session reads the exact files" \
  "e2e-only: observable only in a live orchestrated /antz flow (verifier's e2e QA suite)"

echo ""
echo "$pass_count passed, $fail_count failed, $skip_count skipped (e2e-only, see 02-orchestrator.feature)"
[ "$fail_count" -eq 0 ]
