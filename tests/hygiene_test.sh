#!/usr/bin/env bash
# tests/hygiene_test.sh -- the four permanent laws of the antz test area
# (change optimize-test-suite, sub-spec 09). One hygiene suite scans the
# suite SOURCES and fails loudly (naming file and line) when a law breaks:
#
#   hygiene-01 (laws 1+2): no suite executes another suite, and no suite
#     asserts another existing suite's source content or output; only the
#     documented runner (tests/run_all.sh) answers "is the whole area green".
#   hygiene-02 (law 3): no suite compares the real tree against git HEAD
#     (merge-base / show HEAD: / git diff --quiet HEAD / git -C against the
#     real repo root / any own-file byte-pin against a HEAD copy).
#   hygiene-03 (law 4): no suite pins an exact prose phrase of a role prompt
#     (agents/prompts/) or a doc (docs/, AGENTS.md, CLAUDE.md): no grep of an
#     embedded literal against either, no byte-compare of either's content
#     against embedded expected text. A comparison of two live-read files
#     pins no phrase and is not a violation. The SOLE exception is the
#     Working-Root triplication consistency check in tests/roles_test.sh,
#     delimited there by the marker comments
#     "hygiene:working-root-exception-begin" / "...-end"; the marker pair
#     names no other suite.
#
# Discovery contract (shared): a suite is any "<scan root>/*_test.sh" file;
# tests/bash32-sh.sh and tests/harness.sh are helpers, not suites.
#
# Carve-outs applied to every scan: comment text (whole lines and trailing
# # comments) is dropped; a suite may read its own file; this suite's own
# source is exempt from every scan (it encodes the detection patterns);
# single-quoted literals -- whole strings, including multi-line ones, via a
# shared POSIX-quote lexer -- are stripped before matching, so quote-split
# self-guard needles (the area convention) never self-match; fixture strings
# naming suite files that do not exist in the scan root are not references;
# git operations aimed at throwaway fixture repositories under temp space (a
# -C target variable assigned from mktemp / new_tmp_dir / the harness run
# root) are not real-tree comparisons.
#
# No scan passes vacuously: each scenario plants its own violation in a temp
# fixture copy of the scan root and requires the scan to fail naming the
# planted file and line.
#
# The shared harness library provides the runner plumbing; this suite defines
# none of it itself. Run directly:  sh tests/hygiene_test.sh

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
# shellcheck source=tests/harness.sh
. "$SCRIPT_DIR/tests/harness.sh"

HYGIENE_SELF="hygiene_test.sh"
HYG_AWK="$(new_tmp_dir)"

# ---- the awk scan programs (written once, under the run's temp root) --------

