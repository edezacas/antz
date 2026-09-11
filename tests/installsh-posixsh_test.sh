#!/usr/bin/env bash
# Unit tests for install.sh's POSIX-sh parseability surface (the
# fix-install-sh-syntax change), covering every scenario in
# spdd/changes/fix-install-sh-syntax/01-posixsh.feature.
#
# Self-contained bash test harness (no external framework/dependency -- this
# repo has no package manager or build system), same pattern as
# tests/set-model-command_test.sh. Run directly:
#   ./tests/installsh-posixsh_test.sh
#
# Each reported test name embeds its scenario id (posixsh-01..04) from the
# feature file above, so a failure maps straight back to the scenario it
# covers. Every test that touches the filesystem runs against isolated temp
# dirs, never the real ~/.claude or ~/.config/opencode.
#
# posixsh-02 needs a bash-3.2.57 binary; it is provisioned through
# tests/bash32-sh.sh (cached after the first run). If provisioning fails
# (no gcc/make/curl, no network, refused tarball, build failure), the test
# reports SKIP with the machine reason -- an environmental limitation, not a
# code failure, and not a BLOCKED code refusal (the sub-spec's fix itself is
# implemented and guarded by the posixsh-01 mechanical scan either way).

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INSTALL_SH="$SCRIPT_DIR/install.sh"
BASH32_HELPER="$SCRIPT_DIR/tests/bash32-sh.sh"

pass_count=0
fail_count=0
skip_count=0

# ---- tiny test runner ------------------------------------------------------

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

# ---- helpers ---------------------------------------------------------------

# Prints the pre-fix install.sh to stdout, extracted from git at this
# change's base (merge-base with master) so the suite keeps passing after
# the change is committed. Falls back to HEAD when master is unknown.
base_install_sh() {
  base_commit=$(git -C "$SCRIPT_DIR" merge-base master HEAD 2>/dev/null) || base_commit=HEAD
  git -C "$SCRIPT_DIR" show "$base_commit:install.sh"
}

# Materializes the base install.sh to a temp file ($2) and echoes 1 when the
# base content is still distinct from the fixed tree ($1), 0 when the two
# already agree (a post-merge degenerate tree: the base is the fix itself,
# so base-derived negative assertions are vacuous and must not fail).
prep_base_if_distinct() {
  fixed="$1"; out="$2"
  base_install_sh > "$out"
  ! cmp -s "$fixed" "$out"
}

# Writes the synthetic heredoc-in-command-substitution trap fixture (the
# construct class bash 3.2 mis-parses, in the exact single-line shape the
# base install.sh carried at lines 204/424/448) to $1.
write_trap_fixture() {
  cat > "$1" <<'FIXTURE'
x=$(cat <<'INNER'
case "$1" in
  a) echo one ;;
esac
INNER
)
echo "$x"
FIXTURE
}

# ---- posixsh-01 ------------------------------------------------------------

# The mechanical scan from the feature's Background: every construct whose
# heredoc body is captured inside a shell command substitution, i.e. the
# pattern "<var>=$(cat <<'DELIM'" ... "DELIM" ")" spanning lines. Returns 0
# and prints nothing when the file is clean; on a hit prints the offending
# line number.
scan_heredoc_in_cmdsub() {
  # $1 = file to scan; prints the 1-based line number of every hit (one per
  # line), nothing when the construct class is absent.
  f="$1"
  grep -nF '$(cat <<' "$f" | sed 's/:.*//'
}

