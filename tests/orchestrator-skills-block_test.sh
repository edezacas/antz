#!/usr/bin/env bash
# Unit tests for the delegation skills block added to
# agents/prompts/orchestrator.prompt (sub-spec
# spdd/changes/skills-activation/02-orchestrator.feature,
# scenarios orchestrator-01..04).
#
# The block is produced by a POSIX sh script that lives as a real file,
# scripts/orchestration/antz-skills.sh (injected into the rendered
# antz-orchestrator body by install.sh since change orchestrator-fast-path;
# same temp-file convention as the flow script and the status probe), so the
# tests assert both halves of the contract:
#   - the prompt text carries the block's duty, explicit none-matched line,
#     and implementation constraints (orchestrator-01, -02 wording, -04), and
#   - the file genuinely derives absolute SKILL.md paths from the standard
#     skills directories with the capped, tie-broken, keyword-reasoned
#     matching the scenarios demand (orchestrator-01..03 runtime).
#
# Since change orchestrator-fast-path (sub-spec 01) the snippet is a file and
# the prompt's fence carries only its include marker, so this suite runs the
# file directly -- no extraction from the prompt anymore (testharness-03), and
# the file keeps the shebang first line the old marker-to-fence-close
# extractor dropped.
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
#
# Re-scoped by change orchestrator-fast-path (sub-spec 03, testharness-03):
# the snippet's lines now live in scripts/orchestration/antz-skills.sh and
# the prompt carries only the include markers, so the guard's permitted
# regions are the prompt's three script fences (each verified to carry
# exactly its "# antz-include:" marker line naming an existing file) -- any
# removal outside those three fenced bodies still fails the guard.
#
# Evolved by change orchestrator-fast-path (sub-spec 05, receipts): the
# prompt's step-3 classification prose is legitimately rewritten (from
# run-the-suite classification to receipt-file reading), so the two real-tree
# additive-vs-HEAD checks (orchestrator-01's and descmatch-05's) are gated on
# the prompt's prose (the file minus its fenced blocks) being unchanged vs
# HEAD. While the receipt rewrite is uncommitted they are vacuously retired
# with a loud note (not a failure -- same convention as renderinject_test.sh's
# base-render gate); the synthetic fence-scoping cases and the structural
# assertions (marker-only fences, existing files) stay enforced forever.

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ORCHESTRATOR_PROMPT="$SCRIPT_DIR/agents/prompts/orchestrator.prompt"
SKILLS_SCRIPT="$SCRIPT_DIR/scripts/orchestration/antz-skills.sh"

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

# Prints 1 when the working orchestrator.prompt's prose (the file minus its
# fenced blocks) differs from HEAD's copy -- a later sub-spec's legitimate
# prose edit -- and 0 when it doesn't (or HEAD's copy is unreadable, in
# which case there is nothing to compare against).
prompt_prose_distinct_from_head() {
  work=$(new_tmp)
  basep=$(new_tmp)
  awk '/^[[:space:]]*```/ { infence = !infence; next } !infence' "$ORCHESTRATOR_PROMPT" > "$work"
  if git -C "$SCRIPT_DIR" show HEAD:agents/prompts/orchestrator.prompt > "$basep" 2>/dev/null; then
    awk '/^[[:space:]]*```/ { infence = !infence; next } !infence' "$basep" > "$basep"
    cmp -s "$work" "$basep" && { printf '0'; return 0; }
    printf '1'
  else
    printf '0'
  fi
}

# ---- the script under test (a file, run directly) ----------------------------

run_snippet() {
  # Runs the script with HOME pointed at a temp home.
  # $1 = temp home, $2 = working root, remaining args = match keywords.
  h="$1"; shift
  HOME="$h" sh "$SKILLS_SCRIPT" "$@"
}

# ---- testharness-03: the re-scoped additive-vs-HEAD guard --------------------
# The three script bodies now live as files under scripts/orchestration/ and
# the prompt's three script fences carry only their "# antz-include:" marker
# lines. The guard is re-scoped accordingly: it verifies each of the three
# script fences contains exactly its marker line naming an existing file,
# and a removed line is permitted only inside one of those three fenced
# bodies -- any removal outside them still fails the guard. The pre-change
# (HEAD) copy's three fences are located by the same shapes the old
# extractors used (first 3-space fence; the antz-skills.sh marker comment;
# the ```sh fence), so the old embedded bodies are the permitted old-side
# regions while the change is uncommitted.

