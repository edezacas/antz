#!/usr/bin/env bash
# tests/harness_test.sh -- unit tests for the shared test-harness library
# tests/harness.sh, covering every scenario of
# spdd/changes/optimize-test-suite/01-harness.feature (harness-01..06).
#
# What is under test here is the LIBRARY and its documented contracts -- the
# output contract (one "PASS: <name>" / "FAIL: <name>" /
# "SKIP: <name> (<reason>)" line per registered test, names beginning with
# the scenario id, the final "pass=<n> fail=<n> skip=<n>" aggregate, exit 0
# exactly when no registered test failed), the hermeticity guarantee (temp
# space under ${TMPDIR:-/tmp}; renders into a sandbox HOME with
# XDG_CONFIG_HOME cleared), the render-once caching, and the staged-checkout
# copy. The suites' own migration to sourcing the library is the later
# sub-specs' work (harness-04/harness-05 are whole-area end-state scans; see
# their explicit SKIP stubs below).
#
# Seams under test: (1) sourcing tests/harness.sh from a bash script and
# calling the documented helpers -- the only way the suites consume them;
# (2) the library file's content for the two area-scan scenarios' half that
# is true today (harness.sh is the only file under tests/ that invokes
# install.sh or defines the helpers -- asserted over what exists NOW without
# pretending the unmigrated suites are already converted).
#
# This suite sources its own subject (allowed: a suite's own file is its
# migration target too) and runs entirely in temp space; nothing here
# writes into the repo working tree or the real user config.
#
# Run directly:  ./tests/harness_test.sh

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
HARNESS_LIB="$SCRIPT_DIR/tests/harness.sh"

# shellcheck source=tests/harness.sh
. "$HARNESS_LIB"

# ---- shared fixture text -----------------------------------------------------
# The scenario body is IDENTICAL between the copy-pasted-era oracle script
# (whose helper definitions are the verbatim copies taken from the
# pre-refactor suites -- the frozen independent reference for the
# "behaves as the copy-pasted versions did" claim) and the new-era fixture
# (which sources the library and ends with finish_suite). Byte-identical
# stdout and exit status between the two proves the library preserves the
# observable behavior.

ORACLE_HELPERS='
pass_count=0
fail_count=0
skip_count=0

tmp_roots=()
new_tmp_dir() {
  d=$(mktemp -d)
  tmp_roots+=("$d")
  printf '"'"'%s'"'"' "$d"
}

cleanup() {
  for d in "${tmp_roots[@]:-}"; do
    [ -n "$d" ] && rm -rf "$d"
  done
  return 0
}
trap cleanup EXIT

run_test() {
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
  name="$1"; reason="$2"
  echo "SKIP: $name ($reason)"
  skip_count=$((skip_count + 1))
}

require() {
  if grep -qF -- "$2" "$1"; then return 0; fi
  echo "  missing required text: $2"
  return 1
}

refuse() {
  if grep -qF -- "$2" "$1"; then
    echo "  found forbidden text: $2"
    return 1
  fi
  return 0
}

extract_section() {
  awk -v sec="$2" "
    \$0 == \"## \" sec { flag=1; next }
    flag && /^## / { flag=0 }
    flag { print }
  " "$1" > "$3"
}

extract_bullet() {
  grep -F -- "$2" "$1" | head -n 1
}

extract_bullet_line() {
  grep -F -- "$2" "$1" > "$3"
}

extract_line() {
  grep -m1 -F -- "$2" "$1" > "$3"
}

