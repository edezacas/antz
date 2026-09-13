#!/usr/bin/env bash
# Unit tests for install.sh's provenance-derived install source ref, covering
# every scenario in spdd/changes/hardening-installsh/03-refpin.feature
# (refpin-01..05). The change: RAW_BASE's ref is derived from the ANTZ_REF
# environment variable instead of a hardcoded "master" -- ANTZ_REF, when set
# non-empty, is used verbatim (no validation, no tag-vs-branch assumption) as
# the git ref the fetched install.sh itself came from, and unset or empty
# keeps the documented default ref ("master"). The ref substitution happens
# where RAW_BASE is built, not per call site; all remote reads still route
# through the one fetch_file helper with exactly one executable
# `curl -fsSL` invocation inside it (renderinject-04's shared-path pin stays
# valid, unmodified). Local-checkout installs (LOCAL_ROOT) are unaffected:
# ANTZ_REF governs only the remote fetch path. README.md's install section,
# install.sh's header usage comment, and the AGENTS.md/CLAUDE.md Client
# Integration RAW_BASE bullets document the mechanism.
#
# Self-contained bash test harness (no external framework/dependency -- this
# repo has no package manager or build system), same pattern as
# tests/header-marker_test.sh. Run directly:
#   ./tests/refpin_test.sh
#
# Each reported test name embeds its scenario id (refpin-01..05) from the
# feature file above, so a failure maps straight back to the scenario it
# covers. Every remote-path run uses a recording curl stand-in on PATH serving
# a per-ref fixture tree and logging every requested URL, with install.sh run
# from a directory that has no "agents/" next to it (so LOCAL_ROOT stays
# empty and every fetch is observable); every run gets an isolated temp HOME,
# never the real ~/.claude or ~/.config/opencode.

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INSTALL_SH="$SCRIPT_DIR/install.sh"

RAW_ROOT="https://raw.githubusercontent.com/edezacas/antz"

pass_count=0
fail_count=0
skip_count=0

# ---- tiny test runner -------------------------------------------------------

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

cleanup() { [ "${#tmp_roots[@]}" -gt 0 ] && rm -rf "${tmp_roots[@]}"; }
trap cleanup EXIT

# ---- fixture helpers ---------------------------------------------------------

stage_fixture_tree() {
  # $1 = fixture root, $2 = ref, $3 = VERSION value the served tree carries.
  # A complete remote source tree under "<root>/<ref>": exactly what a remote
  # install fetches (VERSION, CHANGELOG.md, every agents/meta/*.yaml and
  # agents/prompts/*.prompt for the four agents, and every
  # scripts/orchestration/*.sh the orchestrator prompt's include markers name).
  root="$1"; ref="$2"; ver="$3"
  t="$root/$ref"
  mkdir -p "$t/agents/meta" "$t/agents/prompts" "$t/scripts/orchestration"
  printf '%s\n' "$ver" > "$t/VERSION"
  printf '## [%s]\n\n- fixture changelog entry for ref %s\n' "$ver" "$ref" > "$t/CHANGELOG.md"
  cp "$SCRIPT_DIR"/agents/meta/*.yaml "$t/agents/meta/"
  cp "$SCRIPT_DIR"/agents/prompts/*.prompt "$t/agents/prompts/"
  cp "$SCRIPT_DIR"/scripts/orchestration/*.sh "$t/scripts/orchestration/"
}

make_recording_curl() {
  # $1 = bin dir. A curl stand-in for PATH: logs every requested URL to
  # $CURL_LOG and serves "<FIXTURE_ROOT>/<ref>/<relative-path>" resolved from
  # the raw.githubusercontent URL -- so a fetch of the wrong ref gets that
  # ref's tree (or fails loudly when the fixture has no such ref), and the log
  # shows the exact URL install.sh asked for.
  mkdir -p "$1"
  cat > "$1/curl" <<'STUB'
#!/bin/sh
for arg in "$@"; do url="$arg"; done
printf '%s\n' "$url" >> "$CURL_LOG"
case "$url" in
  https://raw.githubusercontent.com/edezacas/antz/*/*)
    rest=${url#https://raw.githubusercontent.com/edezacas/antz/}
    ref=${rest%%/*}
    rel=${rest#*/}
    f="$FIXTURE_ROOT/$ref/$rel"
    if [ -f "$f" ]; then cat "$f"; exit 0; fi
    ;;
esac
echo "recording-curl-stand-in: refusing to serve $url" >&2
exit 22
STUB
  chmod +x "$1/curl"
}