region_from_opener() {
  # $1 = file, $2 = 1-based line number of a fence opener. Prints
  # "opener closer" when the fence closes, nothing (non-zero) otherwise.
  close=$(awk -v o="$2" 'NR > o && /^ *```$/ { print NR; exit }' "$1")
  if [ -n "$close" ] && [ "$close" -gt "$2" ]; then
    printf '%s %s' "$2" "$close"
    return 0
  fi
  return 1
}

region_enclosing_line() {
  # $1 = file, $2 = 1-based line number of a line inside the fence. Prints
  # "opener closer" for the fence enclosing that line.
  open=$(awk -v tgt="$2" 'NR < tgt && /^ *```(sh)?$/ { l = NR } END { print l + 0 }' "$1")
  [ "$open" -gt 0 ] || return 1
  region_from_opener "$1" "$open"
}

compute_fence_regions() {
  # $1 = prompt file; sets FENCE_REGIONS="s1 e1 s2 e2 s3 e3" for the three
  # script fences -- flow (the first 3-space fence), skills (the fence
  # carrying the antz-skills.sh include marker, or the pre-change marker
  # comment as the fallback for the HEAD copy), probe (the 3-space ```sh
  # fence). Fails (non-zero, FENCE_REGIONS empty) when any is missing.
  f="$1"
  FENCE_REGIONS=""
  fl=$(grep -nE '^   ```$' "$f" | head -n 1 | cut -d: -f1)
  [ -n "$fl" ] || { echo "  no flow fence found in $f" >&2; return 1; }
  r=$(region_from_opener "$f" "$fl") || { echo "  flow fence does not close" >&2; return 1; }
  FENCE_REGIONS="$r"
  sl=$(grep -nE '^ *# antz-include: scripts/orchestration/antz-skills\.sh' "$f" | head -n 1 | cut -d: -f1)
  [ -n "$sl" ] || sl=$(grep -nE '^ *# antz-skills\.sh' "$f" | head -n 1 | cut -d: -f1)
  [ -n "$sl" ] || { echo "  no antz-skills marker found in $f" >&2; return 1; }
  r=$(region_enclosing_line "$f" "$sl") || { echo "  skills fence not locatable" >&2; return 1; }
  FENCE_REGIONS="$FENCE_REGIONS $r"
  pl=$(grep -nE '^   ```sh$' "$f" | head -n 1 | cut -d: -f1)
  [ -n "$pl" ] || { echo "  no probe fence found in $f" >&2; return 1; }
  r=$(region_from_opener "$f" "$pl") || { echo "  probe fence does not close" >&2; return 1; }
  FENCE_REGIONS="$FENCE_REGIONS $r"
}

assert_include_markers() {
  # $1 = working-tree prompt file. Each of the three script fences contains
  # exactly its "# antz-include:" marker line, and each named file exists.
  # (The HEAD copy has no markers; this check is for the marker scheme only.)
  # (The loop variable is fence_name, never "name" -- run_test's global name
  # must not be clobbered by a test body.)
  f="$1"
  ok=0
  compute_fence_regions "$f" || { echo "  could not locate the three script fences in $f"; return 1; }
  set -- $FENCE_REGIONS
  [ $# -eq 6 ] || { echo "  expected 3 fence regions, got $# tokens"; return 1; }
  for fence_name in antz-flow antz-skills antz-probe; do
    s="$1"; e="$2"; shift 2
    want="# antz-include: scripts/orchestration/$fence_name.sh"
    body=$(awk -v s="$s" -v e="$e" 'NR > s && NR < e' "$f" | sed 's/^   //')
    [ "$body" = "$want" ] \
      || { echo "  $fence_name fence is not exactly its include marker: $body"; ok=1; }
    [ -f "$SCRIPT_DIR/scripts/orchestration/$fence_name.sh" ] \
      || { echo "  include marker names a missing file: scripts/orchestration/$fence_name.sh"; ok=1; }
  done
  return $ok
}

removals_outside_regions() {
  # $1 = unified diff file; $2 = old-side regions, $3 = new-side regions
  # (each a flat "opener closer opener closer ..." list; empty disables
  # nothing -- a side with no located regions fail-closes, flagging every
  # removal on it). Prints every removed diff line lying outside the three
  # script fences on BOTH sides; empty output means the guard passes.
  awk -v oldr="$2" -v newr="$3" '
    BEGIN {
      on = split(oldr, oa, /[[:space:]]+/)
      ocount = int(on / 2)
      for (i = 1; i <= ocount; i++) { os[i] = oa[2*i - 1] + 0; oe[i] = oa[2*i] + 0 }
      nn = split(newr, na, /[[:space:]]+/)
      ncount = int(nn / 2)
      for (i = 1; i <= ncount; i++) { ns[i] = na[2*i - 1] + 0; ne[i] = na[2*i] + 0 }
    }
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
      for (i = 1; i <= ocount; i++) if (os[i] > 0 && oline >= os[i] && oline <= oe[i]) inside = 1
      for (i = 1; i <= ncount; i++) if (ns[i] > 0 && nline >= ns[i] && nline <= ne[i]) inside = 1
      if (!inside) print
      oline++
      next
    }
    /^ / { oline++; nline++; next }
  ' "$1"
}

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

