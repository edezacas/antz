#!/usr/bin/env bash
# Unit test for the render-consistency guard of change orchestrator-fast-path
# (spdd/changes/orchestrator-fast-path/03-testharness.feature, scenario
# testharness-04), re-scoped by change deembed-orchestration-scripts
# (sub-spec 05, testsuite-07) from fences to files.
#
# The guard's duty is unchanged: installed artifact and source file can never
# drift apart silently. Its surface moved: the orchestrator body embeds no
# script anymore, so the comparison now runs on the libdir install -- each
# installed ~/.config/antz/scripts/<name>.sh must equal its
# scripts/orchestration/<name>.sh source byte-for-byte after stripping the
# single inserted marker line (install_libdir_script's one
# "# antz:generated ..." header comment, immediately after the shebang).
# The old fence-extraction machinery and its antz-skills.sh under-fence-indent
# carve-out are gone with the embed -- nothing is left to re-apply.
#
# Drift is still mechanized: tampering one byte of one installed libdir
# script (after a fresh render) makes the guard report exactly that script
# out of sync.
#
# install.sh's CLI is the test affordance: a full render (--all, both
# clients) runs against an isolated temp HOME with the session's
# XDG_CONFIG_HOME masked, so the libdir resolves inside the temp home and no
# filesystem work ever touches the real ~/.claude, ~/.config, or ~/.config/
# antz. Self-contained bash harness (no external framework/dependency -- this
# repo has no package manager or build system), same pattern as
# tests/renderinject_test.sh. Run directly:
#   ./tests/orchestrator-render-sync_test.sh
#
# Every reported test name embeds its scenario id (testharness-04, plus the
# testsuite-07 re-key pin) so a failure maps straight back to the scenario it
# covers.

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INSTALL_SH="$SCRIPT_DIR/install.sh"
SCRIPTS="antz-flow antz-probe"

pass_count=0
fail_count=0

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

# ---- render affordance ------------------------------------------------------

render_all() {
  # Renders the full install (both clients, plus the libdir scripts) from the
  # working tree into the isolated HOME $1, logging stdout+stderr to $2.
  # Hermetic: XDG_CONFIG_HOME is masked so the resolved libdir lives inside
  # the temp home (testsuite-05's convention, applied here too).
  home="$1"; log="$2"
  (cd "$SCRIPT_DIR" && env -u XDG_CONFIG_HOME HOME="$home" sh ./install.sh --all > "$log" 2>&1)
}

# The libdir install of the scripts, under a rendered temp home.
installed_dir() {
  printf '%s' "$1/.config/antz/scripts"
}

# Prints the installed copy of script $1 with the single inserted marker line
# (line 2, a "# antz:generated ..." header comment immediately after the
# shebang) stripped; if line 2 is not that marker, the content prints
# unchanged and the comparison that follows will report the drift.
strip_marker_line() {
  awk 'NR == 2 && /^# antz:generated / { next } { print }' "$1"
}

out_of_sync_scripts() {
  # $1 = rendered temp home. Prints the space-separated scripts whose
  # installed libdir copy differs from the source file after the marker-line
  # strip (empty output = every installed script matches its source
  # byte-for-byte; a missing installed file also counts as out of sync).
  home="$1"
  dir=$(installed_dir "$home")
  bad=""
  for s in $SCRIPTS; do
    installed="$dir/$s.sh"
    if [ ! -f "$installed" ]; then
      bad="$bad $s"
      continue
    fi
    d=$(new_tmp_dir)
    strip_marker_line "$installed" > "$d/stripped"
    cmp -s "$d/stripped" "$SCRIPT_DIR/scripts/orchestration/$s.sh" || bad="$bad $s"
  done
  # Trim the leading space so the caller can match exact single-script
  # drift reports.
  printf '%s' "${bad# }"
}