extract_fn() {
  awk -v fn="$2" "
    index(\$0, fn \"() {\") == 1 { flag = 1 }
    flag { print }
    flag && \$0 == \"}\" { exit }
  " "$1" > "$3"
}
'

SCENARIO_BODY='
t_require_present() { require "$FX_MD" "hello world"; }
t_require_absent()  { require "$FX_MD" "no such phrase"; }
t_refuse_clear()    { refuse "$FX_MD" "no such phrase"; }
t_refuse_hit()      { refuse "$FX_MD" "hello world"; }
t_extract_section() {
  extract_section "$FX_MD" "Alpha" "$FX_OUT1"
  grep -q "^alpha line$" "$FX_OUT1" && ! grep -q "beta line" "$FX_OUT1"
}
t_extract_bullet() {
  [ "$(extract_bullet "$FX_MD" "- bullet two")" = "- bullet two has quotes and dollars" ]
}
t_extract_bullet_line() {
  extract_bullet_line "$FX_MD" "- bullet one" "$FX_OUT2"
  grep -qx -- "- bullet one" "$FX_OUT2"
}
t_extract_line() {
  extract_line "$FX_SH" "greeter" "$FX_OUT3"
  [ "$(wc -l < "$FX_OUT3" | tr -d " ")" -eq 1 ]
}
t_extract_fn() {
  extract_fn "$FX_SH" "greeter" "$FX_OUT4"
  grep -q "^greeter() {$" "$FX_OUT4" && grep -q "^  echo hi$" "$FX_OUT4" \
    && ! grep -q "nope" "$FX_OUT4"
}
run_test "fx require-present passes" t_require_present
run_test "fx require-absent fails" t_require_absent
run_test "fx refuse-clear passes" t_refuse_clear
run_test "fx refuse-hit fails" t_refuse_hit
run_test "fx extract_section scopes to heading" t_extract_section
run_test "fx extract_bullet prints first match" t_extract_bullet
run_test "fx extract_bullet_line writes out" t_extract_bullet_line
run_test "fx extract_line prints single line" t_extract_line
run_test "fx extract_fn captures one function" t_extract_fn
skip_test "fx skip stub" "e2e-only: not unit-testable here"
skip_test "fx blocked stub" "BLOCKED: shared contract needs changing first"
'

# The frozen expected transcript for the contract-shape test -- literal text
# from the harness output contract in the sub-spec / README shared
# contracts, independent of the library's implementation.
EXPECTED_CORE_TRANSCRIPT='PASS: fx require-present passes
  missing required text: no such phrase
FAIL: fx require-absent fails
PASS: fx refuse-clear passes
  found forbidden text: hello world
FAIL: fx refuse-hit fails
PASS: fx extract_section scopes to heading
PASS: fx extract_bullet prints first match
PASS: fx extract_bullet_line writes out
PASS: fx extract_line prints single line
PASS: fx extract_fn captures one function
SKIP: fx skip stub (e2e-only: not unit-testable here)
SKIP: fx blocked stub (BLOCKED: shared contract needs changing first)
pass=7 fail=2 skip=2'

# Write the fixture input files shared by every fixture script.
fx_setup() {
  fx_dir="$1"
  mkdir -p "$fx_dir"
  cat > "$fx_dir/doc.md" <<'EOF'
# Doc
hello world

## Alpha
alpha line

- bullet one
- bullet two has quotes and dollars

## Beta
beta line
EOF
  cat > "$fx_dir/fns.sh" <<'EOF'
greeter() {
  echo hi
}
other() {
  echo nope
}
EOF
  printf '%s' "$fx_dir/doc.md" > "$fx_dir/md.path"
  printf '%s' "$fx_dir/fns.sh" > "$fx_dir/sh.path"
}

# Assemble the two fixture scripts from the SAME scenario body.
fx_write_scripts() {
  fx_dir="$1"
  {
    printf '%s\n' '#!/usr/bin/env bash' 'set -u'
    printf '%s\n' "$ORACLE_HELPERS"
    printf '%s\n' "$SCENARIO_BODY"
    printf '%s\n' 'echo "pass=$pass_count fail=$fail_count skip=$skip_count"' \
                  '[ "$fail_count" -eq 0 ]'
  } > "$fx_dir/oracle.sh"
  {
    printf '%s\n' '#!/usr/bin/env bash' 'set -u' \
                  ". \"\$1\""
    printf '%s\n' "$SCENARIO_BODY"
    printf '%s\n' 'finish_suite'
  } > "$fx_dir/library.sh"
}

fx_run() {
  # $1 = fixture script, rest -> library.sh gets the harness path as $1
  fx_out="$1"; shift
  fx_script="$1"; shift
  if bash "$fx_script" "$@" > "$fx_out.out" 2>&1; then
    printf '0' > "$fx_out.rc"
  else
    printf '1' > "$fx_out.rc"
  fi
}

# ---- harness-01 --------------------------------------------------------------

test_harness_01_sourced_suite_matches_copied_helpers() {
  d=$(new_tmp_dir)
  fx_setup "$d"
  fx_write_scripts "$d"
  export FX_MD="$d/doc.md" FX_SH="$d/fns.sh"
  export FX_OUT1="$d/o1" FX_OUT2="$d/o2" FX_OUT3="$d/o3" FX_OUT4="$d/o4"

  fx_run "$d/a" "$d/oracle.sh"
  fx_run "$d/b" "$d/library.sh" "$HARNESS_LIB"

  # The two runs must be identical in every observable byte, and both must
  # carry the frozen transcript and exit non-zero (failures were registered).
  cmp -s "$d/a.out" "$d/b.out" || { echo "  sourced suite diverges from copy-pasted oracle"; return 1; }
  cmp -s "$d/a.rc" "$d/b.rc" || { echo "  exit status diverges"; return 1; }
  [ "$(cat "$d/a.rc")" = "1" ] || { echo "  oracle exit not 1 with failures"; return 1; }
  cmp -s <(printf '%s\n' "$EXPECTED_CORE_TRANSCRIPT") "$d/a.out" \
    || { echo "  copy-pasted oracle transcript diverges from the frozen expectation"; return 1; }
  return 0
}

test_harness_01_pass_only_exit_zero() {
  d=$(new_tmp_dir)
  fx_setup "$d"
  # A fixture with NO failing registration: exit 0 exactly when nothing failed.
  {
    printf '%s\n' '#!/usr/bin/env bash' 'set -u' ". \"\$1\""
    printf '%s\n' 't_ok() { require "$FX_MD" "hello world"; }'
    printf '%s\n' 'run_test "fx-only-pass: green" t_ok'
    printf '%s\n' 'skip_test "fx-only-skip: parked" "e2e-only: deferred"'
    printf '%s\n' 'finish_suite'
  } > "$d/onlypass.sh"
  export FX_MD="$d/doc.md"
  bash "$d/onlypass.sh" "$HARNESS_LIB" > "$d/onlypass.out" 2>&1
  rc=$?
  [ "$rc" -eq 0 ] || { echo "  exit $rc, expected 0 with no failed tests"; return 1; }
  cmp -s <(printf '%s\n' 'PASS: fx-only-pass: green
SKIP: fx-only-skip: parked (e2e-only: deferred)
pass=1 fail=0 skip=1') "$d/onlypass.out" \
    || { echo "  transcript diverges from the contract"; return 1; }
  return 0
}

test_harness_01_sourced_suite_defines_no_helpers() {
  d=$(new_tmp_dir)
  fx_write_scripts "$d"
  # The library-sourced fixture (a suite-shaped script) defines none of the
  # harness helpers itself...
  if grep -Eq '^(run_test|skip_test|require|refuse|new_tmp_dir|cleanup|stage_checkout|install_at|install_xdg|render_tree|finish_suite|extract_section|extract_bullet|extract_bullet_line|extract_line|extract_fn)\(\)' "$d/library.sh"; then
    echo "  sourced fixture defines a helper"
    return 1
  fi
  # ...and sourcing the library alone resolves every documented helper.
  if ! bash -c '. "$1"; for h in run_test skip_test require refuse new_tmp_dir cleanup finish_suite extract_section extract_bullet extract_bullet_line extract_line extract_fn stage_checkout install_at install_xdg render_tree; do [ "$(type -t "$h")" = function ] || { echo "  unresolved: $h"; exit 1; }; done' _ "$HARNESS_LIB" 2>&1; then
    echo "  library does not resolve every core helper"
    return 1
  fi
  return 0
}

# The 16 files a full install.sh --all render produces (the documented
# install surface: 4 agents + 2 commands per client, 4 libdir scripts) --
# the literal completeness set for "returns the complete installed tree".
INSTALLED_TREE_FILES='
.claude/agents/antz-coder.md
.claude/agents/antz-orchestrator.md
.claude/agents/antz-specifier.md
.claude/agents/antz-verifier.md
.claude/commands/antz.md
.claude/commands/antz-set-model.md
.config/antz/scripts/antz-flow.sh
.config/antz/scripts/antz-probe.sh
.config/antz/scripts/antz-set-model.sh
.config/opencode/agents/antz-coder.md
.config/opencode/agents/antz-orchestrator.md
.config/opencode/agents/antz-specifier.md
.config/opencode/agents/antz-verifier.md
.config/opencode/commands/antz.md
.config/opencode/commands/antz-set-model.md
'

fx_assert_complete_tree() {
  # $1 = installed tree root: every contract file present, nothing extra.
  home="$1"
  for f in $INSTALLED_TREE_FILES; do
    [ -f "$home/$f" ] || { echo "  installed tree missing $f"; return 1; }
  done
  n=$(find "$home" -type f | wc -l | tr -d ' ')
  [ "$n" -eq 15 ] || { echo "  installed tree has $n files, expected the 15 contract files"; return 1; }
  return 0
}

fx_instrument_tree() {
  # $1 = staged tree: replace install.sh with a counting wrapper around the
  # (relocated, still tree-root) real install.sh, so "the underlying
  # install.sh render executes once" is observed, not inferred.
  tree="$1"
  mv "$tree/install.sh" "$tree/.real-install.sh"
  : > "$tree/render-count"
  cat > "$tree/install.sh" <<EOF
#!/bin/sh
n=\$(cat "$tree/render-count")
echo \$((n + 1)) > "$tree/render-count"
exec sh "$tree/.real-install.sh" "\$@"
EOF
}

# ---- harness-02 ----------------------------------------------------------------

test_harness_02_new_tmp_dir_is_under_tmpdir_never_repo_or_userconfig() {
  d=$(new_tmp_dir)
  canary_home="$d/canary-home"
  canary_xdg="$d/canary-xdg"
  mkdir -p "$d/tmp" "$canary_home" "$canary_xdg"

  # With TMPDIR set, new_tmp_dir creates under it (existence checked while
  # the subshell's own EXIT cleanup can still see it).
  path=$(env TMPDIR="$d/tmp" HOME="$canary_home" XDG_CONFIG_HOME="$canary_xdg" \
    bash -c '. "$1"; p=$(new_tmp_dir); test -d "$p" || exit 2; printf "%s" "$p"' \
    _ "$HARNESS_LIB") || { echo "  fixture new_tmp_dir (TMPDIR set) failed"; return 1; }
  case "$path" in
    "$d/tmp/"*) ;;
    *) echo "  created outside TMPDIR: $path"; return 1 ;;
  esac
  case "$path" in
    "$SCRIPT_DIR"*|"$canary_home"*|"$canary_xdg"*)
      echo "  created under repo or canary config: $path"; return 1 ;;
  esac

  # With TMPDIR unset, creation falls back to /tmp -- never the repo tree
  # and never the (canary) user config.
  path=$(env -u TMPDIR HOME="$canary_home" XDG_CONFIG_HOME="$canary_xdg" \
    bash -c '. "$1"; p=$(new_tmp_dir); test -d "$p" || exit 2; printf "%s" "$p"' \
    _ "$HARNESS_LIB") || { echo "  fixture new_tmp_dir (TMPDIR unset) failed"; return 1; }
  case "$path" in
    /tmp/*) ;;
    "$SCRIPT_DIR"*|"$HOME"*)
      echo "  created under repo or real HOME without TMPDIR: $path"; return 1 ;;
    *) echo "  created outside /tmp fallback: $path"; return 1 ;;
  esac

  # Nothing landed under the canary HOME / canary XDG.
  [ -z "$(find "$canary_home" "$canary_xdg" -mindepth 1 -print -quit)" ] \
    || { echo "  canary config dirs were written into"; return 1; }

  # And the repo working tree is untouched by the whole exchange.
  touches=$(find "$SCRIPT_DIR" -path "$SCRIPT_DIR/.git" -prune -o \
    ! -path "$SCRIPT_DIR/.git*" -newer "$d/canary-home" ! -type d -print | head -5)
  [ -z "$touches" ] || { echo "  repo working tree files newer than run start:"; echo "$touches"; return 1; }
  return 0
}

test_harness_02_render_runs_with_sandbox_home_and_cleared_xdg() {
  d=$(new_tmp_dir)
  mkdir -p "$d/tmp" "$d/canary-home" "$d/canary-xdg"

  # Render from a suite-shaped subshell whose ambient HOME/XDG point at the
  # empty canaries: the library must sandbox the render itself, so the
  # ambient canary HOME must NOT end up holding the installed files. The
  # fixture disarms its EXIT cleanup so the parent can inspect the result.
  home=$(env TMPDIR="$d/tmp" HOME="$d/canary-home" XDG_CONFIG_HOME="$d/canary-xdg" \
    bash -c '
      . "$1"
      t=$(new_tmp_dir)/tree
      stage_checkout "$t" || exit 2
      h=$(render_tree "$t") || exit 3
      trap - EXIT
      printf "%s" "$h"
    ' _ "$HARNESS_LIB") || { echo "  render fixture failed (rc $?)"; return 1; }
  case "$home" in
    "$d/tmp/"*) ;;
    *) echo "  sandbox home not under TMPDIR: $home"; return 1 ;;
  esac
  fx_assert_complete_tree "$home" || return 1
  [ -z "$(find "$d/canary-home" "$d/canary-xdg" -mindepth 1 -print -quit)" ] \
    || { echo "  render wrote into the ambient (canary) HOME/XDG"; return 1; }
  return 0
}

test_harness_02_no_helper_writes_to_real_user_config() {
  # The user-facing half of the hermeticity guarantee: with the real HOME
  # ambient (as every suite runs), the render helpers must touch neither
  # "~/.claude" nor "~/.config/opencode" -- the install can only land in
  # its sandbox.
  d=$(new_tmp_dir)
  marker="$d/marker"; : > "$marker"
  env TMPDIR="$d" bash -c '
    . "$1"
    t=$(new_tmp_dir)/tree
    stage_checkout "$t" || exit 2
    render_tree "$t" >/dev/null || exit 3
  ' _ "$HARNESS_LIB" >/dev/null 2>&1 || { echo "  render fixture failed"; return 1; }
  for real in "$HOME/.claude" "$HOME/.config/opencode" "$HOME/.config/antz"; do
    [ -e "$real" ] || continue
    [ -z "$(find "$real" -newer "$marker" -print -quit)" ] \
      || { echo "  helper wrote into the real config: $real"; return 1; }
  done
  return 0
}

# ---- harness-03 ----------------------------------------------------------------

test_harness_03_repeated_render_of_one_staged_tree_executes_install_once() {
  d=$(new_tmp_dir)
  tree="$d/A"
  stage_checkout "$tree" || { echo "  staging failed"; return 1; }
  fx_instrument_tree "$tree"

  home1=$(render_tree "$tree") || { echo "  first render failed"; return 1; }
  [ "$(cat "$tree/render-count")" = "1" ] \
    || { echo "  first render did not execute install.sh exactly once"; return 1; }
  fx_assert_complete_tree "$home1" || return 1

  # Second call through the library's render helper: same complete tree,
  # contents and mtimes untouched, install.sh NOT re-executed.
  ( cd "$home1" && find . -type f | sort | xargs cksum ) > "$d/cksum1"
  touch "$d/mtime-marker"
  sleep 1   # keep the -newer comparison honest at 1s mtime granularity
  home2=$(render_tree "$tree") || { echo "  second render call failed"; return 1; }
  [ "$home1" = "$home2" ] || { echo "  reused tree path differs: $home1 vs $home2"; return 1; }
  [ "$(cat "$tree/render-count")" = "1" ] \
    || { echo "  render re-executed install.sh (count $(cat "$tree/render-count"))"; return 1; }
  ( cd "$home2" && find . -type f | sort | xargs cksum ) | cmp -s - "$d/cksum1" \
    || { echo "  installed contents changed on the cached render"; return 1; }
  [ -z "$(find "$home2" -newer "$d/mtime-marker" -print -quit)" ] \
    || { echo "  installed mtimes changed on the cached render"; return 1; }
  fx_assert_complete_tree "$home2" || return 1
  return 0
}

test_harness_03_render_of_a_different_staged_tree_performs_its_own_render() {
  d=$(new_tmp_dir)
  treeA="$d/A"
  treeB="$d/B"
  stage_checkout "$treeA" || { echo "  staging A failed"; return 1; }
  stage_checkout "$treeB" || { echo "  staging B failed"; return 1; }
  # Make B's product state genuinely different: its coder meta flips to
  # access: readonly (a supported mapping), so B's rendered agents differ.
  awk '{ sub(/^access: .*/, "access: readonly"); print }' \
    "$treeB/agents/meta/coder.yaml" > "$treeB/coder.yaml.new" \
    && mv "$treeB/coder.yaml.new" "$treeB/agents/meta/coder.yaml"
  fx_instrument_tree "$treeA"
  fx_instrument_tree "$treeB"

  homeA=$(render_tree "$treeA") || { echo "  render A failed"; return 1; }
  homeB=$(render_tree "$treeB") || { echo "  render B failed"; return 1; }
  [ "$homeA" != "$homeB" ] || { echo "  two different trees shared one installed home"; return 1; }
  [ "$(cat "$treeA/render-count")" = "1" ] && [ "$(cat "$treeB/render-count")" = "1" ] \
    || { echo "  renders not one-per-tree (A=$(cat "$treeA/render-count") B=$(cat "$treeB/render-count"))"; return 1; }
  fx_assert_complete_tree "$homeB" || return 1
  # B's render exercised B's staged state, not A's: the flipped meta shows
  # up in the rendered tool grant (the documented readwrite->full vs
  # readonly->no-edit mapping) and separates it from A's copy.
  require "$homeB/.claude/agents/antz-coder.md" "tools: Read, Grep, Glob, Bash" \
    || { echo "  B render did not carry B's staged meta"; return 1; }
  grep -qF "Edit, Write" "$homeB/.claude/agents/antz-coder.md" \
    && { echo "  B rendered the readwrite tools despite the flipped meta"; return 1; }
  require "$homeA/.claude/agents/antz-coder.md" "Edit, Write, Skill" \
    || { echo "  A render lost the readwrite mapping"; return 1; }
  ! cmp -s "$homeA/.claude/agents/antz-coder.md" "$homeB/.claude/agents/antz-coder.md" \
    || { echo "  A and B rendered identical agents from different trees"; return 1; }
  return 0
}