# The shared lexer: a small POSIX-shell-aware line stripper. Single-quoted
# string state persists ACROSS lines (a multi-line '...' assignment), double
# quotes nest only, a whitespace-preceded # outside quotes ends the line, and
# backslash escapes are honored inside "...". Single-quoted content (the
# quote-split needle convention) is dropped; everything else is kept verbatim.
cat > "$HYG_AWK/stripper.awk" <<'AWK'
function lex_strip(s,   out, i, c, n) {
  out = ""; n = length(s)
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (ST == "sq") { if (c == "'") ST = ""; continue }
    if (ST == "dq") {
      if (c == "\\") { out = out c substr(s, i + 1, 1); i++; continue }
      out = out c
      if (c == "\"") ST = ""
      continue
    }
    if (c == "\\") { out = out c substr(s, i + 1, 1); i++; continue }
    if (c == "#" && (i == 1 || substr(s, i - 1, 1) ~ /[ \t]/)) break
    if (c == "'") { ST = "sq"; continue }
    out = out c
    if (c == "\"") ST = "dq"
  }
  return out
}
function has_tool(line) {
  return line ~ /(^|[^A-Za-z0-9_$.])(grep|awk|sed|cmp|diff|cat|head|tail|sort|xargs|find|require|refuse|extract_section|extract_bullet_line|extract_bullet|extract_line|extract_fn)([^A-Za-z0-9_$]|$)/ || line ~ /(^|[ \t;&|(`$])[ \t]*(sh|bash|source|eval)([ \t]|$)/ || line ~ /(^|[ \t;&|(`$])[ \t]+\.[ \t]+["'$]/
}
AWK

cat > "$HYG_AWK/scan_suite_coupling.awk" <<'AWK'
# laws 1+2. -v siblings=<newline-joined existing basenames>. One process over
# every suite file; per-file state resets at the FILENAME boundary. The suite
# glob counts as a reference only where its matches get read or executed (a
# filename comparison, a case pattern, or a name string is not an assertion);
# the glob-LOOP leak -- for f in ...*_test.sh; do sh "$f"; done -- is caught
# by the loop-variable rule (an active variable from the opening for line
# until its done, checked for tool/exec reads of "$var").
BEGIN { n = split(siblings, sib, "\n") }
FILENAME != prev {
  prev = FILENAME; ST = ""; LV = ""; self = FILENAME; sub(/.*\//, "", self)
}
{
  line = lex_strip($0)
  if (line ~ /^[ \t]*$/) next
  if (index(line, "*_test.sh") > 0 && has_tool(line))
    printf "%s:%d: suite-coupling: references the suite-discovery glob *_test.sh (only the runner answers for the whole area)\n", FILENAME, FNR
  for (i = 1; i <= n; i++) {
    if (sib[i] == "" || sib[i] == self) continue
    if (index(line, sib[i]) > 0)
      printf "%s:%d: suite-coupling: references another existing suite %s\n", FILENAME, FNR, sib[i]
  }
  if (match(line, /^[ \t]*for[ \t]+([A-Za-z_][A-Za-z0-9_]*)[ \t]+in[ \t]/, mm) && index(line, "*_test.sh") > 0) LV = mm[1]
  if (LV != "" && has_tool(line) && line ~ "\\$\\{?" LV "\\}?[ \t\";&|)}]")
    printf "%s:%d: suite-coupling: reads or executes suites discovered through the glob loop variable %s\n", FILENAME, FNR, LV
  if (line ~ /(^|[;&|])[ \t]*done([ \t;&|]|$)/) LV = ""
}
AWK

cat > "$HYG_AWK/scan_head_compare.awk" <<'AWK'
# law 3. One process over every suite file; per-file two-pass buffering (pass
# 1 collects temp-fixture repo-root variables, pass 2 flags). Every git-verb
# pattern requires a git invocation on the same line -- a mere mention of
# HEAD (or a git verb) in a test name or a needle is not a comparison, and
# the bare-git rule names real subcommands only.
BEGIN { prev = ""; cnt = 0 }
FILENAME != prev {
  if (prev != "") process()
  prev = FILENAME; ST = ""; cnt = 0; delete L; delete fixture
}
{ cnt = FNR; L[FNR] = lex_strip($0) }
END { if (prev != "") process() }
function process(   i, line, rhs, m, v, isfx, hasgit) {
  for (i = 1; i <= cnt; i++) {
    line = L[i]
    if (line ~ /^[ \t]*$/) continue
    if (match(line, /^[ \t]*(local[ \t]+)?([A-Za-z_][A-Za-z0-9_]*)[ \t]*=/, m)) {
      rhs = substr(line, RSTART + RLENGTH - 1)
      if (rhs ~ /\$\((mktemp|new_tmp_dir)/ || rhs ~ /"\$HARNESS_RUN_TMP/ || rhs ~ /"\$\{TMPDIR/)
        fixture[m[2]] = 1
    }
  }
  for (i = 1; i <= cnt; i++) {
    line = L[i]
    if (line ~ /^[ \t]*$/) continue
    # any git operation aimed at a throwaway fixture repo is not a
    # real-tree comparison
    isfx = 0
    for (v in fixture)
      if (index(line, "git -C \"$" v "\"") > 0 || index(line, "git -C '$" v "'") > 0) isfx = 1
    if (isfx) continue
    hasgit = line ~ /(^|[ \t;&|(`$])git([ \t]|$)/
    if (hasgit && index(line, "merge-base") > 0)
      printf "%s:%d: head-compare: merge-base against the real tree\n", prev, i
    if (hasgit && line ~ /show[ \t]+"?HEAD:/)
      printf "%s:%d: head-compare: shows git HEAD content (show HEAD:)\n", prev, i
    if (hasgit && line ~ /show[ \t]+"?\$[A-Za-z_][A-Za-z0-9_]*:/)
      printf "%s:%d: head-compare: shows a git-rev-qualified file (show $rev:path)\n", prev, i
    if (hasgit && line ~ /cat-file[ \t]+-e[ \t]+HEAD/)
      printf "%s:%d: head-compare: tests file existence against git HEAD\n", prev, i
    if (hasgit && line ~ /diff[ \t]+--quiet[ \t]+HEAD/)
      printf "%s:%d: head-compare: git diff --quiet HEAD comparison\n", prev, i
    if (line ~ /(^|[ \t;&|(`$])git[ \t]+-C[ \t]+"?(\$(SCRIPT_DIR|HARNESS_REPO)|\$\{(SCRIPT_DIR|HARNESS_REPO)\})/)
      printf "%s:%d: head-compare: runs git against the real working tree\n", prev, i
    if (line ~ /(^|[ \t;&|(`$])git[ \t]+(-C|diff|show|cat-file|merge-base|rev-parse|rev-list|log)[ \t]/ && line ~ /(^|[^A-Za-z_])HEAD([^A-Za-z_]|$)/)
      printf "%s:%d: head-compare: git invocation naming HEAD outside a temp fixture repo\n", prev, i
  }
}
AWK

cat > "$HYG_AWK/scan_prose_pin.awk" <<'AWK'
# law 4. One process over every suite file; per-file two-pass buffering
# (pass 1 derives prose-source variables, pass 2 flags). -v
# allow_regions=<0|1> is replaced by the basename rule: the exception region
# is honored only in roles_test.sh (the sole declared carrier).
BEGIN {
  PROSE_RE  = "agents/prompts|\\.prompt($|[^A-Za-z])|AGENTS\\.md|CLAUDE\\.md|docs/[A-Za-z0-9]"
  TOOLS_RE  = "(^|[^A-Za-z0-9_$.])(grep|require|refuse|awk|sed|cmp|diff|extract_section|extract_bullet|extract_bullet_line|extract_line|extract_fn)([^A-Za-z0-9_$]|$)"
  STAGE_RE  = "^[ \t]*(cp|mv|rm|rmdir|touch|ln|chmod|chown|install|find|printf|echo|cat|:)([ \t]|$)"
  prev = ""; cnt = 0
}
FILENAME != prev {
  if (prev != "") process()
  prev = FILENAME; ST = ""; cnt = 0; b = FILENAME; sub(/.*\//, "", b)
  allow = (b == "roles_test.sh") ? 1 : 0
  delete L; delete S; delete start; delete endmark; delete INREG; delete SRC
  inreg = 0
}
{
  cnt = FNR; L[FNR] = $0; S[FNR] = lex_strip($0)
  if ($0 ~ /hygiene:working-root-exception-begin/) { start[FNR] = 1 }
  else if ($0 ~ /hygiene:working-root-exception-end/) { endmark[FNR] = 1 }
}
END { if (prev != "") process() }
function process(   i, line, rounds, changed, rhs, m, m2, mv, toks, hit, lv, s, open, j, cnt_, op, s2, mv2, mv3, ncnt) {
  open = 0
  for (i = 1; i <= cnt; i++) {
    if (i in start) open = i
    else if (i in endmark) { for (j = open; j <= i; j++) INREG[j] = 1; open = 0 }
    else if (open) INREG[i] = 1
  }
  # ---- pass 1: prose-source variables (rounds for chains) ----
  rounds = 0
  while (rounds++ < 4) {
    changed = 0
    for (i = 1; i <= cnt; i++) {
      line = S[i]
      if (line ~ /^[ \t]*$/) continue
      # VAR=<rhs naming a prose path directly>
      if (match(line, /^[ \t]*(local[ \t]+)?([A-Za-z_][A-Za-z0-9_]*)[ \t]*=[ \t]*/, m)) {
        rhs = substr(line, RSTART + RLENGTH - 1)
        if (!(m[2] in SRC) && rhs ~ PROSE_RE) { SRC[m[2]] = 1; changed = 1 }
        # VAR=$(anything reading a prose source or source variable)
        if (!(m[2] in SRC) && rhs ~ /^\$\(/ && (rhs ~ PROSE_RE || hastsrcline(rhs))) { SRC[m[2]] = 1; changed = 1 }
      }
      if (line ~ PROSE_RE || hastsrcline(line)) {
        # ... prose-source read redirected > "$VAR": the output is prose content
        if (match(line, />[ \t]*"?([A-Za-z_][A-Za-z0-9_]*)"?[ \t]*$/, m2) && !(m2[1] in SRC)) { SRC[m2[1]] = 1; changed = 1 }
        # extract_* "$SRCVAR" ... "$OUTVAR": the last quoted variable
        if (line ~ /(extract_section|extract_bullet_line|extract_line|extract_fn|extract_bullet)([ \t]|$)/ && hastsrcline(line)) {
          lv = ""; s = line
          while (match(s, /"\$[A-Za-z_][A-Za-z0-9_]*"/)) {
            lv = substr(s, RSTART + 2, RLENGTH - 3)
            s = substr(s, RSTART + RLENGTH)
          }
          if (lv != "" && !(lv in SRC)) { SRC[lv] = 1; changed = 1 }
        }
      }
      # for VAR in "$SRCVAR" ... -> VAR aliases the prose sources
      if (match(line, /^[ \t]*for[ \t]+([A-Za-z_][A-Za-z0-9_]*)[ \t]+in[ \t]/, m)) {
        toks = substr(line, RSTART + RLENGTH - 1); hit = 0
        while (match(toks, /"\$([A-Za-z_][A-Za-z0-9_]*)"/, mv)) {
          toks = substr(toks, RSTART + RLENGTH)
          if (mv[1] in SRC) { hit = 1; break }
        }
        if (hit && !(m[1] in SRC)) { SRC[m[1]] = 1; changed = 1 }
      }
    }
    if (!changed) break
  }
  # ---- pass 2: flag ----
  for (i = 1; i <= cnt; i++) {
    if (allow && (i in INREG)) continue
    line = S[i]
    if (line ~ /^[ \t]*$/) continue
    if (line ~ STAGE_RE) continue
    # a continuation line that is only a quoted file operand: the assertion's
    # tool lives on the previous line; reading a prose source is still a pin
    if (line ~ /^[ \t]*"\$[A-Za-z_][A-Za-z0-9_]*"[ \t]*\\?[ \t]*$/ && hastsrcline(line)) {
      printf "%s:%d: prose-pin: reads a prompt/doc source with an assertion\n", prev, i
      continue
    }
    if (!(line ~ PROSE_RE || hastsrcline(line))) continue
    if (!(line ~ TOOLS_RE)) continue
    if (line ~ /(^|[^A-Za-z0-9_$])(cmp|diff)([ \t]|$)/) {
      # a comparison of two live-read files pins no phrase
      ncnt = 0; toks = line
      while (match(toks, /"[^"]*"/, mv2)) {
        toks = substr(toks, RSTART + RLENGTH)
        op = substr(mv2[0], 2, length(mv2[0]) - 2)
        if (op ~ PROSE_RE) { ncnt++; continue }
        s2 = op
        while (match(s2, /\$[A-Za-z_][A-Za-z0-9_]*/, mv3)) {
          s2 = substr(s2, RSTART + RLENGTH)
          if (substr(mv3[0], 2) in SRC) { ncnt++; break }
        }
      }
      if (ncnt == 1)
        printf "%s:%d: prose-pin: byte-compares prose content against a non-prose operand\n", prev, i
      continue
    }
    printf "%s:%d: prose-pin: reads a prompt/doc source with an assertion\n", prev, i
  }
}
function hastsrcline(s,   t, mv9) {
  t = s
  while (match(t, /\$([A-Za-z_][A-Za-z0-9_]*)/, mv9)) {
    t = substr(t, RSTART + RLENGTH)
    if (mv9[1] in SRC) return 1
  }
  return 0
}
AWK

# ---- scan drivers -------------------------------------------------------------

discover_suites() {
  # every *_test.sh regular file directly under the scan root (sorted)
  for f in "$1"/*_test.sh; do
    [ -f "$f" ] || continue
    printf '%s\n' "$f"
  done
}

sibling_names() {
  for f in "$1"/*_test.sh; do
    b="$(basename -- "$f")"
    [ "$b" = "$HYGIENE_SELF" ] && continue
    printf '%s\n' "$b"
  done
}

scan_suite_coupling() {
  root="${1:-$HARNESS_REPO/tests}"
  sibs="$(sibling_names "$root")"
  files=
  set --
  for f in "$root"/*_test.sh; do
    [ -f "$f" ] || continue
    b="$(basename -- "$f")"
    [ "$b" = "$HYGIENE_SELF" ] && continue
    set -- "$@" "$f"
  done
  [ "$#" -gt 0 ] || return 0
  awk -v siblings="$sibs" -f "$HYG_AWK/stripper.awk" -f "$HYG_AWK/scan_suite_coupling.awk" "$@"
}

scan_head_compare() {
  root="${1:-$HARNESS_REPO/tests}"
  set --
  for f in "$root"/*_test.sh; do
    [ -f "$f" ] || continue
    b="$(basename -- "$f")"
    [ "$b" = "$HYGIENE_SELF" ] && continue
    set -- "$@" "$f"
  done
  [ "$#" -gt 0 ] || return 0
  awk -f "$HYG_AWK/stripper.awk" -f "$HYG_AWK/scan_head_compare.awk" "$@"
}

scan_prose_pin() {
  root="${1:-$HARNESS_REPO/tests}"
  set --
  for f in "$root"/*_test.sh; do
    [ -f "$f" ] || continue
    b="$(basename -- "$f")"
    [ "$b" = "$HYGIENE_SELF" ] && continue
    set -- "$@" "$f"
  done
  [ "$#" -gt 0 ] || return 0
  awk -f "$HYG_AWK/stripper.awk" -f "$HYG_AWK/scan_prose_pin.awk" "$@"
}

# fixture_copy_root -> a temp copy of the real scan root (every suite file);
# the scans behave identically on it, this suite's own source included.
fixture_copy_root() {
  dest="$(new_tmp_dir)/root"
  mkdir -p "$dest"
  cp "$HARNESS_REPO"/tests/*_test.sh "$dest/"
  printf '%s' "$dest"
}

plant() { printf '%s\n' "$2" >> "$1"; }

# ---- hygiene-01: laws 1+2 -------------------------------------------------------

test_hygiene_01_no_suite_reads_another_suite() {
  violations=$(scan_suite_coupling)
  if [ -n "$violations" ]; then
    printf '%s\n' "$violations" | sed 's/^/  violation: /'
    return 1
  fi
  # the discovery contract holds over the real root: many suites, helpers out
  n=$(discover_suites "$HARNESS_REPO/tests" | wc -l | tr -d ' ')
  [ "$n" -ge 10 ] || { echo "  discovery found only $n suites in tests/"; return 1; }
  if discover_suites "$HARNESS_REPO/tests" | grep -qE '(harness|bash32-sh)\.sh$'; then
    echo "  discovery counted a helper file as a suite"
    return 1
  fi
  discover_suites "$HARNESS_REPO/tests" | grep -q "/$HYGIENE_SELF$" \
    || { echo "  this suite is not picked up by the discovery glob"; return 1; }
  return 0
}

test_hygiene_01_planted_violations_are_named() {
  root="$(fixture_copy_root)"
  target="$root/refpin_test.sh"
  [ -f "$target" ] || { echo "  fixture copy missing refpin_test.sh"; return 1; }
  # (a) executing another existing suite, (b) grepping another suite's
  # source, (c) the suite glob read, (d) the glob-loop exec leak -- all must
  # be named with file and line.
  plant "$target" 'sh "$root/runner_test.sh" >/dev/null 2>&1 || true'
  plant "$target" 'grep -qF "pass=" "$root/installsh-posixsh_test.sh"'
  plant "$target" 'hits=$(grep -lE "run_test" "$root"/*_test.sh)'
  plant "$target" 'for f in "$root"/*_test.sh; do sh "$f"; done'
  # controls: a self-file read and a fixture string naming a nonexistent
  # suite file stay legal
  plant "$target" 'grep -qF "x" "$root/refpin_test.sh"'
  plant "$target" 'grep -qF "x" "$root/no_such_area_suite_test.sh"'
  # controls: a comment line and a single-quoted quote-split needle naming a
  # real suite stay legal (only the planted execution line may name it)
  plant "$target" '# historical note: this replaced runner_test.sh once'
  plant "$target" "refuse \"\$root/refpin_test.sh\" 'runne''r_test.sh'"
  out=$(scan_suite_coupling "$root")
  [ "$(printf '%s\n' "$out" | grep "^$target:" | grep -c "runner_test.sh")" -eq 1 ] || {
    echo "  the comment/quoted-needle runner_test.sh controls were flagged"; return 1; }
  echo "$out" | grep -q "no_such_area_suite" && {
    echo "  a nonexistent fixture string was flagged as a reference"; return 1; }
  echo "$out" | grep -q "^$target:[0-9]*: suite-coupling: references another existing suite runner_test.sh$" || {
    echo "  planted suite execution not named with file and line"; return 1; }
  echo "$out" | grep -q "^$target:[0-9]*: suite-coupling: references another existing suite installsh-posixsh_test.sh$" || {
    echo "  planted suite source-grep not named with file and line"; return 1; }
  echo "$out" | grep -q "^$target:[0-9]*: suite-coupling: references the suite-discovery glob" || {
    echo "  planted *_test.sh glob not flagged"; return 1; }
  echo "$out" | grep -q "^$target:[0-9]*: suite-coupling: reads or executes suites discovered through the glob loop variable f$" || {
    echo "  planted glob-loop exec not flagged"; return 1; }
  return 0
}

# ---- hygiene-02: law 3 ----------------------------------------------------------

test_hygiene_02_no_suite_compares_the_real_tree_to_head() {
  violations=$(scan_head_compare)
  if [ -n "$violations" ]; then
    printf '%s\n' "$violations" | sed 's/^/  violation: /'
    return 1
  fi
  # a suite reading its OWN current file (no history) is how the retained
  # self-pins work; the scan's carve-outs are exercised by the planted test.
  return 0
}

test_hygiene_02_planted_violations_are_named() {
  root="$(fixture_copy_root)"
  target="$root/refpin_test.sh"
  base="$root/antz-flow_test.sh"
  own="$root/header-marker_test.sh"
  plant "$target" 'base=$(git -C "$SCRIPT_DIR" merge-base master HEAD 2>/dev/null || echo HEAD)'
  plant "$target" 'git -C "$SCRIPT_DIR" show HEAD:install.sh > "$tmp/head_install.sh"'
  plant "$target" 'git -C "$SCRIPT_DIR" diff --quiet HEAD -- agents/meta/ || ok=1'
  plant "$base" 'git -C "$SCRIPT_DIR" show "$base:scripts/orchestration/antz-flow.sh" > "$d/vtmp"'
  plant "$own" 'git -C "$SCRIPT_DIR" show HEAD:tests/header-marker_test.sh > "$h" && cmp -s "$h" "$own" && ok=1'
  out=$(scan_head_compare "$root")
  echo "$out" | grep -q "^$target:[0-9]*: head-compare: merge-base" || {
    echo "  planted merge-base not named"; return 1; }
  echo "$out" | grep -q "^$target:[0-9]*: head-compare: shows git HEAD content" || {
    echo "  planted show HEAD: not named"; return 1; }
  echo "$out" | grep -q "^$target:[0-9]*: head-compare: git diff --quiet HEAD" || {
    echo "  planted diff --quiet HEAD not named"; return 1; }
  echo "$out" | grep -q "^$base:[0-9]*: head-compare: shows a git-rev-qualified file" || {
    echo "  planted show \$base: not named"; return 1; }
  echo "$out" | grep -q "^$own:[0-9]*: head-compare:" || {
    echo "  planted own-file HEAD byte-pin not named"; return 1; }
  # git operations inside a throwaway fixture repository are not comparisons
  fx="$root/planted_fixture_only_test.sh"
  printf '%s\n' \
    'REPO_ROOT=$(mktemp -d)' \
    'git -C "$REPO_ROOT" init -q' \
    'git -C "$REPO_ROOT" rev-parse HEAD' \
    'git -C "$REPO_ROOT" show-ref --heads' \
    > "$fx"
  scan_head_compare "$root" | grep -q "^$fx:" && {
    echo "  temp-fixture git operations flagged as real-tree comparisons"; return 1; }
  return 0
}

# ---- hygiene-03: law 4 ----------------------------------------------------------

test_hygiene_03_no_suite_pins_prompt_or_doc_prose() {
  violations=$(scan_prose_pin)
  if [ -n "$violations" ]; then
    printf '%s\n' "$violations" | sed 's/^/  violation: /'
    return 1
  fi
  # the sole declared exception: exactly one suite carries the marker pair,
  # roles_test.sh, and its region byte-compares the three triplicated sections
  marked=$(grep -l 'hygiene:working-root-exception-begin' "$HARNESS_REPO"/tests/*_test.sh 2>/dev/null | grep -v "/$HYGIENE_SELF$")
  [ "$marked" = "$HARNESS_REPO/tests/roles_test.sh" ] || {
    echo "  exception markers are not exactly roles_test.sh's: '$marked'"; return 1; }
  awk '/hygiene:working-root-exception-begin/{s=1;next} /hygiene:working-root-exception-end/{s=0} s' \
      "$HARNESS_REPO/tests/roles_test.sh" | grep -q 'cmp -s "$WR_SPECIFIER"' \
    || { echo "  the exception region no longer holds the triplication cmp"; return 1; }
  return 0
}

test_hygiene_03_planted_violations_are_named() {
  root="$(fixture_copy_root)"
  t="$root/refpin_test.sh"
  plant "$t" 'CODER_P="$HARNESS_REPO/agents/prompts/coder.prompt"'
  plant "$t" 'grep -qF "exact prose phrase" "$CODER_P"'
  plant "$t" 'require "$HARNESS_REPO/AGENTS.md" "some prose sentence"'
  plant "$t" 'sed -n "1,2p" "$CODER_P" > "$d/exp"'
  plant "$t" 'cmp -s "$CODER_P" "$d/exp"'
  out=$(scan_prose_pin "$root")
  echo "$out" | grep -q "^$t:[0-9]*: prose-pin: reads a prompt/doc source with an assertion$" || {
    echo "  planted grep/require prose pins not named"; return 1; }
  echo "$out" | grep -q "^$t:[0-9]*: prose-pin: byte-compares prose content" || {
    echo "  planted byte-compare against embedded text not named"; return 1; }
  # a comparison of two live-read files pins no phrase
  p="$root/libdirinstall_test.sh"
  plant "$p" 'C="$HARNESS_REPO/AGENTS.md"'
  plant "$p" 'D="$HARNESS_REPO/CLAUDE.md"'
  plant "$p" 'cmp -s "$C" "$D" || true'
  plant "$p" 'diff "$C" "$D" > /dev/null || true'
  scan_prose_pin "$root" | grep "^$p:" | grep -q . && {
    echo "  live-vs-live file comparisons were flagged"; return 1; }
  # quote-split self-guard needles never self-match
  q="$root/installsh-posixsh_test.sh"
  plant "$q" "refuse \"\$X_NONCOMMENTS\" 'agents/prom''pts'"
  plant "$q" "refuse \"\$X_NONCOMMENTS\" 'CLA''UDE.md'"
  scan_prose_pin "$root" | grep "^$q:" | grep -q . && {
    echo "  a single-quoted self-guard needle was flagged in $q"; return 1; }
  # comment lines are never violations
  plant "$t" '# the old suite grepped AGENTS.md prose; deleted per law 4'
  # the exception travels ONLY with roles_test.sh
  r="$root/roles_region_copy_test.sh"
  printf '%s\n' \
    'CODER_PROMPT="$HARNESS_REPO/agents/prompts/coder.prompt"' \
    'SPECIFIER_PROMPT="$HARNESS_REPO/agents/prompts/specifier.prompt"' \
    'extract_section "$CODER_PROMPT" "Working Root" "$WR_CODER2"' \
    'extract_section "$SPECIFIER_PROMPT" "Working Root" "$WR_SPEC2"' \
    'cmp -s "$WR_CODER2" "$WR_SPEC2"' \
    > "$r"
  scan_prose_pin "$root" | grep -q "^$r:[0-9]*: prose-pin:" || {
    echo "  prose reads were exempted without the roles_test.sh carrier"; return 1; }
  return 0
}

# ---- run everything -------------------------------------------------------------

run_test "hygiene-01: no suite executes another suite or asserts another existing suite's source content or output (the real tests/ scans clean, the discovery contract holds, self-reads and nonexistent fixture names carve out)" test_hygiene_01_no_suite_reads_another_suite
run_test "hygiene-01: planted suite execution, planted suite source-grep, and a planted *_test.sh glob are each named with file and line (no vacuous pass)" test_hygiene_01_planted_violations_are_named
run_test "hygiene-02: no suite compares the real tree against git HEAD and none byte-pins its own file against a HEAD copy; git in throwaway temp-space fixture repos stays legal" test_hygiene_02_no_suite_compares_the_real_tree_to_head
run_test "hygiene-02: planted merge-base, show HEAD:, diff --quiet HEAD, show \$base:, and own-file HEAD byte-pin are each named with file and line (no vacuous pass)" test_hygiene_02_planted_violations_are_named
run_test "hygiene-03: no suite pins an exact prose phrase of a prompt or doc; the Working-Root triplication check in roles_test.sh is the sole exception and the only marker carrier" test_hygiene_03_no_suite_pins_prompt_or_doc_prose
run_test "hygiene-03: planted prose greps, derived-extract pins, and prose-vs-embedded byte-compares are named, while live-vs-live comparisons, quoted needles, and comment lines are not (no vacuous pass)" test_hygiene_03_planted_violations_are_named

finish_suite
