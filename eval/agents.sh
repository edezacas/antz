#!/usr/bin/env bash
#
# eval/agents.sh — what each subagent spent, from any session file.
#
# run.sh aggregates per dispatch, which hides the agent: a `chains` call of eight
# agents is one row. The per-agent numbers are already persisted — every run in
# `details.runs[]` carries its own `usage` and its own `steps` — so this reads
# them back out. It works on any session, including a real one outside this repo:
#
#   ./agents.sh out/M-1.session.jsonl          # one row per agent run
#   ./agents.sh --summary ~/.pi/agent/sessions/…/session.jsonl
#
# One row per agent run, tab separated, in the order they ran:
#
#   agent  status  turns  reads  antzReads  input  cacheRead  cacheWrite
#   output  seconds  skills  tools
#
# `turns` is the tool calls it made, which is also the LLM round trips: the cost
# driver a token total hides. `antzReads` is how many of its reads opened a file
# under `.antz/`, the number the flow wants at zero for a tester or an
# implementer. Nothing here needs the eval fixture, and nothing here is a
# verdict: it is a measurement.

set -uo pipefail

usage() { sed -n '3,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }
[ $# -ge 1 ] || usage
summary=0
[ "$1" = "-h" ] || [ "$1" = "--help" ] && usage
[ "$1" = "--summary" ] || [ "$1" = "-s" ] && { summary=1; shift; }
[ $# -ge 1 ] || usage

rows() {
  jq -r '
    select(.type == "message" and .message.role == "toolResult" and .message.toolName == "antz_subagent")
    | (.message.details.runs // [])[]
    | select(.agent)
    | [
        .agent,
        (.status // "?"),
        ((.steps // []) | length),
        ([.steps[]? | select(.tool == "read")] | length),
        ([.steps[]? | select(.tool == "read" and (.arg | type == "string") and (.arg | test("(^|/)[.]antz/")))] | length),
        (.usage.input // 0),
        (.usage.cacheRead // 0),
        (.usage.cacheWrite // 0),
        (.usage.output // 0),
        (if .startedAt and .endedAt then ((.endedAt - .startedAt) / 1000 | floor) else 0 end),
        ((.skillsUsed // []) | join("+")),
        ([.steps[]? | .tool] | group_by(.) | map("\(.[0])x\(length)") | join(" "))
      ]
    | @tsv
  ' "$1" 2>/dev/null
}

if [ "$summary" -eq 0 ]; then
  for file in "$@"; do rows "$file"; done
  exit 0
fi

# Per-agent means, the shape the numbers are argued in: one line per agent, so a
# change that moves one role and not another is visible.
for file in "$@"; do
  echo "# $(basename "$file")"
  printf '%-18s %4s %7s %8s %8s %9s %9s %9s %7s\n' \
    agent runs turns reads antzReads input cacheRead output seconds
  rows "$file" | awk -F'\t' '
    { n[$1]++; turns[$1]+=$3; reads[$1]+=$4; ar[$1]+=$5; inp[$1]+=$6; cr[$1]+=$7; out[$1]+=$9; sec[$1]+=$10 }
    END {
      for (a in n) printf "%-18s %4d %7.1f %8.1f %8.1f %9.0f %9.0f %9.0f %7.1f\n",
        a, n[a], turns[a]/n[a], reads[a]/n[a], ar[a]/n[a], inp[a]/n[a], cr[a]/n[a], out[a]/n[a], sec[a]/n[a]
    }' | sort -k3 -nr
done
