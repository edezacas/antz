#!/usr/bin/env bash
# Unit tests for the orchestrator invocation contract, covering every
# scenario in spdd/changes/deembed-orchestration-scripts/02-invocations.feature
# (invocations-01..08). The change: agents/prompts/orchestrator.prompt's three
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
# Each reported test name embeds its scenario id (invocations-01..08) from
# the feature file above, so a failure maps straight back to the scenario it
# covers. Every filesystem-touching run uses an isolated HOME (a fresh temp
# dir per test, XDG_CONFIG_HOME removed or set explicitly) -- never the real
# ~/.claude or ~/.config/opencode.

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INSTALL_SH="$SCRIPT_DIR/install.sh"
PROMPT="$SCRIPT_DIR/agents/prompts/orchestrator.prompt"

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

# The body the invocation contract REQUIRES: the working tree's
# orchestrator.prompt with each "__ANTZ_SCRIPTS_DIR__" token replaced by the
# concrete resolved libdir -- and nothing else (no injection, no re-materialized
# scripts). This is the oracle for "single source of the orchestrator body".
reconstruct_expected_body() {
  # $1 = out path, $2 = libdir
  sed "s|__ANTZ_SCRIPTS_DIR__|$2|g" "$PROMPT" > "$1"
}

assert_body_has_no_script_lines() {
  # $1 = rendered body file: no fenced or unfenced line from any
  # scripts/orchestration/ file appears in it. Trimmed-exact comparison; short
  # lines (< 24 chars after trim, e.g. "}" or ";;") are excluded so incidental
  # prose punctuation can't collide -- every distinctive script line is long.
  f="$1"
  trims=$(mktemp)
  sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$f" > "$trims"
  for s in antz-flow antz-probe antz-skills; do
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

# ---- invocations-01 ----------------------------------------------------------
# The source prompt: step 1 runs discover/ensure/state/release through
# "sh \"__ANTZ_SCRIPTS_DIR__/antz-flow.sh\" ..." (state still carrying the
# probe's path), the skills bullet runs the skills script by path, every
# "save ... to a temp file" instruction is gone, and no "# antz-include:"
# marker survives anywhere under agents/prompts/.

invocations_01_source_prompt() {
  ok=0
  for form in \
    'sh "__ANTZ_SCRIPTS_DIR__/antz-flow.sh" discover' \
    'sh "__ANTZ_SCRIPTS_DIR__/antz-flow.sh" ensure <slug>' \
    'sh "__ANTZ_SCRIPTS_DIR__/antz-flow.sh" state <slug> "__ANTZ_SCRIPTS_DIR__/antz-probe.sh"' \
    'sh "__ANTZ_SCRIPTS_DIR__/antz-flow.sh" release <slug>' \
    'sh "__ANTZ_SCRIPTS_DIR__/antz-skills.sh" <working-root> <match keyword> ...'
  do
    grep -qF "$form" "$PROMPT" || {
      echo "  orchestrator.prompt missing the invocation form: $form"; ok=1; }
  done
  # every prior "save the script below to a temp file" instruction is gone
  if grep -qiE 'save .*(script|probe|snippet)[^.]*temp file|tempfile' "$PROMPT"; then
    echo "  a temp-file instruction survives in the prompt source:"
    grep -niE 'save .*(script|probe|snippet)[^.]*temp file|tempfile' "$PROMPT" | sed 's/^/    /'; ok=1
  fi
  # no include marker anywhere under agents/prompts/
  if grep -rl '# antz-include:' "$SCRIPT_DIR/agents/prompts/" 2>/dev/null | grep .; then
    echo "  a '# antz-include:' marker survives under agents/prompts/"; ok=1
  fi
  # the placeholder's dollar-digit-free shape: the token itself carries no
  # $<digit> and no $ARGUMENTS sequence (client templating cannot corrupt it)
  case '__ANTZ_SCRIPTS_DIR__' in
    *'$'*) echo "  the placeholder token shape carries a dollar sign"; ok=1 ;;
  esac
  n=$(grep -o '__ANTZ_SCRIPTS_DIR__' "$PROMPT" | wc -l | tr -d ' ')
  [ "$n" -eq 6 ] || { echo "  expected 6 placeholder occurrences (4 flow + 1 probe + 1 skills), got: $n"; ok=1; }
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
  d=$(new_tmp_dir); ok=0
  co="$d/checkout"; stage_checkout "$co"
  home="$d/home"; mkdir -p "$home"
  lib="$home/.config/antz/scripts"
  install_at "$home" "$co/install.sh" --all > "$d/install.log" 2>&1 \
    || { echo "  install.sh --all exited non-zero:"; head -5 "$d/install.log" | sed 's/^/    /'; return 1; }

  for client in .claude .config/opencode; do
    cl=${client//\//_}
    f="$home/$client/agents/antz-orchestrator.md"
    [ -f "$f" ] || { echo "  missing rendered file: $f"; ok=1; continue; }
    body="$d/body.$cl"
    strip_frontmatter "$f" > "$body"
    # the body is exactly the single source prompt with the token replaced
    exp="$d/expected.$cl"
    reconstruct_expected_body "$exp" "$lib"
    cmp -s "$exp" "$body" || {
      echo "  $client body is not the source prompt with the resolved path substituted:"
      diff "$exp" "$body" | head -8 | sed 's/^/    /'; ok=1; }
    # zero fenced or unfenced lines from any scripts/orchestration/ file
    assert_body_has_no_script_lines "$f" || { echo "  ($client)"; ok=1; }
    # every invocation line carries the concrete resolved libdir path
    for form in \
      "sh \"$lib/antz-flow.sh\" discover" \
      "sh \"$lib/antz-flow.sh\" ensure <slug>" \
      "sh \"$lib/antz-flow.sh\" state <slug> \"$lib/antz-probe.sh\"" \
      "sh \"$lib/antz-flow.sh\" release <slug>" \
      "sh \"$lib/antz-skills.sh\" <working-root> <match keyword> ..."
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
  d=$(new_tmp_dir); ok=0
  co="$d/checkout"; stage_checkout "$co"
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
  d=$(new_tmp_dir); ok=0
  co="$d/checkout"; stage_checkout "$co"
  home="$d/home"; mkdir -p "$home"
  install_at "$home" "$co/install.sh" --all > "$d/install.log" 2>&1 \
    || { echo "  install exited non-zero"; return 1; }
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
  grep -qF 'skill=%s path=%s matched=%s' "$so/antz-skills.sh" || {
    echo "  the skills script's skill= line format is lost"; ok=1; }
  grep -qF 'Skills: none matched' "$so/antz-skills.sh" || {
    echo "  the skills script's none-matched line is lost"; ok=1; }
  # byte-identity: the scripts/orchestration/ files are exactly what the
  # change's base commit holds (vocabulary identity rests on file identity)
  base=$(git -C "$SCRIPT_DIR" merge-base master HEAD 2>/dev/null || echo HEAD)
  for s in antz-flow antz-probe antz-skills; do
    git -C "$SCRIPT_DIR" show "$base:scripts/orchestration/$s.sh" > "$d/vtmp" 2>/dev/null || {
      echo "  could not read the base copy of $s.sh"; ok=1; continue; }
    cmp -s "$d/vtmp" "$so/$s.sh" || {
      echo "  scripts/orchestration/$s.sh is NOT byte-unchanged vs the base commit"; ok=1; }
    rm -f "$d/vtmp"
  done
  # the flow script's header usage comment keeps the historical "sh <tempfile>"
  # wording (byte-identity wins over cosmetic freshness)
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
  d=$(new_tmp_dir); ok=0
  co="$d/checkout"; stage_checkout "$co"
  home="$d/home"; mkdir -p "$home"
  install_at "$home" "$co/install.sh" --all > "$d/install.log" 2>&1 \
    || { echo "  install exited non-zero"; return 1; }
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
# Structural pins of the DE-EMBEDDED source prompt: fences drop from seven
# blocks (14 lines) to four (8), no ```sh fence remains, the four tables and
# the steps-ending-at-6 survive, no new fenced block was added.

invocations_06_structure() {
  ok=0
  fl=$(grep -cE '^[[:space:]]*```' "$PROMPT")
  [ "$fl" -eq 8 ] || { echo "  expected 8 fence lines, got: $fl"; ok=1; }
  sh=$(grep -cE '^[[:space:]]*```sh' "$PROMPT")
  [ "$sh" -eq 0 ] || { echo "  expected no \`\`\`sh fence, got: $sh"; ok=1; }
  blocks=$((fl / 2))
  [ "$blocks" -eq 4 ] || { echo "  expected 4 fenced blocks, got: $blocks"; ok=1; }
  # the four surviving blocks are the delegation header, the two skills-block
  # shapes, and the human follow-up print
  grep -qF 'Working root: <repo root absolute path>' "$PROMPT" || { echo "  delegation-header block lost"; ok=1; }
  grep -qF 'Skills: none matched' "$PROMPT" || { echo "  none-matched block shape lost"; ok=1; }
  grep -qF '(matched: <keyword>, <keyword>)' "$PROMPT" || { echo "  matched-list block shape lost"; ok=1; }
  grep -qF 'git branch -d antz/<slug>' "$PROMPT" || { echo "  follow-up print block lost"; ok=1; }
  # the four tables survive, steps still end at 6
  for hdr in \
    '| discover output | Meaning / action |' \
    '| Output | Meaning |' \
    '| `rejected_count` | Action |' \
    '| release output | Meaning / action |'
  do
    grep -qF "$hdr" "$PROMPT" || { echo "  table header lost: $hdr"; ok=1; }
  done
  grep -qE '^6\. On a fresh rejection' "$PROMPT" || { echo "  step 6 is gone"; ok=1; }
  grep -qE '^7\. ' "$PROMPT" && { echo "  a step 7 appeared"; ok=1; }
  # the three former script-fence positions are gone with their markers
  grep -qF 'antz-include' "$PROMPT" && { echo "  an include marker survives in the prompt"; ok=1; }
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
  readme="$SCRIPT_DIR/spdd/changes/deembed-orchestration-scripts/README.md"
  # the expected cache effect is on record in the change README: the KV-cache
  # priority, the ~335 embedded script lines leaving, and the per-session
  # re-materialization dropping out
  grep -qF 'KV-cache' "$readme" || { echo "  README lost the KV-cache priority"; ok=1; }
  grep -qF '~335' "$readme" || { echo "  README does not record the ~335 embedded lines"; ok=1; }
  grep -qE 'per-session re-materialization|re-emits the whole script text' "$readme" || {
    echo "  README does not record the per-session re-materialization that drops to zero"; ok=1; }
  return $ok
}

# ---- invocations-08 ----------------------------------------------------------
# The skills-derivation contract at the installed file: the rendered body runs
# antz-skills.sh by resolved path (never a CLI on PATH, hook, plugin, or
# temp-file copy), the derivation output contract is untouched (skill=/
# none-matched/cap-5/alphabetical tie-break/case-insensitive), the block
# shapes are byte-unchanged, and the never-read/SKILL.md constraint survives.

invocations_08_body_skills_bullets() {
  d=$(new_tmp_dir); ok=0
  co="$d/checkout"; stage_checkout "$co"
  home="$d/home"; mkdir -p "$home"
  install_at "$home" "$co/install.sh" --all > "$d/install.log" 2>&1 \
    || { echo "  install exited non-zero"; return 1; }
  lib="$home/.config/antz/scripts"
  for client in .claude .config/opencode; do
    f="$home/$client/agents/antz-orchestrator.md"
    grep -qF "sh \"$lib/antz-skills.sh\" <working-root> <match keyword> ..." "$f" || {
      echo "  ($client) the skills bullet does not run the installed script by resolved path"; ok=1; }
    grep -qF 'never a temp-file copy' "$f" || {
      echo "  ($client) the never-a-temp-file-copy clause is gone"; ok=1; }
    grep -qF 'never a new installed command, CLI, hook, or plugin' "$f" || {
      echo "  ($client) the no-CLI/hook/plugin clause is gone"; ok=1; }
    # the "## Skills to load before work" block shapes, byte-unchanged
    grep -qF '## Skills to load before work' "$f" || {
      echo "  ($client) the delegation block heading shape is gone"; ok=1; }
    grep -qF -- '- /absolute/path/to/first-skill/SKILL.md (matched: <keyword>, <keyword>)' "$f" || {
      echo "  ($client) the matched-list shape is gone"; ok=1; }
    grep -qF "it never reads or follows a SKILL.md's instructions" "$f" || {
      echo "  ($client) the never-read constraint is gone"; ok=1; }
    grep -qF 'paths, not summaries' "$f" || {
      echo "  ($client) the paths-not-summaries constraint is gone"; ok=1; }
  done
  return $ok
}

invocations_08_derivation_contract() {
  d=$(new_tmp_dir); ok=0
  co="$d/checkout"; stage_checkout "$co"
  home="$d/home"; mkdir -p "$home"
  install_at "$home" "$co/install.sh" --claude > "$d/install.log" 2>&1 \
    || { echo "  install exited non-zero"; return 1; }
  skills="$home/.config/antz/scripts/antz-skills.sh"
  [ -f "$skills" ] || { echo "  installed antz-skills.sh missing"; return 1; }

  wroot="$d/wroot"
  empty="$d/empty-home"; mkdir -p "$empty"
  for n in a b c d e f g; do
    mkdir -p "$wroot/.agents/skills/sk-$n"
    printf -- '---\nname: sk-%s\ndescription: a kw-matching fixture skill\n---\n\nbody\n' "$n" \
      > "$wroot/.agents/skills/sk-$n/SKILL.md"
  done
  phys=$(cd "$wroot" && pwd)

  # matched run: at most five, best score first with an alphabetical-by-name
  # tie-break (all equal here -> sk-a..sk-e), each line skill=/path=/matched=
  out=$(env -u XDG_CONFIG_HOME HOME="$empty" sh "$skills" "$phys" kw 2>&1); rc=$?
  [ "$rc" -eq 0 ] || { echo "  matched run exited $rc"; ok=1; }
  n=$(printf '%s\n' "$out" | grep -c '^skill=')
  [ "$n" -eq 5 ] || { echo "  expected the cap of five matched lines, got: $n"; ok=1; }
  printf '%s\n' "$out" | head -1 | grep -qxF "skill=sk-a path=$phys/.agents/skills/sk-a/SKILL.md matched=kw" || {
    echo "  first line is not the alphabetical-by-name tie-break winner: $(printf '%s\n' "$out" | head -1)"; ok=1; }
  printf '%s\n' "$out" | grep -qF 'sk-f' && { echo "  sk-f leaked past the cap of five"; ok=1; }

  # case-insensitive description matching: uppercase KW hits the same skills
  out2=$(env -u XDG_CONFIG_HOME HOME="$empty" sh "$skills" "$phys" KW 2>&1); rc=$?
  [ "$rc" -eq 0 ] && [ "$out2" = "$out" ] || { echo "  case-insensitive matching drifted"; ok=1; }

  # nothing matches -> exactly one line, exit 0
  out3=$(env -u XDG_CONFIG_HOME HOME="$empty" sh "$skills" "$phys" zzznomatchzzz 2>&1); rc=$?
  [ "$rc" -eq 0 ] || { echo "  none-matched run exited $rc"; ok=1; }
  [ "$out3" = "Skills: none matched" ] || { echo "  none-matched output drifted: $out3"; ok=1; }
  return $ok
}

# ---- run ---------------------------------------------------------------------

run_test "invocations-01: the source prompt runs discover/ensure/state/release and the skills derivation as one-line path invocations of __ANTZ_SCRIPTS_DIR__ (state still carries the probe's path), no temp-file instruction and no include marker survives" invocations_01_source_prompt
run_test "invocations-02: inject_includes(), its orchestrator-keyed call site and the antz-skills.sh done-carve-out are gone from install.sh, which substitutes the once-resolved libdir for the placeholder at render time" invocations_02_mechanism_retired
run_test "invocations-03: both rendered orchestrator bodies are exactly the source prompt with the concrete resolved path substituted -- zero script lines, zero markers, zero placeholders anywhere installed -- with the Claude and OpenCode frontmatter shapes intact" invocations_03_render
run_test "invocations-03: with XDG_CONFIG_HOME set the invocation lines carry that XDG-resolved concrete path (never the HOME fallback, never a trailing slash)" invocations_03_xdg_concrete_path
run_test "invocations-04: the rendered body instructs zero re-materialization (no temp file anywhere; every installed-file run is a one-line sh call), the 'Never writes anything itself' Owns bullet holds, and every script-machine-line invocation is by path" invocations_04_no_rematerialization
run_test "invocations-04: the scripts' machine-line vocabulary is byte-identical -- every pinned literal present in the byte-unchanged scripts/orchestration/ files, historical sh <tempfile> header wording included" invocations_04_machine_line_vocabulary
run_test "invocations-05: the four tables, step 3 classification, step 4 rejection routing, the session guards, the Report Format, the byte-pinned delegation header and the human follow-up print survive both renders; the flow script keeps exactly its four subcommands" invocations_05_routing_surface
run_test "invocations-06: the source prompt's structural pins of the de-embedded shape -- 4 fenced blocks (8 fence lines, no \`\`\`sh), the four tables, steps ending at 6, no new fenced block" invocations_06_structure
run_test "invocations-07: renders are deterministic and idempotent (two fresh-HOME installs and a same-HOME re-install give byte-identical trees), the body carries no per-session data with the frontmatter marker as its only version-bearing string, and no script line appears in any rendered agent body" invocations_07_stable_prefix
run_test "invocations-07: the expected cache effect (KV-cache priority, ~335 embedded lines gone, per-session re-materialization dropping to zero) is recorded in the change README" invocations_07_cache_effect_recorded
run_test "invocations-08: the rendered skills bullets run the installed antz-skills.sh by resolved path with never-a-temp-file-copy, the no-CLI/hook/plugin clause, the byte-unchanged block shapes and the never-read constraint" invocations_08_body_skills_bullets
run_test "invocations-08: the installed antz-skills.sh keeps the derivation output contract untouched -- skill=/path=/matched= lines, cap of five with the alphabetical-by-name tie-break, case-insensitive matching, 'Skills: none matched' at exit 0" invocations_08_derivation_contract

# ---- deferred clause: explicit SKIP stub -------------------------------------
# invocations-07's CHANGELOG half ("the expected cache effect is recorded ...
# in the CHANGELOG entry") is sub-spec 06's declared artifact (versionbump,
# 4.7.1 -> 4.8.0 with the explicit note); the README half is pinned green
# above. Explicit stub so the clause is accounted for, never silently omitted.
skip_test "invocations-07 (CHANGELOG clause): the expected cache effect (~483 measured lines to ~150 prose, per-session re-materialization of ~335 lines to zero, version-marker invalidation accepted) lands in the CHANGELOG entry" \
  "deferred: the CHANGELOG entry is sub-spec 06's (versionbump) declared artifact"

echo
echo "pass=$pass_count fail=$fail_count skip=$skip_count"
[ "$fail_count" -eq 0 ]
