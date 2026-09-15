#!/usr/bin/env bash
# Unit tests for install.sh's libdir script installation, covering every
# scenario in spdd/changes/deembed-orchestration-scripts/01-libdirinstall.feature
# (libdirinstall-01..07). The change: the two orchestration scripts
# (scripts/orchestration/antz-flow.sh, antz-probe.sh) plus the
# set-model script (emitted today by install.sh's emit_set_model_script)
# install as three marked files in one shared, resolved library directory
# "${XDG_CONFIG_HOME:-$HOME/.config}/antz/scripts" (change decisions 1 and 7),
# with the same marker / backup / --check policy every other installed file
# carries. The repo sources under scripts/orchestration/ stay byte-unchanged;
# each installed copy is its source plus one inserted marker line after the
# shebang, and `sh "<path>"` invocation is the whole contract (no CLI on PATH,
# no hook or plugin, no exec bit required). The rendered prompt/command bodies
# that invoke the scripts by their concrete resolved path arrive with
# sub-specs 02 and 03 -- here the resolution is made available and the files
# install.
#
# Self-contained bash test harness (no external framework/dependency -- this
# repo has no package manager or build system), same pattern as
# tests/refpin_test.sh. Run directly:
#   ./tests/libdirinstall_test.sh
#
# Each reported test name embeds its scenario id (libdirinstall-01..07) from
# the feature file above, so a failure maps straight back to the scenario it
# covers. Every run gets an isolated HOME (a fresh temp dir per test) AND an
# explicitly controlled XDG_CONFIG_HOME (set to an isolated dir, empty, or
# unset via `env -u`) -- never the session's own config home and never the
# real ~/.claude or ~/.config/opencode.

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INSTALL_SH="$SCRIPT_DIR/install.sh"

CURRENT_VERSION=$(tr -d ' \t\r\n' < "$SCRIPT_DIR/VERSION")

LIB_SCRIPTS="antz-flow.sh antz-probe.sh antz-set-model.sh"

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

marker_line() {
  # $1 = version; the exact rendered marker line (Background): a line-start
  # header comment, unchanged in format from every other installed file's.
  printf '# antz:generated version=%s -- do not edit by hand; regenerate with install.sh' "$1"
}

stage_checkout() {
  # $1 = checkout dir: a complete staged checkout (install.sh, agents/,
  # scripts/orchestration/, VERSION, CHANGELOG.md) with the VERSION value in
  # $2 (default: the working tree's), so drift scenarios can install at one
  # version and re-run at another.
  dir="$1"; ver="${2:-$CURRENT_VERSION}"
  mkdir -p "$dir"
  cp "$INSTALL_SH" "$dir/install.sh"
  cp "$SCRIPT_DIR/CHANGELOG.md" "$dir/CHANGELOG.md"
  cp -R "$SCRIPT_DIR/agents" "$dir/agents"
  cp -R "$SCRIPT_DIR/scripts" "$dir/scripts"
  printf '%s\n' "$ver" > "$dir/VERSION"
}

