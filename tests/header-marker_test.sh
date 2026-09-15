#!/usr/bin/env bash
# Unit tests for install.sh's header-anchored antz:generated marker detection
# and the .bak.<timestamp> backup policy, covering every scenario in
# spdd/changes/hardening-installsh/01-marker.feature (marker-01..06).
#
# The change: a destination counts as antz-managed only when its content
# carries "# antz:generated " as a LINE-START header comment (install_file's
# grep and installed_version_of's sed are anchored; a mid-body mention of the
# marker no longer suppresses the backup nor passes as an installed version).
# The marker string and the rendered marker line's format are unchanged --
# only the detection is anchored. The policy (backups created exactly when an
# unmanaged destination is overwritten, never pruned automatically, cleanup
# is the user's) is additionally stated in install.sh's header comment, which
# is also completed to name all four agents and both commands.
#
# Hermetic since change deembed-orchestration-scripts sub-spec 01: every
# install run in this suite also unsets XDG_CONFIG_HOME, so the four libdir
# scripts that install.sh writes there resolve inside the staged HOME and a
# session's exported config home is never touched.
#
# Self-contained bash test harness (no external framework/dependency -- this
# repo has no package manager or build system), same pattern as
# tests/description-quoting_test.sh. Run directly:
#   ./tests/header-marker_test.sh
#
# Each reported test name embeds its scenario id (marker-01..06) from the
# feature file above, so a failure maps straight back to the scenario it
# covers. Every test that touches the filesystem runs against an isolated
# HOME (a fresh temp dir per test), never the real ~/.claude or
# ~/.config/opencode directories.

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INSTALL_SH="$SCRIPT_DIR/install.sh"

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

new_home() {
  mktemp -d
}

cleanup_note() { :; }  # per-test homes are rm -rf'd inline; no trap needed

# ---- fixture helpers --------------------------------------------------------

# The rendered marker line's format, unchanged by this change (Background):
# a line-start header comment "# antz:generated version=<X.Y.Z> -- do not
# edit by hand; regenerate with install.sh".
marker_line() {
  # $1 = version value
  printf '# antz:generated version=%s -- do not edit by hand; regenerate with install.sh\n' "$1"
}

CURRENT_VERSION=$(tr -d ' \t\r\n' < "$SCRIPT_DIR/VERSION")

write_managed_agent_fixture() {
  # $1 = dest path, $2 = version embedded in the line-start header marker.
  # A copy that legitimately IS antz-managed: header comment at line start,
  # mirroring render_claude's frontmatter shape.
  dest="$1"; ver="$2"
  mkdir -p "$(dirname "$dest")"
  {
    echo '---'
    marker_line "$ver"
    echo 'name: antz-specifier'
    echo 'description: An old antz-managed copy.'
    echo 'tools: Read, Grep, Glob, Bash'
    echo '---'
    echo ''
    echo "Body of the old managed copy ($ver)."
  } > "$dest"
}

write_pseudo_managed_fixture() {
  # $1 = dest path. A user file that is NOT antz-generated but mentions the
  # marker string ONLY somewhere other than a line-start header comment:
  # mid-line in the description and indented inside the body. The whole
  # point of the anchored detection: this must count as unmanaged.
  dest="$1"
  mkdir -p "$(dirname "$dest")"
  {
    echo '---'
    echo 'name: antz-specifier'
    echo "description: A user's own agent; docs mention antz:generated mid-line somewhere."
    echo 'tools: Read'
    echo '---'
    echo ''
    echo 'Body prose that quotes the marker, indented, not at line start:'
    echo "    $(marker_line 9.9.9)"
  } > "$dest"
}

count_backups() {
  # $1 = dir, $2 = base name -> number of ".bak.*" siblings
  find "$1" -maxdepth 1 -name "$2.bak.*" 2>/dev/null | wc -l | tr -d ' '
}

# ---- marker-01 --------------------------------------------------------------
# A destination whose content carries the marker as a line-start header
# comment is recognized as antz-managed and overwritten in place, no backup.

