#!/usr/bin/env bash
# Unit tests for install.sh's POSIX-sh parseability surface: the posixsh
# scenarios of the posixsh domain spec (posixsh-01..04), re-keyed to the
# current version's behavior by change optimize-test-suite's sub-spec
# 07-posixshfix (posixshfix-01..04).
#
# Current-version law (the re-key's premise): every expectation derives from
# the working tree's install.sh alone. This suite extracts nothing from git
# history, compares nothing against the default branch, and counts no lines
# through a text comparison. The old posixsh-04 pair -- a HOME-tree identity
# against a base render, and a base-vs-working console report diff whose
# empty-removal counting idiom reported an empty diff as one line (the "got:
# 1" root red) -- is re-keyed to ONE console-inventory registration: a
# single fresh hermetic --all render asserted, whole-report and in order,
# against the documented 22-line inventory (two client status lines, four
# script-artifact report lines, twelve client "Installed" lines, four libdir
# "Installed" lines; the outcome vocabulary is libdirinstall-04's, and the
# sixteen-file HOME tree those renders create is pinned by the render and
# libdir suites, not here).
#
# The shared harness library (tests/harness.sh) provides the plumbing helpers
# (run_test, skip_test, temp bookkeeping, cleanup, the content readers, and
# the install render helper install_at that posixsh-04 renders through); this
# suite defines none of them itself. Run directly:
#   sh tests/installsh-posixsh_test.sh
#
# Each reported test name embeds its scenario id (posixsh-01..04,
# posixshfix-01..04), so a failure maps straight back to the scenario it
# covers. Every test that touches the filesystem runs against isolated temp
# dirs, never the real ~/.claude or ~/.config/opencode.
#
# posixsh-02 needs a bash-3.2.57 binary; it is provisioned through
# tests/bash32-sh.sh (cached after the first run). If provisioning fails
# (no gcc/make/curl, no network, refused tarball, build failure), the test
# reports SKIP with the machine reason -- an environmental limitation, not a
# code failure, and not a BLOCKED code refusal (the posixsh-01 mechanical
# scan still guards the fix either way).

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INSTALL_SH="$SCRIPT_DIR/install.sh"
BASH32_HELPER="$SCRIPT_DIR/tests/bash32-sh.sh"
# This suite's own source, the scan surface of the posixshfix structural
# clauses (a suite may read its own file).
SELF="$SCRIPT_DIR/tests/installsh-posixsh_test.sh"

# shellcheck source=tests/harness.sh
. "$SCRIPT_DIR/tests/harness.sh"

# ---- helpers ---------------------------------------------------------------

# Writes the synthetic heredoc-in-command-substitution trap fixture (the
# construct class bash 3.2 mis-parses, the exact single-line shape the
# pre-fix install.sh carried) to $1.
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
  # scanner must find exactly 3 there, forever, from this file alone. (The
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
  # The current install.sh must parse clean under the macOS-fidelity parser.
  if ! "$BASH32" --posix -n "$INSTALL_SH" 2>"$err"; then
    echo "fixed install.sh failed bash3.2 --posix -n: $(cat "$err")"
    return 1
  fi
  [ ! -s "$err" ] || { echo "unexpected stderr on fixed parse: $(cat "$err")"; return 1; }
  # Proof the instrument reproduces the macOS failure: the synthetic trap
  # fixture must always fail to parse -- the negative control, carried by
  # the fixture alone.
  fixture=$(new_tmp_dir)/fixture.sh
  write_trap_fixture "$fixture"
  fixture_err=$(new_tmp_dir)/fixture-err.txt
  if "$BASH32" -n "$fixture" >/dev/null 2>"$fixture_err"; then
    echo "trap fixture unexpectedly parsed clean -- instrument lost the defect"
    return 1
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
#
# The single console-inventory registration (re-keyed by sub-spec 07): one
# fresh hermetic --all render of the CURRENT install.sh, through the harness
# library's render helper, asserted whole-report and in order against the
# documented 22-line report inventory -- two client status lines, four
# script-artifact report lines, twelve client "Installed" lines, four libdir
# "Installed" lines. The version token is the only free slot (the outcome
# vocabulary libdirinstall-04 pins carries it); every other byte is pinned.
# The whole-report cmp means no line count is ever derived from a
# comparison, so the empty-removal "got: 1" bug class cannot recur. The
# sixteen-file HOME tree the render creates is pinned by the render and
# libdir suites.