# ---- descmatch-05: the script-fences-scoped additive-vs-HEAD guard -----------
# (Scoping history and the testharness-03 re-scope are documented at the
# removals_outside_regions helper above.)

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

  # The addition is additive except inside the three script fences
  # (re-scoped by testharness-03): each script fence must carry exactly its
  # "# antz-include:" marker line naming an existing file, and removed lines
  # are permitted only inside those three fenced bodies -- any removal
  # outside them still fails the guard. Gated per the header note on the
  # prompt prose being unchanged vs HEAD (the receipts sub-spec's step-3
  # rewrite retires the real-tree check with a loud note).
  if command -v git >/dev/null 2>&1 && [ -e "$SCRIPT_DIR/.git" ]; then
    assert_include_markers "$ORCHESTRATOR_PROMPT" || ok=1
    if [ "$(prompt_prose_distinct_from_head)" -eq 1 ]; then
      echo "  note: orchestrator.prompt prose changed vs HEAD (a later sub-spec's legitimate edit); the additive-vs-HEAD removal check is vacuously retired, structural assertions still enforced"
    else
      diff_file=$(new_tmp)
      git -C "$SCRIPT_DIR" diff HEAD -- agents/prompts/orchestrator.prompt > "$diff_file" \
        || { echo "  git diff failed"; ok=1; }
      compute_fence_regions "$ORCHESTRATOR_PROMPT"
      ns="$FENCE_REGIONS"
      [ -n "$ns" ] || { echo "  could not locate the three script fences in the working tree"; ok=1; }
      os=""
      if git -C "$SCRIPT_DIR" cat-file -e HEAD:agents/prompts/orchestrator.prompt 2>/dev/null; then
        head_prompt=$(new_tmp)
        git -C "$SCRIPT_DIR" show HEAD:agents/prompts/orchestrator.prompt > "$head_prompt" 2>/dev/null
        compute_fence_regions "$head_prompt"
        os="$FENCE_REGIONS"
        [ -n "$os" ] || { echo "  could not locate the three script fences in the HEAD copy"; ok=1; }
      fi
      bad=$(removals_outside_regions "$diff_file" "$os" "$ns")
      if [ -n "$bad" ]; then
        echo "  orchestrator.prompt has removed lines outside the three script fences:"
        printf '%s\n' "$bad"
        ok=1
      fi
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
# descmatch-05: the additive-vs-HEAD guard is script-fences-scoped (re-scoped
# by testharness-03) -- a removal inside one of the three script fences is
# permitted (on either the old-side or new-side region check), a removal
# outside them is still flagged, and the real tree's diff passes the scoped
# guard. (The script's POSIX sh parse is asserted by the orchestrator-04
# constraint test; the fences' marker-only bodies by assert_include_markers.)
# =============================================================================
test_descmatch_05_guard_scoping() {
  ok=0
  if command -v git >/dev/null 2>&1 && [ -e "$SCRIPT_DIR/.git" ]; then
    compute_fence_regions "$ORCHESTRATOR_PROMPT"
    ns="$FENCE_REGIONS"
    set -- $ns
    [ $# -eq 6 ] \
      || { echo "  could not locate the three script fences in the working tree"; ok=1; }
    # Safe defaults keep the synthetic cases well-defined (a 0 start never
    # falls inside a real fence region, so they fail loudly, not crash) even
    # when the fences could not be located.
    fs=${1:-0}; fe=${2:-0}

    # The real tree's diff vs HEAD passes the scoped guard -- gated per the
    # header note on the prompt prose being unchanged vs HEAD (the receipts
    # sub-spec's step-3 rewrite retires this real-tree check with a loud
    # note; the synthetic fence-scoping cases below stay enforced).
    diff_file=$(new_tmp)
    git -C "$SCRIPT_DIR" diff HEAD -- agents/prompts/orchestrator.prompt > "$diff_file" \
      || { echo "  git diff failed"; ok=1; }
    os=""
    if git -C "$SCRIPT_DIR" cat-file -e HEAD:agents/prompts/orchestrator.prompt 2>/dev/null; then
      head_prompt=$(new_tmp)
      git -C "$SCRIPT_DIR" show HEAD:agents/prompts/orchestrator.prompt > "$head_prompt" 2>/dev/null
      compute_fence_regions "$head_prompt"
      os="$FENCE_REGIONS"
      [ -n "$os" ] || { echo "  could not locate the three script fences in the HEAD copy"; ok=1; }
    fi
    if [ "$(prompt_prose_distinct_from_head)" -eq 1 ]; then
      echo "  note: orchestrator.prompt prose changed vs HEAD (a later sub-spec's legitimate edit); the real-tree additive-vs-HEAD check is vacuously retired, synthetic fence-scoping cases still enforced"
    else
      bad=$(removals_outside_regions "$diff_file" "$os" "$ns")
      [ -z "$bad" ] || { echo "  the scoped guard flags the real tree's diff: $bad"; ok=1; }
    fi

    # Synthetic hunks (using the flow fence's region): a removal whose
    # new-side position lies inside a script fence is permitted...
    syn=$(new_tmp)
    printf '@@ -1,2 +%d,2 @@\n context\n-removed inside the fence\n+added inside the fence\n context\n' "$fs" > "$syn"
    bad=$(removals_outside_regions "$syn" "" "$ns")
    [ -z "$bad" ] || { echo "  a removal inside a script fence was flagged: $bad"; ok=1; }

    # ...a removal outside them is still flagged...
    printf '@@ -1,2 +1,2 @@\n context\n-removed outside the fences\n+added outside the fences\n context\n' > "$syn"
    bad=$(removals_outside_regions "$syn" "" "$ns")
    [ -n "$bad" ] || { echo "  a removal outside the script fences was not flagged"; ok=1; }

    # ...and the old-side region check behaves the same way: a removal whose
    # old-side position lies inside a script fence is permitted...
    printf '@@ -%d,2 +1,2 @@\n context\n-removed inside an old-side fence\n+added\n context\n' "$fs" > "$syn"
    bad=$(removals_outside_regions "$syn" "$ns" "")
    [ -z "$bad" ] || { echo "  a removal inside an old-side fence region was flagged: $bad"; ok=1; }
    # ...and one outside them is still flagged.
    printf '@@ -500,2 +500,2 @@\n context\n-removed outside old regions\n+added outside them\n context\n' > "$syn"
    bad=$(removals_outside_regions "$syn" "$ns" "")
    [ -n "$bad" ] || { echo "  a removal outside the old-side fence regions was not flagged"; ok=1; }
  fi
  return $ok
}

# =============================================================================
# testharness-03: the skills suite runs scripts/orchestration/antz-skills.sh
# directly (no extraction from the prompt; the file keeps the shebang first
# line the old marker-to-fence-close extractor dropped), and each of the
# prompt's three script fences carries exactly its "# antz-include:" marker
# line naming an existing file.
# =============================================================================
test_testharness_03_file_source() {
  ok=0
  [ "$SKILLS_SCRIPT" = "$SCRIPT_DIR/scripts/orchestration/antz-skills.sh" ] \
    || { echo "  the suite is not running scripts/orchestration/antz-skills.sh"; ok=1; }
  [ -f "$SKILLS_SCRIPT" ] \
    || { echo "  no skills script at scripts/orchestration/antz-skills.sh"; ok=1; }
  first=$(head -n 1 "$SKILLS_SCRIPT")
  [ "$first" = '#!/bin/sh' ] \
    || { echo "  antz-skills.sh lost its shebang first line: $first"; ok=1; }
  assert_include_markers "$ORCHESTRATOR_PROMPT" || ok=1
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
run_test "descmatch-05: the additive-vs-HEAD guard is script-fences-scoped -- removals inside the three script fences are permitted, any removal outside them still fails, and the real tree's diff passes" test_descmatch_05_guard_scoping
run_test "testharness-03: the skills suite runs scripts/orchestration/antz-skills.sh directly (shebang kept), and each prompt script fence carries exactly its include marker naming an existing file" test_testharness_03_file_source

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