marker_01() {
  home=$(new_home); ok=0
  dest="$home/.claude/agents/antz-specifier.md"
  write_managed_agent_fixture "$dest" 1.2.3

  ( cd "$SCRIPT_DIR" && env -u XDG_CONFIG_HOME HOME="$home" sh ./install.sh --claude > "$home/install.log" 2>&1 ) \
    || { echo "  install.sh --claude failed"; ok=1; }

  # overwritten in place with the new render (current VERSION in the header)
  grep -qxF "$(marker_line "$CURRENT_VERSION")" "$dest" \
    || { echo "  managed destination was not overwritten with the fresh render"; ok=1; }
  grep -qF "Body of the old managed copy (1.2.3)." "$dest" \
    && { echo "  old body survived the overwrite"; ok=1; }
  # no backup created for it
  [ "$(count_backups "$home/.claude/agents" 'antz-specifier.md')" -eq 0 ] \
    || { echo "  a .bak.<timestamp> file was created for a managed destination"; ok=1; }

  rm -rf "$home"
  return $ok
}

# ---- marker-02 --------------------------------------------------------------
# The closed hole: a file that mentions "antz:generated" only somewhere other
# than a line-start header comment is NOT antz-managed -- it is backed up
# before the overwrite, exactly like any other unmanaged file.

marker_02() {
  home=$(new_home); ok=0
  dest="$home/.claude/agents/antz-specifier.md"
  write_pseudo_managed_fixture "$dest"
  cp "$dest" "$home/original.copy"

  ( cd "$SCRIPT_DIR" && env -u XDG_CONFIG_HOME HOME="$home" sh ./install.sh --claude > "$home/install.log" 2>&1 ) \
    || { echo "  install.sh --claude failed"; ok=1; }

  baks="$home/.claude/agents/antz-specifier.md.bak."*
  # shellcheck disable=SC2086
  set -- $baks
  [ "$#" -eq 1 ] && [ -f "$1" ] \
    || { echo "  expected exactly one backup '<destination>.bak.<timestamp>', got: $*"; ok=1; }
  if [ -f "${1:-}" ]; then
    case "${1##*.}" in
      [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) ;;
      *) echo "  backup suffix is not a <YYYYMMDDHHMMSS> timestamp: $1"; ok=1 ;;
    esac
    cmp -s "$1" "$home/original.copy" \
      || { echo "  backup does not hold the original content byte-for-byte"; ok=1; }
  fi
  # destination overwritten with the fresh managed render
  grep -qxF "$(marker_line "$CURRENT_VERSION")" "$dest" \
    || { echo "  destination was not overwritten with the fresh managed render"; ok=1; }
  # console output states the file was backed up as not antz-managed
  grep -qF 'not antz-managed' "$home/install.log" \
    || { echo "  console output does not state the backup as 'not antz-managed'"; ok=1; }

  rm -rf "$home"
  return $ok
}

# ---- marker-03 --------------------------------------------------------------
# installed_version_of reads the embedded version only from the line-start
# header comment: a body-mention of antz:generated version=9.9.9 makes
# --check report a fresh install of the current VERSION, while a real header
# marker still reports its embedded version.

