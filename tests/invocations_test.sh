#!/usr/bin/env bash
# Unit tests for the orchestrator invocation contract, covering every
# scenario in spdd/changes/deembed-orchestration-scripts/02-invocations.feature
# (invocations-01..07). The change: agents/prompts/orchestrator.prompt's three
# "# antz-include:" script fences become one-line invocations of the installed
# libdir files (sub-spec 01) at the placeholder token "__ANTZ_SCRIPTS_DIR__",
# which install.sh substitutes with the concrete resolved libdir at render
# time (resolved once by sub-spec 01's resolve_libdir). inject_includes(), its
# orchestrator-keyed call site, and the antz-skills.sh under-fence-indent
# carve-out are retired wholesale. The routing law, the four tables, the
# session guards, and every machine line stay byte-identical; the rendered
# orchestrator body becomes a stable prefix (scenario 07's KV-cache priority).
#
# Boundary note (sub-spec 05, testsuite): the suites pinning the OLD embedded
# shape (antz-flow, orchestrator-status-probe, orchestrator-skills-block,
# orchestrator-sessionguards, renderinject, roles, orchestrator-render-sync)
# re-scope there, not here. This suite adds the render-side no-survivor and
# structural pins this sub-spec's scenarios call for (invocations-02's
# "re-appear below in render-side form"), superseding the retired mechanism's
# pins without touching those files.
#
# Self-contained bash test harness (no external framework/dependency -- this
# repo has no package manager or build system), same pattern as
# tests/libdirinstall_test.sh. Run directly:
#   ./tests/invocations_test.sh
#
# Each reported test name embeds its scenario id (invocations-01..07) from
# the feature file above, so a failure maps straight back to the scenario it
# covers. Every filesystem-touching run uses an isolated HOME (a fresh temp
# dir per test, XDG_CONFIG_HOME removed or set explicitly) -- never the real
# ~/.claude or ~/.config/opencode.

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INSTALL_SH="$SCRIPT_DIR/install.sh"

CURRENT_VERSION=$(tr -d ' \t\r\n' < "$SCRIPT_DIR/VERSION")

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

stage_checkout() {
  # $1 = checkout dir: a complete staged checkout (install.sh, agents/,
  # scripts/orchestration/, VERSION, CHANGELOG.md) -- libdirinstall_test.sh's
  # fixture idiom.
  dir="$1"
  mkdir -p "$dir"
  cp "$INSTALL_SH" "$dir/install.sh"
  cp "$SCRIPT_DIR/CHANGELOG.md" "$dir/CHANGELOG.md"
  cp -R "$SCRIPT_DIR/agents" "$dir/agents"
  cp -R "$SCRIPT_DIR/scripts" "$dir/scripts"
  cp "$SCRIPT_DIR/VERSION" "$dir/VERSION"
}

install_at() {
  # $1 = HOME, $2 = install.sh path, rest = flags. Always a fully explicit
  # environment (session XDG leakage removed), so a test never writes into
  # the real ~/.config.
  home="$1"; sh_path="$2"; shift 2
  env -u XDG_CONFIG_HOME HOME="$home" sh "$sh_path" "$@"
}

install_xdg() {
  # $1 = HOME, $2 = XDG_CONFIG_HOME value to export, $3 = install.sh path, rest = flags.
  home="$1"; xdg="$2"; sh_path="$3"; shift 3
  env XDG_CONFIG_HOME="$xdg" HOME="$home" sh "$sh_path" "$@"
}

marker_line() {
  printf '# antz:generated version=%s -- do not edit by hand; regenerate with install.sh' "$1"
}

strip_frontmatter() {
  # Renders the given file's body (the two '---' fences, the blank separator
  # line stripped), same helper as tests/renderinject_test.sh.
  awk '
    /^---$/ { if (n < 2) { n++; next } }
    n < 2 { next }
    n == 2 && !seen && $0 == "" { seen = 1; next }
    { print }
  ' "$1"
}

