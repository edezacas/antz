#!/usr/bin/env bash
# Unit tests for change deembed-orchestration-scripts, sub-spec 04
# (spdd/changes/deembed-orchestration-scripts/04-docslaw.feature, scenarios
# docslaw-01..04): the AGENTS.md/CLAUDE.md runtime-law bullets rewritten for
# the de-embedded convention (scripts installed as files to the resolved antz
# scripts libdir, invoked by path), the Client Integration libdir sentence,
# and the dated note at the top of docs/orchestrator.md.
#
# Self-contained bash harness (no external framework/dependency -- this repo
# has no package manager or build system), mirroring the harness style of
# tests/docs-bump_test.sh. Run directly:
#   sh tests/docslaw_test.sh
#
# Scope note: the VERSION/CHANGELOG bump is sub-spec 06's, not this suite's.
# The suite that pinned the OLD embedded-shape doc wording
# (tests/renderinject_test.sh's renderinject-07) is re-scoped by sub-spec 05;
# this suite owns the docslaw-01..04 ids.
#
# The branch-marker gotcha bullet is byte-identical between AGENTS.md and
# CLAUDE.md and stays so. The probe gotcha bullet's SOURCING statement (the
# text before "It deliberately stops short ...") is what the specs pin
# identical; the tail of that sentence legitimately differs between the two
# docs ("the coder role's job" vs "`coder`'s job"), a carve-out the existing
# renderinject-07 helper already makes -- so the probe parity test uses the
# same head boundary, and each doc's unchanged tail is pinned verbatim.

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
AGENTS_MD="$SCRIPT_DIR/AGENTS.md"
CLAUDE_MD="$SCRIPT_DIR/CLAUDE.md"
ORCH_DOC="$SCRIPT_DIR/docs/orchestrator.md"

pass_count=0
fail_count=0

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

# ---- tiny assertion helpers (mirrors tests/docs-bump_test.sh) ---------------

require() {
  # $1 = file, $2 = literal string that must appear
  grep -qF -- "$2" "$1" || { echo "  expected but missing: $2"; return 1; }
}

refuse() {
  # $1 = file, $2 = literal string that must NOT appear
  if grep -qF -- "$2" "$1"; then
    echo "  forbidden but present: $2"
    return 1
  fi
  return 0
}

extract_bullet() {
  # $1 = file, $2 = fixed line prefix -- bullets are single lines in both docs
  grep -F -- "$2" "$1"
}

branch_bullet() {
  extract_bullet "$1" '- **Branch-marked flow'
}

probe_bullet() {
  # $1 = file -- the probe gotcha bullet (one line, like every bullet here).
  grep -E '^- `orchestrator\.prompt`' "$1" || true
}

probe_bullet_head() {
  # The probe gotcha bullet up to (not including) the sentence that
  # legitimately differs between the two docs -- the same head boundary
  # tests/renderinject_test.sh's probe_bullet_head uses.
  probe_bullet "$1" | sed 's/It deliberately.*$//'
}

client_integration_section() {
  # $1 = file -- everything from '## Client Integration' to the next '## '.
  awk '/^## Client Integration/{f=1} f&&/^## /&&!/Client Integration/{exit} f' "$1"
}

# =============================================================================
# docslaw-01: the branch-marker gotcha's antz-flow.sh sentence states the
# installed-library law, keeps the create-and-checkout phrase, the
# no-standalone-CLI/hook/plugin law, and the never-commits law; identical in
# both files.
# =============================================================================

check_branch_new_law() {
  hok=0
  require "$1" 'source of truth: `scripts/orchestration/<name>.sh`' || hok=1
  require "$1" '`install.sh` installs these scripts as files to the resolved antz scripts libdir' || hok=1
  require "$1" '${XDG_CONFIG_HOME:-$HOME/.config}/antz/scripts/' || hok=1
  require "$1" 'the orchestrator invokes them there by path' || hok=1
  require "$1" 'sh "<libdir>/antz-flow.sh" ...' || hok=1
  require "$1" 'instead of re-materializing any script into the rendered `antz-orchestrator` body or saving a temp file' || hok=1
  return $hok
}

check_branch_old_wording_gone() {
  hok=0
  refuse "$1" 'whose content `install.sh` injects into the rendered `antz-orchestrator` body' || hok=1
  refuse "$1" 'runtime unchanged: saved to a temp file and run via `sh <tempfile>`' || hok=1
  refuse "$1" '`scripts/orchestration/antz-flow.sh`, whose content' || hok=1
  return $hok
}

check_branch_laws_kept() {
  hok=0
  require "$1" 'created **and checked out** by the orchestrator'"'"'s `antz-flow.sh`' || hok=1
  require "$1" 'nothing installed as a standalone CLI/hook/plugin' || hok=1
  require "$1" '**no role ever commits anything**' || hok=1
  refuse "$1" 'no checkouts' || hok=1
  return $hok
}

