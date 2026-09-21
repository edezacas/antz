#!/usr/bin/env bash
#
# eval/dispatch.sh — the dispatch tool's own checks, with no provider and no cost.
#
# `extensions/antz-subagent.ts` is this repo's one file of code, and `run.sh` is
# the only thing that exercised it: end to end, with real agents, for money and
# minutes. That is the wrong instrument for "did I break the four shapes?". This
# one substitutes the pi SDK with stubs, so the tool can be driven directly —
# shapes, concurrency cap, per-chain handoff, failure path, both renderers —
# deterministically and in about a second.
#
#   ./dispatch.sh
#
# It tests the WORKING TREE, which is the opposite of `run.sh`: the eval grades
# what is installed in ~/.pi/agent. Neither replaces the other. A green run here
# says the tool behaves, not that the flow works: the SDK and the agents are fake.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

command -v node >/dev/null 2>&1 || {
  echo "node is required: the harness imports the extension and lets node strip its types" >&2
  exit 1
}

# Type stripping is on by default from node 23.6 (and 22.18); on 22.6 through
# 23.5 it needs the flag. Passing it is harmless where it is the default.
NODE=(node)
if node --experimental-strip-types -e 'process.exit(0)' >/dev/null 2>&1; then
  NODE=(node --experimental-strip-types)
fi

# The extension imports the SDK by bare specifier, so the stubs have to sit in a
# node_modules next to the copy under test. Nothing is written into the repo.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp -R "$HERE/stubs/node_modules" "$WORK/node_modules"
cp "$HERE/dispatch.mjs" "$WORK/"
cp "$REPO/extensions/antz-subagent.ts" "$WORK/"

cd "$WORK"
"${NODE[@]}" dispatch.mjs