stage_fixture_tree() {
  # $1 = fixture root, $2 = ref: a complete remote source tree under
  # "<root>/<ref>" for the recording curl stand-in (what a remote install
  # fetches through RAW_BASE), same shape as tests/refpin_test.sh's fixture.
  root="$1"; ref="$2"
  t="$root/$ref"
  mkdir -p "$t/agents/meta" "$t/agents/prompts" "$t/scripts/orchestration"
  printf '%s\n' "$CURRENT_VERSION" > "$t/VERSION"
  printf '## [%s]\n\n- fixture changelog entry for ref %s\n' "$CURRENT_VERSION" "$ref" > "$t/CHANGELOG.md"
  cp "$SCRIPT_DIR"/agents/meta/*.yaml "$t/agents/meta/"
  cp "$SCRIPT_DIR"/agents/prompts/*.prompt "$t/agents/prompts/"
  cp "$SCRIPT_DIR"/scripts/orchestration/*.sh "$t/scripts/orchestration/"
}

make_recording_curl() {
  # $1 = bin dir. curl stand-in on PATH: logs every requested URL, serves
  # "<FIXTURE_ROOT>/<ref>/<relative-path>" (refpin_test.sh's idiom).
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

install_at() {
  # $1 = HOME, $2 = install.sh path, rest = install.sh flags. Always a fully
  # explicit environment (PATH plus session config-home leakage removed), so
  # a test never writes into the real ~/.config.
  home="$1"; sh_path="$2"; shift 2
  env -u XDG_CONFIG_HOME HOME="$home" sh "$sh_path" "$@"
}

install_xdg() {
  # $1 = HOME, $2 = XDG_CONFIG_HOME value to export (set or empty -- both
  # explicit), $3 = install.sh path, rest = flags.
  home="$1"; xdg="$2"; sh_path="$3"; shift 3
  env XDG_CONFIG_HOME="$xdg" HOME="$home" sh "$sh_path" "$@"
}

emitted_set_model_source() {
  # $1 = install.sh path; prints the emit_set_model_script emitter's exact
  # emitted text (the set-model script's source under this sub-spec's
  # Background: "the set-model script text is emitted by install.sh itself").
  # The range ends at the '}' that closes the function -- the first line that
  # is exactly '}' AFTER the heredoc's own 'SCRIPT' terminator, since the
  # emitted script contains its own column-0 '}' lines.
  awk '
    /^emit_set_model_script\(\) \{$/ { f = 1 }
    f { print }
    f && /^SCRIPT$/ { closedelim = 1 }
    f && closedelim && /^\}$/ { exit }
  ' "$1" | {
    src=$(cat)
    printf '%s\n%s\n' "$src" "emit_set_model_script" | sh
  }
}

behaviour_dump() {
  # $1 = script path, $2 = script kind (flow|probe|setmodel),
  # $3 = scratch dir. Runs the script with a deterministic probe invocation
  # whose combined stdout+stderr carries no path of its own, and dumps
  # "rc=<n>" plus the output to stdout. Same probes for installed copies and
  # sources, so byte-identical dumps are exactly "running each installed
  # file behaves exactly like running its source" (libdirinstall-01).
  f="$1"; kind="$2"
  case "$kind" in
    flow)     env -u CHANGE_DIR sh "$f" ;;
    probe)    env CHANGE_DIR="$f/../no-such-change-dir" sh "$f" ;;
    setmodel) env HOME=/nonexistent-isolated-home sh "$f" --agent coder --model opus ;;
  esac > "$3/out" 2>&1
  printf 'rc=%s\n' "$?" >> "$3/out"
  cat "$3/out"
}

# ---- libdirinstall-01 ---------------------------------------------------------
# The three scripts install as marked files in the libdir; the two
# orchestration scripts are byte-faithful copies of their sources plus one
# inserted marker line, the repo sources stay byte-unchanged, and running
# each installed file via `sh <path>` behaves exactly like running its source.

libdirinstall_01() {
  d=$(new_tmp_dir); ok=0
  co="$d/checkout"; stage_checkout "$co"
  home="$d/home"; mkdir -p "$home"
  log="$d/install.log"

  src_sums_before=$(cksum "$co"/scripts/orchestration/*.sh)

  if ! install_at "$home" "$co/install.sh" --claude > "$log" 2>&1; then
    echo "  install.sh --claude exited non-zero:"; head -5 "$log" | sed 's/^/    /'; return 1
  fi

  lib="$home/.config/antz/scripts"
  for f in $LIB_SCRIPTS; do
    [ -f "$lib/$f" ] || { echo "  libdirinstall-01: installed script missing: $lib/$f"; ok=1; }
  done
  [ "$ok" -eq 0 ] || return 1

  for f in $LIB_SCRIPTS; do
    # marker is a line-start header comment inserted immediately after the
    # "#!/bin/sh" shebang: line 1 stays the shebang, line 2 is the marker
    [ "$(sed -n '1p' "$lib/$f")" = '#!/bin/sh' ] || {
      echo "  $f: line 1 is not the shebang"; ok=1; }
    [ "$(sed -n '2p' "$lib/$f")" = "$(marker_line "$CURRENT_VERSION")" ] || {
      echo "  $f: line 2 is not the '# antz:generated version=$CURRENT_VERSION ...' marker: $(sed -n '2p' "$lib/$f")"; ok=1; }
  done

  # byte-faithfulness of the two orchestration files: installed minus the
  # single inserted line 2 is its source byte-for-byte
  for s in antz-flow antz-probe; do
    sed '2d' "$lib/$s.sh" | cmp -s - "$co/scripts/orchestration/$s.sh" || {
      echo "  $s.sh: installed copy is not the source plus one marker line"; ok=1; }
  done

  # the repo source files stay byte-unchanged by the install run
  src_sums_after=$(cksum "$co"/scripts/orchestration/*.sh)
  [ "$src_sums_before" = "$src_sums_after" ] || {
    echo "  the install run modified the checkout's scripts/orchestration/ sources"; ok=1; }

  # running each installed file with "sh <path>" behaves exactly like running
  # its source (deterministic probes; the set-model source is the emitter's
  # emitted text per the sub-spec Background)
  emitted_set_model_source "$co/install.sh" > "$d/set-model.source.sh"
  for pair in "flow $lib/antz-flow.sh $co/scripts/orchestration/antz-flow.sh" \
              "probe $lib/antz-probe.sh $co/scripts/orchestration/antz-probe.sh" \
              "setmodel $lib/antz-set-model.sh $d/set-model.source.sh"; do
    set -- $pair
    mkdir -p "$d/pa" "$d/pb"
    behaviour_dump "$2" "$1" "$d/pa" > "$d/dump-installed"
    behaviour_dump "$3" "$1" "$d/pb" > "$d/dump-source"
    cmp -s "$d/dump-installed" "$d/dump-source" || {
      echo "  $1: installed copy does not behave exactly like its source:"
      diff "$d/dump-source" "$d/dump-installed" | head -6 | sed 's/^/    /'; ok=1; }
  done
  return $ok
}

# ---- libdirinstall-02 ---------------------------------------------------------
# The libdir path is resolved once by install.sh, honoring XDG_CONFIG_HOME:
# a set directory is the base; unset or empty falls back to "$HOME/.config"
# the same way; the concrete resolved absolute path (no variable, no
# fallback token, no trailing slash) is what install.sh works with.
# libdirinstall-02's rendered-body clause ("what install.sh writes into
# every rendered prompt and command body that references a script") has no
# written referent yet in this sub-spec -- the invocation lines land with
# sub-specs 02/03 -- so what this test pins here is the resolution itself
# plus its hygiene (no placeholder token leaks into any installed or
# rendered file under HOME).

libdirinstall_02() {
  d=$(new_tmp_dir); ok=0
  co="$d/checkout"; stage_checkout "$co"

  # XDG_CONFIG_HOME set to a non-default directory
  home1="$d/home-set"; xdg="$d/xdgbase"; mkdir -p "$home1" "$xdg"
  if ! install_xdg "$home1" "$xdg" "$co/install.sh" --claude > "$d/run-set.log" 2>&1; then
    echo "  install with XDG_CONFIG_HOME set exited non-zero:"; head -5 "$d/run-set.log" | sed 's/^/    /'; return 1
  fi
  for f in $LIB_SCRIPTS; do
    [ -f "$xdg/antz/scripts/$f" ] || { echo "  XDG set: $f did not install under <that directory>/antz/scripts/"; ok=1; }
    [ ! -e "$home1/.config/antz/scripts/$f" ] || { echo "  XDG set: $f also installed under the HOME fallback (XDG not honored)"; ok=1; }
  done
  # no placeholder or fallback token survives any written file under HOME or
  # the XDG base (the resolved path is concrete; the $HOME literal inside the
  # emitted set-model script is its own documented runtime token and stays)
  if find "$home1" "$xdg" -type f -exec grep -l '__ANTZ_SCRIPTS_DIR__' {} + 2>/dev/null | grep .; then
    echo "  a written file still carries the __ANTZ_SCRIPTS_DIR__ placeholder"; ok=1
  fi
  if find "$home1" "$xdg" -type f -exec grep -l 'XDG_CONFIG_HOME' {} + 2>/dev/null | grep .; then
    echo "  a written file still carries the XDG_CONFIG_HOME fallback token"; ok=1
  fi

  # XDG_CONFIG_HOME unset -> $HOME/.config fallback
  home2="$d/home-unset"; mkdir -p "$home2"
  install_at "$home2" "$co/install.sh" --claude > "$d/run-unset.log" 2>&1 \
    || { echo "  install with XDG_CONFIG_HOME unset exited non-zero"; ok=1; }
  for f in $LIB_SCRIPTS; do
    [ -f "$home2/.config/antz/scripts/$f" ] || { echo "  XDG unset: $f not under \$HOME/.config/antz/scripts/"; ok=1; }
  done

  # XDG_CONFIG_HOME empty -> falls back exactly like unset (same trees,
  # same report). The trees are compared modulo the per-run HOME: since
  # sub-spec 02 the rendered orchestrator body embeds the concrete resolved
  # libdir path under the run's HOME, so "falls back identically" means the
  # same install shape and content for a given HOME value -- both trees get
  # their HOME path masked to one token before the diff (same normalization
  # the report comparison below applies to "Installed <path>" lines).
  home3="$d/home-empty"; mkdir -p "$home3"
  install_xdg "$home3" "" "$co/install.sh" --claude > "$d/run-empty.log" 2>&1 \
    || { echo "  install with XDG_CONFIG_HOME empty exited non-zero"; ok=1; }
  ta="$d/tree-unset"; tb="$d/tree-empty"
  cp -R "$home2" "$ta" && cp -R "$home3" "$tb"
  for t in "$ta" "$tb"; do
    find "$t" -type f | while IFS= read -r f; do
      sed -e "s|$home2|/MASKED-HOME|g" -e "s|$home3|/MASKED-HOME|g" "$f" > "$f.m" && mv "$f.m" "$f"
    done
  done
  diff -r "$ta" "$tb" > "$d/fallback.diff" 2>&1 || {
    echo "  empty XDG_CONFIG_HOME does not fall back like unset:"; sed 's/^/    /' "$d/fallback.diff" | head -6; ok=1; }
  sed "s|$home2||" "$d/run-unset.log" > "$d/report-unset"
  sed "s|$home3||" "$d/run-empty.log" > "$d/report-empty"
  cmp -s "$d/report-unset" "$d/report-empty" || {
    echo "  empty vs unset XDG_CONFIG_HOME reported differently"; ok=1; }

  # the resolution is one runtime computation of "${XDG_CONFIG_HOME:-...}"
  # in install.sh (resolved once, never hardcoded to $HOME/.config)
  grep -qF 'XDG_CONFIG_HOME:-$HOME/.config' "$INSTALL_SH" || {
    echo "  install.sh does not resolve the libdir from XDG_CONFIG_HOME with a \$HOME/.config fallback"; ok=1; }
  n=$(grep -v '^[[:space:]]*#' "$INSTALL_SH" | grep -c 'resolve_libdir')
  [ "$n" -eq 2 ] || { echo "  expected resolve_libdir defined once and called once in executable code, got: $n"; ok=1; }
  return $ok
}

# ---- libdirinstall-03 ---------------------------------------------------------
# The .bak.<ts> backup policy and the anchored line-start marker detection
# apply to libdir files unchanged: an unmanaged pre-existing file is backed
# up byte-for-byte before being overwritten; a managed one is overwritten in
# place with no new backup and its marker restamped; backups are never read,
# renamed, pruned, or deleted.

count_libdir_backups() {
  # $1 = libdir, $2 = base name -> number of ".bak.*" siblings
  find "$1" -maxdepth 1 -name "$2.bak.*" 2>/dev/null | wc -l | tr -d ' '
}

libdirinstall_03() {
  d=$(new_tmp_dir); ok=0
  co="$d/checkout"; stage_checkout "$co"
  home="$d/home"; mkdir -p "$home"
  lib="$home/.config/antz/scripts"; mkdir -p "$lib"

  # (a) unmanaged pre-existing file: mentions the marker string only
  # somewhere other than a line-start header comment (anchored detection)
  unmanaged_orig="$d/unmanaged.orig"
  { echo '#!/bin/sh'; echo "# someone's own script; docs mention antz:generated mid-body."; } | tee "$lib/antz-flow.sh" > "$unmanaged_orig"
  printf '%s\n' 'user content' > "$lib/antz-flow.sh.bak.20260101010101"
  printf '%s\n' 'older user content' > "$lib/antz-flow.sh.bak.20260202020202"

  # (b) managed pre-existing file: line-start marker at an old version
  printf '%s\n%s\n%s\n' '#!/bin/sh' "$(marker_line 1.2.3)" 'echo old managed copy' > "$lib/antz-probe.sh"

  install_at "$home" "$co/install.sh" --claude > "$d/run1.log" 2>&1 \
    || { echo "  install exited non-zero:"; head -5 "$d/run1.log" | sed 's/^/    /'; return 1; }

  # (a) backed up to "<file>.bak.<YYYYMMDDHHMMSS>" holding the original bytes
  newb=$(find "$lib" -maxdepth 1 -name 'antz-flow.sh.bak.*' \
      ! -name 'antz-flow.sh.bak.20260101010101' ! -name 'antz-flow.sh.bak.20260202020202' | wc -l | tr -d ' ')
  [ "$newb" -eq 1 ] || { echo "  unmanaged libdir file: expected exactly 1 new .bak.<ts> backup, got $newb"; ok=1; }
  tsb=$(find "$lib" -maxdepth 1 -name 'antz-flow.sh.bak.*' \
      ! -name 'antz-flow.sh.bak.20260101010101' ! -name 'antz-flow.sh.bak.20260202020202' | head -1)
  if [ -n "$tsb" ]; then
    case "$tsb" in
      *.bak.[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) ;;
      *) echo "  backup name is not <file>.bak.<YYYYMMDDHHMMSS>: $tsb"; ok=1 ;;
    esac
    cmp -s "$tsb" "$unmanaged_orig" || { echo "  backup does not hold the original content byte-for-byte"; ok=1; }
  fi
  # the destination is now the managed copy
  [ "$(sed -n '2p' "$lib/antz-flow.sh")" = "$(marker_line "$CURRENT_VERSION")" ] || {
    echo "  the unmanaged file was not overwritten with the marked managed copy"; ok=1; }

  # (b) managed pre-existing file overwritten in place: no new backup...
  [ "$(count_libdir_backups "$lib" antz-probe.sh)" -eq 0 ] || {
    echo "  managed libdir file grew a backup"; ok=1; }
  # ...and its marker is restamped to the current VERSION
  [ "$(sed -n '2p' "$lib/antz-probe.sh")" = "$(marker_line "$CURRENT_VERSION")" ] || {
    echo "  managed libdir file's marker was not restamped"; ok=1; }

  # (c) the two pre-existing backups survive byte-for-byte under their
  # original names (never read, renamed, pruned, or deleted)
  printf '%s\n' 'user content' | cmp -s - "$lib/antz-flow.sh.bak.20260101010101" || {
    echo "  pre-existing backup .bak.20260101010101 was modified"; ok=1; }
  printf '%s\n' 'older user content' | cmp -s - "$lib/antz-flow.sh.bak.20260202020202" || {
    echo "  pre-existing backup .bak.20260202020202 was modified"; ok=1; }
  # a second run creates no further backups and leaves all three in place
  install_at "$home" "$co/install.sh" --claude > "$d/run2.log" 2>&1 || { echo "  second install failed"; ok=1; }
  [ "$(count_libdir_backups "$lib" antz-flow.sh)" -eq 3 ] || {
    echo "  second run changed the libdir backup set (expected the same 3)"; ok=1; }
  return $ok
}

# ---- libdirinstall-04 ---------------------------------------------------------
# --check (and the install-run report) also report the installed scripts,
# keyed off each script's own marker version: one line per script artifact
# naming the script file with the same three outcomes the client lines
# state, CHANGELOG entries at most once for the whole report, --check
# writes nothing, and the installing run carries the same script lines.

libdirinstall_04_fresh_and_check() {
  d=$(new_tmp_dir); ok=0
  co="$d/checkout"; stage_checkout "$co"
  home="$d/home"; mkdir -p "$home"

  # --check on a machine with nothing installed: fresh, and writes nothing
  install_at "$home" "$co/install.sh" --claude --check > "$d/check.log" 2>&1 \
    || { echo "  --check exited non-zero"; return 1; }
  for f in $LIB_SCRIPTS; do
    line=$(grep -c "^$f: fresh install of antz $CURRENT_VERSION\$" "$d/check.log")
    [ "$line" -eq 1 ] || { echo "  --check: expected exactly one '$f: fresh install of antz $CURRENT_VERSION' line, got $line"; ok=1; }
  done
  # after the per-client report lines
  client_line=$(grep -n '^Claude Code: fresh install' "$d/check.log" | cut -d: -f1 | head -1)
  first_script=$(grep -n "^antz-flow.sh: fresh install" "$d/check.log" | cut -d: -f1 | head -1)
  [ -n "$client_line" ] && [ -n "$first_script" ] && [ "$first_script" -gt "$client_line" ] || {
    echo "  script report lines do not follow the per-client report line"; ok=1; }
  # --check writes nothing: no libdir directory, no file, no backup
  [ -z "$(find "$home" -mindepth 1 -print -quit 2>/dev/null)" ] || {
    echo "  --check wrote something under HOME:"; find "$home" -mindepth 1 | sed 's/^/    /'; ok=1; }

  # an installing run carries the same script report lines
  install_at "$home" "$co/install.sh" --claude > "$d/install.log" 2>&1 \
    || { echo "  installing run exited non-zero"; return 1; }
  for f in $LIB_SCRIPTS; do
    grep -q "^$f: fresh install of antz $CURRENT_VERSION\$" "$d/install.log" || {
      echo "  installing run is missing the '$f' fresh-install report line"; ok=1; }
  done

  # after a real install, --check reports each script already up to date
  install_at "$home" "$co/install.sh" --claude --check > "$d/check2.log" 2>&1 || { echo "  second --check failed"; ok=1; }
  for f in $LIB_SCRIPTS; do
    grep -q "^$f: already up to date (antz $CURRENT_VERSION)\$" "$d/check2.log" || {
      echo "  --check after install: '$f' not reported up to date"; ok=1; }
  done
  # each line is keyed off the script's own marker: restamp one to 4.5.6
  restamped="$d/restamped"
  { sed '2d' "$home/.config/antz/scripts/antz-flow.sh"; } > "$restamped"
  { sed -n '1p' "$home/.config/antz/scripts/antz-flow.sh"; marker_line 4.5.6; echo; sed -n '3,$p' "$restamped"; } \
    > "$home/.config/antz/scripts/antz-flow.sh"
  install_at "$home" "$co/install.sh" --claude --check > "$d/check3.log" 2>&1 || { echo "  third --check failed"; ok=1; }
  grep -q "^antz-flow.sh: antz 4\.5\.6 -> $CURRENT_VERSION\$" "$d/check3.log" || {
    echo "  the restamped script's drift line is missing (marker version not honored per script)"; ok=1; }
  grep -q "^antz-probe.sh: already up to date" "$d/check3.log" || {
    echo "  a sibling script stopped reporting up to date after the restamp"; ok=1; }
  return $ok
}

libdirinstall_04_drift_once() {
  d=$(new_tmp_dir); ok=0
  co="$d/checkout"; stage_checkout "$co" 9.9.9
  cat > "$co/CHANGELOG.md" <<'CL'
# Changelog

## [9.9.10]

- FIXTURE-CHG the newest entry

## [9.9.9]

- FIXTURE-CHG the installed entry
CL
  home="$d/home"; mkdir -p "$home"
  env -u XDG_CONFIG_HOME HOME="$home" sh "$co/install.sh" --all > "$d/install.log" 2>&1 \
    || { echo "  install at 9.9.9 exited non-zero"; return 1; }
  printf '9.9.10\n' > "$co/VERSION"

  env -u XDG_CONFIG_HOME HOME="$home" sh "$co/install.sh" --all --check > "$d/check.log" 2>&1 \
    || { echo "  drift --check exited non-zero"; return 1; }
  # every artifact line reports the same drift: 2 clients + 4 scripts
  for label in 'Claude Code' 'OpenCode' $LIB_SCRIPTS; do
    grep -q "^$label: antz 9\.9\.9 -> 9\.9\.10\$" "$d/check.log" || {
      echo "  missing drift line for '$label': $(grep -c "$label" "$d/check.log") mentions"; ok=1; }
  done
  # the intervening CHANGELOG entries print at most once for the whole report
  n=$(grep -c 'FIXTURE-CHG the newest entry' "$d/check.log")
  [ "$n" -eq 1 ] || { echo "  CHANGELOG entries printed $n times (expected exactly 1 for the whole report)"; ok=1; }
  # --check still wrote nothing: every installed marker sits at 9.9.9
  for f in $LIB_SCRIPTS; do
    grep -q "^# antz:generated version=9\.9\.9 " "$home/.config/antz/scripts/$f" || {
      echo "  --check restamped $f (expected untouched at 9.9.9)"; ok=1; }
  done
  [ -z "$(find "$home" -name '*.bak.*' -print -quit)" ] || { echo "  --check created a backup"; ok=1; }
  # the installing run restamps and prints the same script drift lines
  env -u XDG_CONFIG_HOME HOME="$home" sh "$co/install.sh" --all > "$d/install2.log" 2>&1 \
    || { echo "  drift install exited non-zero"; return 1; }
  for f in $LIB_SCRIPTS; do
    grep -q "^$f: antz 9\.9\.9 -> 9\.9\.10\$" "$d/install2.log" || {
      echo "  installing run is missing the '$f' drift report line"; ok=1; }
    grep -q "^# antz:generated version=9\.9\.10 " "$home/.config/antz/scripts/$f" || {
      echo "  $f was not restamped by the installing run"; ok=1; }
  done
  n=$(grep -c 'FIXTURE-CHG the newest entry' "$d/install2.log")
  [ "$n" -eq 1 ] || { echo "  installing-run CHANGELOG entries printed $n times (expected 1)"; ok=1; }
  return $ok
}

# ---- libdirinstall-05 ---------------------------------------------------------
# Fail-closed atomic single-pass source read: a script source that cannot be
# read (local) or fetched (remote, failing curl stand-in) aborts install.sh
# non-zero naming it, and because all four sources are read before any
# destination is written, the previous install (client files and libdir) is
# left completely intact.

tree_state() {
  # $1 = HOME -> sorted per-file checksums of every file under it
  find "$1" -type f -exec cksum {} + | sed "s|$1/||" | sort
}

libdirinstall_05_local() {
  d=$(new_tmp_dir); ok=0
  co="$d/checkout"; stage_checkout "$co" 9.9.9
  home="$d/home"; mkdir -p "$home"
  env -u XDG_CONFIG_HOME HOME="$home" sh "$co/install.sh" --all > "$d/run1.log" 2>&1 \
    || { echo "  baseline install at 9.9.9 exited non-zero"; return 1; }
  before=$(tree_state "$home")
  # bump the version AND break one script source: the run must fail naming
  # the unreadable script and touch nothing
  printf '9.9.10\n' > "$co/VERSION"
  rm -f "$co/scripts/orchestration/antz-probe.sh"
  rc=0
  env -u XDG_CONFIG_HOME HOME="$home" sh "$co/install.sh" --all > "$d/run2.log" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || { echo "  install succeeded despite a missing script source"; ok=1; }
  grep -qF 'scripts/orchestration/antz-probe.sh' "$d/run2.log" || {
    echo "  failure output does not name the unreadable script:"; head -5 "$d/run2.log" | sed 's/^/    /'; ok=1; }
  # previous install completely intact -- client files and libdir both, one
  # pass, no partial libdir from this run
  after=$(tree_state "$home")
  [ "$before" = "$after" ] || {
    echo "  the failed run modified the previous install:"; diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") | sed 's/^/    /' | head -8; ok=1; }
  grep -q '^# antz:generated version=9\.9\.9 ' "$home/.config/antz/scripts/antz-flow.sh" || {
    echo "  the intact check above lost meaning (baseline libdir marker wrong)"; ok=1; }
  # with no previous install at all, the failing run writes nothing
  home2="$d/home-fresh"; mkdir -p "$home2"
  env -u XDG_CONFIG_HOME HOME="$home2" sh "$co/install.sh" --claude > "$d/run3.log" 2>&1 && {
    echo "  fresh install with a missing source exited zero"; ok=1; }
  [ -z "$(find "$home2" -mindepth 1 -print -quit 2>/dev/null)" ] || {
    echo "  the failing fresh run wrote destinations before reading all sources:"
    find "$home2" -type f | sed 's/^/    /'; ok=1; }
  return $ok
}

libdirinstall_05_remote() {
  d=$(new_tmp_dir); ok=0
  root="$d/fixture"; bin="$d/bin"; log="$d/curl.log"; : > "$log"
  make_recording_curl "$bin"
  stage_fixture_tree "$root" master
  rm -f "$root/master/scripts/orchestration/antz-probe.sh"
  work="$d/work"; mkdir -p "$work"; cp "$INSTALL_SH" "$work/install.sh"
  home="$d/home"; mkdir -p "$home"
  rc=0
  ( cd "$work" && env -u ANTZ_REF -u XDG_CONFIG_HOME HOME="$home" PATH="$bin:$PATH" \
      CURL_LOG="$log" FIXTURE_ROOT="$root" sh ./install.sh --claude > "$d/run.log" 2>&1 ) || rc=$?
  [ "$rc" -ne 0 ] || { echo "  remote install succeeded despite an unfetchable script"; return 1; }
  grep -qF 'scripts/orchestration/antz-probe.sh' "$d/run.log" || {
    echo "  the remote failure does not name the unfetchable script:"; head -5 "$d/run.log" | sed 's/^/    /'; ok=1; }
  # the fetch went through RAW_BASE (the recording stand-in saw the URL),
  # and no destination was written
  grep -qF 'raw.githubusercontent.com/edezacas/antz/master/scripts/orchestration/antz-probe.sh' "$log" || {
    echo "  the script fetch did not go through RAW_BASE (see $log)"; ok=1; }
  [ -z "$(find "$home" -mindepth 1 -print -quit 2>/dev/null)" ] || {
    echo "  the failing remote run wrote destinations:"; find "$home" -type f | sed 's/^/    /'; ok=1; }
  return $ok
}

# ---- libdirinstall-06 ---------------------------------------------------------
# The libdir is client-independent and installs in the same single pass; the
# invocation contract is "sh <path>": no PATH additions, no hook or plugin,
# no exec bit required.

libdirinstall_06() {
  d=$(new_tmp_dir); ok=0
  co="$d/checkout"; stage_checkout "$co"
  home="$d/home"; mkdir -p "$home"

  # one invocation for exactly one client writes that client's files AND the
  # four shared libdir scripts -- no second command, no post-install step
  install_at "$home" "$co/install.sh" --claude > "$d/run1.log" 2>&1 \
    || { echo "  --claude install exited non-zero"; return 1; }
  n=$(find "$home" -type f | wc -l | tr -d ' ')
  [ "$n" -eq 9 ] || { echo "  single-client install wrote $n files (expected 6 Claude + 3 shared libdir)"; ok=1; }
  [ -d "$home/.config/opencode" ] && { echo "  an OpenCode tree appeared for a Claude-only install"; ok=1; }
  for f in $LIB_SCRIPTS; do
    [ -f "$home/.config/antz/scripts/$f" ] || { echo "  libdir script missing after --claude: $f"; ok=1; }
  done

  # the other client's install reuses the SAME shared libdir (no per-client
  # subdirectory), restamping it in place with no backup
  install_at "$home" "$co/install.sh" --opencode > "$d/run2.log" 2>&1 \
    || { echo "  --opencode install exited non-zero"; ok=1; }
  n=$(find "$home" -type f | wc -l | tr -d ' ')
  [ "$n" -eq 15 ] || { echo "  second client install grew the tree to $n files (expected 15, no second libdir)"; ok=1; }
  n=$(find "$home" -type d -name scripts -path '*antz*' | wc -l | tr -d ' ')
  [ "$n" -eq 1 ] || { echo "  expected exactly one antz scripts libdir directory, found $n"; ok=1; }
  [ -z "$(find "$home" -name '*.bak.*' -print -quit)" ] || { echo "  the libdir reuse created a backup"; ok=1; }
  for f in $LIB_SCRIPTS; do
    grep -q "^# antz:generated version=$CURRENT_VERSION " "$home/.config/antz/scripts/$f" || {
      echo "  $f lost its restamped marker on the second-client run"; ok=1; }
  done

  # the invocation contract: no exec bit installed, "sh <path>" runs them,
  # nothing added to PATH, no hook or plugin anywhere in the tree
  for f in $LIB_SCRIPTS; do
    p="$home/.config/antz/scripts/$f"
    [ -x "$p" ] && { echo "  $f carries an exec bit (the contract requires none)"; ok=1; }
  done
  usage_line=$(sh "$home/.config/antz/scripts/antz-flow.sh" 2>&1; echo "rc=$?")
  case "$usage_line" in
    *"usage: sh <tempfile> discover"*rc=1) ;;
    *) echo "  non-executable libdir file does not run via \"sh <path>\": $usage_line"; ok=1 ;;
  esac
  ex=$(grep -v '^[[:space:]]*#' "$INSTALL_SH" | grep -cE '(^|[[:space:]])PATH=')
  [ "$ex" -eq 0 ] || { echo "  install.sh assigns PATH in executable code ($ex times)"; ok=1; }
  return $ok
}

# ---- libdirinstall-07 ---------------------------------------------------------
# The fetch architecture survives with its subject changed to script
# installation: each of the two on-disk script sources is fetched through
# the one fetch_file helper, the set-model source is install.sh's own emitter
# text (read, never fetched from outside -- since change
# deembed-orchestration-scripts sub-spec 03 that text is redirected straight
# into the libdir file, no command-substitution capture: this test's pin
# re-scoped accordingly, loud note), there is exactly one executable
# "curl -fsSL" invocation inside fetch_file, and RAW_BASE still carries the
# ANTZ_REF-constructed URL (clauses unchanged).

libdirinstall_07() {
  d=$(new_tmp_dir); ok=0
  for rel in scripts/orchestration/antz-flow.sh scripts/orchestration/antz-probe.sh; do
    grep -qF "fetch_file \"$rel\"" "$INSTALL_SH" || {
      echo "  the script install does not fetch $rel through fetch_file"; ok=1; }
  done
  grep -qF 'emit_set_model_script > "$dest"' "$INSTALL_SH" || {
    echo "  the set-model source is no longer written straight from install.sh's own emitter"; ok=1; }
  grep -qF 'src_set_model=$(emit_set_model_script' "$INSTALL_SH" && {
    echo "  the set-model emitter text is captured through a command substitution again (retired by setmodeldeembed-03)"; ok=1; }
  # exactly one executable curl invocation, inside fetch_file, reading the
  # whole URL from the ANTZ_REF-pinned RAW_BASE (unchanged clauses)
  n=$(grep -v '^[[:space:]]*#' "$INSTALL_SH" | grep -c 'curl -fsSL')
  [ "$n" -eq 1 ] || { echo "  expected exactly one executable curl -fsSL invocation, got: $n"; ok=1; }
  awk '/^fetch_file\(\) \{/,/^\}/' "$INSTALL_SH" > "$d/fetch_file.sh"
  grep -qF 'curl -fsSL "$RAW_BASE/$rel"' "$d/fetch_file.sh" || {
    echo "  fetch_file's curl invocation no longer reads the whole URL from RAW_BASE"; ok=1; }
  ex=$(grep -v '^[[:space:]]*#' "$INSTALL_SH" | grep -c 'ANTZ_REF')
  [ "$ex" -eq 1 ] || { echo "  expected ANTZ_REF read exactly once in executable code (at the RAW_BASE construction), got: $ex"; ok=1; }
  grep -v '^[[:space:]]*#' "$INSTALL_SH" | grep 'ANTZ_REF' | grep -q '^RAW_BASE=' || {
    echo "  the ref substitution is not at the RAW_BASE construction"; ok=1; }
  return $ok
}

# ---- run ---------------------------------------------------------------------

run_test "libdirinstall-01: the four scripts install as marked files in the resolved libdir; the three orchestration copies are byte-faithful sources plus one inserted marker line, the sources stay byte-unchanged, and sh <path> behaves exactly like running the source" libdirinstall_01
run_test "libdirinstall-02: the libdir is resolved once by install.sh honoring XDG_CONFIG_HOME (set installs under it, unset and empty fall back to \$HOME/.config identically), with no fallback token or placeholder surviving any written file" libdirinstall_02
run_test "libdirinstall-03: the .bak.<ts> policy and anchored marker detection apply to libdir files unchanged -- unmanaged is backed up byte-for-byte before overwrite, managed is overwritten in place and restamped, backups are never touched" libdirinstall_03
run_test "libdirinstall-04: --check and installing runs report each script (fresh / already up to date / old -> new drift, keyed off its own marker version) after the per-client lines, CHANGELOG prints at most once per report, --check writes nothing" libdirinstall_04_fresh_and_check
run_test "libdirinstall-04: drift with both clients and all four scripts reports every artifact line while the intervening CHANGELOG entries print exactly once for the whole report, and the installing run restamps all markers" libdirinstall_04_drift_once
run_test "libdirinstall-05: a missing script source (local read or remote fetch) aborts install.sh non-zero naming it, before any destination write, leaving the previous client files and libdir completely intact" libdirinstall_05_local
run_test "libdirinstall-05: the remote path fetches script sources through RAW_BASE and a failing curl on one source aborts the whole pass with no destination written" libdirinstall_05_remote
run_test "libdirinstall-06: one client-only invocation installs the four scripts to the shared client-independent libdir and the other client's run reuses and restamps it without backups; no exec bit, no PATH change, no hook or plugin" libdirinstall_06
run_test "libdirinstall-07: script installation fetches each on-disk source through the one fetch_file helper (set-model read from install.sh's own emitter), with exactly one executable curl -fsSL inside fetch_file and the RAW_BASE/ANTZ_REF construction unchanged" libdirinstall_07

echo
echo "pass=$pass_count fail=$fail_count skip=$skip_count"
[ "$fail_count" -eq 0 ]
