#!/bin/sh
# Change-time verification for sub-spec 01 (scriptsource) of change
# orchestrator-fast-path. Transient by design (like descmatch-04): it
# compares the working tree against the flow's base commit
# (antz/orchestrator-fast-path), which only exists while the change is
# uncommitted. Run from the repo root:
#   sh spdd/changes/orchestrator-fast-path/verify-scriptsource.sh
#
# Covers scenarios scriptsource-01..04 (ids in test names, per the repo's
# tagging convention). All checks are mechanical:
#   - scriptsource-01: the three source files exist, parse as POSIX sh, and
#     keep their embedded counterparts' headers.
#   - scriptsource-02: each file is byte-equal to the dedented fenced
#     snippet extracted from the base-commit prompt. The extraction is the
#     full fenced body (including any shebang), dedented by removing the
#     uniform three-space prefix -- the reference the sub-spec names. Note:
#     the skills fence's marker-based extractor in
#     tests/orchestrator-skills-block_test.sh drops the shebang; the
#     byte-identical-render shared contract requires the file to carry it,
#     so the full-body dedent is the reference here.
#   - scriptsource-03: the prompt's three script fences carry exactly one
#     include-marker line each, in the same positions, fence style
#     unchanged, every other line byte-identical to the base prompt.
#   - scriptsource-04: the working tree's diff vs the base touches only
#     scripts/orchestration/ and the three fenced bodies; the other listed
#     files are byte-for-byte unchanged.
set -eu

root=$(git rev-parse --show-toplevel)
base=$(git rev-parse antz/orchestrator-fast-path)
base_prompt="$root/spdd/changes/orchestrator-fast-path/.base-orchestrator.prompt"
git show "$base:agents/prompts/orchestrator.prompt" > "$base_prompt"
trap 'rm -f "$base_prompt"' EXIT

ORCH="$root/agents/prompts/orchestrator.prompt"
SRC="$root/scripts/orchestration"

pass=0
fail=0

run_test() {
  name="$1"; fn="$2"
  if "$fn"; then
    echo "PASS: $name"
    pass=$((pass + 1))
  else
    echo "FAIL: $name"
    fail=$((fail + 1))
  fi
}

# ---- fence line numbers in the base prompt -----------------------------------
# flow: the first 3-space bare fence pair. skills: the fence pair enclosing
# the "# antz-skills.sh" marker line. probe: the "```sh" fence pair.
flow_open=$(grep -n '^   ```$' "$base_prompt" | head -n 1 | cut -d: -f1)
flow_close=$(grep -n '^   ```$' "$base_prompt" | sed -n 2p | cut -d: -f1)
marker=$(grep -n '^ *# antz-skills.sh' "$base_prompt" | head -n 1 | cut -d: -f1)
skills_open=$(awk -v m="$marker" 'NR < m && /^ *```$/ { l = NR } END { print l }' "$base_prompt")
skills_close=$(awk -v m="$marker" 'NR > m && /^ *```$/ { print NR; exit }' "$base_prompt")
probe_open=$(grep -n '^   ```sh$' "$base_prompt" | head -n 1 | cut -d: -f1)
probe_close=$(awk -v o="$probe_open" 'NR > o && /^ *```$/ { print NR; exit }' "$base_prompt")

# ---- body extraction: lines strictly inside a fence, dedented ----------------
body_dedent() {
  # $1 = open line, $2 = close line, stdin = the prompt text
  sed -n "$(($(($1)) + 1)),$(($(($2)) - 1))p" | sed 's/^   //'
}

# =============================================================================
# scriptsource-01: the three source files exist, parse as POSIX sh, and keep
# their embedded counterparts' headers (flow/skills usage headers with the
# "sh <tempfile> ..." line; the probe's "#!/bin/sh" start).
# =============================================================================
test_scriptsource_01_files_headers_parse() {
  ok=0
  for f in antz-flow.sh antz-probe.sh antz-skills.sh; do
    [ -f "$SRC/$f" ] || { echo "  missing scripts/orchestration/$f"; ok=1; }
  done
  [ "$ok" = 0 ] || return 1
  for f in antz-flow.sh antz-probe.sh antz-skills.sh; do
    sh -n "$SRC/$f" || { echo "  $f fails POSIX sh parse"; ok=1; }
  done
  grep -qF 'sh <tempfile> discover | ensure <slug> | state <slug> <probe-path> | release <slug>' "$SRC/antz-flow.sh" \
    || { echo "  antz-flow.sh lost its usage header line"; ok=1; }
  grep -qF '# antz-flow.sh' "$SRC/antz-flow.sh" \
    || { echo "  antz-flow.sh lost its '# antz-flow.sh' header comment"; ok=1; }
  head -n 1 "$SRC/antz-probe.sh" | grep -qF '#!/bin/sh' \
    || { echo "  antz-probe.sh lost its shebang start"; ok=1; }
  grep -qF 'sh <tempfile> <working-root> <match keyword>' "$SRC/antz-skills.sh" \
    || { echo "  antz-skills.sh lost its usage header line"; ok=1; }
  grep -qF '# antz-skills.sh' "$SRC/antz-skills.sh" \
    || { echo "  antz-skills.sh lost its '# antz-skills.sh' header comment"; ok=1; }
  return $ok
}