# Materialize one file's branch bullet into $2, then run bullet checks on it.
bullet_of() { branch_bullet "$1" > "$2"; [ -s "$2" ] || { echo "  $1 has no branch-marker gotcha bullet"; return 1; } }

test_docslaw_01_branch_bullet_states_installed_library_law() {
  d=$(mktemp -d); trap 'rm -rf "$d"' RETURN
  ok=0
  bullet_of "$AGENTS_MD" "$d/a" || ok=1
  bullet_of "$CLAUDE_MD" "$d/c" || ok=1
  for b in "$d/a" "$d/c"; do
    check_branch_new_law "$b" || ok=1
  done
  return $ok
}

test_docslaw_01_branch_bullet_drops_injection_and_tempfile_wording() {
  d=$(mktemp -d); trap 'rm -rf "$d"' RETURN
  ok=0
  bullet_of "$AGENTS_MD" "$d/a" || ok=1
  bullet_of "$CLAUDE_MD" "$d/c" || ok=1
  for b in "$d/a" "$d/c"; do
    check_branch_old_wording_gone "$b" || ok=1
  done
  return $ok
}

test_docslaw_01_branch_bullet_keeps_checkout_phrase_no_cli_hook_plugin_and_never_commits_laws() {
  d=$(mktemp -d); trap 'rm -rf "$d"' RETURN
  ok=0
  bullet_of "$AGENTS_MD" "$d/a" || ok=1
  bullet_of "$CLAUDE_MD" "$d/c" || ok=1
  for b in "$d/a" "$d/c"; do
    check_branch_laws_kept "$b" || ok=1
  done
  return $ok
}

test_docslaw_01_branch_bullet_byte_identical_between_agents_and_claude() {
  d=$(mktemp -d); trap 'rm -rf "$d"' RETURN
  ok=0
  bullet_of "$AGENTS_MD" "$d/a" || ok=1
  bullet_of "$CLAUDE_MD" "$d/c" || ok=1
  cmp -s "$d/a" "$d/c" || { echo "  branch-marker bullet differs between AGENTS.md and CLAUDE.md"; ok=1; }
  return $ok
}

# =============================================================================
# docslaw-02: the probe gotcha's sourcing sentence states the same law for
# antz-probe.sh (installed to the resolved libdir, run by the flow script's
# state subcommand by path); the "deliberately stops short" sentence is
# unchanged; the sourcing head stays byte-identical between the two files.
# =============================================================================

check_probe_new_law() {
  hok=0
  require "$1" 'source of truth: `scripts/orchestration/antz-probe.sh`, installed by `install.sh` as a file to the resolved antz scripts libdir' || hok=1
  require "$1" '${XDG_CONFIG_HOME:-$HOME/.config}/antz/scripts/' || hok=1
  require "$1" 'the flow script'"'"'s `state` subcommand runs it there by path' || hok=1
  require "$1" 'taking the probe'"'"'s path as its second argument' || hok=1
  return $hok
}

check_probe_old_wording_gone() {
  hok=0
  refuse "$1" 'whose content `install.sh` injects into the rendered `antz-orchestrator` body' || hok=1
  refuse "$1" 'same runtime convention as `/antz-set-model`'"'"'s embedded script' || hok=1
  refuse "$1" 'saved to a temp file and run via `sh`, rather than installed anywhere' || hok=1
  return $hok
}

probe_of() { probe_bullet_head "$1" > "$2"; [ -s "$2" ] || { echo "  $1 has no probe gotcha bullet"; return 1; } }

test_docslaw_02_probe_bullet_sourcing_states_libdir_install_and_state_by_path() {
  d=$(mktemp -d); trap 'rm -rf "$d"' RETURN
  ok=0
  probe_of "$AGENTS_MD" "$d/a" || ok=1
  probe_of "$CLAUDE_MD" "$d/c" || ok=1
  for b in "$d/a" "$d/c"; do
    check_probe_new_law "$b" || ok=1
    check_probe_old_wording_gone "$b" || ok=1
  done
  return $ok
}

test_docslaw_02_probe_sourcing_head_byte_identical_between_agents_and_claude() {
  d=$(mktemp -d); trap 'rm -rf "$d"' RETURN
  ok=0
  probe_of "$AGENTS_MD" "$d/a" || ok=1
  probe_of "$CLAUDE_MD" "$d/c" || ok=1
  cmp -s "$d/a" "$d/c" || { echo "  probe bullet's sourcing statement differs between AGENTS.md and CLAUDE.md"; ok=1; }
  return $ok
}