# ---- harness-06 ----------------------------------------------------------------

test_harness_06_stage_checkout_copies_current_working_tree_products() {
  d=$(new_tmp_dir)
  dest="$d/stage/fresh"

  stage_checkout "$dest" || { echo "  stage_checkout failed"; return 1; }

  # A fresh temp tree carrying exactly the scenario's product set.
  case "$dest" in "$d"/*) ;; *) echo "  dest not under the run's temp space"; return 1 ;; esac
  for f in install.sh VERSION CHANGELOG.md \
           agents/prompts/coder.prompt agents/prompts/orchestrator.prompt \
           agents/prompts/specifier.prompt agents/prompts/verifier.prompt \
           agents/meta/coder.yaml agents/meta/orchestrator.yaml \
           agents/meta/specifier.yaml agents/meta/verifier.yaml \
           scripts/orchestration/antz-flow.sh scripts/orchestration/antz-probe.sh; do
    [ -f "$dest/$f" ] || { echo "  staged tree missing $f"; return 1; }
  done

  # ...byte-identical to the working tree's CURRENT state, file for file.
  for src in "$SCRIPT_DIR"/install.sh "$SCRIPT_DIR"/VERSION "$SCRIPT_DIR"/CHANGELOG.md \
             "$SCRIPT_DIR"/agents/prompts/*.prompt "$SCRIPT_DIR"/agents/meta/*.yaml \
             "$SCRIPT_DIR"/scripts/orchestration/*.sh; do
    rel="${src#"$SCRIPT_DIR"/}"
    cmp -s "$src" "$dest/$rel" || { echo "  staged copy differs from working tree: $rel"; return 1; }
  done

  # The staged tree carries nothing the repo's product dirs don't have.
  n_repo=$(find "$SCRIPT_DIR/agents" "$SCRIPT_DIR/scripts/orchestration" -type f | wc -l | tr -d ' ')
  n_stage=$(find "$dest/agents" "$dest/scripts/orchestration" -type f | wc -l | tr -d ' ')
  [ "$n_repo" -eq "$n_stage" ] || { echo "  staged tree has $n_stage files vs repo $n_repo"; return 1; }

  # Optional VERSION override (the libdirinstall-era second argument) writes
  # the given version instead of the working tree's, rest as before.
  dest2="$d/stage2"
  stage_checkout "$dest2" "0.0.0-harness-probe" || { echo "  stage_checkout with version failed"; return 1; }
  [ "$(cat "$dest2/VERSION")" = "0.0.0-harness-probe" ] \
    || { echo "  VERSION override not applied"; return 1; }
  cmp -s "$SCRIPT_DIR/CHANGELOG.md" "$dest2/CHANGELOG.md" \
    || { echo "  override run no longer copies CHANGELOG.md"; return 1; }
  return 0
}

test_harness_06_cleanup_removes_every_new_tmp_dir_even_on_early_failure() {
  d=$(new_tmp_dir)
  mkdir -p "$d/tmp"
  cat > "$d/fixture.sh" <<'EOF'
#!/usr/bin/env bash
set -eu
. "$1"
a=$(new_tmp_dir)
b=$(new_tmp_dir)
mkdir -p "$a/inner/sub"
: > "$b/file"
printf '%s\n%s\n' "$a" "$b"
false
EOF
  env TMPDIR="$d/tmp" bash "$d/fixture.sh" "$HARNESS_LIB" > "$d/dirs" 2>/dev/null && rc=0 || rc=$?
  [ "$rc" -ne 0 ] || { echo "  early-failure fixture unexpectedly succeeded"; return 1; }
  [ "$(wc -l < "$d/dirs" | tr -d ' ')" -eq 2 ] || { echo "  fixture did not report two dirs"; return 1; }
  while read -r dir; do
    [ ! -e "$dir" ] || { echo "  leftover after early-failure cleanup: $dir"; return 1; }
  done < "$d/dirs"

  # The normal exit path is just as clean, and the run leaves the whole
  # TMPDIR root empty (nothing but the fixture scripts' own files).
  cat > "$d/fixture2.sh" <<'EOF'
#!/usr/bin/env bash
set -eu
. "$1"
printf '%s\n%s\n' "$(new_tmp_dir)" "$(new_tmp_dir)"
EOF
  env TMPDIR="$d/tmp" bash "$d/fixture2.sh" "$HARNESS_LIB" > "$d/dirs2" 2>/dev/null \
    || { echo "  clean-exit fixture failed"; return 1; }
  while read -r dir; do
    [ ! -e "$dir" ] || { echo "  leftover after clean-exit cleanup: $dir"; return 1; }
  done < "$d/dirs2"
  [ -z "$(find "$d/tmp" -mindepth 1 -print -quit)" ] \
    || { echo "  run left content under its TMPDIR root"; return 1; }
  return 0
}

# ---- run all -----------------------------------------------------------------

run_test "harness-01: a suite sourcing the harness library reproduces the copy-pasted helpers byte-for-byte (PASS/FAIL/SKIP shapes, accounting, exit status)" test_harness_01_sourced_suite_matches_copied_helpers
run_test "harness-01: registered-only-pass suite prints the frozen contract transcript and exits 0 exactly when no registered test failed" test_harness_01_pass_only_exit_zero
run_test "harness-01: a suite that sources tests/harness.sh defines none of the helpers itself and resolves them all from the library" test_harness_01_sourced_suite_defines_no_helpers

run_test "harness-02: new_tmp_dir creates under TMPDIR (or the /tmp fallback) and never under the repo working tree or the user config, leaving canary HOME/XDG empty" test_harness_02_new_tmp_dir_is_under_tmpdir_never_repo_or_userconfig
run_test "harness-02: every library render runs with HOME at a sandbox under temp space and XDG_CONFIG_HOME cleared, so install.sh writes only inside the sandbox" test_harness_02_render_runs_with_sandbox_home_and_cleared_xdg
run_test "harness-02: no helper writes into the real ~/.claude, ~/.config/opencode, or ~/.config/antz while staging and rendering" test_harness_02_no_helper_writes_to_real_user_config

run_test "harness-03: rendering one staged tree twice executes install.sh exactly once and reuses the identical installed tree (contents and mtimes unchanged, still complete)" test_harness_03_repeated_render_of_one_staged_tree_executes_install_once
run_test "harness-03: rendering a different staged tree performs its own render, exercising that tree's staged state" test_harness_03_render_of_a_different_staged_tree_performs_its_own_render

# harness-04 and harness-05 are whole-test-area end-state scans ("only
# tests/harness.sh invokes install.sh"; "every helper definition lives in
# tests/harness.sh"). Per the change README's dependency note and this
# session's delegation, they complete only when the 38 suites are migrated
# to sourcing the library -- the later sub-specs' work, re-asserted
# permanently by the hygiene suite (09). Explicit stubs, so no scenario id
# is silently unaccounted for; the library side they need (a single
# definition and invocation point) exists and is proven green above.
skip_test "harness-04: the area scan for install.sh invocations outside tests/harness.sh" \
  "deferred to the suite-migration sub-specs (02-09): all 38 suites still carry their own invocations until migrated; the library is the single invocation point from this sub-spec on"
skip_test "harness-05: the area scan for helper definitions outside tests/harness.sh, and the suites' unchanged scenario-id registrations" \
  "deferred to the suite-migration sub-specs (02-09): all 38 suites still define their own copies until migrated; harness.sh is the single definition from this sub-spec on"

run_test "harness-06: cleanup removes every directory new_tmp_dir created for the run, also on early failure, leaving the TMPDIR root empty" test_harness_06_cleanup_removes_every_new_tmp_dir_even_on_early_failure
run_test "harness-06: stage_checkout copies the working tree's current product files (install.sh, VERSION, CHANGELOG.md, agents/, scripts/orchestration/) into a fresh temp tree, with the optional VERSION override honored" test_harness_06_stage_checkout_copies_current_working_tree_products

finish_suite
