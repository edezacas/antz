#!/usr/bin/env bash
# tests/libdirinstall_test.sh -- the owning suite for install.sh's libdir
# script installation: the flow script (scripts/orchestration/antz-flow.sh)
# installing as a marked, byte-faithful copy in the one shared, resolved
# library directory "${XDG_CONFIG_HOME:-$HOME/.config}/antz/scripts", with
# the same marker / backup / --check policy every other installed file
# carries. Covered by spdd/specs/install-render.md (installrender-02/03/04)
# and spdd/specs/flow.md.
#
# Every run gets an isolated HOME and an explicitly controlled
# XDG_CONFIG_HOME (set to an isolated dir, empty, or unset via env -u) --
# never the session's own config home and never a real client directory.
# Run:  sh tests/libdirinstall_test.sh

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INSTALL_SH="$SCRIPT_DIR/install.sh"
CURRENT_VERSION=$(tr -d ' \t\r\n' < "$SCRIPT_DIR/VERSION")
LIB_SCRIPT="antz-flow.sh"

pass_count=0
fail_count=0
skip_count=0

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

tmp_roots=()
new_tmp_dir() {
  d=$(mktemp -d)
  tmp_roots+=("$d")
  printf '%s' "$d"
}

cleanup() { [ "${#tmp_roots[@]}" -gt 0 ] && rm -rf "${tmp_roots[@]}"; }
trap cleanup EXIT

# ---- helpers -----------------------------------------------------------------

marker_line() {
  printf '# antz:generated version=%s -- do not edit by hand; regenerate with install.sh' "$1"
}

stage_checkout() {
  # $1 = checkout dir, $2 = optional VERSION override.
  dir="$1"; ver="${2:-$CURRENT_VERSION}"
  mkdir -p "$dir"
  cp "$INSTALL_SH" "$dir/install.sh"
  cp "$SCRIPT_DIR/CHANGELOG.md" "$dir/CHANGELOG.md"
  cp -R "$SCRIPT_DIR/agents" "$dir/agents"
  cp -R "$SCRIPT_DIR/scripts" "$dir/scripts"
  printf '%s\n' "$ver" > "$dir/VERSION"
}

install_at() {
  # $1 = sandbox HOME, $2 = install.sh path, rest = flags.
  home="$1"; sh_path="$2"; shift 2
  env -u XDG_CONFIG_HOME HOME="$home" sh "$sh_path" "$@"
}

install_xdg() {
  # $1 = sandbox HOME, $2 = XDG_CONFIG_HOME value, $3 = install.sh path, rest = flags.
  home="$1"; xdg="$2"; sh_path="$3"; shift 3
  env XDG_CONFIG_HOME="$xdg" HOME="$home" sh "$sh_path" "$@"
}

behaviour_dump() {
  # $1 = flow script path, $2 = scratch dir. A deterministic invocation
  # (no arguments: usage text, exit 1) whose output carries no path of its
  # own, so identical dumps mean "the installed copy behaves exactly like
  # its source".
  env -u CHANGE_DIR sh "$1" > "$2/out" 2>&1
  printf 'rc=%s\n' "$?" >> "$2/out"
  cat "$2/out"
}

# ---- installrender-03 / libdirinstall-01 ------------------------------------