test_docslaw_02_probe_deliberately_stops_short_clause_unchanged() {
  d=$(mktemp -d); trap 'rm -rf "$d"' RETURN
  ok=0
  # The shared "stops short" clause, byte-identical in both docs today.
  probe_bullet "$AGENTS_MD" > "$d/pa"; probe_bullet "$CLAUDE_MD" > "$d/pc"
  [ -s "$d/pa" ] || { echo "  AGENTS.md has no probe gotcha bullet"; ok=1; }
  [ -s "$d/pc" ] || { echo "  CLAUDE.md has no probe gotcha bullet"; ok=1; }
  require "$d/pa" 'It deliberately stops short of running the unit suite itself' || ok=1
  require "$d/pa" 'the receipts are read as files, like everything else it reports, and classification is mechanical from their fields' || ok=1
  require "$d/pc" 'It deliberately stops short of running the unit suite itself' || ok=1
  require "$d/pc" 'the receipts are read as files, like everything else it reports, and classification is mechanical from their fields' || ok=1
  # Each doc's own tail after the shared clause survives unchanged (the
  # legitimate coder-role-name divergence between the two files is preserved).
  require "$d/pa" 'discovering a project'"'"'s own test command is the coder role'"'"'s job' || ok=1
  require "$d/pa" 'since antz is agent-framework-agnostic' || ok=1
  require "$d/pc" 'discovering a project'"'"'s own test command is `coder`'"'"'s job' || ok=1
  require "$d/pc" 'since antz is language/framework-agnostic' || ok=1
  return $ok
}

# =============================================================================
# docslaw-03: the Client Integration section names the libdir among what
# install.sh installs, with the same marker/backup/--check policy; the
# sentence is byte-identical between the two files.
# =============================================================================

libdir_sentence() {
  # $1 = file -- the Client Integration line naming the libdir install.
  client_integration_section "$1" | grep -F 'antz/scripts' || true
}

test_docslaw_03_client_integration_names_libdir_install_with_marker_backup_check_policy() {
  d=$(mktemp -d); trap 'rm -rf "$d"' RETURN
  ok=0
  libdir_sentence "$AGENTS_MD" > "$d/sa"; libdir_sentence "$CLAUDE_MD" > "$d/sc"
  [ "$(wc -l < "$d/sa" | tr -d ' ')" -eq 1 ] || { echo "  AGENTS.md Client Integration: expected exactly 1 libdir sentence, got $(wc -l < "$d/sa")"; ok=1; }
  [ "$(wc -l < "$d/sc" | tr -d ' ')" -eq 1 ] || { echo "  CLAUDE.md Client Integration: expected exactly 1 libdir sentence, got $(wc -l < "$d/sc")"; ok=1; }
  for s in "$d/sa" "$d/sc"; do
    [ -s "$s" ] || { echo "  no libdir sentence in Client Integration"; ok=1; continue; }
    require "$s" 'installs the three orchestration scripts and the set-model script as files under the resolved `antz/scripts` libdir' || ok=1
    require "$s" '${XDG_CONFIG_HOME:-$HOME/.config}/antz/scripts/' || ok=1
    require "$s" 'shared by both clients' || ok=1
    require "$s" 'carrying the same `antz:generated` marker, backup, and `--check` reporting as every other installed file' || ok=1
  done
  return $ok
}

test_docslaw_03_libdir_sentence_byte_identical_between_agents_and_claude() {
  d=$(mktemp -d); trap 'rm -rf "$d"' RETURN
  ok=0
  libdir_sentence "$AGENTS_MD" > "$d/sa"; libdir_sentence "$CLAUDE_MD" > "$d/sc"
  [ -s "$d/sa" ] && [ -s "$d/sc" ] || { echo "  libdir sentence missing in one of the docs"; return 1; }
  cmp -s "$d/sa" "$d/sc" || { echo "  the libdir sentence differs between AGENTS.md and CLAUDE.md"; ok=1; }
  return $ok
}

# =============================================================================
# docslaw-04: docs/orchestrator.md gains a short dated note near the top;
# the historical sections are not rewritten and the file's historical-record
# framing survives intact.
# =============================================================================

test_docslaw_04_orchestrator_doc_has_dated_note_near_the_top() {
  d=$(mktemp -d); trap 'rm -rf "$d"' RETURN
  ok=0
  [ -f "$ORCH_DOC" ] || { echo "  missing docs/orchestrator.md"; return 1; }
  # The note sits above the first section heading (truly near the top).
  first_sec=$(grep -n '^## ' "$ORCH_DOC" | head -n 1 | cut -d: -f1)
  [ -n "$first_sec" ] || { echo "  docs/orchestrator.md has no '## ' section heading"; return 1; }
  head -n "$((first_sec - 1))" "$ORCH_DOC" > "$d/note"
  require "$d/note" '2026-09-13' || ok=1
  require "$d/note" 'deembed-orchestration-scripts' || ok=1
  require "$d/note" 'resolved antz scripts libdir' || ok=1
  require "$d/note" 'invokes them there by path' || ok=1
  require "$d/note" 'historical' || ok=1
  # The note itself stays short (a note, not a rewritten section).
  note_lines=$(wc -l < "$d/note" | tr -d ' ')
  [ "$note_lines" -le 30 ] || { echo "  the top-of-file region is $note_lines lines, too long for a short note"; ok=1; }
  return $ok
}