assert_body_has_no_script_lines() {
  # $1 = rendered body file: no fenced or unfenced line from any
  # scripts/orchestration/ file appears in it. Trimmed-exact comparison; short
  # lines (< 24 chars after trim, e.g. "}" or ";;") are excluded so incidental
  # prose punctuation can't collide -- every distinctive script line is long.
  f="$1"
  trims=$(mktemp)
  sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$f" > "$trims"
  for s in antz-flow antz-probe; do
    src="$SCRIPT_DIR/scripts/orchestration/$s.sh"
    while IFS= read -r line || [ -n "$line" ]; do
        line=${line#"${line%%[![:space:]]*}"}   # ltrim
        line=${line%"${line##*[![:space:]]}"}   # rtrim
        [ "${#line}" -ge 24 ] || continue
        if grep -qxF "$line" "$trims"; then
          echo "  body contains a line from scripts/orchestration/$s.sh: $line"
          rm -f "$trims"; return 1
        fi
      done < "$src"
  done
  rm -f "$trims"
  return 0
}

# One staged render shared by the re-keyed prompt-shape tests below.
# install.sh's render is deterministic, so re-rendering per test would pay
# the same cost for identical bytes; the render-side bodies are what the
# source prompt's invocation and structure facts are observed through (the
# exact-substitution render mechanism itself is pinned against install.sh in
# invocations-02).
INV_D=$(new_tmp_dir)
INV_CO="$INV_D/checkout"
stage_checkout "$INV_CO"
INV_HOME="$INV_D/home"
mkdir -p "$INV_HOME"
install_at "$INV_HOME" "$INV_CO/install.sh" --all > "$INV_D/install.log" 2>&1 \
  || echo "note: the shared staged install exited non-zero; invocations-01 and -06 will fail" >&2
INV_LIB="$INV_HOME/.config/antz/scripts"

# ---- invocations-01 ----------------------------------------------------------
# The invocation forms, observed on the rendered bodies for both clients:
# discover/ensure/state/release run as one-line path invocations of the
# resolved libdir (state still carrying the probe's path), no "save ... to a
# temp file" instruction survives anywhere in the body, and no include marker
# or unresolved placeholder token survives.

invocations_01_invocation_forms() {
  ok=0
  for client in .claude .config/opencode; do
    f="$INV_HOME/$client/agents/antz-orchestrator.md"
    [ -f "$f" ] || { echo "  missing rendered file: $f"; ok=1; continue; }
    for form in \
      "sh \"$INV_LIB/antz-flow.sh\" discover" \
      "sh \"$INV_LIB/antz-flow.sh\" ensure <slug>" \
      "sh \"$INV_LIB/antz-flow.sh\" state <slug> \"$INV_LIB/antz-probe.sh\"" \
      "sh \"$INV_LIB/antz-flow.sh\" release <slug>"
    do
      grep -qF "$form" "$f" || {
        echo "  ($client) body missing the one-line invocation form: $form"; ok=1; }
    done
    # every prior "save the script below to a temp file" instruction is gone
    if grep -qiE 'save .*(script|probe|snippet)[^.]*temp file|tempfile' "$f"; then
      echo "  ($client) a temp-file instruction survives in the rendered body:"
      grep -niE 'save .*(script|probe|snippet)[^.]*temp file|tempfile' "$f" | sed 's/^/    /'; ok=1
    fi
    # no include marker and no unresolved placeholder survive the render
    grep -qF 'antz-include' "$f" && {
      echo "  ($client) an '# antz-include:' marker survives in the rendered body"; ok=1; }
    grep -qF '__ANTZ_SCRIPTS_DIR__' "$f" && {
      echo "  ($client) an unresolved __ANTZ_SCRIPTS_DIR__ token survives in the rendered body"; ok=1; }
  done
  return $ok
}

# ---- invocations-02 ----------------------------------------------------------
# install.sh's executable code: inject_includes() and its orchestrator-keyed
# call site are gone; the antz-skills.sh "s/^     done$/  done/" carve-out is
# gone with them; the include-marker mechanism is retired wholesale (the
# render-side no-survivor and fail-loud clauses are pinned in invocations-03/07).

invocations_02_mechanism_retired() {
  ok=0
  grep -qF 'inject_includes' "$INSTALL_SH" && {
    echo "  inject_includes() or its call site still exists in install.sh"; ok=1; }
  grep -qF 'antz-include' "$INSTALL_SH" && {
    echo "  the include-marker mechanism is still named anywhere in install.sh"; ok=1; }
  grep -qF 's/^     done$/  done/' "$INSTALL_SH" && {
    echo "  the antz-skills.sh under-fence-indent carve-out survives in install.sh"; ok=1; }
  grep -qF 'orchestrator-skills.sh fence' "$INSTALL_SH" && {
    echo "  a stale carve-out comment still references the fence indent exception"; ok=1; }
  # render time substitutes the concrete resolved libdir for the placeholder,
  # using the value resolved ONCE by resolve_libdir (sub-spec 01's variable)
  grep -qF 's|__ANTZ_SCRIPTS_DIR__|$ANTZ_SCRIPTS_DIR|g' "$INSTALL_SH" || {
    echo "  install.sh does not substitute __ANTZ_SCRIPTS_DIR__ with the once-resolved \$ANTZ_SCRIPTS_DIR at render time"; ok=1; }
  grep -qF 'if [ "$agent" = "orchestrator" ]' "$INSTALL_SH" && {
    echo "  the orchestrator-keyed render branch of the retired call site survives"; ok=1; }
  return $ok
}

# ---- invocations-03 ----------------------------------------------------------
# The rendered bodies (isolated HOME, both clients): zero script content,
# zero markers, zero unresolved placeholders; every invocation line carries
# the concrete resolved libdir path; the body is exactly the source prompt
# with the token replaced; frontmatter shapes unchanged with only the marker
# version moving. A run with XDG_CONFIG_HOME set renders the XDG path.

invocations_03_render() {
  # Reuses the suite's single staged render (install.sh's render is
  # deterministic; the shared staging is defined next to the helpers).
  ok=0
  home="$INV_HOME"
  lib="$INV_LIB"

  for client in .claude .config/opencode; do
    f="$home/$client/agents/antz-orchestrator.md"
    [ -f "$f" ] || { echo "  missing rendered file: $f"; ok=1; continue; }
    # zero fenced or unfenced lines from any scripts/orchestration/ file
    assert_body_has_no_script_lines "$f" || { echo "  ($client)"; ok=1; }
    # every invocation line carries the concrete resolved libdir path
    for form in \
      "sh \"$lib/antz-flow.sh\" discover" \
      "sh \"$lib/antz-flow.sh\" ensure <slug>" \
      "sh \"$lib/antz-flow.sh\" state <slug> \"$lib/antz-probe.sh\"" \
      "sh \"$lib/antz-flow.sh\" release <slug>"
    do
      grep -qF "$form" "$f" || {
        echo "  $client body missing the concrete-path invocation: $form"; ok=1; }
    done
  done

  # no marker and no placeholder survives in ANY rendered or installed file
  if find "$home" -type f -exec grep -l -e '# antz-include:' -e '__ANTZ_SCRIPTS_DIR__' {} + 2>/dev/null | grep .; then
    echo "  a marker or placeholder survived an installed file"; ok=1
  fi

  # frontmatter shapes survive with only the marker version changing
  c="$home/.claude/agents/antz-orchestrator.md"
  grep -qxF 'tools: Read, Grep, Glob, Bash, Agent' "$c" || {
    echo "  Claude frontmatter lost the orchestrateonly tools grant"; ok=1; }
  grep -qxF "$(marker_line "$CURRENT_VERSION")" "$c" || {
    echo "  Claude frontmatter marker is not the current-version line"; ok=1; }
  o="$home/.config/opencode/agents/antz-orchestrator.md"
  grep -qxF 'mode: primary' "$o" || { echo "  OpenCode frontmatter lost mode: primary"; ok=1; }
  grep -qxF '  edit: deny' "$o" || { echo "  OpenCode frontmatter lost edit: deny"; ok=1; }
  grep -qxF '  task: ' "$o" || grep -qxF '  task:' "$o" || {
    echo "  OpenCode frontmatter lost the bare task: key"; ok=1; }
  grep -qxF '    "*": deny' "$o" || { echo "  OpenCode task allowlist lost the deny-all glob"; ok=1; }
  for role in specifier coder verifier; do
    grep -qxF "    antz-$role: allow" "$o" || {
      echo "  OpenCode task allowlist lost antz-$role: allow"; ok=1; }
  done
  return $ok
}

invocations_03_xdg_concrete_path() {
  # Its own HOME+XDG render is required (the env differs), but the staged
  # checkout is read-only input: reuse the suite's shared one.
  d=$(new_tmp_dir); ok=0
  co="$INV_CO"
  home="$d/home"; xdg="$d/xdgbase"; mkdir -p "$home" "$xdg"
  install_xdg "$home" "$xdg" "$co/install.sh" --all > "$d/install.log" 2>&1 \
    || { echo "  install with XDG_CONFIG_HOME set exited non-zero"; return 1; }
  lib="$xdg/antz/scripts"
  for client in .claude .config/opencode; do
    f="$home/$client/agents/antz-orchestrator.md"
    grep -qF "sh \"$lib/antz-flow.sh\" discover" "$f" || {
      echo "  $client body does not carry the XDG-resolved concrete path"; ok=1; }
    grep -qF "$home/.config/antz/scripts" "$f" && {
      echo "  $client body fell back to the HOME path despite XDG_CONFIG_HOME"; ok=1; }
    # no trailing slash before the script name (the concrete path ends bare)
    grep -qF "$lib//antz" "$f" && {
      echo "  the substituted path carries a trailing slash ($lib//...)"; ok=1; }
  done
  return $ok
}

# ---- invocations-04 ----------------------------------------------------------
# The runtime contract: invoke by path with zero re-materialization (no
# temp-file instruction anywhere in the rendered body; every installed-file
# run is a one-line invocation), the "Never writes anything itself" bullet
# survives, and the scripts' machine-line vocabulary is byte-identical: each
# pinned literal is present in the untouched scripts/orchestration/ files.

invocations_04_no_rematerialization() {
  # Reuses the suite's single staged render (install.sh's render is
  # deterministic; the shared staging is defined next to the helpers).
  ok=0
  home="$INV_HOME"
  lib="$INV_LIB"
  for client in .claude .config/opencode; do
    f="$home/$client/agents/antz-orchestrator.md"
    # the body instructs no temp file at all, in any form
    if grep -qiE 'temp file|tempfile' "$f"; then
      echo "  rendered $client body still instructs a temp file:"
      grep -niE 'temp file|tempfile' "$f" | sed 's/^/    /'; ok=1
    fi
    # every line naming an installed script is a one-line sh "<path>" call
    lib="$home/.config/antz/scripts"
    if grep -F "$lib/antz-" "$f" | grep -vF 'sh "' | grep .; then
      echo "  ($client) a reference to an installed script is not an sh \"<path>\" invocation"; ok=1
    fi
    # the Owns bullet that the de-embed makes literal
    grep -qF 'Never writes anything itself' "$f" || {
      echo "  the 'Never writes anything itself' Owns bullet is gone"; ok=1; }
  done
  return $ok
}

invocations_04_machine_line_vocabulary() {
  ok=0
  so="$SCRIPT_DIR/scripts/orchestration"
  # every pinned literal, in the vocabulary of the sub-spec scenario
  for lit in \
    'candidate=branch slug=%s' 'candidate=on-disk slug=%s' \
    'state=created' 'state=reused' 'dirty=yes' \
    'state=no_commits' 'state=checkout_refused' 'state=no_branch' \
    'state=no_git' 'state=no_repo' 'state=tree_dirty' 'state=bad_slug' \
    'branch=missing' 'change_dir=missing' 'open_questions=' 'rejected_count=' \
    'receipt=missing covered=0/' 'complete=no class=' 'gate=refused reason=' \
    'released branch=antz/'
  do
    grep -rqF "$lit" "$so" || { echo "  machine-line literal lost: $lit"; ok=1; }
  done
  grep -qF 'subspec=%s ids=%s %s' "$so/antz-probe.sh" || {
    echo "  the probe's subspec= line format is lost"; ok=1; }
  # the flow script's header usage comment keeps the historical "sh <tempfile>"
  # wording (presence in the product source is the fact; comparing the tree
  # against a git HEAD copy was deleted by change optimize-test-suite,
  # sub-spec 09's law 3)
  grep -qF 'sh <tempfile>' "$so/antz-flow.sh" || {
    echo "  the flow script's header lost its historical sh <tempfile> usage wording"; ok=1; }
  return $ok
}

# ---- invocations-05 ----------------------------------------------------------
# The routing surface keeps its pinned meaning: the four tables, step 3's
# classification rules, step 4's rejection routing, the session guards, the
# Report Format, the byte-pinned delegation header, and the human follow-up
# print all survive the render; the flow script still has exactly the four
# subcommands.

invocations_05_routing_surface() {
  # Reuses the suite's single staged render (install.sh's render is
  # deterministic; the shared staging is defined next to the helpers).
  ok=0
  home="$INV_HOME"
  lib="$INV_LIB"
  for client in .claude .config/opencode; do
    f="$home/$client/agents/antz-orchestrator.md"
    # the four table headers, byte-exact
    for hdr in \
      '| discover output | Meaning / action |' \
      '| Output | Meaning |' \
      '| `rejected_count` | Action |' \
      '| release output | Meaning / action |'
    do
      grep -qF "$hdr" "$f" || { echo "  ($client) table header lost: $hdr"; ok=1; }
    done
    # step 3's classification rules and step 4's rejection routing, byte-pinned
    for pin in \
      'class=blocked' 'checked first regardless of coverage' \
      'sequentially, never in parallel' \
      'The bounded retry already happened and was rejected again' \
      'never invoke `coder` or `verifier` again for this change' \
      'Relay each attributable blocker'
    do
      grep -qF "$pin" "$f" || { echo "  ($client) routing pin lost: $pin"; ok=1; }
    done
    # session guards: dedup with exactly two exceptions, latch
    for pin in '**Dedup.**' '**Latch.**' 'exactly two exceptions' 'no delegation ledger'
    do
      grep -qF "$pin" "$f" || { echo "  ($client) session-guard pin lost: $pin"; ok=1; }
    done
    # Report Format and the closing-block grammar
    for pin in '## Report Format' 'status=<value>' 'waiting-user' 'delegated-verifier'
    do
      grep -qF "$pin" "$f" || { echo "  ($client) Report Format pin lost: $pin"; ok=1; }
    done
    # the byte-pinned delegation header and the human follow-up print
    grep -qF 'Working root: <repo root absolute path>' "$f" || {
      echo "  ($client) delegation header lost"; ok=1; }
    grep -qF 'Change slug: <slug>' "$f" || { echo "  ($client) delegation slug line lost"; ok=1; }
    grep -qF 'git switch <integration> && git merge antz/<slug>' "$f" || {
      echo "  ($client) human follow-up print lost"; ok=1; }
  done
  # the flow script still has exactly the four subcommands (column-0 case arms)
  n=$(grep -cE '^(discover|ensure|state|release)\)' "$SCRIPT_DIR/scripts/orchestration/antz-flow.sh")
  [ "$n" -eq 4 ] || { echo "  expected exactly 4 flow subcommand arms, got: $n"; ok=1; }
  return $ok
}

# ---- invocations-06 ----------------------------------------------------------
# Structural pins of the de-embedded orchestrator body, observed on the
# rendered bodies for both clients: fences drop from seven blocks (14 lines)
# to four (8), no ```sh fence remains, the four tables and the steps-ending
# at 6 survive, and no new fenced block or include marker was added.

invocations_06_structure() {
  ok=0
  for client in .claude .config/opencode; do
    f="$INV_HOME/$client/agents/antz-orchestrator.md"
    [ -f "$f" ] || { echo "  missing rendered file: $f"; ok=1; continue; }
    fl=$(grep -cE '^[[:space:]]*```' "$f")
    [ "$fl" -eq 4 ] || { echo "  ($client) expected 4 fence lines, got: $fl"; ok=1; }
    sh=$(grep -cE '^[[:space:]]*```sh' "$f")
    [ "$sh" -eq 0 ] || { echo "  ($client) expected no \`\`\`sh fence, got: $sh"; ok=1; }
    blocks=$((fl / 2))
    [ "$blocks" -eq 2 ] || { echo "  ($client) expected 2 fenced blocks, got: $blocks"; ok=1; }
    # the two surviving blocks are the delegation header and the human
    # follow-up print
    grep -qF 'Working root: <repo root absolute path>' "$f" || { echo "  ($client) delegation-header block lost"; ok=1; }
    grep -qF 'git branch -d antz/<slug>' "$f" || { echo "  ($client) follow-up print block lost"; ok=1; }
    # the four tables survive, steps still end at 6
    for hdr in \
      '| discover output | Meaning / action |' \
      '| Output | Meaning |' \
      '| `rejected_count` | Action |' \
      '| release output | Meaning / action |'
    do
      grep -qF "$hdr" "$f" || { echo "  ($client) table header lost: $hdr"; ok=1; }
    done
    grep -qE '^6\. On a fresh rejection' "$f" || { echo "  ($client) step 6 is gone"; ok=1; }
    grep -qE '^7\. ' "$f" && { echo "  ($client) a step 7 appeared"; ok=1; }
    # the three former script-fence positions are gone with their markers
    grep -qF 'antz-include' "$f" && { echo "  ($client) an include marker survives in the body"; ok=1; }
  done
  return $ok
}

# ---- invocations-07 ----------------------------------------------------------
# Stable prefix: rendering both clients twice with an unchanged VERSION into
# fresh isolated HOMEs produces byte-identical trees (deterministic,
# idempotent); the rendered body carries no per-session/per-run data (no
# temp paths, no timestamps, no session state), the frontmatter marker line
# is its only version-bearing string, and no script line appears in any
# rendered agent body.

invocations_07_stable_prefix() {
  d=$(new_tmp_dir); ok=0
  co="$d/checkout"; stage_checkout "$co"
  # "renders twice into fresh isolated HOMEs": the same HOME VALUE, the tree
  # freshly empty before each render (the concrete resolved libdir embeds the
  # HOME path, so determinism is only meaningful for a fixed HOME -- every
  # session of one installed version re-renders the very same bytes).
  home="$d/home"

  tree_snapshot() {
    # $1 = HOME -> the tree's sorted path+content-checksum list
    find "$1" -type f -exec cksum {} + | sed "s|$1/||" | sort
  }

  mkdir -p "$home"
  install_at "$home" "$co/install.sh" --all > "$d/install1.log" 2>&1 \
    || { echo "  first install exited non-zero"; return 1; }
  tree_snapshot "$home" > "$d/snap1"
  rm -rf "$home"; mkdir -p "$home"
  install_at "$home" "$co/install.sh" --all > "$d/install2.log" 2>&1 \
    || { echo "  second (fresh-HOME) install exited non-zero"; return 1; }
  tree_snapshot "$home" > "$d/snap2"
  cmp -s "$d/snap1" "$d/snap2" || {
    echo "  the two fresh renders are not byte-identical (render is not deterministic):"
    diff "$d/snap1" "$d/snap2" | head -8 | sed 's/^/    /'; ok=1; }

  # idempotence: a re-render over the existing tree changes nothing and grows
  # no backups (every destination is already antz-managed)
  install_at "$home" "$co/install.sh" --all > "$d/reinstall.log" 2>&1 \
    || { echo "  re-install exited non-zero"; return 1; }
  tree_snapshot "$home" > "$d/snap3"
  cmp -s "$d/snap2" "$d/snap3" || {
    echo "  re-installing at the same HOME changed the tree (expected byte-identical idempotence)"; ok=1; }
  find "$home" -name '*.bak.*' | grep . && { echo "  a backup appeared on a managed re-install"; ok=1; }

  # no per-session or per-run data in the rendered orchestrator bodies: no
  # timestamps anywhere, no temp paths, and VERSION appears ONLY on the
  # frontmatter marker line
  for client in .claude .config/opencode; do
    f="$home/$client/agents/antz-orchestrator.md"
    grep -qE '[0-9]{14}|[0-9]{4}-[0-9]{2}-[0-9]{2}' "$f" && {
      echo "  ($client) body carries a timestamp pattern"; ok=1; }
    if grep -nF "$CURRENT_VERSION" "$f" | grep -v '# antz:generated version=' | grep .; then
      echo "  ($client) the VERSION string appears outside the frontmatter marker line"; ok=1
    fi
  done

  # no line of any scripts/orchestration/ file appears in ANY rendered agent body
  for agent in specifier coder verifier orchestrator; do
    for client in .claude .config/opencode; do
      assert_body_has_no_script_lines "$home/$client/agents/antz-$agent.md" || {
        echo "  ($client antz-$agent)"; ok=1; }
    done
  done
  return $ok
}

invocations_07_cache_effect_recorded() {
  ok=0
  # the durable record: the change was approved and archived, so the clause
  # reads the immutable archived record (spdd/archive/), not the in-flight
  # path that moves out from under it
  readme="$SCRIPT_DIR/spdd/archive/deembed-orchestration-scripts/README.md"
  # the expected cache effect is on record there: the KV-cache priority, the
  # ~335 embedded script lines leaving, and the per-session re-materialization
  # dropping out
  grep -qF 'KV-cache' "$readme" || { echo "  README lost the KV-cache priority"; ok=1; }
  grep -qF '~335' "$readme" || { echo "  README does not record the ~335 embedded lines"; ok=1; }
  grep -qE 'per-session re-materialization|re-emits the whole script text' "$readme" || {
    echo "  README does not record the per-session re-materialization that drops to zero"; ok=1; }
  return $ok
}

# ---- invocationsfix-01 (change optimize-test-suite, sub-spec 06) ----------------
# The record clause of invocations-07 re-keys from the in-flight change README
# (a path that only exists while a change is in flight, and this one is since
# archived) to the immutable archived record. Re-key, not deletion: all three
# recorded cache-effect facts stay required; the clause is green at the current
# disk state; and the read is a durable-record read -- no real-tree-vs-git-HEAD
# comparison, no byte-pin vs git HEAD, no exact-phrase prose pin of prompts or
# product docs. (The clause's deferred CHANGELOG half is deleted outright with
# its SKIP stub by invocationsfix-02 below.)

invocationsfix_01_record_clause_reads_archive() {
  d=$(new_tmp_dir); ok=0
  # The clause's own body: its "name() {" line through the first column-0 "}".
  body="$d/record_clause"
  awk '
    index($0, "invocations_07_cache_effect_recorded() {") == 1 { flag = 1 }
    flag { print }
    flag && $0 == "}" { exit }
  ' "$0" > "$body"
  [ -s "$body" ] || { echo "  could not extract the record clause's body from this suite"; return 1; }

  # Re-keyed to the durable record: the clause reads the archived change README...
  grep -qF 'spdd/archive/deembed-orchestration-scripts/README.md' "$body" || {
    echo "  the record clause does not read spdd/archive/deembed-orchestration-scripts/README.md"; ok=1; }
  # ...and no longer the in-flight change path that moved out from under it.
  if grep -qF 'spdd/chan''ges/deembed-orchestration-scripts' "$body"; then
    echo "  the record clause still reads the in-flight change path"; ok=1; fi

  # Re-key, not deletion: the three recorded facts each stay an independent
  # gated read of the record (three fail-gated greps, three fact literals).
  n=$(grep -cF '"$readme" || {' "$body")
  [ "$n" -eq 3 ] || { echo "  expected 3 gated fact-reads of the record, got: $n"; ok=1; }
  for fact in 'KV-cache' '~335' 'per-session re-materialization'; do
    grep -qF "$fact" "$body" || {
      echo "  the clause no longer requires the recorded fact: $fact"; ok=1; }
  done

  # Durable-record read only: the clause body performs no git comparison of
  # any kind (no HEAD access, no byte-pin, no merge-base), and touches no
  # prompt or product-doc surface -- its only readable file is the record.
  for forbidden in 'git ' 'HE''AD' 'cm''p' 'diff' 'merge' 'agents/' 'AGE''NTS' 'CLA''UDE' 'docs/' 'install.sh'; do
    if grep -qF "$forbidden" "$body"; then
      echo "  the re-keyed clause introduces a forbidden form: $forbidden"; ok=1; fi
  done

  # Green at the current disk state: actually run the clause -- the read that
  # was RED against the in-flight path must now pass against the archive.
  if ! invocations_07_cache_effect_recorded > "$d/clause.log" 2>&1; then
    echo "  the record clause fails at the current disk state:"
    sed 's/^/    /' "$d/clause.log"; ok=1; fi
  return $ok
}

# ---- invocationsfix-02 (change optimize-test-suite, sub-spec 06) ----------------
# The deferred CHANGELOG clause of invocations-07 is deleted with its SKIP stub
# (history/evolution calibration is deleted, not relocated). invocations-07
# stays carried by exactly two registrations -- the stable-prefix check and the
# re-keyed record clause -- both keeping the id at the start of their reported
# names. The suite's exit 0 is this run itself: the area-wide "is it green"
# question belongs to the runner (permanent law 1), never to a suite
# re-executing itself.

invocationsfix_02_changelog_clause_deleted() {
  d=$(new_tmp_dir); ok=0
  # Non-comment view of this suite's own source (a suite may read its own
  # file; comments are documentation, not registrations).
  code="$d/code"
  grep -vE '^[[:space:]]*#' "$0" > "$code"

  # The SKIP stub is gone: no skip_test registration carries invocations-07,
  # and the stub's stale deferral-reason text appears in no non-comment line.
  n=$(grep -cE '^[[:space:]]*skip_test[[:space:]]+"invocations-0''7' "$code")
  [ "$n" -eq 0 ] || { echo "  $n skip_test registration(s) still carry invocations-07"; ok=1; }
  for gone in 'CHANGELOG cl''ause' 'versio''nbump' 'deferre''d:'; do
    if grep -qF "$gone" "$code"; then
      echo "  the stub's stale text survives in a non-comment line: $gone"; ok=1; fi
  done

  # Neither retained invocations-07 registration asserts CHANGELOG content:
  # the area's only version assertion stays versioncurrent-02's own suite.
  for fn in invocations_07_stable_prefix invocations_07_cache_effect_recorded; do
    fb="$d/$fn"
    awk -v fn="$fn" '
      index($0, fn "() {") == 1 { flag = 1 }
      flag { print }
      flag && $0 == "}" { exit }
    ' "$0" > "$fb"
    [ -s "$fb" ] || { echo "  could not extract $fn's body"; ok=1; continue; }
    if grep -qF 'CHANGELO''G' "$fb"; then
      echo "  $fn asserts CHANGELOG content"; ok=1; fi
  done

  # Exactly two registrations carry invocations-07, both run_test calls with
  # the id at the start of the reported name (the anchored count of name-start
  # matches equals the loose count of quoted-id occurrences).
  anchored=$(grep -cE '^run_test "invocations-0''7: ' "$code")
  quoted=$(grep -c '"invocations-0''7' "$code")
  [ "$anchored" -eq 2 ] && [ "$quoted" -eq 2 ] || {
    echo "  expected exactly 2 id-headed invocations-07 registrations, found anchored=$anchored quoted=$quoted"; ok=1; }
  return $ok
}

# ---- run ---------------------------------------------------------------------

run_test "invocations-01: the rendered bodies run discover/ensure/state/release as one-line path invocations of the resolved libdir (state still carrying the probe's path), with no temp-file instruction and no include marker or unresolved placeholder surviving" invocations_01_invocation_forms
run_test "invocations-02: inject_includes(), its orchestrator-keyed call site and the antz-skills.sh done-carve-out are gone from install.sh, which substitutes the once-resolved libdir for the placeholder at render time" invocations_02_mechanism_retired
run_test "invocations-03: both rendered orchestrator bodies are exactly the source prompt with the concrete resolved path substituted -- zero script lines, zero markers, zero placeholders anywhere installed -- with the Claude and OpenCode frontmatter shapes intact" invocations_03_render
run_test "invocations-03: with XDG_CONFIG_HOME set the invocation lines carry that XDG-resolved concrete path (never the HOME fallback, never a trailing slash)" invocations_03_xdg_concrete_path
run_test "invocations-04: the rendered body instructs zero re-materialization (no temp file anywhere; every installed-file run is a one-line sh call), the 'Never writes anything itself' Owns bullet holds, and every script-machine-line invocation is by path" invocations_04_no_rematerialization
run_test "invocations-04: the scripts' machine-line vocabulary survives -- every pinned literal present in the scripts/orchestration/ product files, historical sh <tempfile> header wording included" invocations_04_machine_line_vocabulary
run_test "invocations-05: the four tables, step 3 classification, step 4 rejection routing, the session guards, the Report Format, the byte-pinned delegation header and the human follow-up print survive both renders; the flow script keeps exactly its four subcommands" invocations_05_routing_surface
run_test "invocations-06: structural pins of the de-embedded shape, observed on the rendered bodies -- 2 fenced blocks (4 fence lines, no \`\`\`sh), the four tables, steps ending at 6, no new fenced block" invocations_06_structure
run_test "invocations-07: renders are deterministic and idempotent (two fresh-HOME installs and a same-HOME re-install give byte-identical trees), the body carries no per-session data with the frontmatter marker as its only version-bearing string, and no script line appears in any rendered agent body" invocations_07_stable_prefix
run_test "invocations-07: the expected cache effect (KV-cache priority, ~335 embedded lines gone, per-session re-materialization dropping to zero) is recorded in the change README" invocations_07_cache_effect_recorded
run_test "invocationsfix-01: invocations-07's record clause reads the immutable archived change README (spdd/archive/deembed-orchestration-scripts/README.md), still requires the three recorded cache-effect facts as gated reads, runs green at the current disk state, and introduces no git comparison, byte-pin vs HEAD, or prose pin of prompts/docs" invocationsfix_01_record_clause_reads_archive
run_test "invocationsfix-02: the CHANGELOG-clause SKIP stub of invocations-07 is deleted with its stale deferral text, neither retained invocations-07 registration asserts CHANGELOG content, and exactly two id-headed registrations carry the invocations-07 id" invocationsfix_02_changelog_clause_deleted

echo
echo "pass=$pass_count fail=$fail_count skip=$skip_count"
[ "$fail_count" -eq 0 ]