posixsh_01() {
  hits=$(scan_heredoc_in_cmdsub "$INSTALL_SH")
  if [ -n "$hits" ]; then
    echo "heredoc-in-command-substitution found at line(s): $hits"
    return 1
  fi
  # Second clause of the scenario: every heredoc body sits at top level or
  # directly inside a function body, never inside a command substitution.
  # The scan above IS that assertion for this construct class; pin the
  # scanner against false negatives with a synthetic three-hit file: the
  # scanner must find exactly 3 there, forever, without needing git. (The
  # pin is only scanned, never parsed -- three repeated heredocs would not
  # be a valid shell file.)
  one=$(new_tmp_dir)/one.sh
  write_trap_fixture "$one"
  pin=$(new_tmp_dir)/pin.sh
  cat "$one" "$one" "$one" > "$pin"
  pins=$(scan_heredoc_in_cmdsub "$pin" | grep -c "[0-9]")
  [ "$pins" -eq 3 ] || {
    echo "scanner drifted: synthetic 3-hit pin shows $pins hits (expected 3)"
    return 1
  }
  # Historical fidelity check: while this change's base tree is still
  # distinct (pre-merge), the same scan there must find exactly the three
  # documented instances (lines 204, 424, 448). Post-fix changes that
  # legitimately edit install.sh (e.g. skills-activation's readwrite tools
  # grant) leave the merge-base as neither the broken tree nor the fixed
  # tree; the base clause is then vacuous, not a failure -- a broken-era
  # signature (any hit) is required before asserting the count.
  base=$(new_tmp_dir)/base-install.sh
  if prep_base_if_distinct "$INSTALL_SH" "$base"; then
    base_hits=$(scan_heredoc_in_cmdsub "$base" | grep -c "[0-9]")
    if [ "$base_hits" -gt 0 ]; then
      [ "$base_hits" -eq 3 ] || {
        echo "scanner drifted: base tree shows $base_hits hits (expected 3)"
        return 1
      }
    fi
  fi
  return 0
}

# ---- posixsh-02 ------------------------------------------------------------

posixsh_02() {
  # Resolve the bash 3.2.57 binary inline (not inside $()), so the BASH32
  # variable survives into this function's process.
  out=$(sh "$BASH32_HELPER" 2>/dev/null) || {
    posixsh_02_rc=2
    posixsh_02_skip="bash32 provision failed: ${out:-no output from helper}"
    return 1
  }
  case "$out" in
    "<bash32="*">")
      BASH32=${out#<bash32=}
      BASH32=${BASH32%>}
      ;;
    *)
      posixsh_02_skip="bash32 provision failed: unexpected helper output"
      return 1
      ;;
  esac
  [ -x "$BASH32" ] || {
    posixsh_02_rc=2
    posixsh_02_skip="bash32 provision succeeded but the binary is not executable"
    return 1
  }
  err=$(new_tmp_dir)/err.txt
  # Fixed tree must parse clean under the macOS-fidelity parser.
  if ! "$BASH32" --posix -n "$INSTALL_SH" 2>"$err"; then
    echo "fixed install.sh failed bash3.2 --posix -n: $(cat "$err")"
    return 1
  fi
  [ ! -s "$err" ] || { echo "unexpected stderr on fixed parse: $(cat "$err")"; return 1; }
  # Proof the instrument reproduces the macOS failure -- two instruments:
  # (a) the synthetic trap fixture must always fail to parse; (b) while the
  # base tree is still distinct (pre-merge), the base commit's install.sh
  # must fail there with the reported error.
  fixture=$(new_tmp_dir)/fixture.sh
  write_trap_fixture "$fixture"
  fixture_err=$(new_tmp_dir)/fixture-err.txt
  if "$BASH32" -n "$fixture" >/dev/null 2>"$fixture_err"; then
    echo "trap fixture unexpectedly parsed clean -- instrument lost the defect"
    return 1
  fi
  base=$(new_tmp_dir)/base-install.sh
  if prep_base_if_distinct "$INSTALL_SH" "$base"; then
    # The base negative assertion only applies while the base is still the
    # documented broken tree (has the trap signature). Post-fix install.sh
    # changes (e.g. skills-activation) evolve the merge-base past that era;
    # the clause is then vacuous, like the base==fixed degenerate case.
    if [ -n "$(scan_heredoc_in_cmdsub "$base")" ]; then
      base_err=$(new_tmp_dir)/base-err.txt
      if "$BASH32" --posix -n "$base" >/dev/null 2>"$base_err"; then
        echo "base install.sh unexpectedly parsed clean -- instrument lost the defect"
        return 1
      fi
      grep -q "syntax error near unexpected token" "$base_err" || {
        echo "base failure was not the reported syntax error: $(cat "$base_err")"
        return 1
      }
      grep -q "line 230" "$base_err" || {
        echo "base failure was not at line 230: $(cat "$base_err")"
        return 1
      }
    fi
  fi
  return 0
}