test_docslaw_04_orchestrator_doc_historical_sections_not_rewritten() {
  ok=0
  [ -f "$ORCH_DOC" ] || { echo "  missing docs/orchestrator.md"; return 1; }
  # The historical-record framing sentence survives.
  require "$ORCH_DOC" 'This is a historical design record, not living documentation' || ok=1
  require "$ORCH_DOC" 'not a spec' || ok=1
  # Everything from the first '## ' heading down equals git HEAD's copy from
  # its first '## ' heading down (the note is an insertion near the top, not
  # a rewrite below it).
  d=$(mktemp -d); trap 'rm -rf "$d"' RETURN
  git -C "$SCRIPT_DIR" show HEAD:docs/orchestrator.md > "$d/base" 2>/dev/null \
    || { echo "  cannot read docs/orchestrator.md from git HEAD"; return 1; }
  awk '/^## /{f=1} f' "$ORCH_DOC" > "$d/now"
  awk '/^## /{f=1} f' "$d/base" > "$d/was"
  cmp -s "$d/now" "$d/was" || { echo "  sections below the note changed vs git HEAD (historical sections must not be rewritten)"; diff "$d/was" "$d/now" | head -5; ok=1; }
  return $ok
}

# ---- run ---------------------------------------------------------------------

run_test "docslaw-01: the branch-marker gotcha bullet in AGENTS.md/CLAUDE.md states the installed-library law (source of truth scripts/orchestration/<name>.sh, install.sh installs as files to the resolved \${XDG_CONFIG_HOME:-\$HOME/.config}/antz/scripts/ libdir, orchestrator invokes by path sh \"<libdir>/antz-flow.sh\" ... instead of re-materializing or saving a temp file)" test_docslaw_01_branch_bullet_states_installed_library_law
run_test "docslaw-01: the branch-marker gotcha bullet drops the injects-into-the-rendered-body and temp-file wording it re-keys" test_docslaw_01_branch_bullet_drops_injection_and_tempfile_wording
run_test "docslaw-01: the branch-marker gotcha bullet keeps created-and-checked-out, nothing installed as a standalone CLI/hook/plugin, and the no-role-ever-commits law" test_docslaw_01_branch_bullet_keeps_checkout_phrase_no_cli_hook_plugin_and_never_commits_laws
run_test "docslaw-01: the branch-marker gotcha bullet is byte-identical between AGENTS.md and CLAUDE.md" test_docslaw_01_branch_bullet_byte_identical_between_agents_and_claude
run_test "docslaw-02: the probe gotcha's sourcing sentence states scripts/orchestration/antz-probe.sh installed by install.sh to the resolved libdir and run by the flow script's state subcommand by path, replacing the injects/temp-file wording" test_docslaw_02_probe_bullet_sourcing_states_libdir_install_and_state_by_path
run_test "docslaw-02: the probe gotcha's sourcing statement stays byte-identical between AGENTS.md and CLAUDE.md" test_docslaw_02_probe_sourcing_head_byte_identical_between_agents_and_claude
run_test "docslaw-02: the probe bullet's deliberately-stops-short clause (never running the unit suite; receipts read as files) is unchanged in both docs, with each doc's own tail preserved" test_docslaw_02_probe_deliberately_stops_short_clause_unchanged
run_test "docslaw-03: the Client Integration section states install.sh installs the three orchestration scripts and the set-model script as files under the resolved antz/scripts libdir, shared by both clients, with the same antz:generated marker, backup, and --check policy" test_docslaw_03_client_integration_names_libdir_install_with_marker_backup_check_policy
run_test "docslaw-03: the Client Integration libdir sentence is byte-identical between AGENTS.md and CLAUDE.md" test_docslaw_03_libdir_sentence_byte_identical_between_agents_and_claude
run_test "docslaw-04: docs/orchestrator.md gains a short dated note near the top stating the runtime convention changed to libdir install plus invocation by path" test_docslaw_04_orchestrator_doc_has_dated_note_near_the_top
run_test "docslaw-04: docs/orchestrator.md keeps its historical-record framing and the sections below the note are not rewritten" test_docslaw_04_orchestrator_doc_historical_sections_not_rewritten

echo "pass=$pass_count fail=$fail_count"
[ "$fail_count" -eq 0 ] || exit 1
exit 0