marker_03() {
  home=$(new_home); ok=0
  dest="$home/.claude/agents/antz-specifier.md"
  write_pseudo_managed_fixture "$dest"

  ( cd "$SCRIPT_DIR" && env -u XDG_CONFIG_HOME HOME="$home" sh ./install.sh --claude --check > "$home/check.log" 2>&1 ) \
    || { echo "  install.sh --check failed"; ok=1; }
  # fresh install of the current VERSION, not "already up to date (antz 9.9.9)"
  grep -qF "fresh install of antz $CURRENT_VERSION" "$home/check.log" \
    || { echo "  --check did not report a fresh install for the mid-body-marker file"; ok=1; }
  grep -qF '9.9.9' "$home/check.log" \
    && { echo "  --check passed a body-mentioned 9.9.9 as the installed version"; ok=1; }
  # --check writes nothing
  [ -f "$dest" ] || { echo "  --check modified the destination"; ok=1; }

  # and a file whose frontmatter DOES carry the line-start header marker
  # still reports the version embedded in that header comment
  home2=$(new_home)
  write_managed_agent_fixture "$home2/.claude/agents/antz-specifier.md" 1.2.3
  ( cd "$SCRIPT_DIR" && env -u XDG_CONFIG_HOME HOME="$home2" sh ./install.sh --claude --check > "$home2/check.log" 2>&1 ) \
    || { echo "  install.sh --check (managed fixture) failed"; ok=1; }
  grep -qF '1.2.3' "$home2/check.log" \
    || { echo "  --check lost the version embedded in a real header marker"; ok=1; }
  # Refuse the fresh-install REPORT LINE ("<label>: fresh install of antz
  # X.Y.Z"), not the bare phrase: a version drift makes --check print every
  # intervening CHANGELOG entry, and entry prose may legitimately contain
  # "fresh install" (06-bump470's [4.7.0] entry does, describing this very
  # behavior). The report line's colon-anchored shape is what --check emits
  # for an unmanaged file.
  #
  # Re-scoped by change deembed-orchestration-scripts (sub-spec 01,
  # libdirinstall-04, loud note per the repo's re-scope convention): the
  # unanchored shape also matched the NEW script-artifact report lines
  # ("antz-flow.sh: fresh install of antz X.Y.Z"), which libdirinstall-04
  # requires --check to emit and which this scenario's fixture never
  # installs (its HOME has no libdir copies). marker-03's spec sentence is
  # about THAT CLIENT'S report ("that client's report says ... not 'already
  # up to date'"), so the refusal is tightened to its actual subject: the
  # per-client report line. The libdir lines' own shape is pinned by
  # tests/libdirinstall_test.sh.
  grep -qE '^Claude Code: fresh install of antz ' "$home2/check.log" \
    && { echo "  --check called a header-marked file a fresh install"; ok=1; }

  rm -rf "$home" "$home2"
  return $ok
}

# ---- marker-04 --------------------------------------------------------------
# The policy as behavior: a backup is created exactly when the destination
# exists without the line-start header marker; install.sh never reads,
# renames, or deletes existing backups; re-runs over managed files create
# none; accumulated backups survive under their original names.

marker_04() {
  home=$(new_home); ok=0
  dir="$home/.claude/agents"
  dest="$dir/antz-specifier.md"
  write_managed_agent_fixture "$dest" 1.2.3
  printf 'first accumulated backup\n' > "$dir/antz-specifier.md.bak.20260101010101"
  printf 'second accumulated backup\n' > "$dir/antz-specifier.md.bak.20260202020202"

  ( cd "$SCRIPT_DIR" && env -u XDG_CONFIG_HOME HOME="$home" sh ./install.sh --claude >/dev/null 2>&1 ) || ok=1
  ( cd "$SCRIPT_DIR" && env -u XDG_CONFIG_HOME HOME="$home" sh ./install.sh --claude >/dev/null 2>&1 ) || ok=1

  # no new backup created by either run; both pre-existing ones survive
  # byte-for-byte under their original names
  [ -f "$dir/antz-specifier.md.bak.20260101010101" ] \
    || { echo "  pre-existing backup .bak.20260101010101 was removed or renamed"; ok=1; }
  [ -f "$dir/antz-specifier.md.bak.20260202020202" ] \
    || { echo "  pre-existing backup .bak.20260202020202 was removed or renamed"; ok=1; }
  grep -qF 'first accumulated backup' "$dir/antz-specifier.md.bak.20260101010101" 2>/dev/null \
    || { echo "  pre-existing backup .bak.20260101010101 content was read/rewritten"; ok=1; }
  grep -qF 'second accumulated backup' "$dir/antz-specifier.md.bak.20260202020202" 2>/dev/null \
    || { echo "  pre-existing backup .bak.20260202020202 content was read/rewritten"; ok=1; }
  [ "$(count_backups "$dir" 'antz-specifier.md')" -eq 2 ] \
    || { echo "  a managed re-run created a new backup"; ok=1; }

  # a run against an unmanaged destination still creates exactly one backup,
  # named <destination>.bak.<YYYYMMDDHHMMSS>, of the content it overwrites
  printf 'a user file the second run overwrites\n' > "$dest"
  cp "$dest" "$home/original.copy"
  ( cd "$SCRIPT_DIR" && env -u XDG_CONFIG_HOME HOME="$home" sh ./install.sh --claude >/dev/null 2>&1 ) || ok=1
  [ "$(count_backups "$dir" 'antz-specifier.md')" -eq 3 ] \
    || { echo "  expected exactly one new backup of the unmanaged destination (3 total)"; ok=1; }
  newbak=$(ls "$dir" | grep -E '^antz-specifier\.md\.bak\.[0-9]{14}$' | grep -v -e 20260101010101 -e 20260202020202)
  [ "$(printf '%s\n' "$newbak" | grep -c .)" -eq 1 ] \
    || { echo "  new backup is not named <destination>.bak.<YYYYMMDDHHMMSS>: $newbak"; ok=1; }
  cmp -s "$dir/$newbak" "$home/original.copy" \
    || { echo "  new backup does not hold the overwritten content byte-for-byte"; ok=1; }

  rm -rf "$home"
  return $ok
}