# ---- posixsh-03 ------------------------------------------------------------

posixsh_03_parse() {
  err=$(new_tmp_dir)/err.txt
  if ! sh -n "$INSTALL_SH" 2>"$err"; then
    echo "sh -n failed: $(cat "$err")"
    return 1
  fi
  [ ! -s "$err" ] || { echo "unexpected stderr: $(cat "$err")"; return 1; }
  return 0
}

posixsh_03_execute() {
  home=$(new_tmp_dir)/home
  mkdir -p "$home"
  err=$(new_tmp_dir)/err.txt
  # A sanitized PATH: no claude/opencode CLI, and HOME with neither client
  # config directory -- so neither client is detected and the no-flag run
  # must refuse. The refusal happens after full-file parse (the script only
  # reaches its argument/detection logic having parsed the whole file).
  rc=0
  env -i HOME="$home" PATH="/usr/bin:/bin" sh "$INSTALL_SH" > /dev/null 2>"$err" || rc=$?
  [ "$rc" -ne 0 ] || { echo "expected a failure exit, got 0"; return 1; }
  [ "$rc" -lt 2 ] || { echo "expected a shell-refusal-free exit (parse/usage failure), got $rc: $(cat "$err")"; return 1; }
  grep -q "Neither Claude Code nor OpenCode detected" "$err" || {
    echo "refusal message missing from stderr: $(cat "$err")"
    return 1
  }
  # No file written anywhere under the isolated HOME.
  if [ -n "$(find "$home" -mindepth 1 -print -quit 2>/dev/null)" ]; then
    echo "HOME was written to despite the refusal: $(find "$home" -mindepth 1)"
    return 1
  fi
  return 0
}

# ---- posixsh-04 ------------------------------------------------------------

# Renders with install.sh at $2 (--all, isolated $1 as HOME), stdout+stderr
# to $3, returning the exit status.
render_tree() {
  home="$1"; install_sh="$2"; log="$3"
  mkdir -p "$home"
  HOME="$home" sh "$install_sh" --all > "$log" 2>&1
}

# The base install.sh materialized to a temp file (the pre-fix tree),
# extracted from git so the suite keeps passing after this change is
# committed. See prep_base_if_distinct.
base_install_file() {
  base=$(new_tmp_dir)/base-install.sh
  prep_base_if_distinct "$1" "$base" >/dev/null
  printf '%s' "$base"
}