test_libdirinstall_01() {
  d=$(new_tmp_dir); ok=0
  co="$d/checkout"; stage_checkout "$co"
  home="$d/home"; mkdir -p "$home"

  src_before=$(cksum "$co"/scripts/orchestration/*.sh)
  install_at "$home" "$co/install.sh" --claude > "$d/install.log" 2>&1 \
    || { echo "  install.sh --claude exited non-zero"; head -5 "$d/install.log" | sed 's/^/    /'; return 1; }

  lib="$home/.config/antz/scripts"
  [ -f "$lib/$LIB_SCRIPT" ] || { echo "  libdir script missing: $lib/$LIB_SCRIPT"; return 1; }
  [ "$(sed -n '1p' "$lib/$LIB_SCRIPT")" = '#!/bin/sh' ] || { echo "  line 1 is not the shebang"; ok=1; }
  [ "$(sed -n '2p' "$lib/$LIB_SCRIPT")" = "$(marker_line "$CURRENT_VERSION")" ] || {
    echo "  line 2 is not the marker: $(sed -n '2p' "$lib/$LIB_SCRIPT")"; ok=1; }

  sed '2d' "$lib/$LIB_SCRIPT" | cmp -s - "$co/scripts/orchestration/$LIB_SCRIPT" \
    || { echo "  installed copy is not the source plus one marker line"; ok=1; }

  [ "$src_before" = "$(cksum "$co"/scripts/orchestration/*.sh)" ] \
    || { echo "  the install run modified the checkout's script sources"; ok=1; }

  mkdir -p "$d/pa" "$d/pb"
  behaviour_dump "$lib/$LIB_SCRIPT" "$d/pa" > "$d/dump-installed"
  behaviour_dump "$co/scripts/orchestration/$LIB_SCRIPT" "$d/pb" > "$d/dump-source"
  cmp -s "$d/dump-installed" "$d/dump-source" \
    || { echo "  the installed copy does not behave like its source"; ok=1; }

  return $ok
}

# ---- libdirinstall-02 --------------------------------------------------------

test_libdirinstall_02() {
  d=$(new_tmp_dir); ok=0
  co="$d/checkout"; stage_checkout "$co"

  home1="$d/home1"; xdg="$d/xdg"; mkdir -p "$home1" "$xdg"
  install_xdg "$home1" "$xdg" "$co/install.sh" --claude > "$d/run-set.log" 2>&1 \
    || { echo "  XDG-set install failed"; ok=1; }
  [ -f "$xdg/antz/scripts/$LIB_SCRIPT" ] || { echo "  XDG set: script not under the XDG base"; ok=1; }

  home2="$d/home2"; mkdir -p "$home2"
  install_at "$home2" "$co/install.sh" --claude > "$d/run-unset.log" 2>&1 \
    || { echo "  XDG-unset install failed"; ok=1; }
  [ -f "$home2/.config/antz/scripts/$LIB_SCRIPT" ] || { echo "  XDG unset: no HOME fallback"; ok=1; }

  home3="$d/home3"; mkdir -p "$home3"
  install_xdg "$home3" "" "$co/install.sh" --claude > "$d/run-empty.log" 2>&1 \
    || { echo "  XDG-empty install failed"; ok=1; }
  [ -f "$home3/.config/antz/scripts/$LIB_SCRIPT" ] || { echo "  XDG empty does not fall back like unset"; ok=1; }

  if find "$home1" "$xdg" "$home2" "$home3" -type f -exec grep -l '__ANTZ_SCRIPTS_DIR__' {} + 2>/dev/null | grep .; then
    echo "  a written file still carries the __ANTZ_SCRIPTS_DIR__ placeholder"; ok=1
  fi
  return $ok
}

# ---- installrender-02 / libdirinstall-03 ------------------------------------

test_libdirinstall_03() {
  d=$(new_tmp_dir); ok=0
  co="$d/checkout"; stage_checkout "$co"
  home="$d/home"; mkdir -p "$home/.config/antz/scripts"
  lib="$home/.config/antz/scripts"

  # An unmanaged file (no line-start marker) is backed up byte-for-byte.
  printf 'echo foreign\n' > "$lib/$LIB_SCRIPT"
  install_at "$home" "$co/install.sh" --claude > "$d/run1.log" 2>&1 || { echo "  install failed"; return 1; }
  bak=$(ls "$lib" | grep -c "^$LIB_SCRIPT.bak\." || true)
  [ "$bak" -eq 1 ] || { echo "  unmanaged file was not backed up exactly once (got $bak)"; ok=1; }
  bf=$(ls "$lib"/$LIB_SCRIPT.bak.* 2>/dev/null | head -1)
  [ -n "$bf" ] && grep -qx 'echo foreign' "$bf" || { echo "  backup is not byte-faithful"; ok=1; }

  # A managed file is overwritten in place, restamped, and not backed up again.
  install_at "$home" "$co/install.sh" --claude > "$d/run2.log" 2>&1 || { echo "  second install failed"; ok=1; }
  [ "$(ls "$lib" | grep -c "^$LIB_SCRIPT.bak\." || true)" -eq 1 ] \
    || { echo "  managed overwrite created a new backup"; ok=1; }
  [ "$(sed -n '2p' "$lib/$LIB_SCRIPT")" = "$(marker_line "$CURRENT_VERSION")" ] \
    || { echo "  managed copy was not restamped"; ok=1; }
  return $ok
}

# ---- installrender-04 / libdirinstall-04 ------------------------------------

test_libdirinstall_04() {
  d=$(new_tmp_dir); ok=0
  co="$d/checkout"; stage_checkout "$co"
  home="$d/home"; mkdir -p "$home"

  install_at "$home" "$co/install.sh" --claude > /dev/null 2>&1 || { echo "  install failed"; return 1; }

  # --check writes nothing and reports the script's own state.
  snap_before=$(find "$home" -type f | sort | xargs cksum 2>/dev/null)
  install_at "$home" "$co/install.sh" --claude --check > "$d/check.log" 2>&1 || { echo "  --check exited non-zero"; ok=1; }
  snap_after=$(find "$home" -type f | sort | xargs cksum 2>/dev/null)
  [ "$snap_before" = "$snap_after" ] || { echo "  --check wrote files"; ok=1; }
  grep -qF "$LIB_SCRIPT: already up to date (antz $CURRENT_VERSION)" "$d/check.log" \
    || { echo "  --check did not report the script as up to date: $(cat "$d/check.log")"; ok=1; }

  # A newer tree reports old -> new for the script and prints CHANGELOG once.
  co2="$d/checkout2"; stage_checkout "$co2" "9.9.9"
  home2="$d/home2"; mkdir -p "$home2"
  install_at "$home2" "$co2/install.sh" --claude > /dev/null 2>&1 || { echo "  old-version install failed"; return 1; }
  install_at "$home2" "$co/install.sh" --claude --check > "$d/check2.log" 2>&1 || true
  grep -q "^$LIB_SCRIPT: antz 9.9.9 -> $CURRENT_VERSION" "$d/check2.log" \
    || { echo "  no drift line for $LIB_SCRIPT"; ok=1; }
  return $ok
}

# ---- libdirinstall-05 --------------------------------------------------------

test_libdirinstall_05() {
  d=$(new_tmp_dir); ok=0
  co="$d/checkout"; stage_checkout "$co"
  home="$d/home"; mkdir -p "$home"

  install_at "$home" "$co/install.sh" --claude > /dev/null 2>&1 || { echo "  baseline install failed"; return 1; }
  before=$(find "$home" -type f | sort | xargs cksum 2>/dev/null)

  rm -f "$co/scripts/orchestration/$LIB_SCRIPT"
  if install_at "$home" "$co/install.sh" --claude > "$d/run2.log" 2>&1; then
    echo "  install succeeded despite a missing script source"; ok=1
  fi
  grep -qF "scripts/orchestration/$LIB_SCRIPT" "$d/run2.log" \
    || { echo "  the failure does not name the unreadable script"; ok=1; }
  [ "$before" = "$(find "$home" -type f | sort | xargs cksum 2>/dev/null)" ] \
    || { echo "  a failed install still wrote destinations"; ok=1; }
  return $ok
}

run_test "libdirinstall-01: the flow script installs as a marked, byte-faithful copy in the resolved libdir, sources stay unchanged, and sh <path> behaves like the source" test_libdirinstall_01
run_test "libdirinstall-02: the libdir honors XDG_CONFIG_HOME (set, unset, empty) and no placeholder survives any written file" test_libdirinstall_02
run_test "libdirinstall-03: the .bak.<ts> policy and anchored marker detection apply to the libdir file" test_libdirinstall_03
run_test "libdirinstall-04: --check reports the script's own state and writes nothing" test_libdirinstall_04
run_test "libdirinstall-05: a missing script source aborts before any destination write" test_libdirinstall_05

echo "pass=$pass_count fail=$fail_count skip=$skip_count"
[ "$fail_count" -eq 0 ]
