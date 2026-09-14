#!/usr/bin/env bash
# tests/harness.sh -- the shared antz test-harness library.
#
# One sourced definition of the test-area plumbing that the suites used to
# copy-paste (run_test/skip_test accounting, temp-dir bookkeeping, cleanup,
# staged checkouts, install.sh renders, and the content readers). Suites
# source this file and keep only their scenario logic; a suite that sources
# the library defines none of the helpers below itself.
#
# Output contract (shared contract of change optimize-test-suite; every
# suite that sources this library carries it):
#   - exactly one "PASS: <name>" / "FAIL: <name>" / "SKIP: <name> (<reason>)"
#     line per registered test, where <name> begins with the test's scenario
#     id (the repo's id-tagging convention; a refusal stub's <reason> carries
#     the "BLOCKED: <why>" prefix verbatim);
#   - the suite's final output line is the aggregate "pass=<n> fail=<n>
#     skip=<n>", printed by finish_suite;
#   - the suite exits 0 exactly when no registered test failed (finish_suite
#     returns that status as the suite's last command).
#
# Hermeticity guarantees (library-level, not per-suite discipline):
#   - sourcing creates one per-suite-run temp root under "${TMPDIR:-/tmp}"
#     (mktemp); every new_tmp_dir directory lives inside it, and cleanup --
#     armed automatically by a trap on EXIT when this file is sourced --
#     removes the whole root, including on early failure;
#   - the install-render helpers (install_at/install_xdg/render_tree) are the
#     library's single invocation point for install.sh: every render runs
#     with HOME pointed at a caller-provided sandbox directory (always under
#     temp space) and XDG_CONFIG_HOME cleared (install_at/render_tree), so
#     install.sh can only write inside the sandbox -- never into the repo
#     working tree or the real "~/.claude" / "~/.config/opencode";
#   - render_tree renders a given staged tree exactly once per suite run and
#     returns the complete installed tree on every later call (content and
#     mtimes unchanged); a different staged tree performs its own render.
#
# Sourcing side effects (intentional, matching what the suites did by hand):
# initializes pass_count/fail_count/skip_count to 0, creates the run's temp
# root, and arms the cleanup trap. Sourced from the bash suites; the body
# keeps to syntax that also survives the `sh "$t"` re-invocations the
# cross-suite coherence runners use.

# Repo root, resolved from this file's own location ("tests/" parent).
HARNESS_REPO="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE:-$0}")/.." && pwd)"

pass_count=0
fail_count=0
skip_count=0

# ---- temp-dir bookkeeping ------------------------------------------------------
# Hermeticity is a library guarantee: every directory lives under one
# per-suite-run root (mktemp under "${TMPDIR:-/tmp}"), and cleanup removes
# the whole root -- robust even when a suite captures new_tmp_dir through
# command substitution, where the copy-pasted array bookkeeping silently
# lost its entries in the substitution subshell.

HARNESS_RUN_TMP="$(mktemp -d "${TMPDIR:-/tmp}/antz-harness.XXXXXX")"

new_tmp_dir() {
  d=$(mktemp -d "$HARNESS_RUN_TMP/tmp.XXXXXX")
  printf '%s' "$d"
}

cleanup() {
  [ -n "${HARNESS_RUN_TMP:-}" ] && rm -rf "$HARNESS_RUN_TMP"
  return 0
}
trap cleanup EXIT

# ---- the tiny test runner -----------------------------------------------------

run_test() {
  # $1 = reported test name (must begin with its scenario id), $2 = function
  # name, $3.. = optional arguments passed through to the function.
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
  # $1 = reported test name (must begin with its scenario id), $2 = reason.
  # An explicit, accounted-for stub for a scenario that is out of scope for
  # unit-level TDD (never a silent omission). A refusal/escalation carries
  # the "BLOCKED: <why>" convention in <reason>.
  name="$1"; reason="$2"
  echo "SKIP: $name ($reason)"
  skip_count=$((skip_count + 1))
}

finish_suite() {
  # The suite's final act: print the aggregate line and exit 0 exactly when
  # no registered test failed (put this last in the suite file; the EXIT
  # trap armed above still runs cleanup after it).
  echo "pass=$pass_count fail=$fail_count skip=$skip_count"
  [ "$fail_count" -eq 0 ]
}

# ---- content readers ------------------------------------------------------------

require() {
  # $1 = file, $2 = fixed string that must appear in it
  if grep -qF -- "$2" "$1"; then return 0; fi
  echo "  missing required text: $2"
  return 1
}

refuse() {
  # $1 = file, $2 = fixed string that must NOT appear in it
  if grep -qF -- "$2" "$1"; then
    echo "  found forbidden text: $2"
    return 1
  fi
  return 0
}