# ---- marker-05 --------------------------------------------------------------
# The policy as documentation: install.sh's header comment states the
# .bak.<timestamp> backup policy -- backups exist so no overwritten user
# content is lost, install.sh never prunes them automatically, and cleanup
# is the user's job.

header_comment_of() {
  # $1 = install.sh path; prints its header comment (everything before the
  # 'set -eu' line, exclusive) -- same window as renderinject-06's helper.
  sed '/^set -eu$/q' "$1" | sed '$d'
}

marker_05() {
  d=$(mktemp -d); ok=0
  header_comment_of "$INSTALL_SH" > "$d/header.txt"
  [ -s "$d/header.txt" ] || { echo "  no header comment found"; rm -rf "$d"; return 1; }

  # backups exist so no overwritten user content is lost (stated as the
  # <file>.bak.<timestamp> backup taken before an unmanaged file is
  # overwritten)
  grep -qF '.bak.<timestamp>' "$d/header.txt" \
    || { echo "  header does not name the '<file>.bak.<timestamp>' backup form"; ok=1; }
  grep -qiE 'back(ed)? up.*before|before.*overwrit' "$d/header.txt" \
    || { echo "  header does not state unmanaged files are backed up before being overwritten"; ok=1; }
  grep -qiE 'never (reads?,? )?.*(prune|delet)|does not prune|never prunes' "$d/header.txt" \
    || { echo "  header does not state install.sh never deletes or prunes backups automatically"; ok=1; }
  grep -qiE "user'?s (job|own)" "$d/header.txt" \
    || { echo "  header does not state backup cleanup is the user's"; ok=1; }

  rm -rf "$d"
  return $ok
}

# ---- marker-06 --------------------------------------------------------------
# The header comment is completed: its description of what gets installed
# names all four agents (specifying the orchestrator too) and both commands.

marker_06() {
  d=$(mktemp -d); ok=0
  header_comment_of "$INSTALL_SH" > "$d/header.txt"
  [ -s "$d/header.txt" ] || { echo "  no header comment found"; rm -rf "$d"; return 1; }

  for agent in antz-specifier antz-coder antz-verifier antz-orchestrator; do
    grep -qF "$agent" "$d/header.txt" \
      || { echo "  header comment does not name $agent among what gets installed"; ok=1; }
  done
  # the /antz command, named among what install.sh installs
  grep -qE '/antz([ ,.)]|$)' "$d/header.txt" \
    || { echo "  header comment does not name the /antz command"; ok=1; }

  rm -rf "$d"
  return $ok
}

# ---- run ---------------------------------------------------------------------

run_test "marker-01: a destination with the marker as a line-start header comment stays antz-managed: overwritten in place, no backup" marker_01
run_test "marker-02: a file mentioning antz:generated only mid-body is NOT managed: backed up to <destination>.bak.<timestamp> byte-for-byte, then overwritten, stated on the console" marker_02
run_test "marker-03: installed_version_of reads only the line-start header marker -- a body-mentioned version=9.9.9 reports a fresh install in --check, a real header marker still reports its version" marker_03
run_test "marker-04: backups are created exactly on unmanaged overwrites; accumulated .bak.<ts> files are never pruned, renamed, or rewritten; managed re-runs create none" marker_04
run_test "marker-05: install.sh's header comment states the .bak.<timestamp> policy -- never pruned automatically, cleanup is the user's" marker_05
run_test "marker-06: install.sh's header comment names all four agents (including antz-orchestrator) and the /antz command" marker_06

echo
echo "pass=$pass_count fail=$fail_count skip=$skip_count"
[ "$fail_count" -eq 0 ]