posixsh_04() {
  home=$(new_tmp_dir)/home
  mkdir -p "$home"
  log=$(new_tmp_dir)/report.log
  # XDG_CONFIG_HOME cleared by the helper, so the libdir resolves inside the
  # sandbox HOME -- hermetic, never the developer's real config directory.
  install_at "$home" "$INSTALL_SH" --all > "$log" 2>&1 \
    || { echo "fresh --all render failed: $(cat "$log")"; return 1; }
  # Normalize the two volatile pieces: the sandbox HOME prefix inside the
  # "Installed <dest>" lines, and the version token inside the six outcome
  # lines (each exactly one non-space word).
  norm=$(new_tmp_dir)/report.norm
  exp=$(new_tmp_dir)/report.expected
  sed -e "s|$home||g" \
      -e 's|^\(.*: fresh install of antz\) [^ ]*$|\1 @VERSION@|' \
      "$log" > "$norm"
  cat > "$exp" <<'INVENTORY'
Claude Code: fresh install of antz @VERSION@
OpenCode: fresh install of antz @VERSION@
antz-flow.sh: fresh install of antz @VERSION@
antz-probe.sh: fresh install of antz @VERSION@
antz-skills.sh: fresh install of antz @VERSION@
antz-set-model.sh: fresh install of antz @VERSION@
Installed /.claude/agents/antz-specifier.md
Installed /.config/opencode/agents/antz-specifier.md
Installed /.claude/agents/antz-coder.md
Installed /.config/opencode/agents/antz-coder.md
Installed /.claude/agents/antz-verifier.md
Installed /.config/opencode/agents/antz-verifier.md
Installed /.claude/agents/antz-orchestrator.md
Installed /.config/opencode/agents/antz-orchestrator.md
Installed /.claude/commands/antz.md
Installed /.claude/commands/antz-set-model.md
Installed /.config/opencode/commands/antz.md
Installed /.config/opencode/commands/antz-set-model.md
Installed /.config/antz/scripts/antz-flow.sh
Installed /.config/antz/scripts/antz-probe.sh
Installed /.config/antz/scripts/antz-skills.sh
Installed /.config/antz/scripts/antz-set-model.sh
INVENTORY
  if ! cmp -s "$exp" "$norm"; then
    echo "fresh --all report does not match the documented inventory:"
    echo "--- expected ---"; sed 's/^/  /' "$exp"
    echo "--- actual ---"; sed 's/^/  /' "$norm"
    return 1
  fi
  return 0
}

# ---- posixshfix-01..04 (change optimize-test-suite, sub-spec 07) ---------
#
# Structural scans over this suite's own source: the current-version-only
# re-key of posixsh-04 (direct console inventories instead of a
# base-vs-working render diff), the retirement of the base-extraction
# machinery and the tree-identity registration, and the freedom of the
# retained suite from history comparisons and prose pins. The suite's
# "exits 0 with every id green" clauses are bought by the recorded run
# itself (permanent law 1: no suite executes another suite, this one
# included).

mk() {
  # Prints the plain concatenation of its arguments. Used to spell forbidden
  # strings in two fragments so this file never carries whole the literals
  # its own scans forbid (the quote-split needle pattern).
  s=""
  for a in "$@"; do s="$s$a"; done
  printf '%s' "$s"
}

count_f() {
  # $1 = fixed needle, $2 = file: number of lines containing the needle.
  c=$(grep -cF "$1" "$2" 2>/dev/null || true)
  printf '%s' "${c:-0}"
}

suite_nc_file() {
  # Writes this suite's source minus full-line comments to $1 -- the
  # whole-suite scan surface of the posixshfix clauses.
  grep -v '^[[:space:]]*#' "$SELF" > "$1"
}

body_nc_file() {
  # $1 = function name, $2 = output file: the named function's source body
  # minus its full-line comment lines.
  raw=$(new_tmp_dir)/body.raw
  extract_fn "$SELF" "$1" "$raw"
  grep -v '^[[:space:]]*#' "$raw" > "$2"
}