# =============================================================================
# testharness-04 (re-keyed by testsuite-07): each installed libdir script
# equals its scripts/orchestration/ source byte-for-byte after stripping the
# single inserted marker line.
# =============================================================================
test_testharness_04_installed_matches_source() {
  home=$(new_tmp_dir)/home
  log="$home-render.log"
  tmp_roots+=("$(dirname "$log")")
  render_all "$home" "$log" \
    || { echo "  install.sh --all failed: $(cat "$log")"; return 1; }
  bad=$(out_of_sync_scripts "$home")
  [ -z "$bad" ] \
    || { echo "  installed libdir scripts differ from their sources after the marker-line strip: $bad"; return 1; }
  # The inserted line is exactly one line, and it is the marker: the
  # installed copy is the source plus one (shebang preserved).
  dir=$(installed_dir "$home")
  for s in $SCRIPTS; do
    src_n=$(wc -l < "$SCRIPT_DIR/scripts/orchestration/$s.sh")
    inst_n=$(wc -l < "$dir/$s.sh")
    [ "$inst_n" -eq $((src_n + 1)) ] \
      || { echo "  $s.sh installed with $inst_n lines, expected $((src_n + 1)) (source + marker)"; return 1; }
    head -n 1 "$dir/$s.sh" | grep -qx '#!/bin/sh' \
      || { echo "  $s.sh installed copy lost the source shebang at line 1"; return 1; }
    sed -n '2p' "$dir/$s.sh" | grep -q '^# antz:generated ' \
      || { echo "  $s.sh installed line 2 is not the antz:generated marker"; return 1; }
  done
  return 0
}

# =============================================================================
# testharness-04 (drift half, re-keyed): tampering one byte of one installed
# libdir script makes the guard report exactly that script out of sync (the
# others still matching).
# =============================================================================
test_testharness_04_drift_is_caught() {
  home=$(new_tmp_dir)/home
  log="$home-render.log"
  render_all "$home" "$log" \
    || { echo "  install.sh --all failed: $(cat "$log")"; return 1; }
  dir=$(installed_dir "$home")
  [ -f "$dir/antz-probe.sh" ] || { echo "  missing installed antz-probe.sh"; return 1; }
  # Tamper one byte below the marker line: flip the first executable-looking
  # line after line 2 of the installed probe copy.
  target=$(awk 'NR > 2 && /^[a-z_]+=/ { print NR; exit }' "$dir/antz-probe.sh")
  [ -n "$target" ] || { echo "  no assignable line found to tamper"; return 1; }
  sed -i "${target}s/$/_TAMPERED/" "$dir/antz-probe.sh"
  bad=$(out_of_sync_scripts "$home")
  [ "$bad" = "antz-probe" ] \
    || { echo "  expected exactly antz-probe out of sync after the tamper, got: '$bad'"; return 1; }
  return 0
}

# =============================================================================
# testsuite-07 (change deembed-orchestration-scripts): the re-key itself. The
# fence-extraction machinery is gone from this suite (no definitions, no
# call sites), the antz-skills.sh under-fence-indent carve-out is gone, and
# the file-vs-source comparison above is what now carries the duty. The
# needles are split below so this scan can never match its own lines.
# =============================================================================
test_testsuite_07_guard_compares_files() {
  ok=0
  self="$SCRIPT_DIR/tests/orchestrator-render-sync_test.sh"
  for needle in 'extract_''fences' 'expected_''block' "s/^     done\$/  done/"; do
    n=$(grep -v '^[[:space:]]*#' "$self" | grep -cF -- "$needle" || true)
    [ "$n" -eq 0 ] \
      || { echo "  the retired fence-era helper still has $n non-comment mention(s): $needle"; ok=1; }
  done
  # The new comparison surface is live: the marker-strip helper and the
  # byte-for-byte cmp against scripts/orchestration/ sources.
  grep -qF 'strip_marker_line' "$self" \
    || { echo "  the marker-line strip helper is missing"; ok=1; }
  grep -qF 'cmp -s "$d/stripped" "$SCRIPT_DIR/scripts/orchestration/$s.sh"' "$self" \
    || { echo "  the file-vs-source byte-for-byte comparison is missing"; ok=1; }
}

# ---- run everything ---------------------------------------------------------

run_test "testharness-04: each installed libdir script equals its scripts/orchestration/ source byte-for-byte after stripping the single inserted marker line" test_testharness_04_installed_matches_source
run_test "testharness-04: a file change without a matching re-render is caught -- one tampered byte in an installed libdir script reports that script out of sync" test_testharness_04_drift_is_caught
run_test "testsuite-07: the drift guard compares installed files against sources -- fence-extraction and the skills carve-out are gone" test_testsuite_07_guard_compares_files

echo ""
echo "$pass_count passed, $fail_count failed"
[ "$fail_count" -eq 0 ]