make_failing_curl() {
  # $1 = bin dir. A curl stand-in that counts itself in (touches $CURL_LOG)
  # and fails any fetch attempt loudly, so a local-checkout install that
  # never touches the network proves it by leaving the log empty -- and any
  # attempted fetch aborts the install through fetch_file's loud failure.
  mkdir -p "$1"
  cat > "$1/curl" <<'STUB'
#!/bin/sh
for arg in "$@"; do url="$arg"; done
printf '%s\n' "$url" >> "$CURL_LOG"
echo "failing-curl-stub: fetch attempted, aborting: $url" >&2
exit 22
STUB
  chmod +x "$1/curl"
}

remote_run() {
  # Run a REMOTE install.sh: $1 = work dir holding the install.sh copy with no
  # "agents/" next to it, $2 = bin dir (curl stand-in), $3 = HOME, $4 = curl
  # log, $5 = fixture root, $6 = env prefix assignment for ANTZ_REF ("unset",
  # "empty", or "NAME"), $7 = log capture file. Echoes the exit status.
  work="$1"; bin="$2"; home="$3"; log="$4"; root="$5"; refsig="$6"; capture="$7"
  mkdir -p "$home"
  case "$refsig" in
    unset) refenv=(-u ANTZ_REF) ;;
    empty) refenv=(ANTZ_REF=) ;;
    *)     refenv=("ANTZ_REF=$refsig") ;;
  esac
  ( cd "$work" && env "${refenv[@]}" HOME="$home" PATH="$bin:$PATH" \
      CURL_LOG="$log" FIXTURE_ROOT="$root" sh ./install.sh --claude \
      > "$capture" 2>&1 )
  echo "$?"
}

rels_fetched() {
  # $1 = curl log -> the sorted unique relative paths behind the raw URLs.
  sed -n 's|^https://raw.githubusercontent.com/edezacas/antz/[^/]*/||p' "$1" | sort -u
}

# ---- refpin-01 ---------------------------------------------------------------
# No ref signal -> the documented master invocation behaves exactly as
# before: every fetch URL carries /master/ and the install completes from the
# served tree. Unset and empty ANTZ_REF are the same default, byte-for-byte.

refpin_01() {
  d=$(new_tmp_dir); ok=0
  root="$d/fixture"; bin="$d/bin"; log="$d/curl.log"; : > "$log"
  make_recording_curl "$bin"
  stage_fixture_tree "$root" master 9.9.9
  work="$d/work"; mkdir -p "$work"; cp "$INSTALL_SH" "$work/install.sh"

  st=$(remote_run "$work" "$bin" "$d/home-a" "$log" "$root" unset "$d/run-a.log")
  [ "$st" -eq 0 ] || { echo "  remote install (ANTZ_REF unset) exited $st"; ok=1; }
  [ -s "$log" ] || { echo "  no fetch was attempted (empty curl log) -- not a remote run"; ok=1; }
  # every requested URL is "<raw-root>/master/<relative-path>"
  grep -v "^$RAW_ROOT/master/" "$log" > "$d/bad-urls" || true
  [ -s "$d/bad-urls" ] && { echo "  URLs outside master fetched:"; sed 's/^/    /' "$d/bad-urls"; ok=1; }
  # the served tree drove the install (VERSION, CHANGELOG.md, all four meta +
  # prompts, all three injected scripts)
  rels_fetched "$log" > "$d/rels"
  for rel in VERSION CHANGELOG.md \
      agents/meta/specifier.yaml agents/meta/coder.yaml agents/meta/verifier.yaml agents/meta/orchestrator.yaml \
      agents/prompts/specifier.prompt agents/prompts/coder.prompt agents/prompts/verifier.prompt agents/prompts/orchestrator.prompt \
      scripts/orchestration/antz-flow.sh scripts/orchestration/antz-probe.sh scripts/orchestration/antz-skills.sh; do
    grep -qxF "$rel" "$d/rels" || { echo "  never fetched from master: $rel"; ok=1; }
  done
  grep -qF "fresh install of antz 9.9.9" "$d/run-a.log" \
    || { echo "  install did not complete from the served (master) tree"; ok=1; }
  grep -qF '# antz:generated version=9.9.9' "$d/home-a/.claude/agents/antz-specifier.md" \
    || { echo "  installed agent does not carry the master tree's VERSION marker"; ok=1; }

  # ANTZ_REF set-but-empty: same default, and byte-identical behavior
  : > "$log"
  st=$(remote_run "$work" "$bin" "$d/home-b" "$log" "$root" empty "$d/run-b.log")
  [ "$st" -eq 0 ] || { echo "  remote install (ANTZ_REF empty) exited $st"; ok=1; }
  grep -v "^$RAW_ROOT/master/" "$log" > "$d/bad-urls-b" || true
  [ -s "$d/bad-urls-b" ] && { echo "  empty ANTZ_REF changed the fetched URLs:"; sed 's/^/    /' "$d/bad-urls-b"; ok=1; }
  diff -r "$d/home-a" "$d/home-b" > "$d/home.diff" 2>&1 \
    || { echo "  empty vs unset ANTZ_REF installed differently:"; sed 's/^/    /' "$d/home.diff"; ok=1; }
  # same console report modulo the per-run HOME embedded in "Installed <path>"
  sed "s|$d/home-a||" "$d/run-a.log" > "$d/report-a"
  sed "s|$d/home-b||" "$d/run-b.log" > "$d/report-b"
  cmp -s "$d/report-a" "$d/report-b" \
    || { echo "  empty vs unset ANTZ_REF reported differently:"; diff "$d/report-a" "$d/report-b" | head -5; ok=1; }
  return $ok
}