posixshfix_01() {
  ok=0
  b4=$(new_tmp_dir)/posixsh_04.nc
  body_nc_file posixsh_04 "$b4"
  nc=$(new_tmp_dir)/suite.nc
  suite_nc_file "$nc"
  n_at=$(mk 'install_' 'at')
  n_d=$(mk 'di' 'ff')
  n_vxF=$(mk 'grep -vx' 'F')
  n_empty=$(mk 'grep -c ' "''")
  # One render through the harness library's render helper, of the CURRENT
  # install.sh; no second render of any other source.
  [ "$(count_f "$n_at" "$nc")" -eq 1 ] || {
    echo "  expected exactly one $n_at line in the suite, found $(count_f "$n_at" "$nc")"
    ok=1
  }
  grep -F "$n_at" "$nc" | grep -qF 'INSTALL_SH' || {
    echo "  the suite's single render helper line does not reference INSTALL_SH (the current install.sh)"
    ok=1
  }
  # The documented inventory and its order are embedded in the clause.
  require "$b4" 'Claude Code: fresh install of antz @VERSION@' || ok=1
  require "$b4" 'OpenCode: fresh install of antz @VERSION@' || ok=1
  require "$b4" 'antz-set-model.sh: fresh install of antz @VERSION@' || ok=1
  require "$b4" 'Installed /.claude/agents/antz-specifier.md' || ok=1
  require "$b4" 'Installed /.config/opencode/commands/antz-set-model.md' || ok=1
  require "$b4" 'Installed /.config/antz/scripts/antz-set-model.sh' || ok=1
  # Order is asserted by the whole-report cmp, never by a counted view.
  require "$b4" 'cmp -s' || ok=1
  refuse "$b4" "$n_d" || ok=1
  # The empty-count bug class cannot recur: no comparison machinery and no
  # comparison-derived line count remains anywhere in the suite.
  refuse "$nc" "$n_d" || ok=1
  refuse "$nc" "$n_vxF" || ok=1
  refuse "$nc" "$n_empty" || ok=1
  # The clause itself runs green at the current disk state.
  if ! posixsh_04; then
    echo "  posixsh-04's console-inventory clause is not green at the current disk state"
    ok=1
  fi
  [ "$ok" -eq 0 ]
}

posixshfix_02() {
  ok=0
  nc=$(new_tmp_dir)/suite.nc
  suite_nc_file "$nc"
  # The base-extraction machinery is gone from the whole suite.
  refuse "$nc" "$(mk 'base_install_' 'sh')" || ok=1
  refuse "$nc" "$(mk 'base_install_' 'file')" || ok=1
  refuse "$nc" "$(mk 'prep_base_if_' 'distinct')" || ok=1
  refuse "$nc" "$(mk '$ba' 'se')" || ok=1
  refuse "$nc" "$(mk 'merge-' 'base')" || ok=1
  # The tree-identity registration is gone: it rendered a second install.sh
  # source and byte-compared two trees.
  refuse "$nc" "$(mk 'byte-identic' 'al')" || ok=1
  refuse "$nc" "$(mk 'pre-fix ren' 'der')" || ok=1
  # The suite sources the harness library and defines none of its helpers.
  require "$nc" '. "$SCRIPT_DIR/tests/harness.sh"' || ok=1
  defs_re='^(run_te''st|skip_te''st|new_tm''p_dir|clea''nup|fin''ish_suite|requi''re|refu''se|extract_sec''tion|extract_bu''llet|extract_bulle''t_line|extract_li''ne|extract_f''n|stage_che''ckout|install_''at|install_xd''g|render_''tree)\(\)'
  defs=$(grep -Ec "$defs_re" "$nc" || true)
  [ "${defs:-0}" -eq 0 ] || {
    echo "  the suite still defines $defs library helper(s) locally"
    ok=1
  }
  # posixsh-01 keeps its synthetic-fixture pin and drops the historical
  # clause; posixsh-02's negative control is the synthetic fixture alone.
  b1=$(new_tmp_dir)/posixsh_01.nc
  body_nc_file posixsh_01 "$b1"
  require "$b1" 'write_trap_fixture' || ok=1
  require "$b1" '-eq 3' || ok=1
  refuse "$b1" "$(mk 'ba' 'se')" || ok=1
  b2=$(new_tmp_dir)/posixsh_02.nc
  body_nc_file posixsh_02 "$b2"
  require "$b2" 'write_trap_fixture' || ok=1
  require "$b2" 'trap fixture unexpectedly parsed clean' || ok=1
  refuse "$b2" "$(mk 'ba' 'se')" || ok=1
  refuse "$b2" 'line 230' || ok=1
  # posixsh-01..03 keep their ids and registrations.
  rt=$(mk 'run_te' 'st')
  [ "$(count_f "$rt \"posixsh-01 " "$nc")" -eq 1 ] || ok=1
  [ "$(count_f "$rt \"posixsh-02 " "$nc")" -eq 1 ] || ok=1
  [ "$(count_f "$rt \"posixsh-03 " "$nc")" -eq 2 ] || ok=1
  [ "$ok" -eq 0 ]
}