# =============================================================================
# scriptsource-02: each file is byte-for-byte identical to the dedented
# fenced snippet extracted from the pre-change prompt at the flow's base
# commit.
# =============================================================================
test_scriptsource_02_byte_equal_dedents() {
  ok=0
  t=$(mktemp)
  trap 'rm -f "$base_prompt" "$t"' EXIT
  body_dedent "$flow_open" "$flow_close" < "$base_prompt" > "$t"
  cmp -s "$t" "$SRC/antz-flow.sh" || { echo "  antz-flow.sh differs from the dedented flow fence"; ok=1; }
  body_dedent "$probe_open" "$probe_close" < "$base_prompt" > "$t"
  cmp -s "$t" "$SRC/antz-probe.sh" || { echo "  antz-probe.sh differs from the dedented probe fence"; ok=1; }
  body_dedent "$skills_open" "$skills_close" < "$base_prompt" > "$t"
  cmp -s "$t" "$SRC/antz-skills.sh" || { echo "  antz-skills.sh differs from the dedented skills fence"; ok=1; }
  rm -f "$t"
  return $ok
}

# =============================================================================
# scriptsource-03: each of the three script fences' bodies is exactly one
# include-marker line, in the same position, fence style unchanged, and
# every other line of the prompt byte-identical to the base prompt --
# verified by rebuilding the expected prompt from the base and comparing.
# =============================================================================
test_scriptsource_03_markers_only_change() {
  expected=$(mktemp)
  trap 'rm -f "$base_prompt" "$expected"' EXIT
  awk -v fo="$flow_open" -v fc="$flow_close" \
      -v so="$skills_open" -v sc="$skills_close" \
      -v po="$probe_open" -v pc="$probe_close" '
    NR == fo + 1 { print "   # antz-include: scripts/orchestration/antz-flow.sh"; next }
    NR == so + 1 { print "   # antz-include: scripts/orchestration/antz-skills.sh"; next }
    NR == po + 1 { print "   # antz-include: scripts/orchestration/antz-probe.sh"; next }
    (NR > fo && NR < fc) || (NR > so && NR < sc) || (NR > po && NR < pc) { next }
    { print }
  ' "$base_prompt" > "$expected"
  ok=0
  cmp -s "$expected" "$ORCH" \
    || { echo "  the prompt is not the base prompt with the three fenced bodies replaced by markers"; ok=1; }
  rm -f "$expected"
  return $ok
}

# =============================================================================
# scriptsource-04: the change's diff vs the base commit touches only
# scripts/orchestration/ (three new files) and the three fenced bodies of
# orchestrator.prompt; specifier/coder/verifier prompts, all four meta
# files, and install.sh are byte-for-byte unchanged.
# =============================================================================
test_scriptsource_04_scope() {
  ok=0
  # Tracked changes: only orchestrator.prompt may differ from the base.
  changed=$(git diff --name-only "$base" -- . ':(exclude)spdd/changes')
  [ "$changed" = "agents/prompts/orchestrator.prompt" ] \
    || { echo "  tracked changes beyond orchestrator.prompt: $changed"; ok=1; }
  # Untracked additions: only spdd/changes/ and scripts/orchestration/.
  untracked=$(git status --porcelain -uall | awk '$1 == "??" { print $2 }')
  for f in $untracked; do
    case "$f" in
      spdd/changes/*|scripts/orchestration/*) ;;
      *) echo "  unexpected untracked path: $f"; ok=1 ;;
    esac
  done
  # The three new files are the only things under scripts/.
  created=$(find "$root/scripts" -type f | sed "s|^$root/||" | sort | tr '\n' ' ')
  [ "$created" = "scripts/orchestration/antz-flow.sh scripts/orchestration/antz-probe.sh scripts/orchestration/antz-skills.sh " ] \
    || { echo "  unexpected files under scripts/: $created"; ok=1; }
  # The untouched files, byte-for-byte vs the base.
  for f in agents/prompts/specifier.prompt agents/prompts/coder.prompt \
           agents/prompts/verifier.prompt agents/meta/specifier.yaml \
           agents/meta/coder.yaml agents/meta/verifier.yaml \
           agents/meta/orchestrator.yaml install.sh; do
    git show "$base:$f" | cmp -s - "$root/$f" \
      || { echo "  $f is not byte-identical to the base commit"; ok=1; }
  done
  return $ok
}

# ---- run ---------------------------------------------------------------------

run_test "scriptsource-01: the three source files exist, parse as POSIX sh, and keep their headers" test_scriptsource_01_files_headers_parse
run_test "scriptsource-02: each file is a byte-equal dedent of its pre-change fenced snippet" test_scriptsource_02_byte_equal_dedents
run_test "scriptsource-03: the prompt's script fences carry exactly one include-marker line each, everything else byte-unchanged" test_scriptsource_03_markers_only_change
run_test "scriptsource-04: the diff touches only scripts/orchestration/ and the three fenced bodies; the other listed files are unchanged" test_scriptsource_04_scope

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