# ---- refpin-02 ---------------------------------------------------------------
# ANTZ_REF set -> every remote fetch uses that ref, verbatim: the named
# sources are all fetched from "<raw-root>/<ref>/<relative-path>", nothing
# comes from master, and the rendered markers embed the fetched tree's
# VERSION (the fixture serves a distinct tree per ref).

refpin_02() {
  d=$(new_tmp_dir); ok=0
  root="$d/fixture"; bin="$d/bin"; log="$d/curl.log"; : > "$log"
  make_recording_curl "$bin"
  stage_fixture_tree "$root" master 9.9.9
  stage_fixture_tree "$root" v4.7.0 3.14.1
  work="$d/work"; mkdir -p "$work"; cp "$INSTALL_SH" "$work/install.sh"

  st=$(remote_run "$work" "$bin" "$d/home" "$log" "$root" v4.7.0 "$d/run.log")
  [ "$st" -eq 0 ] || { echo "  remote install (ANTZ_REF=v4.7.0) exited $st"; ok=1; }
  [ -s "$log" ] || { echo "  no fetch was attempted (empty curl log) -- not a remote run"; ok=1; }
  grep -v "^$RAW_ROOT/v4.7.0/" "$log" > "$d/bad-urls" || true
  [ -s "$d/bad-urls" ] && { echo "  URLs outside the ANTZ_REF ref fetched:"; sed 's/^/    /' "$d/bad-urls"; ok=1; }
  grep -qF '/master/' "$log" && { echo "  a URL still carried /master/:"; grep -F '/master/' "$log" | sed 's/^/    /'; ok=1; }
  rels_fetched "$log" > "$d/rels"
  for rel in VERSION CHANGELOG.md agents/meta/specifier.yaml \
      agents/prompts/orchestrator.prompt scripts/orchestration/antz-flow.sh; do
    grep -qxF "$rel" "$d/rels" || { echo "  never fetched from the v4.7.0 ref: $rel"; ok=1; }
  done
  # the fetched tree's VERSION (3.14.1, not master's 9.9.9) is embedded in the
  # rendered markers -- the ref is used verbatim, its content actually served
  grep -qF '# antz:generated version=3.14.1' "$d/home/.claude/agents/antz-specifier.md" \
    || { echo "  installed agents do not embed the fetched (v4.7.0 tree) VERSION"; ok=1; }
  grep -qF '9.9.9' "$d/home/.claude/agents/antz-specifier.md" \
    && { echo "  installed agent embeds the master tree's VERSION"; ok=1; }
  return $ok
}

# ---- refpin-03 ---------------------------------------------------------------
# Local provenance wins: a checkout install reads every file from disk and
# never touches the network regardless of ANTZ_REF (a failing curl stub
# earlier on PATH would abort any fetch attempt; it is never invoked).