posixsh_04() {
  old_home=$(new_tmp_dir)/old-home
  new_home=$(new_tmp_dir)/new-home
  base=$(base_install_file "$INSTALL_SH")
  olog=$(new_tmp_dir)/old-render.log; nlog=$(new_tmp_dir)/new-render.log
  render_tree "$old_home" "$base" "$olog" || { echo "pre-fix render failed: $(cat "$olog")"; return 1; }
  render_tree "$new_home" "$INSTALL_SH" "$nlog" || { echo "post-fix render failed: $(cat "$nlog")"; return 1; }
  # Byte-for-byte recursive comparison of the two HOME trees -- applies
  # while the base is the documented broken tree (the trap signature) and
  # the fix could have altered output. Post-fix install.sh changes
  # (e.g. skills-activation's readwrite tools grant) legitimately change the
  # render, so in that era the full-tree identity is vacuous; the render
  # must still succeed and the documented inventory must still hold below.
  if [ -n "$(scan_heredoc_in_cmdsub "$base")" ]; then
    treediff=$(new_tmp_dir)/treediff.txt
    if ! diff -r "$old_home" "$new_home" > "$treediff"; then
      head -20 "$treediff"
      return 1
    fi
  fi
  # The full documented inventory must actually be present in both trees
  # (diff -r alone would vacuously pass two equally empty trees).
  for f in \
    .claude/agents/antz-specifier.md .config/opencode/agents/antz-specifier.md \
    .claude/agents/antz-coder.md .config/opencode/agents/antz-coder.md \
    .claude/agents/antz-verifier.md .config/opencode/agents/antz-verifier.md \
    .claude/agents/antz-orchestrator.md .config/opencode/agents/antz-orchestrator.md \
    .claude/commands/antz.md .config/opencode/commands/antz.md \
    .claude/commands/antz-set-model.md .config/opencode/commands/antz-set-model.md; do
    [ -f "$new_home/$f" ] || { echo "missing installed file: $f"; return 1; }
  done
  # The heredoc-emitted set-model script text must be intact in the rendered
  # command bodies -- its `for arg do` line included (feature clause).
  grep -q '^for arg do$' "$new_home/.claude/commands/antz-set-model.md" || {
    echo "emitted set-model script's 'for arg do' line missing from the claude command body"
    return 1
  }
  grep -q '^for arg do$' "$new_home/.config/opencode/commands/antz-set-model.md" || {
    echo "emitted set-model script's 'for arg do' line missing from the opencode command body"
    return 1
  }
  return 0
}

# The console-report half of posixsh-04, as its own test so a console drift
# is distinguishable from a tree drift: stdout identical except for the HOME
# path prefixes inside the "Installed <dest>" lines.
posixsh_04_console() {
  old_home=$(new_tmp_dir)/old-home
  new_home=$(new_tmp_dir)/new-home
  base=$(base_install_file "$INSTALL_SH")
  olog=$(new_tmp_dir)/old-render.log; nlog=$(new_tmp_dir)/new-render.log
  render_tree "$old_home" "$base" "$olog" || { echo "pre-fix render failed: $(cat "$olog")"; return 1; }
  render_tree "$new_home" "$INSTALL_SH" "$nlog" || { echo "post-fix render failed: $(cat "$nlog")"; return 1; }
  # Strip the HOME prefixes inside the "Installed <dest>" lines, then compare.
  sed "s|$old_home||g" "$olog" > "$olog.n"
  sed "s|$new_home||g" "$nlog" > "$nlog.n"
  diff "$olog.n" "$nlog.n" || return 1
  return 0
}

# ---- run -------------------------------------------------------------------

run_test "posixsh-01 no heredoc inside a command substitution" posixsh_01

run_test "posixsh-02 parse clean under macOS-fidelity POSIX sh (bash 3.2)" posixsh_02
if [ "${posixsh_02_rc:-0}" -eq 2 ]; then
  # The helper's SKIP path: downgrade the FAIL accounting run_test just did
  # into an explicit SKIP stub (environmental, not a code failure and not a
  # BLOCKED refusal -- posixsh-01's mechanical scan still guards the fix).
  fail_count=$((fail_count - 1))
  echo "SKIP: posixsh-02 parse clean under macOS-fidelity POSIX sh (bash 3.2) (${posixsh_02_skip:-bash32 provision failed})"
  skip_count=$((skip_count + 1))
fi
unset posixsh_02_rc

run_test "posixsh-03 parse and execute clean under plain POSIX sh: sh -n" posixsh_03_parse
run_test "posixsh-03 parse and execute clean under plain POSIX sh: no-flag refusal" posixsh_03_execute
run_test "posixsh-04 rendered output byte-identical to the pre-fix render (HOME trees)" posixsh_04
run_test "posixsh-04 rendered output byte-identical to the pre-fix render (console report)" posixsh_04_console

echo
echo "pass=$pass_count fail=$fail_count skip=$skip_count"
[ "$fail_count" -eq 0 ]