posixshfix_03() {
  ok=0
  nc=$(new_tmp_dir)/suite.nc
  suite_nc_file "$nc"
  rt=$(mk 'run_te' 'st')
  # The retained posixsh-04 id keeps its name and is carried by exactly one
  # console registration, whose function is posixsh_04.
  [ "$(count_f "$rt \"posixsh-04 " "$nc")" -eq 1 ] || {
    echo "  expected exactly one posixsh-04 registration, found $(count_f "$rt \"posixsh-04 " "$nc")"
    ok=1
  }
  reg=$(grep -F "$rt \"posixsh-04 " "$nc")
  case "$reg" in
    *console*posixsh_04) ;;
    *) echo "  the posixsh-04 registration is not the console-inventory one: $reg"; ok=1 ;;
  esac
  # Every scenario id of this suite is carried by exactly its own
  # registrations: 5 posixsh + 4 posixshfix = 9 run_test lines.
  [ "$(count_f "$rt \"" "$nc")" -eq 9 ] || {
    echo "  expected 9 id-headed registrations, found $(count_f "$rt \"" "$nc")"
    ok=1
  }
  i=1
  while [ "$i" -le 4 ]; do
    [ "$(count_f "$rt \"posixshfix-0$i:" "$nc")" -eq 1 ] || {
      echo "  posixshfix-0$i is not carried by exactly one registration"
      ok=1
    }
    i=$((i + 1))
  done
  [ "$ok" -eq 0 ]
}

posixshfix_04() {
  ok=0
  nc=$(new_tmp_dir)/suite.nc
  suite_nc_file "$nc"
  # No comparison of the real tree against git history, no byte-pin against
  # HEAD: the history machinery cannot even be named in the suite.
  refuse "$nc" "$(mk 'gi' 't')" || ok=1
  refuse "$nc" "$(mk 'HEA' 'D')" || ok=1
  refuse "$nc" "$(mk 'merge-' 'base')" || ok=1
  refuse "$nc" "$(mk 'base_commit' ':')" || ok=1
  g=$(mk 'gi' 't')
  h=$(mk 'HEA' 'D')
  d=$(mk 'di' 'ff')
  refuse "$nc" "$g show" || ok=1
  refuse "$nc" "show $h:" || ok=1
  refuse "$nc" "$d --quiet" || ok=1
  refuse "$nc" "$d -" || ok=1
  # No exact-phrase prose pins of prompts or docs; assertions on install.sh
  # itself and on installed product files are not prose pins.
  refuse "$nc" "$(mk 'agents/p' 'rompts')" || ok=1
  refuse "$nc" "$(mk 'agents/me' 'ta')" || ok=1
  refuse "$nc" "$(mk '.pro' 'mpt')" || ok=1
  refuse "$nc" "$(mk 'AGENTS.m' 'd')" || ok=1
  refuse "$nc" "$(mk 'CLAUDE.m' 'd')" || ok=1
  refuse "$nc" "$(mk 'spd' 'd/')" || ok=1
  [ "$ok" -eq 0 ]
}

# ---- run -------------------------------------------------------------------

run_test "posixsh-01 no heredoc inside a command substitution" posixsh_01

run_test "posixsh-02 parse clean under macOS-fidelity POSIX sh (bash 3.2)" posixsh_02
if [ "${posixsh_02_rc:-0}" -eq 2 ]; then
  # The helper's SKIP path: downgrade the FAIL accounting run_test just did
  # into an explicit SKIP stub (environmental, not a code failure and not a
  # BLOCKED refusal -- posixsh-01's mechanical scan still guards the fix).
  fail_count=$((fail_count - 1))
  skip_test "posixsh-02 parse clean under macOS-fidelity POSIX sh (bash 3.2)" "${posixsh_02_skip:-bash32 provision failed}"
fi
unset posixsh_02_rc

run_test "posixsh-03 parse and execute clean under plain POSIX sh: sh -n" posixsh_03_parse
run_test "posixsh-03 parse and execute clean under plain POSIX sh: no-flag refusal" posixsh_03_execute
run_test "posixsh-04 fresh hermetic --all console report matches the documented line inventory and order" posixsh_04

run_test "posixshfix-01: posixsh-04's console half asserts the fresh render against the documented inventory and order, from the current install.sh alone, with no second render and no comparison-derived line count" posixshfix_01
run_test "posixshfix-02: the base-extraction machinery and the tree-identity registration are gone; every render uses the current install.sh; posixsh-01..03 keep their ids, registrations, and synthetic instruments" posixshfix_02
run_test "posixshfix-03: the retained posixsh-04 id keeps its name with exactly one console-inventory registration, and all nine scenario registrations are accounted for" posixshfix_03
run_test "posixshfix-04: the retained suite source holds no history comparison, no byte-pin against the default branch, and no exact-phrase pin of prompts or docs" posixshfix_04

finish_suite