refpin_03() {
  d=$(new_tmp_dir); ok=0
  co="$d/checkout"; bin="$d/bin"; log="$d/curl.log"; : > "$log"
  make_failing_curl "$bin"
  mkdir -p "$co"
  cp "$INSTALL_SH" "$co/install.sh"
  printf '5.5.5\n' > "$co/VERSION"
  cp "$SCRIPT_DIR/CHANGELOG.md" "$co/CHANGELOG.md"
  cp -R "$SCRIPT_DIR/agents" "$co/agents"
  cp -R "$SCRIPT_DIR/scripts" "$co/scripts"
  # a staged-tree marker proving prompt content is read from the checkout
  printf '\nStaged-checkout-only prose line 5R8KQ.\n' >> "$co/agents/prompts/specifier.prompt"

  st=$(cd "$co" && env ANTZ_REF=bogus-ref HOME="$d/home-a" PATH="$bin:$PATH" CURL_LOG="$log" \
        sh ./install.sh --claude > "$d/run-a.log" 2>&1; echo "$?")
  [ "$st" -eq 0 ] || { echo "  local install with ANTZ_REF=bogus-ref exited $st (read $d/run-a.log)"; ok=1; }
  [ -s "$log" ] && { echo "  the curl stub WAS invoked despite the checkout:"; sed 's/^/    /' "$log"; ok=1; }
  dest="$d/home-a/.claude/agents/antz-specifier.md"
  grep -qF '# antz:generated version=5.5.5' "$dest" \
    || { echo "  installed agent does not carry the checkout's VERSION"; ok=1; }
  grep -qF 'Staged-checkout-only prose line 5R8KQ.' "$dest" \
    || { echo "  installed agent was not rendered from the checkout's prompt file"; ok=1; }

  # the invariant: the local install is byte-identical with and without the
  # variable (it governs only the remote fetch path)
  st=$(cd "$co" && env -u ANTZ_REF HOME="$d/home-b" PATH="$bin:$PATH" CURL_LOG="$log" \
        sh ./install.sh --claude > "$d/run-b.log" 2>&1; echo "$?")
  [ "$st" -eq 0 ] || { echo "  local install without ANTZ_REF exited $st"; ok=1; }
  [ -s "$log" ] && { echo "  the curl stub WAS invoked on the second (unset) run"; ok=1; }
  diff -r "$d/home-a" "$d/home-b" > "$d/home.diff" 2>&1 \
    || { echo "  local install differs with vs without ANTZ_REF:"; sed 's/^/    /' "$d/home.diff"; ok=1; }
  return $ok
}

# ---- refpin-04 ---------------------------------------------------------------
# Discoverability: README.md's install section, install.sh's header usage
# comment, and the AGENTS.md/CLAUDE.md Client Integration RAW_BASE bullets
# all document the mechanism (tagged-URL invocation with ANTZ_REF=<tag>
# passed to sh; default master, overridden by ANTZ_REF).

header_comment_of() {
  # $1 = install.sh path; the header comment (everything before 'set -eu').
  sed '/^set -eu$/q' "$1" | sed '$d'
}

readme_install_section() {
  awk '/^# Install/{f=1} /^## Usage/{f=0} f' "$1"
}

refpin_04() {
  d=$(new_tmp_dir); ok=0
  example="antz/v4.7.0/install.sh | ANTZ_REF=v4.7.0 sh"

  # README.md's install section: fetching install.sh from the tag's raw URL
  # and passing ANTZ_REF=<tag> to sh, with the shared tagged-URL example.
  readme_install_section "$SCRIPT_DIR/README.md" > "$d/readme-install.txt"
  [ -s "$d/readme-install.txt" ] || { echo "  README.md install section not found"; return 1; }
  grep -qF 'ANTZ_REF=<tag>' "$d/readme-install.txt" \
    || { echo "  README install section does not document passing ANTZ_REF=<tag>"; ok=1; }
  grep -qF "$example" "$d/readme-install.txt" \
    || { echo "  README install section lacks the tagged-URL example: $example"; ok=1; }
  grep -qiE 'default.*master|master.*default' "$d/readme-install.txt" \
    || { echo "  README install section does not state master as the default ref"; ok=1; }

  # install.sh's header usage comment: ANTZ_REF + the same tagged-URL example
  header_comment_of "$INSTALL_SH" > "$d/header.txt"
  grep -qF 'ANTZ_REF' "$d/header.txt" \
    || { echo "  install.sh's header comment does not document ANTZ_REF"; ok=1; }
  grep -qF "$example" "$d/header.txt" \
    || { echo "  install.sh's header comment lacks the same tagged-URL example: $example"; ok=1; }
  grep -qiE 'default.*master|master.*default' "$d/header.txt" \
    || { echo "  install.sh's header comment does not state master as the default ref"; ok=1; }

  # both policy docs' Client Integration RAW_BASE bullet: the ref comes from
  # ANTZ_REF (default master), not a fixed master source; identical twins.
  for doc in AGENTS.md CLAUDE.md; do
    n=$(grep -c 'RAW_BASE' "$SCRIPT_DIR/$doc")
    [ "$n" -eq 1 ] || { echo "  $doc: expected exactly 1 RAW_BASE bullet, got $n"; ok=1; continue; }
  done
  grep 'RAW_BASE' "$SCRIPT_DIR/AGENTS.md" > "$d/bullet.agents"
  grep 'RAW_BASE' "$SCRIPT_DIR/CLAUDE.md" > "$d/bullet.claude"
  cmp -s "$d/bullet.agents" "$d/bullet.claude" \
    || { echo "  the RAW_BASE bullet differs between AGENTS.md and CLAUDE.md"; ok=1; }
  grep -qF 'ANTZ_REF' "$d/bullet.agents" \
    || { echo "  the policy docs' RAW_BASE bullet does not name ANTZ_REF"; ok=1; }
  grep -qiE 'default.*master|master.*default' "$d/bullet.agents" \
    || { echo "  the policy docs' RAW_BASE bullet does not state master as the default ref"; ok=1; }
  grep -qF 'currently GitHub' "$d/bullet.agents" \
    && { echo "  the policy docs still describe master as the fixed source"; ok=1; }
  return $ok
}