extract_section() {
  # $1 = file, $2 = heading text, $3 = output file: the section from the
  # "## <heading>" line down to (excluding) the next "## " line.
  awk -v sec="$2" '
    $0 == "## " sec { flag=1; next }
    flag && /^## / { flag=0 }
    flag { print }
  ' "$1" > "$3"
}

extract_bullet() {
  # $1 = file, $2 = fixed bullet prefix; prints the first matching line.
  grep -F -- "$2" "$1" | head -n 1
}

extract_bullet_line() {
  # $1 = file, $2 = fixed prefix, $3 = output file: every matching line.
  grep -F -- "$2" "$1" > "$3"
}

extract_line() {
  # $1 = file, $2 = fixed substring, $3 = output file: the first match only.
  grep -m1 -F -- "$2" "$1" > "$3"
}

extract_fn() {
  # $1 = file, $2 = function name, $3 = output file: the function's source
  # from its "name() {" line through the first column-0 "}".
  awk -v fn="$2" '
    index($0, fn "() {") == 1 { flag = 1 }
    flag { print }
    flag && $0 == "}" { exit }
  ' "$1" > "$3"
}

# ---- staged checkouts ----------------------------------------------------------

stage_checkout() {
  # $1 = destination directory, $2 = optional VERSION content override
  # (the libdirinstall-era second argument). Copies the working tree's
  # current product files -- install.sh, VERSION, CHANGELOG.md, agents/,
  # scripts/orchestration/ -- into a fresh tree, so suites always exercise
  # the working tree's current state (as the copy-pasted versions did).
  dest="$1"; ver="${2:-}"
  mkdir -p "$dest"
  cp "$HARNESS_REPO/install.sh" "$dest/install.sh"
  if [ -n "$ver" ]; then
    printf '%s\n' "$ver" > "$dest/VERSION"
  else
    cp "$HARNESS_REPO/VERSION" "$dest/VERSION"
  fi
  cp "$HARNESS_REPO/CHANGELOG.md" "$dest/CHANGELOG.md"
  cp -R "$HARNESS_REPO/agents" "$dest/agents"
  mkdir -p "$dest/scripts"
  cp -R "$HARNESS_REPO/scripts/orchestration" "$dest/scripts/orchestration"
}

# ---- install.sh renders (the library's single invocation point) --------------
# The suites never call install.sh themselves; every render funnels through
# the helpers here, always with HOME pointed at a sandbox directory and
# XDG_CONFIG_HOME cleared (install_xdg is the one deliberate exception: it
# exists for the XDG-resolution checks, and the caller MUST pass a sandbox
# path for it -- never the real config dir).

install_at() {
  # $1 = sandbox HOME, $2 = install.sh path, rest = install.sh flags.
  # A fully explicit environment (session XDG leakage removed).
  home="$1"; sh_path="$2"; shift 2
  env -u XDG_CONFIG_HOME HOME="$home" sh "$sh_path" "$@"
}

install_xdg() {
  # $1 = sandbox HOME, $2 = XDG_CONFIG_HOME value to export (set or empty --
  # both explicit, and sandbox either way), $3 = install.sh path, rest = flags.
  home="$1"; xdg="$2"; sh_path="$3"; shift 3
  env XDG_CONFIG_HOME="$xdg" HOME="$home" sh "$sh_path" "$@"
}

# Render cache: one directory per (staged-tree, flags) key under the run
# root, holding the sandbox home path, the render's exit status, and a
# "done" sentinel written last. File-based, not array-based, so it survives
# the command-substitution subshells suites capture render results in
# (`home=$(render_tree ...)`).

render_tree() {
  # $1 = staged checkout dir (stage_checkout produced), rest = install.sh
  # flags (default --all). Prints the sandbox home holding the COMPLETE
  # installed tree and returns that render's exit status -- executing
  # install.sh only the first time this exact (tree, flags) pair is asked
  # for: later calls return the same home with contents and mtimes
  # untouched. A different staged tree is a different key: its own render.
  tree="$1"; shift
  if [ ! -f "$tree/install.sh" ]; then
    echo "render_tree: no install.sh under $tree (stage it first)" >&2
    return 1
  fi
  if [ "$#" -eq 0 ]; then
    set -- --all
  fi
  slot="$HARNESS_RUN_TMP/render/$(printf '%s' "$tree|$*" | cksum | tr ' /' '__')"
  if [ -f "$slot/done" ]; then
    printf '%s' "$(cat "$slot/home")"
    return "$(cat "$slot/rc")"
  fi
  sb=$(new_tmp_dir)
  home="$sb/home"
  mkdir -p "$home"
  install_at "$home" "$tree/install.sh" "$@" > "$sb/install.log" 2>&1
  rc=$?
  mkdir -p "$slot"
  printf '%s' "$home" > "$slot/home"
  printf '%s' "$rc" > "$slot/rc"
  : > "$slot/done"
  printf '%s' "$home"
  return "$rc"
}
