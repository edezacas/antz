#!/usr/bin/env bash
#
# eval/prompts.sh — the wiring of the prompt files, checked in a second.
#
# run.sh can only tell you a prompt is broken by paying for a flow run, which is the
# wrong instrument for "did I leave an agent over its line budget" or "does /antz route
# on an artifact nobody writes". Both of those cost a batch to discover and a second to
# check, so this checks them before anything is installed:
#
#   - the line budgets AGENTS.md declares: 9-13 lines per agent, 32 for prompts/antz.md;
#   - every `.antz/NN-name.md` prompt/antz.md routes on is one some agent is told to
#     write, and every artifact an agent writes is one the prompt routes on;
#   - prompts/antz.md names no dispatch tool, so its body stays byte-identical on every
#     client and only the frontmatter changes;
#   - every agent declares the name, description and tools pi needs.
#
# It says nothing about prose, wording or judgement — only about wiring.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
cd "$REPO"

failed=0
check() { [ "$1" = "1" ] || failed=$((failed + 1)); printf '%s  %s%s\n' "$([ "$1" = "1" ] && echo PASS || echo FAIL)" "$2" "${3:+  $3}"; }

echo "== line budgets"
for file in agents/antz-*.md; do
  lines=$(wc -l <"$file")
  check "$([ "$lines" -ge 9 ] && [ "$lines" -le 13 ] && echo 1 || echo 0)" "$file is 9-13 lines" "$lines"
done
lines=$(wc -l <prompts/antz.md)
check "$([ "$lines" -le 32 ] && echo 1 || echo 0)" "prompts/antz.md is at most 32 lines" "$lines"

echo
echo "== the artifacts, both directions"
artifacts() { grep -oh '\.antz/[0-9][0-9]-[a-z-]*\.md' "$@" 2>/dev/null | sort -u; }
routed="$(artifacts prompts/antz.md)"
written="$(artifacts agents/antz-*.md)"
check "$([ "$routed" = "$written" ] && echo 1 || echo 0)" "what the prompt routes on is what the agents write" \
  "routed: $(echo "$routed" | tr '\n' ' ')written: $(echo "$written" | tr '\n' ' ')"
for name in $routed; do
  check "$(grep -q "$name" prompts/antz.md && echo 1 || echo 0)" "$name is routed on"
done

echo
echo "== the prompt stays client-agnostic"
check "$(grep -q 'antz_subagent' prompts/antz.md && echo 0 || echo 1)" "prompts/antz.md names no dispatch tool"
check "$(grep -qE '`(Task|task)`' prompts/antz.md && echo 0 || echo 1)" "and no client's tool in backticks"

echo
echo "== the agents pi reads"
for file in agents/antz-*.md; do
  front="$(sed -n '2,/^---$/p' "$file")"
  missing=""
  for key in name description tools; do
    grep -q "^$key:" <<<"$front" || missing="$missing $key"
  done
  check "$([ -z "$missing" ] && echo 1 || echo 0)" "$file declares name, description and tools" "$missing"
done

echo
[ "$failed" -eq 0 ] && echo "all checks passed" || echo "$failed check(s) failed"
exit "$([ "$failed" -eq 0 ] && echo 0 || echo 1)"