# ---- refpin-05 ---------------------------------------------------------------
# The fetch architecture is preserved: the include injection still fetches
# through fetch_file "$rel", there is exactly one executable `curl -fsSL`
# invocation and it lives inside fetch_file, and the ref substitution happens
# where RAW_BASE is built -- not per call site (renderinject-04's pin stays
# valid; the full-suite run proves it stays green, unmodified).

refpin_05() {
  d=$(new_tmp_dir); ok=0
  grep -qF 'fetch_file "$rel"' "$INSTALL_SH" \
    || { echo "  the include injection no longer fetches through fetch_file \"\$rel\""; ok=1; }
  # exactly one executable curl invocation (comments excluded) -- and it is
  # fetch_file's own, still going through "$RAW_BASE/$rel" (no per-site ref)
  n=$(grep -v '^[[:space:]]*#' "$INSTALL_SH" | grep -c 'curl -fsSL')
  [ "$n" -eq 1 ] || { echo "  expected exactly one executable curl -fsSL invocation, got: $n"; ok=1; }
  awk '/^fetch_file\(\) \{/,/^\}/' "$INSTALL_SH" > "$d/fetch_file.sh"
  grep -qF 'curl -fsSL "$RAW_BASE/$rel"' "$d/fetch_file.sh" \
    || { echo "  fetch_file's curl invocation no longer reads the whole URL from RAW_BASE (ref moved per call site?)"; ok=1; }
  # the ANTZ_REF signal is consumed once, at the RAW_BASE construction itself
  ex=$(grep -v '^[[:space:]]*#' "$INSTALL_SH" | grep -c 'ANTZ_REF')
  [ "$ex" -eq 1 ] || { echo "  expected ANTZ_REF to be read exactly once in executable code (at RAW_BASE's construction), got: $ex"; ok=1; }
  grep -v '^[[:space:]]*#' "$INSTALL_SH" | grep 'ANTZ_REF' | grep -q '^RAW_BASE=' \
    || { echo "  the ref substitution is not at the RAW_BASE construction: $(grep -v '^[[:space:]]*#' "$INSTALL_SH" | grep 'ANTZ_REF')"; ok=1; }
  return $ok
}

# ---- run ---------------------------------------------------------------------

run_test "refpin-01: with no ref signal every fetch URL carries /master/, the install completes from the served tree, and empty ANTZ_REF is byte-for-byte the unset default" refpin_01
run_test "refpin-02: with ANTZ_REF=v4.7.0 every fetched URL carries /v4.7.0/ (VERSION, CHANGELOG.md, agents/meta/specifier.yaml, agents/prompts/orchestrator.prompt, scripts/orchestration/antz-flow.sh among them), none carries /master/, and the markers embed the fetched tree's VERSION" refpin_02
run_test "refpin-03: a checkout install reads every file from disk and never touches the network regardless of ANTZ_REF (failing curl stub never invoked; byte-identical with and without it)" refpin_03
run_test "refpin-04: README's install section, install.sh's header usage, and the AGENTS.md/CLAUDE.md RAW_BASE bullets document the tag-pinned ANTZ_REF invocation (shared tagged-URL example, master default, ANTZ_REF override)" refpin_04
run_test "refpin-05: the fetch architecture is preserved -- injection fetches through fetch_file \"\$rel\", exactly one executable curl -fsSL inside fetch_file, and the ref is substituted at the RAW_BASE construction, not per call site" refpin_05

echo
echo "pass=$pass_count fail=$fail_count skip=$skip_count"
[ "$fail_count" -eq 0 ]
